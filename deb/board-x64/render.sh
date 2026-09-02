#!/usr/bin/env bash
# Render the x64 board's configuration files for the mos-board-x64 package.
#
#   bash render.sh <src-root> <out-dir>
#
#   <src-root>/boards/x64/board.env
#   <src-root>/boards/x64/overlay/etc/systemd/system/boot.mount.in
#   <src-root>/rootfs/overlay/etc/fstab.in
#   <src-root>/pkgs/rauc/render-config.sh
#     -> <out-dir>/fstab, <out-dir>/boot.mount, <out-dir>/system.conf
#
# Runs INSIDE the producer's packing stage, from boards/x64/deb/board-x64/Dockerfile,
# not on the host. The rendered files are generated artifacts: rendering them
# on the host would either write them into the worktree -- where a committed
# rendering drifts from its template, which is the reason
# pkgs/rauc/render-config.sh's output is gitignored -- or make the package
# depend on a host step `bash build-env/deb/build.sh` does not
# run. <src-root> is therefore a reconstruction of the repository layout inside
# the build, and not a checkout.
#
# WHAT THIS SHARES WITH rootfs/build.sh AND WHAT IT DOES NOT. The RAUC
# configuration is not rendered here at all: render-config.sh is INVOKED, so
# the template, the statusfile placement and the boot-attempts refusal have one
# owner. The two overlay templates have no such renderer -- build.sh renders
# them inline, in the middle of a build that also stages an image -- so their
# rules are restated here: the same lowercased PARTUUIDs, the same VAR_OPTS,
# the same /mnt/data line, and the same refusal to emit a file with a placeholder
# left in it.
set -euo pipefail

die() {
    echo "render.sh: error: $*" >&2
    exit 1
}

SRC="${1-}"
OUT="${2-}"
[ -n "${SRC}" ] && [ -n "${OUT}" ] ||
    die "usage: render.sh <src-root> <out-dir>"

BOARD=x64
BOARD_ENV="${SRC}/boards/${BOARD}/board.env"
FSTAB_IN="${SRC}/rootfs/overlay/etc/fstab.in"
BOOT_MOUNT_IN="${SRC}/boards/${BOARD}/overlay/etc/systemd/system/boot.mount.in"
RENDER_CONFIG="${SRC}/pkgs/rauc/render-config.sh"
for f in "${BOARD_ENV}" "${FSTAB_IN}" "${BOOT_MOUNT_IN}" "${RENDER_CONFIG}"; do
    [ -f "${f}" ] || die "${f} does not exist"
done
mkdir -p "${OUT}"

# board.env is THE source of truth and is sourced, never grepped: it carries
# `$((...))` arithmetic and one `${MOS_VAR_MIB}` alias, so a line-wise parser
# would read those verbatim and a hand-copied GUID would be a second copy that
# can disagree with it.
# shellcheck source=../../board.env
. "${BOARD_ENV}"

# Named rather than left to `set -u`, which would report the shell's own
# "unbound variable" from inside a sed argument list.
missing=""
for key in DATA_GUID STATE_GUID META_GUID EPHEMERAL_GUID ESP_GUID; do
    eval "value=\${$key:-}"
    [ -n "${value}" ] || missing="${missing} ${key}"
done
[ -z "${missing}" ] || die "${BOARD_ENV} is missing:${missing}"

# Lowercase, for the reason rootfs/build.sh gives: udev derives
# /dev/disk/by-partuuid/ from libblkid, which formats GUIDs in lowercase, and
# systemd's fstab-generator resolves PARTUUID= through those symlinks without
# normalising case.
lower() { echo "$1" | tr 'A-Z' 'a-z'; }

render() {
    local src="$1" dst="$2"
    shift 2
    local expr=()
    while [ "$#" -gt 0 ]; do
        expr+=(-e "s|@$1@|$2|g")
        shift 2
    done
    sed "${expr[@]}" "${src}" >"${dst}"
    # `grep -c ... >/dev/null` and not `grep -q`: this file sets pipefail, and
    # tests/shell-pipefail-lint.sh flags the early-exiting form.
    if grep -c '@[A-Z_]\+@' "${dst}" >/dev/null; then
        echo "render.sh: error: unrendered placeholder left in ${dst}:" >&2
        grep -n '@[A-Z_]\+@' "${dst}" >&2
        exit 1
    fi
}

# The RAUC system configuration, rendered by the script that owns the template.
# SYSTEM_CONF_OUT redirects it out of the overlay tree it writes by default:
# here that tree is the reconstruction above, and the package stages this file
# rather than a copy of the overlay.
MOS_BOARD="${BOARD}" SYSTEM_CONF_OUT="${OUT}/system.conf" bash "${RENDER_CONFIG}"
[ -s "${OUT}/system.conf" ] ||
    die "${RENDER_CONFIG} produced no system.conf for ${BOARD}"

# /mnt/data is the only filesystem that grows and /var must NOT carry
# x-systemd.growfs: it is fixed-size disposable residue. Tab-separated, the
# shape build.sh emits, so the two renderings can be compared byte for byte.
printf -v DATA_LINE 'PARTUUID=%s\t/mnt/data\text4\tnoatime,x-systemd.growfs\t0\t2' \
    "$(lower "${DATA_GUID}")"
VAR_OPTS="noatime"

render "${FSTAB_IN}" "${OUT}/fstab" \
    EPHEMERAL_GUID "$(lower "${EPHEMERAL_GUID}")" \
    STATE_GUID "$(lower "${STATE_GUID}")" \
    META_GUID "$(lower "${META_GUID}")" \
    VAR_OPTS "${VAR_OPTS}" \
    DATA_LINE "${DATA_LINE}"

# No /etc/fw_env.config, and its absence is the statement: there is no U-Boot
# on this board, and that template names two partitions boards/x64/board.env
# does not create. build.sh deletes it on MOS_ARCH=amd64 for the same
# reason; a producer that rendered it anyway would put a configuration file
# describing storage that does not exist into a signed root.

# /boot is a mountpoint on x64 and not on cx3576 because RAUC's grub backend
# runs `grub-editenv <path>` on a file while the U-Boot backend writes a raw
# partition -- so the ESP has to be mounted here and nowhere there.
render "${BOOT_MOUNT_IN}" "${OUT}/boot.mount" \
    ESP_GUID "$(lower "${ESP_GUID}")"

echo "render.sh: ${BOARD} -> fstab, boot.mount, system.conf in ${OUT}"
