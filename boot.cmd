# Source for the boot.scr written into BOOT-A and BOOT-B. Compiled by
# build/src/mkimage-s905x5m-sd.ts with SOURCE_DATE_EPOCH pinned to the
# layout-v2 FILE_MTIME. Body follows docs/design/uboot-ab-handshake.md section
# 5.3, with TWO deliberate divergences from the version first published there.
# Both were defects that made updates silently revert, and section 5.3
# documents both and is synced to this file.
#
# Amlogic-specific behavior comes from boot-sd.ini.in, not cx3576/boot.cmd.
# cx3576 supplies only the generic RAUC state machine: RK3576 has neither
# Amlogic's add_kernel_bootargs() merge behavior nor its vout/aml_media/hdmitx
# display path. On this board leave /chosen/bootargs absent after fdt rm, and
# keep vout output paired with aml_media.vout=...,disable.
#
# 1. The verity parameters are loaded from the slot-suffixed
#    mos-verity-<slot>.env, falling back to the unsuffixed name. A RAUC bundle
#    installs a single boot payload into whichever slot is inactive, so it has
#    to ship both slots' files under distinct names; an unsuffixed file cannot
#    identify a slot.
# 2. bootargs carries rauc.slot=${bootslot}. The root device is /dev/dm-0, a
#    device-mapper node rather than a partition, which rauc cannot match against
#    any slot's bootname, slot name or realpath(device) — verified against rauc
#    1.8: without rauc.slot= it fails with "Did not find booted slot (matching
#    '/dev/dm-0')", so the health gate never reaches `rauc status mark-good`
#    and the installed slot is rolled back.
#
# boot.cmd — mos A/B handshake for S905X5M / BM201 (layout v2).
# Compiled to boot.scr and written to BOTH boot partitions by the assembler.
# Identical in both slots: whichever copy runs may boot either slot.
#
# hush notes: no arithmetic without setexpr; setexpr is HEXADECIMAL, which is
# also the radix RAUC uses for BOOT_x_LEFT. Keep boot-attempts in 1..9.
#
# PARTITION NUMBERS. bootpart/rootpart below are literal GPT partition numbers,
# because hush cannot read boards/s905x5m/board.env. They are BOOT_A_PARTNUM /
# BOOT_B_PARTNUM / ROOTFS_A_PARTNUM / ROOTFS_B_PARTNUM from that file, and
# build/src/mkimage-s905x5m-sd.ts refuses to compile this script if any of
# the four disagrees. Do not edit one here without editing the layout: a stale
# number sends U-Boot to the wrong partition after it has already persisted the
# attempt decrement.

# This small text environment is staged between the measured DTB and kernel
# addresses. It is overwritten by neither later fatload, and is not a kernel or
# DTB placement promise.
setenv verityaddr 0x2000000

# --- defaults, only used on a virgin environment ---------------------------
test -n "${BOOT_ORDER}"  || setenv BOOT_ORDER "A B"
test -n "${BOOT_A_LEFT}" || setenv BOOT_A_LEFT 3
test -n "${BOOT_B_LEFT}" || setenv BOOT_B_LEFT 3

# --- pick the leftmost slot in BOOT_ORDER that still has credits -----------
setenv bootslot
for slot in ${BOOT_ORDER}; do
    if test -n "${bootslot}"; then
        echo "skipping ${slot}"
    elif test "${slot}" = "A"; then
        if test ${BOOT_A_LEFT} -gt 0; then
            setexpr BOOT_A_LEFT ${BOOT_A_LEFT} - 1
            setenv bootslot A
            setenv slotsuffix a
            setenv bootpart 5
            setenv rootpart 7
        fi
    elif test "${slot}" = "B"; then
        if test ${BOOT_B_LEFT} -gt 0; then
            setexpr BOOT_B_LEFT ${BOOT_B_LEFT} - 1
            setenv bootslot B
            setenv slotsuffix b
            setenv bootpart 6
            setenv rootpart 8
        fi
    fi
done

# --- no credits anywhere: refill, persist, reboot --------------------------
if test -z "${bootslot}"; then
    echo "mos: no bootable slot left, resetting attempt counters"
    setenv BOOT_A_LEFT 3
    setenv BOOT_B_LEFT 3
    saveenv
    reset
fi

# --- persist the decrement BEFORE booting: this is what makes it a watchdog -
# An unpersisted decrement quietly degrades the whole scheme to boot-forever:
# every reset would start from the old counter, so a slot that can never reach
# mark-good would be retried without end instead of rolling back. saveenv's
# result cannot change what happens next (the kernel either boots or it does
# not), but a failing env write must not be silent -- it is the watchdog
# disarming itself, and the console line is the only witness.
saveenv || echo "mos: WARNING: saveenv FAILED, boot-attempt decrement NOT persisted; the A/B watchdog cannot count this attempt and a bad slot will be retried forever"

echo "mos: booting slot ${bootslot} (A=${BOOT_A_LEFT} B=${BOOT_B_LEFT} left)"

# --- per-slot verity parameters, from the chosen slot's boot partition ------
# mos-verity-<slot>.env is a one-line text env file defining verity_args= with
# the full dm-mod.create=/dm-mod.waitfor= tail for THIS slot's rootfs.
# The name carries the slot because one RAUC boot payload can be installed into
# either boot partition: it ships both slots' files, so the slot-identifying
# file cannot be slot-neutral. slotsuffix is set alongside bootslot above,
# lowercase to match the filenames, rather than leaning on FAT case folding.
# The unsuffixed name is a fallback for older, hand-assembled boot partitions;
# nothing this tree builds relies on it.
if fatload mmc 1:${bootpart} ${verityaddr} mos-verity-${slotsuffix}.env; then
    env import -t ${verityaddr} ${filesize}
elif fatload mmc 1:${bootpart} ${verityaddr} mos-verity.env; then
    env import -t ${verityaddr} ${filesize}
else
    echo "mos: slot ${bootslot} has no mos-verity-${slotsuffix}.env"
    setenv BOOT_${bootslot}_LEFT 0
    saveenv
    reset
fi

# --- machine identity: only when U-Boot actually has one (see section 6) ---
setenv machineid_arg
if test -n "${machine_id}"; then
    setenv machineid_arg "systemd.machine_id=${machine_id}"
fi

# Values measured by the SD bridge. The production path does not inherit its
# cfgload or p1 dependency, but it must establish the same Amlogic display mode
# before it boots Linux. These are fixed board values, deliberately literal:
# hush cannot read board.env and boot-s905x5m.test.ts guards their exact form.
setenv connector0_type "HDMI-A-A"
setenv outputmode "1080p60hz"
setenv hdmimode "${outputmode}"
setenv colorattribute "444,8bit"
setenv display_layer "osd0"
setenv fb_addr "0x00300000"

# ttyS0 must stay the last console= parameter, so /dev/console remains on the
# serial bench even while fbcon is available on HDMI.
setenv consoleargs "console=tty1 console=ttyS0,921600 earlycon=aml_uart,0xfe07a000"
setenv displayargs "logo=${display_layer},loaded,${fb_addr} aml_media.vout=${outputmode},disable aml_media.connector0_type=${connector0_type} hdmitx=,${colorattribute} hdmimode=${hdmimode}"
setenv rootargs "root=/dev/dm-0 rootfstype=squashfs ro rootwait"

# rauc.slot= is how rauc identifies which slot it is running from. It cannot be
# derived from root=: the verity design makes root a device-mapper node, and
# rauc matches the boot slot by bootname, slot name or realpath(device), none of
# which /dev/dm-0 can ever be. ${bootslot} is A or B, which are exactly the
# bootname values /etc/rauc/system.conf declares, so no separate mapping exists
# to drift. Without this, `rauc status` fails, the health gate never runs
# `rauc status mark-good`, and U-Boot rolls the new slot back on credit
# exhaustion — an update that reverts while the device looks healthy.
setenv raucargs "rauc.slot=${bootslot}"

setenv bootargs "${rootargs} ${verity_args} ${raucargs} ${consoleargs} ${displayargs} net.ifnames=0 ${machineid_arg}"

# --- load and go -----------------------------------------------------------
# These are the board's measured production load addresses and DTB name, not
# values inherited from cx3576 or the SD-only cfgload bridge.
setenv loadaddr_kernel 0x3000000
setenv dtb_mem_addr 0x1000000
setenv fdtfile s7d_s905x5m_m100.dtb
fatload mmc 1:${bootpart} ${loadaddr_kernel} Image
fatload mmc 1:${bootpart} ${dtb_mem_addr} ${fdtfile}

# Amlogic's add_kernel_bootargs path splits the quoted dm-mod.create table on
# spaces and de-duplicates the repeated verity fields. Leave this DT merge
# input absent: the later standard bootm FDT fixup copies ${bootargs} from the
# environment intact. Do not restore the property here; cx3576 can do that,
# but this Amlogic path cannot.
fdt addr ${dtb_mem_addr}
fdt resize 65536
if fdt rm /chosen bootargs; then
    echo "bootargs: removed DT merge input"
fi

# Amlogic needs U-Boot to establish a mode before Linux takes over. Keep this
# paired with aml_media.vout=...,disable above: Linux must reprogram the path,
# because seamless handoff produces a duplicated half-width console on BM201.
if vout output ${outputmode}; then
    echo "display: ${outputmode} enabled"
fi
booti ${loadaddr_kernel} - ${dtb_mem_addr}

# booti only returns on failure: burn this slot's remaining credits so the
# next reset moves on instead of retrying a slot we know cannot boot.
echo "mos: booti returned, slot ${bootslot} is bad"
setenv BOOT_${bootslot}_LEFT 0
saveenv
reset
