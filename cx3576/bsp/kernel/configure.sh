#!/usr/bin/env bash
# mica-build-side: container -- kconfig and `make olddefconfig` run in the BSP
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
# only form of boot/common/mos-required.fragment's floor that survives into an
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
    echo "error: ${FRAGMENT} does not exist. It arrives through the mos-common build context that bsp/Makefile wires up; a bare \`docker buildx build\` without it fails here rather than building a kernel with no shared floor" >&2
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
#
# THE BOOT LOGO is the fourth group, and it is a board decision rather than a
# shared one: this board has an HDMI output that shows a login prompt otherwise,
# and PLAN-088 turns that into a logo. CLUT224 is the only variant kept --
# fb_find_logo picks by colour depth and this board's fbdev is never below 8
# bits, so LOGO_LINUX_MONO and LOGO_LINUX_VGA16 (both `default y` under LOGO)
# would compile two bitmaps nothing can select.
scripts/config --disable LOCALVERSION_AUTO \
               --disable WL_ROCKCHIP --disable WIFI_BUILD_MODULE \
               --disable AP6XXX --disable BCMDHD \
               --disable BCMDHD_SDIO --disable BCMDHD_PCIE \
               --enable RFKILL_RK \
               --enable RTC_DRV_HYM8563 \
               --enable LEDS_TRIGGERS \
               --enable LEDS_TRIGGER_HEARTBEAT \
               --disable MALI400 --disable TEE --disable OPTEE \
               --disable ARM_SCMI_TRANSPORT_OPTEE --disable HW_RANDOM_OPTEE \
               --enable AUTOFS_FS \
               --enable LOGO \
               --enable LOGO_LINUX_CLUT224 \
               --disable LOGO_LINUX_MONO \
               --disable LOGO_LINUX_VGA16 \
               --set-str AIC_FW_PATH "/lib/firmware"

env "${CROSS[@]}" scripts/kconfig/merge_config.sh -m .config "${FRAGMENT}"
make "${CROSS[@]}" olddefconfig

for option in WATCHDOG_NOWAYOUT WATCHDOG_SYSFS DW_WATCHDOG CMDLINE_FORCE; do
    grep -qx "CONFIG_${option}=y" .config || { echo "missing signed-boot requirement: ${option}" >&2; exit 1; }
done
grep -q '^CONFIG_CMDLINE=".*dm_verity.require_signatures=1' .config

# THE TRUST ANCHOR, and the two ways it goes wrong. The value is a string, so
# the fragment loop at the bottom of this file -- which reads =y lines only --
# cannot see it, exactly as it cannot see the LSM list. An empty value builds a
# kernel whose .builtin_trusted_keys keyring is empty, so every root-hash
# signature fails to find an issuer at the first boot rather than here; a value
# naming a file that the mos-trust build context did not deliver fails in the
# middle of the compile, at extract-cert.
trusted_keys="$(grep '^CONFIG_SYSTEM_TRUSTED_KEYS=' "${FRAGMENT}")"
[ -n "${trusted_keys}" ] || {
    echo "error: ${FRAGMENT} declares no CONFIG_SYSTEM_TRUSTED_KEYS, so this assertion has nothing to compare and would pass over a kernel that trusts nothing" >&2
    exit 1
}
require "^${trusted_keys}$"
anchor="$(printf '%s' "${trusted_keys}" | sed 's/^CONFIG_SYSTEM_TRUSTED_KEYS=//; s/^"//; s/"$//')"
[ -s "${anchor}" ] || {
    echo "error: ${trusted_keys} names ${anchor}, which does not exist in the kernel tree. certs/Makefile resolves that path against the source tree; the compile would fail at extract-cert" >&2
    exit 1
}
grep -q 'BEGIN CERTIFICATE' "${anchor}" || {
    echo "error: ${anchor} is not a PEM certificate. The mos-trust build context delivered something else, and extract-cert would refuse it in the middle of the compile" >&2
    exit 1
}
echo "config: ${trusted_keys} ($(stat -c%s "${anchor}") bytes)"

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

# THE LOGO, AND THE SYMBOL THAT WOULD SILENTLY SUPPRESS IT. Both halves matter
# and only the first is obvious. CONFIG_LOGO_LINUX_CLUT224 is what
# drivers/video/logo/Makefile turns this board's logo_linux_clut224.ppm into an
# object; without it the PPM the Dockerfile stages is compiled by nothing and
# the screen stays blank with every other check green.
#
# FRAMEBUFFER_CONSOLE_DEFERRED_TAKEOVER is refused rather than merely left
# alone. It is off today, but "off" and "decided to be off" are different
# facts, and this one is worth pinning: fbcon's deferred path sets
# logo_shown = FBCON_LOGO_DONTSHOW BEFORE it registers the framebuffers
# (fbcon.c:3338-3340), so turning it on -- which reads like protection for the
# logo, and is exactly that for a firmware-painted one -- means this logo is
# never drawn at all. PLAN-088 section 2.1 carries the measurement.
require '^CONFIG_LOGO=y'
require '^CONFIG_LOGO_LINUX_CLUT224=y'
refuse '^CONFIG_FRAMEBUFFER_CONSOLE_DEFERRED_TAKEOVER=y'

# THE BOARD'S OWN OPTIONS, AND NOTHING ELSE. This loop used to restate 19
# symbols that boot/common/mos-required.fragment now pins -- BRIDGE, VETH, the
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

require '^CONFIG_AUTOFS_FS=y'
require '^CONFIG_ARM_SCMI_TRANSPORT_SMC=y'
require '^CONFIG_MALI_BIFROST=y'
for option in MALI400 TEE OPTEE ARM_SCMI_TRANSPORT_OPTEE HW_RANDOM_OPTEE; do
    refuse "^CONFIG_${option}=[ym]"
done
