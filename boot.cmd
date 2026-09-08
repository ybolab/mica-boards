# Source for the boot.scr written into BOOT-A and BOOT-B. Compiled by
# build/src/mkimage-cx3576.ts with SOURCE_DATE_EPOCH pinned to the A/B-layout FILE_MTIME.
# Body follows docs/design/uboot-ab-handshake.md section 5.3, with
# THREE deliberate divergences from the version first published there. All
# three were defects, and section 5.3 documents all three and is synced to this
# file.
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
# 3. The kernel and the dtb are loaded through a guard, not bare. The published
#    version checked the 370-byte verity env and not the 42 MB kernel, and a
#    board booted a MIXTURE of two kernel builds and died in paging_init while
#    the console reported the full 44493312 bytes read (RFCT-351, RFCT-352).
#    mos-boot-digest.env carries each file's byte count and CRC-32; the script
#    asserts both and burns the slot when either disagrees. This one needs
#    CONFIG_CRC32_VERIFY=y in the U-Boot build (section 3.2), so unlike the
#    other two it is NOT deployable to a device by an update alone.
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
setenv digestaddr 0x40f10000

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

setenv consoleargs "console=ttyFIQ0,1500000 earlycon=uart8250,mmio32,0x2ad40000"
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

# --- load the kernel and the dtb, and prove what landed ---------------------
# mos-boot-digest.env records the byte count and the CRC-32 of the Image and the
# rk3576-src.dtb sitting beside it in THIS boot partition, and it is what turns
# `load` from a command whose success means "the FAT directory had an entry and
# the read did not error" into one whose success means "the bytes in DRAM are
# the bytes on the card". A board booted a mixture of two kernel builds and died
# in paging_init while the console reported the full 44493312 bytes read
# (RFCT-351, RFCT-352): an unguarded load cannot tell those two apart, and it
# was the cheap 370-byte file that was checked and the 42 MB one that was not.
#
# The file carries NO slot suffix, and the contrast with mos-verity-<slot>.env
# above is the reason. That file describes a DIFFERENT partition -- the rootfs
# slot this boot partition will be paired with -- which one RAUC boot payload
# cannot know, since it is installed into whichever boot slot is inactive, so it
# ships both slots' copies under distinct names. These digests describe this
# partition's OWN two files, of which there is exactly one set whichever slot
# the partition turns out to be, exactly as there is one Image and one boot.scr.
# A suffix here would be two names for one fact, and the copy that is never read
# would be free to drift.
#
# WHAT THE TWO ASSERTIONS CATCH, stated separately because they are not the same
# claim. The byte count catches a short read, and names it precisely, which the
# checksum alone would not. The CRC-32 catches any divergence present in DRAM at
# the moment it runs -- a short read or stale bytes in the middle -- and it is
# the one of the two that would have caught the failure above. NEITHER can catch
# a corruption that happens after the check and before the kernel reads the
# page: the window is now the milliseconds between crc32 and booti instead of
# the whole load, but it is not zero, and this script cannot make it zero.
#
# The four values are cleared first. `env import` leaves whatever a previous
# boot persisted in place for any key the file does not carry, and the burn
# paths call saveenv, so a truncated digest file could otherwise be checked
# against a stale value some earlier boot wrote -- the guard passing on the
# strength of the number it exists to test.
setenv bootfault
setenv kernel_bytes
setenv kernel_crc
setenv fdt_bytes
setenv fdt_crc

if load mmc 0:${bootpart} ${digestaddr} mos-boot-digest.env; then
    env import -t ${digestaddr} ${filesize} || setenv bootfault "mos-boot-digest.env would not import"
else
    setenv bootfault "no mos-boot-digest.env beside Image"
fi

# `load` reports ${filesize} through env_set_hex, i.e. "%lx": lowercase hex, no
# 0x prefix, no leading zeros. mos-boot-digest.env spells the byte counts the
# same way, so this is a string compare and needs no arithmetic -- hush has none
# without setexpr, and setexpr is hexadecimal (see the header).
if test -z "${bootfault}"; then
    if load mmc 0:${bootpart} ${kernel_addr_r} Image; then
        if test "${filesize}" != "${kernel_bytes}"; then
            setenv bootfault "Image: ${filesize} bytes landed, mos-boot-digest.env says ${kernel_bytes}"
        elif crc32 -v ${kernel_addr_r} ${filesize} ${kernel_crc}; then
            echo "mos: Image ${kernel_bytes} bytes, crc32 ${kernel_crc} verified in DRAM"
        else
            setenv bootfault "Image: ${kernel_bytes} bytes landed and their crc32 is not ${kernel_crc}"
        fi
    else
        setenv bootfault "Image would not load"
    fi
fi

if test -z "${bootfault}"; then
    if load mmc 0:${bootpart} ${fdt_addr_r} rk3576-src.dtb; then
        if test "${filesize}" != "${fdt_bytes}"; then
            setenv bootfault "rk3576-src.dtb: ${filesize} bytes landed, mos-boot-digest.env says ${fdt_bytes}"
        elif crc32 -v ${fdt_addr_r} ${filesize} ${fdt_crc}; then
            echo "mos: rk3576-src.dtb ${fdt_bytes} bytes, crc32 ${fdt_crc} verified in DRAM"
        else
            setenv bootfault "rk3576-src.dtb: ${fdt_bytes} bytes landed and their crc32 is not ${fdt_crc}"
        fi
    else
        setenv bootfault "rk3576-src.dtb would not load"
    fi
fi

# The same route the missing-verity-env case takes, for the same reason: burn
# this slot's remaining credits so the next reset moves on instead of retrying a
# slot we know cannot boot. It is not a permanent loss -- when both slots reach
# zero the refill block above puts three credits back on each -- so a transient
# fault costs a trip through the other slot and back, not the device.
if test -n "${bootfault}"; then
    echo "mos: slot ${bootslot} p${bootpart}: ${bootfault}"
    setenv BOOT_${bootslot}_LEFT 0
    saveenv
    reset
fi

booti ${kernel_addr_r} - ${fdt_addr_r}

# booti only returns on failure: burn this slot's remaining credits so the
# next reset moves on instead of retrying a slot we know cannot boot.
echo "mos: booti returned, slot ${bootslot} is bad"
setenv BOOT_${bootslot}_LEFT 0
saveenv
reset
