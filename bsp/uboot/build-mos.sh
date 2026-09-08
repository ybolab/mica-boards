#!/usr/bin/env bash
# mos-build-side: container -- the same builder image and the same tree
# build.sh left behind; nothing here runs on the host.
#
# Reconfigure the already-built U-Boot tree with the mos A/B env and boot
# contract of docs/design/uboot-ab-handshake.md 3.2/10, and rebuild it.
#
#   build-mos.sh <source-tree> <rkbin-dir> <ddr-blob> <bl31-blob>
#
# * redundant env pair pinned at uenv-a 0x1000000 / uenv-b 0x1100000, 64 KiB each,
#   eMMC user area (ENV_SIZE must stay 0x10000: the Rockchip default 0x1f000 would
#   overrun into uenv-b)
# * ENV_MMC_USE_DT / ENV_MMC_USE_SW_PARTITION / PARTITION_TYPE_GUID stay off, or
#   env/mmc.c relocates the env to a partition END instead of the offsets
# * boot.scr is the only auto-discoverable entry: bootmeth order pinned to script;
#   the rockusb rescue tail and the PREBOOT recovery key are preserved
# * CRC32_VERIFY is on, because boot.scr checks the kernel and the dtb it just
#   loaded against mos-boot-digest.env before booti. `load` reporting success
#   means the FAT directory had an entry and the read did not error; a board
#   booted a MIXTURE of two kernel builds while the console printed the full
#   44493312 bytes read (RFCT-351/RFCT-352). CMD_CRC32 alone gives a crc32 that
#   can only write its answer to memory, and reading it back needs a byteswap
#   and an unpadded "%llx" -- two spellings nothing checks. `crc32 -v` compares
#   in one command, returns the verdict as an exit status hush can branch on,
#   and prints the two values when they differ. Losing it does not degrade the
#   script, it BRICKS it: an unknown flag is a usage error, the script reads
#   that as a failed verification and burns the slot.
# * BOOTCOMMAND clears boot_targets first. A non-empty boot_targets overrides the
#   device-tree bootdev-order, and unlike the ENV_IS_NOWHERE variant this stage's
#   env persists in eMMC, so a value left behind by a saveenv or by hand at the
#   U-Boot prompt would outlive the reboot and silently undo the eMMC-first order.
#   The assertion below pins this stage's own string.
#
# It pairs with the mos image only -- its env offsets fall inside the alpine
# image's boot partition.
set -euo pipefail

[ "$#" -eq 4 ] || {
    echo "usage: build-mos.sh <source-tree> <rkbin-dir> <ddr-blob> <bl31-blob>" >&2
    exit 1
}
SRC="$1"
RKBIN="$2"
DDR="${RKBIN}/bin/rk35/$3"
BL31="${RKBIN}/bin/rk35/$4"

cd "${SRC}"

scripts/config --disable ENV_IS_NOWHERE \
               --enable ENV_IS_IN_MMC \
               --set-val ENV_OFFSET 0x1000000 \
               --set-val ENV_SIZE 0x10000 \
               --enable ENV_REDUNDANT \
               --set-val ENV_OFFSET_REDUND 0x1100000 \
               --set-val ENV_MMC_DEVICE_INDEX 0 \
               --set-val ENV_MMC_EMMC_HW_PARTITION 0 \
               --enable SAVEENV --enable CMD_SAVEENV \
               --enable CMD_SETEXPR --enable CMD_SOURCE --enable CMD_IMPORTENV \
               --enable CMD_CRC32 --enable CRC32_VERIFY \
               --enable CMD_FS_GENERIC --enable CMD_FAT --enable CMD_BOOTI --enable CMD_PART \
               --enable LEGACY_IMAGE_FORMAT --enable HUSH_PARSER \
               --disable ENV_MMC_USE_DT --disable ENV_MMC_USE_SW_PARTITION \
               --disable PARTITION_TYPE_GUID \
               --set-str BOOTCOMMAND "setenv boot_targets; bootmeth order script; bootflow scan -lb; echo BOOT FAILED - entering rockusb; rockusb 0 mmc 0"

make olddefconfig

# The two ENV_MMC_* values place the redundant env on the eMMC user area; if
# olddefconfig ever drops them (v2026.07 spellings per
# docs/design/uboot-ab-handshake.md 1.2, env/Kconfig:738,748) the env silently
# lands on the default MMC device -- so their absence must be red. CRC32_VERIFY
# is in the same list for the same reason and a sharper consequence: it is
# `default n`, so it is exactly the kind of symbol an olddefconfig drops, and a
# blob without it refuses BOTH slots on the first boot rather than misbehaving
# quietly.
for line in \
    CONFIG_ENV_IS_IN_MMC=y \
    CONFIG_ENV_OFFSET=0x1000000 \
    CONFIG_ENV_SIZE=0x10000 \
    CONFIG_ENV_REDUNDANT=y \
    CONFIG_ENV_OFFSET_REDUND=0x1100000 \
    CONFIG_ENV_MMC_DEVICE_INDEX=0 \
    CONFIG_ENV_MMC_EMMC_HW_PARTITION=0 \
    CONFIG_CMD_SETEXPR=y \
    CONFIG_CMD_SAVEENV=y \
    CONFIG_CMD_CRC32=y \
    CONFIG_CRC32_VERIFY=y \
    CONFIG_HUSH_PARSER=y; do
    grep -q "^${line}$" .config || {
        echo "ERROR: ${line} missing from mos .config" >&2
        exit 1
    }
done

grep -q '^CONFIG_BOOTCOMMAND="setenv boot_targets; bootmeth order script; bootflow scan -lb; echo BOOT FAILED - entering rockusb; rockusb 0 mmc 0"' .config || {
    echo "ERROR: this stage's own BOOTCOMMAND is not what landed in the mos .config" >&2
    exit 1
}

for sym in CONFIG_ENV_IS_NOWHERE CONFIG_ENV_MMC_USE_DT \
           CONFIG_ENV_MMC_USE_SW_PARTITION CONFIG_PARTITION_TYPE_GUID; do
    if grep -q "^${sym}=y" .config; then
        echo "ERROR: ${sym}=y would relocate the env off the pinned offsets" >&2
        exit 1
    fi
done

make -j"$(nproc)" CROSS_COMPILE=aarch64-linux-gnu- \
    ROCKCHIP_TPL="${DDR}" BL31="${BL31}"

# Textual check only, as in build.sh: it does not bind the mmc0 alias to the eMMC
# controller (needs hardware; recorded no-action). This stage rebuilds
# u-boot.dtb, so bootdev-order is re-asserted here: the one property mos
# deliberately diverges from upstream on (eMMC first, SD as fallback) and the one
# that ships in the mos A/B image. build.sh's LED and SD-power assertions are not
# repeated, because this stage edits no DTS and the nodes they cover are
# unchanged by scripts/config.
[ "$(fdtget u-boot.dtb /bootstd bootdev-order)" = "mmc0 mmc1 usb" ]

ls -la u-boot-rockchip.bin spl/u-boot-spl.bin u-boot.itb
