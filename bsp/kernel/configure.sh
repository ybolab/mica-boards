#!/usr/bin/env bash
# mos-build-side: container -- kconfig and `make olddefconfig` run in the BSP
# builder image against the vendor tree fetched there; no kernel configuration
# happens on the host.
#
# Resolve the CX3576-Z kernel configuration and prove the result carries the
# floor, before anything is compiled.
#
#   configure.sh <source-tree> <mos-required-fragment>
#
# THE OUTPUT IS AN ARTEFACT. The .config this leaves behind is exported by
# kernel/Dockerfile's artifact stage and packaged as /boot/config-<release>, and
# verify/src/checks-kernel.ts reads it back out of the packed root. It is the
# only form of boards/common/mos-required.fragment's floor that survives into an
# assembled image, which is why the assertions below are on the RESOLVED config
# and not on the committed input.
set -euo pipefail

[ "$#" -eq 2 ] || {
    echo "usage: configure.sh <source-tree> <mos-required-fragment>" >&2
    exit 1
}
SRC="$1"
FRAGMENT="$2"

[ -f "${FRAGMENT}" ] || {
    echo "error: ${FRAGMENT} does not exist. It arrives through the mos-common build context that boards/cx3576/bsp/Makefile wires up; a bare \`docker buildx build\` without it fails here rather than building a kernel with no shared floor" >&2
    exit 1
}

cd "${SRC}"
# Passed on each command line rather than exported, which is what the Dockerfile
# did before this file existed. Kbuild takes both with `?=`, so an exported value
# would also work -- but a make VARIABLE assignment outranks anything the vendor
# tree's own makefiles set and an environment variable does not, and the
# difference is only visible in the compiled bytes.
CROSS=(ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-)

require() {
    grep -q "$1" .config || {
        echo "error: the resolved .config does not match: $1" >&2
        exit 1
    }
}
refuse() {
    ! grep -q "$1" .config || {
        echo "error: the resolved .config matches, and must not: $1" >&2
        exit 1
    }
}

# THE BOARD'S OWN DELTAS over the committed vendor config. The three groups are
# the vendor Wi-Fi stack turned off (this board's radio is the AIC8800 and the
# Broadcom/Rockchip drivers fight it for the SDIO slot), the small board devices
# turned on, and the firmware path the AIC driver looks in.
#
# LOCALVERSION_AUTO is disabled for reproducibility: it appends the git
# description of the SOURCE TREE to the kernel release, and the tree here is a
# detached FETCH_HEAD with a patch series applied and not committed, so it would
# stamp "-dirty" and a hash into every module path.
scripts/config --disable LOCALVERSION_AUTO \
               --disable WL_ROCKCHIP --disable WIFI_BUILD_MODULE \
               --disable AP6XXX --disable BCMDHD \
               --disable BCMDHD_SDIO --disable BCMDHD_PCIE \
               --enable RFKILL_RK \
               --enable RTC_DRV_HYM8563 \
               --enable LEDS_TRIGGERS \
               --enable LEDS_TRIGGER_HEARTBEAT \
               --set-str AIC_FW_PATH "/lib/firmware"

env "${CROSS[@]}" scripts/kconfig/merge_config.sh -m .config "${FRAGMENT}"
make "${CROSS[@]}" olddefconfig

require "^CONFIG_SQUASHFS_ZSTD=y"
require "^CONFIG_OVERLAY_FS=y"
require "^CONFIG_MEMCG=y"
require "^CONFIG_FRAMEBUFFER_CONSOLE=y"
require "^CONFIG_DRM_FBDEV_EMULATION=y"
require "^CONFIG_AIC_WLAN_SUPPORT=y"
require '^CONFIG_AIC_FW_PATH="/lib/firmware"'
require '^CONFIG_RFKILL_RK=y'
require '^CONFIG_RTC_DRV_HYM8563=y'
require '^CONFIG_LEDS_TRIGGER_HEARTBEAT=y'
require '^# CONFIG_WL_ROCKCHIP is not set'
refuse '^CONFIG_AP6XXX='
refuse '^CONFIG_BCMDHD='

# THE BOARD'S OWN OPTIONS, AND NOTHING ELSE. This loop used to restate 19
# symbols that boards/common/mos-required.fragment now pins -- BRIDGE, VETH, the
# NF_TABLES and NFT_* core, CGROUP_BPF and the NFT_FIB family -- and the fragment
# loop below asserts every one of them against the same built .config, on both
# boards. Two lists free to disagree are one list that is not enforced, so the
# duplicates are gone and what is left is what no shared floor could state:
#
#   * this hardware -- an RK3576 with a USB gadget controller and a gadget serial
#     console, and eMMC/USB storage. A QEMU machine has none of it.
#   * the arm64 accelerated AES. The shared floor carries the generic xts(aes)
#     the crypt target resolves through and says why that is capability rather
#     than a feature; CE_BLK is this architecture's fast path for it and exists
#     on no other, which is why the floor cannot name it. x64 carries
#     CRYPTO_AES_NI_INTEL for the same reason.
#
# THE FIREWALL REMAINDER IS GONE FROM HERE TOO, and it left by two different
# routes (RFCT-304). The seven xt matches and targets moved into the shared
# fragment, because the measurement made them an engine-and-tooling fact rather
# than policy: the shipped iptables stores every extension as an nft_compat `xt`
# expression, and on a kernel without the module the rule is refused outright.
# They were =y here and absent or =m on x64, which is why `iptables -j REDIRECT`
# worked on this board and not on that one. The ten legacy IP_NF_*/IP6_NF_*
# entries are simply gone: iptables-nft builds its raw and nat tables in
# nf_tables and needs none of them -- measured, on a kernel with IP_NF_RAW unset,
# `iptables -t raw -A PREROUTING -j ACCEPT` succeeds and stores a native rule --
# and the only front-end that does need them is iptables-legacy, which nothing in
# this tree selects. Asserting them here made this board's legacy surface look
# like a requirement when it is a leftover of the vendor config.
#
# tests/netavark-kernel-config-test.sh READS THIS LOOP by name (`for option in`
# through `; do`) and requires every symbol netavark programs a rule against to
# be gated either here or by the shared fragment. It followed this loop out of
# the Dockerfile into this file under RFCT-345; the loop's shape is the contract.
for option in \
    BLK_DEV_SD CONFIGFS_FS HID_GENERIC INPUT_EVDEV \
    SCSI USB_CONFIGFS USB_CONFIGFS_ACM USB_DWC3 \
    USB_DWC3_DUAL_ROLE USB_F_ACM USB_GADGET USB_HID \
    USB_LIBCOMPOSITE USB_OTG USB_STORAGE USB_U_SERIAL \
    CRYPTO_AES_ARM64_CE_BLK; do
    grep -q "^CONFIG_${option}=y" .config || {
        echo "missing cx3576 board kernel option: CONFIG_${option}=y" >&2
        exit 1
    }
done

n=0
for line in $(sed -n 's/^\(CONFIG_[A-Z0-9_]*=y\)$/\1/p' "${FRAGMENT}"); do
    n=$((n + 1))
    grep -q "^${line}$" .config || {
        echo "missing mos-required option: ${line}" >&2
        exit 1
    }
done
# The count, because this loop is the ONLY assertion for the 28 symbols the board
# loop above stopped restating. A fragment that failed to arrive would make it
# iterate zero times and report nothing; an assertion over an empty list is green
# whatever the kernel does.
[ "${n}" -gt 0 ] || {
    echo "zero =y lines were read from ${FRAGMENT}; the shared floor asserted nothing" >&2
    exit 1
}
echo "config: all ${n} mos-required options are set"
