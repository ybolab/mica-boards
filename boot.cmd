# Source for the boot.scr written into BOOT-A and BOOT-B. Compiled by
# build/src/mkimage-cx3576.ts with SOURCE_DATE_EPOCH pinned to the A/B-layout FILE_MTIME.
# Body follows docs/design/uboot-ab-handshake.md section 5.3, with
# TWO deliberate divergences from the version first published there. Both were
# defects that made updates silently revert, and section 5.3 documents both
# and is synced to this file.
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
# boot.cmd — mos A/B handshake for CX3576-Z (A/B layout).
# Compiled to boot.scr and written to BOTH boot partitions by the assembler.
# Identical in both slots: whichever copy runs may boot either slot.
#
# hush notes: no arithmetic without setexpr; setexpr is HEXADECIMAL, which is
# also the radix RAUC uses for BOOT_x_LEFT. Keep boot-attempts in 1..9.
#
# PARTITION NUMBERS. bootpart/rootpart below are literal GPT partition numbers,
# because hush cannot read boards/cx3576/board.env. They are BOOT_A_PARTNUM /
# BOOT_B_PARTNUM / ROOTFS_A_PARTNUM / ROOTFS_B_PARTNUM from that file, and
# build/src/mkimage-cx3576.ts refuses to compile this script if any of the four disagrees.
# Do not edit one here without editing the layout: a stale number sends U-Boot
# to the wrong partition after it has already persisted the attempt decrement.

setenv verityaddr 0x40f00000

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
            setenv bootpart 4
            setenv rootpart 6
        fi
    elif test "${slot}" = "B"; then
        if test ${BOOT_B_LEFT} -gt 0; then
            setexpr BOOT_B_LEFT ${BOOT_B_LEFT} - 1
            setenv bootslot B
            setenv slotsuffix b
            setenv bootpart 5
            setenv rootpart 7
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
if load mmc 0:${bootpart} ${verityaddr} mos-verity-${slotsuffix}.env; then
    env import -t ${verityaddr} ${filesize}
elif load mmc 0:${bootpart} ${verityaddr} mos-verity.env; then
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

# CONSOLE ORDER IS LOAD-BEARING, AND IT IS THE FIRST THING TO GET WRONG HERE.
# Every console= receives printk, but /dev/console -- where init, systemd and
# every service's stdout go -- is the LAST one: __add_preferred_console() sets
# preferred_console on each entry it parses, so the last assignment wins
# (kernel/printk/printk.c:2437-2468). tty1 is this board's HDMI output, so
# tty1 FIRST and the serial console LAST is what puts kernel messages on the
# screen while leaving userspace output on the cable. Swapping them is a
# working boot that moves the console onto a customer's display and silences
# serial, which is why verify asserts the ORDER and not the presence.
#
# loglevel=5, AND IT IS NOT AN ARBITRARY NUMBER. fbcon draws the boot logo only
# when console_loglevel EXCEEDS CONFIG_CONSOLE_LOGLEVEL_QUIET, which this kernel
# sets to 4 (fbcon_init, drivers/video/fbdev/core/fbcon.c:1009-1010) -- so
# `quiet`, which sets exactly 4, suppresses the logo, and any smaller value does
# too. 5 is the floor that shows it, and it leaves EMERG..WARNING printing while
# dropping NOTICE and INFO, so a healthy boot is quiet without being mute.
#
# loglevel=0 WOULD BE WORSE THAN A BLANK SCREEN and must never be set here:
# suppress_message_printing() drops a message when `level >= console_loglevel`,
# which at zero includes KERN_EMERG, and console_verbose() -- the call an oops
# and a panic use to raise the level -- is guarded by `if (console_loglevel)`
# and does nothing at zero (printk.c:1230-1233, :2567-2571). The crash would be
# invisible on HDMI and on serial. Upstream warns about exactly this in
# init/main.c:255-258.
#
# fbcon=logo-pos:center,logo-count:1. fb_logo_count defaults to -1, which means
# ONE LOGO PER ONLINE CPU (fbmem.c:695); on this eight-core SoC that is a row of
# logos rather than a splash. logo-count:1 pins one and logo-pos:center places
# it, since fbcon otherwise draws at the top-left corner.
#
# PLAN-088 carries the measurements, and boards/cx3576/board.env's
# BOARD_CMDLINE_ARGS carries the same console list -- verify compares the two,
# so this line and that one cannot drift apart.
setenv consoleargs "console=tty1 console=ttyFIQ0,1500000 earlycon=uart8250,mmio32,0x2ad40000 loglevel=5 fbcon=logo-pos:center,logo-count:1"
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

setenv bootargs "${rootargs} ${verity_args} ${raucargs} ${consoleargs} net.ifnames=0 ${machineid_arg}"

# --- load and go -----------------------------------------------------------
load mmc 0:${bootpart} ${kernel_addr_r} Image
load mmc 0:${bootpart} ${fdt_addr_r} rk3576-src.dtb
booti ${kernel_addr_r} - ${fdt_addr_r}

# booti only returns on failure: burn this slot's remaining credits so the
# next reset moves on instead of retrying a slot we know cannot boot.
echo "mos: booti returned, slot ${bootslot} is bad"
setenv BOOT_${bootslot}_LEFT 0
saveenv
reset
