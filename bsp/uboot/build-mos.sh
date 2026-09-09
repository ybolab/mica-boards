#!/usr/bin/env bash
# mos-build-side: container -- fixed signed FIT policy and public boot anchor.
set -euo pipefail
[ "$#" -eq 5 ] || { echo 'usage: build-mos.sh SOURCE RKBIN DDR BL31 PUBLIC_CERTIFICATE' >&2; exit 1; }
SRC="$1"
DDR="$2/bin/rk35/$3"
BL31="$2/bin/rk35/$4"
CERTIFICATE="$5"
TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SRC"
! grep -q 'PRIVATE KEY' "$CERTIFICATE"
scripts/config --enable MOS_FILE_BOOT --enable ENV_IS_NOWHERE \
    --disable BOOTSTD --disable BOOTSTD_DEFAULTS --disable DISTRO_DEFAULTS \
    --enable EFI_PARTITION --enable SUPPORT_RAW_INITRD \
    --disable ENV_IS_IN_MMC --disable ENV_REDUNDANT --disable ENV_REDUNDANT_UPGRADE \
    --disable SAVEENV --disable CMD_SAVEENV --disable CMD_SOURCE --disable CMD_IMPORTENV \
    --disable CMD_BOOTI --disable LEGACY_IMAGE_FORMAT --disable USE_PREBOOT \
    --disable USE_BOOTCOMMAND --set-val BOOTDELAY -2 \
    --enable FIT --enable FIT_SIGNATURE --enable FIT_FULL_CHECK \
    --enable IMAGE_SIGN_INFO --enable RSA --enable RSA_VERIFY --enable CMD_BOOTM \
    --enable FS_EXT4 --enable WDT --enable WATCHDOG --enable DESIGNWARE_WATCHDOG \
    --set-val WATCHDOG_TIMEOUT_MSECS 120000
make olddefconfig
for symbol in MOS_FILE_BOOT ENV_IS_NOWHERE FIT FIT_SIGNATURE FIT_FULL_CHECK \
    IMAGE_SIGN_INFO RSA RSA_VERIFY CMD_BOOTM FS_EXT4 WDT WATCHDOG DESIGNWARE_WATCHDOG; do
    grep -qx "CONFIG_${symbol}=y" .config || { echo "error: missing ${symbol}" >&2; exit 1; }
done
for symbol in ENV_IS_IN_MMC ENV_REDUNDANT_UPGRADE CMD_SAVEENV CMD_SOURCE CMD_BOOTI LEGACY_IMAGE_FORMAT USE_PREBOOT; do
    if grep -qx "CONFIG_${symbol}=y" .config; then echo "error: forbidden ${symbol}" >&2; exit 1; fi
done
make -j8 CROSS_COMPILE=aarch64-linux-gnu- ROCKCHIP_TPL="$DDR" BL31="$BL31"
bash "$TOOLS_DIR/embed-trust.sh" u-boot.dtb "$CERTIFICATE" mos-control.dtb "$SRC/tools"
make -j8 CROSS_COMPILE=aarch64-linux-gnu- ROCKCHIP_TPL="$DDR" BL31="$BL31" EXT_DTB="$SRC/mos-control.dtb"
cmp u-boot.dtb mos-control.dtb
[ "$(stat -c%s u-boot-rockchip.bin)" -le 16744448 ]
aarch64-linux-gnu-nm u-boot | grep -c ' T mos_file_boot$' >/dev/null
cp .config mos.config
printf '%s\n' 'MOS_SIGNED_FIT_FIRMWARE_BUILD_PASS'
