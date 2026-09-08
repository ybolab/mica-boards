#!/usr/bin/env bash
# Stage the selected BSP artifacts without compiling or changing the source tree.
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BOARD_ROOT=$(cd "$HERE/../.." && pwd)
REPO_ROOT=$(cd "$BOARD_ROOT/../.." && pwd)
BOARD_DIR=${BOARD_DIR:-"$BOARD_ROOT/bsp"}
BSP_OUT=${BSP_OUT:-"$REPO_ROOT/_out/boards/s905x5m"}
LAYOUT_ENV="$BOARD_ROOT/board.env"
# shellcheck source=../../board.env
. "$LAYOUT_ENV"

missing=0
examined=0
require_file() {
    examined=$((examined + 1))
    if [ ! -s "$1" ] || [ ! -f "$1" ]; then
        echo "error: missing BSP input $1; build the s905x5m kernel, U-Boot and userland first" >&2
        missing=$((missing + 1))
    fi
}
for f in Image modules.tar s7d_s905x5m_m100.dtb config kernel.release System.map; do
    require_file "$BSP_OUT/kernel/$f"
done
for f in u-boot.bin.signed u-boot.bin.sd.bin.signed DDR.USB; do
    require_file "$BSP_OUT/uboot/$f"
done
for f in $BOARD_FIRMWARE_FILES; do require_file "$BOARD_DIR/rootfs/firmware/${f##*/}"; done
for f in $BOARD_USERLAND_FILES; do require_file "$BSP_OUT/userland$f"; done
require_file "$BOARD_ROOT/boot.cmd"
require_file "$BOARD_ROOT/boot-sd.ini.in"
if [ "${MOS_DEB_PREFLIGHT:-0}" = 1 ]; then
    printf 'preflight-examined: %s\npreflight-missing: %s\npreflight-warned: 0\n' "$examined" "$missing"
    [ "$missing" -eq 0 ]
    exit $?
fi
[ "$missing" -eq 0 ] || exit 1
: "${MOS_DEB_STAGE:?run through build-env/deb/build.sh}"
STAGE=$MOS_DEB_STAGE
mkdir -p "$STAGE/etc/rauc" "$STAGE/firmware" "$STAGE/boot" "$STAGE/userland"
cp "$LAYOUT_ENV" "$STAGE/board.env"
lower() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }
render() {
    local src=$1 dst=$2
    shift 2
    local expr=()
    while [ "$#" -gt 0 ]; do expr+=(-e "s|@$1@|$2|g"); shift 2; done
    sed "${expr[@]}" "$src" >"$dst"
    if grep -q '@[A-Z_]\+@' "$dst"; then echo "error: unresolved placeholder in $dst" >&2; exit 1; fi
}
DATA_LINE="PARTUUID=$(lower "$DATA_GUID")	/mnt/data	ext4	noatime,x-systemd.growfs	0	2"
render "$REPO_ROOT/rootfs/overlay/etc/fstab.in" "$STAGE/etc/fstab" \
    EPHEMERAL_GUID "$(lower "$EPHEMERAL_GUID")" STATE_GUID "$(lower "$STATE_GUID")" \
    META_GUID "$(lower "$META_GUID")" VAR_OPTS noatime DATA_LINE "$DATA_LINE"
render "$REPO_ROOT/rootfs/overlay/etc/fw_env.config.in" "$STAGE/etc/fw_env.config" \
    UENV_A_GUID "$(lower "$UENV_A_GUID")" UENV_B_GUID "$(lower "$UENV_B_GUID")" \
    UENV_SIZE_HEX "$(printf '0x%x' "$UENV_SIZE_BYTES")"
MOS_BOARD=s905x5m SYSTEM_CONF_OUT="$STAGE/etc/rauc/system.conf" bash "$REPO_ROOT/pkgs/rauc/render-config.sh"
for f in $BOARD_FIRMWARE_FILES; do cp "$BOARD_DIR/rootfs/firmware/${f##*/}" "$STAGE/firmware/"; done
for f in modules.tar config kernel.release; do cp "$BSP_OUT/kernel/$f" "$STAGE/"; done
for f in Image s7d_s905x5m_m100.dtb; do cp "$BSP_OUT/kernel/$f" "$STAGE/boot/"; done
cp "$BOARD_ROOT/boot.cmd" "$BOARD_ROOT/boot-sd.ini.in" "$STAGE/boot/"
for f in u-boot.bin.signed u-boot.bin.sd.bin.signed DDR.USB; do cp "$BSP_OUT/uboot/$f" "$STAGE/boot/"; done
for f in $BOARD_USERLAND_FILES; do
    mkdir -p "$(dirname "$STAGE/userland$f")"
    cp "$BSP_OUT/userland$f" "$STAGE/userland$f"
done
echo "staged s905x5m BSP inputs from $BSP_OUT"
