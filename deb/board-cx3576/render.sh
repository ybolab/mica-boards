#!/usr/bin/env bash
# Stage the BSP-dependent inputs of mos-board-cx3576 into ${MOS_DEB_STAGE}.
#
# This is the producer's PREPARE hook, named in boards/cx3576/deb/board-cx3576/producer.env
# and run by the driver -- it is not an entry point and does not build anything:
#
#   [BOARD_DIR=...] bash build-env/deb/build.sh \
#       --producer board-cx3576 --arch arm64
#
# The driver empties ${MOS_DEB_STAGE}, exports the hook environment
# build-env/deb/README.md documents, runs this script on the HOST
# before any container is started, and then hands the directory to the build as
# the `bin` context.
#
# Three things force a host-side step here, and no other producer in the family
# needed one:
#
#   - BOARD_DIR and BSP_OUT. BOARD_DIR is the bsp SOURCE directory
#     (${BOARD_DIR:-boards/<b>/bsp}) and BSP_OUT is where that board's build
#     products are (${BSP_OUT:-_out/boards/<b>}); rootfs/build.sh accepts the
#     first and this producer accepts both. A build context in producer.env is
#     a fixed repository-relative path -- that file is plain KEY=value with no
#     expansion, deliberately -- so a directory chosen by an environment
#     variable cannot be named there.
#   - The refusal. A missing BSP input must be reported BEFORE anything is
#     built; inside the Dockerfile it would be reported after buildkit has
#     already resolved the base, transferred the contexts and started a stage.
#   - pkgs/rauc/render-config.sh, which is INVOKED rather than reimplemented
#     or copied from. It derives its own repository root from its location and
#     reads three files this producer does not own, so it runs where the
#     repository is: here.
#
# Everything that is a function of committed content alone -- the hwinit split,
# the firmware selection, the modules unpack, the payload's modes and symlinks
# -- is in the Dockerfile, where the rest of the producer family keeps it.
set -euo pipefail

die() {
    echo "render.sh: error: $*" >&2
    exit 1
}

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# TWO hops to the board, not one. A producer's NAME is its directory's
# basename -- that is what `make os-deb-<name>` selects on and what refuses a
# duplicate -- so this producer is boards/<board>/deb/board-<board>/ and not
# boards/<board>/deb/, whose basename `deb` both boards would have claimed.
# The board directory is therefore the grandparent: deb/ in between holds the
# board's producers and nothing else.
BOARD_ROOT="$(cd "${HERE}/../.." && pwd)"
REPO_ROOT="$(cd "${BOARD_ROOT}/../.." && pwd)"
# The board is this producer's LOCATION, not a constant written down twice: the
# directory that holds board.env is the one this script is nested under.
MOS_BOARD="$(basename "${BOARD_ROOT}")"
LAYOUT_ENV="${BOARD_ROOT}/board.env"

# The staging directory belongs to the driver: it creates it empty, hands it to
# the build as `bin` and refuses a hook that leaves it that way. So this script
# neither chooses the path nor clears it -- it only fills it, and a run outside
# the driver has no stage to fill.
#
# In PRE-FLIGHT MODE there is no stage and none is required: the mode exists to
# report what is missing before anything is built, so a hook that demanded
# somewhere to write would be demanding a build have started.
STAGE="${MOS_DEB_STAGE:-}"
if [ "${MOS_DEB_PREFLIGHT:-0}" = 0 ]; then
    [ -n "${STAGE}" ] ||
        die "MOS_DEB_STAGE is unset. This is a PREPARE hook: build-env/deb/build.sh exports the directory to stage into and passes it to the build as the 'bin' context. Run the producer through the driver -- bash build-env/deb/build.sh --producer board-${MOS_BOARD} --arch arm64"
    [ -d "${STAGE}" ] ||
        die "MOS_DEB_STAGE=${STAGE} is not a directory"
fi

[ -f "${LAYOUT_ENV}" ] ||
    die "${LAYOUT_ENV} does not exist. Every value this producer renders or selects is read from it; there is no default for any of them"
# shellcheck source=../../board.env
. "${LAYOUT_ENV}"

# The same override rootfs/build.sh accepts, spelled the same way. BOARD_DIR is
# the bsp SOURCE directory: committed vendor firmware, containers.env, the
# Makefile. Build products are not in it.
BOARD_DIR="${BOARD_DIR:-${BOARD_ROOT}/bsp}"
BSP_MAKEFILE="${BOARD_ROOT}/bsp/Makefile"

# THE BUILD PRODUCTS, which since RFCT-343 live under _out/ with everything else
# this repository builds instead of in an `out/` hidden beside the Makefile. The
# two were one variable before, and that is why "point BOARD_DIR at prebuilt
# artefacts" also repointed the committed firmware.
#
# This default and the `BSP_OUT ?=` in boards/<board>/bsp/Makefile are the same
# path written twice, which is the one duplication the move could not avoid:
# make cannot export a default into a hook the deb driver runs before make is
# involved. They are not free to drift silently -- bsp_target_for below reads
# the Makefile's own text, so a Makefile that stopped writing there stops
# naming a target and require_bsp says so.
BSP_OUT="${BSP_OUT:-${REPO_ROOT}/_out/boards/${MOS_BOARD}}"

# The command that produces a missing BSP artifact, READ OUT OF the BSP
# Makefile rather than written down here. `kernel` and `uboot-mos` are that
# file's target names; a second copy of them in this message is a copy that
# starts naming a target nobody has the day one is renamed, and the whole point
# of the message is that it can be pasted into a shell.
#
# It matches the LITERAL, UNEXPANDED Makefile text `-o $(BSP_OUT)/<subdir> `,
# because that is what the file contains -- awk is reading make source, not
# running it. The trailing space is what stops `uboot` matching the
# `uboot-mos` recipe.
bsp_target_for() {
    awk -v want="-o \$(BSP_OUT)/$1 " '
        /^[a-zA-Z][a-zA-Z0-9_.-]*:/ { target = substr($0, 1, index($0, ":") - 1) }
        target != "" && index($0, want) > 0 { print target; exit }
    ' "${BSP_MAKEFILE}"
}

# Every missing input is collected and reported TOGETHER. Reporting the first
# one alone sends a reader through two ten-minute builds to learn that the
# second was missing as well.
#
# EXAMINED is what was looked at, missing or not, and it is what this hook
# reports to build-env/deb/preflight.sh under the pre-flight contract at the
# bottom of this block. A run that found nothing missing because it looked at
# nothing -- a board.env that stopped declaring boot inputs, firmware or a
# U-Boot variant -- prints the same "all present" as a complete one, and the
# count is the only thing that tells the two apart.
MISSING=()
EXAMINED=0
require_bsp() {
    local path="$1" out_subdir="$2"
    EXAMINED=$((EXAMINED + 1))
    [ ! -f "${path}" ] || return 0
    local target
    target="$(bsp_target_for "${out_subdir}")"
    [ -n "${target}" ] ||
        die "no target in ${BSP_MAKEFILE} writes out/${out_subdir}, so this script cannot name the command that produces ${path}. Either the Makefile's output directories moved or ${LAYOUT_ENV} names a variant that is not built there"
    MISSING+=("error: ${path} not found.
Build it with 'make -C boards/${MOS_BOARD}/bsp ${target}' or point BSP_OUT at a
tree that already has them, e.g. BSP_OUT=/srv/mos/_out/boards/${MOS_BOARD}")
}

# The boot inputs the finalizer consumes, derived from the board's own boot-slot
# declaration. BOOT_SLOT_REQUIRED_FILES is what a slot must CONTAIN; two of its
# entries are BSP artifacts and two are made during assembly, so they are
# separated by what produces them rather than by name:
#   @SLOT@       -- the per-slot verity parameters, written by the assembler
#   BOOT_SCRIPT_NAME -- compiled from BOOT_CMD_SOURCE, which is staged below
BOOT_INPUTS=""
for f in ${BOOT_SLOT_REQUIRED_FILES}; do
    case "${f}" in
    *'@SLOT@'*) continue ;;
    "${BOOT_SCRIPT_NAME}") continue ;;
    esac
    BOOT_INPUTS="${BOOT_INPUTS} ${f}"
    require_bsp "${BSP_OUT}/kernel/${f}" kernel
done
[ -n "${BOOT_INPUTS# }" ] ||
    die "${LAYOUT_ENV} declares BOOT_SLOT_REQUIRED_FILES=\"${BOOT_SLOT_REQUIRED_FILES}\" and none of it is a BSP artifact. The package would carry no kernel and no device tree for the finalizer to export"

UBOOT_BIN="${BSP_OUT}/${UBOOT_VARIANT_DIR}/${UBOOT_BIN_NAME}"
require_bsp "${UBOOT_BIN}" "${UBOOT_VARIANT_DIR}"
MODULES_TAR="${BSP_OUT}/kernel/modules.tar"
require_bsp "${MODULES_TAR}" kernel

# The resolved kernel config and the release that names it. Both are outputs of
# the same BSP kernel build as modules.tar, and they are required rather than
# optional: the image contract asserts boards/common/mos-required.fragment's
# floor by reading /boot/config-<release> back out of the packed root, and a
# board that staged no config would make that assertion have nothing to read.
# require_bsp is what makes an out/kernel predating RFCT-343 a refusal naming
# `make -C boards/cx3576/bsp kernel`, rather than a package silently missing the
# only file that check has a subject in.
KERNEL_CONFIG="${BSP_OUT}/kernel/config"
require_bsp "${KERNEL_CONFIG}" kernel
KERNEL_RELEASE_FILE="${BSP_OUT}/kernel/kernel.release"
require_bsp "${KERNEL_RELEASE_FILE}" kernel

# Firmware is committed vendor content rather than a build product, so a
# missing file is not answered with a make target. The shape of the message is
# rootfs/build.sh's for the same failure.
for fw in ${BOARD_FIRMWARE_FILES}; do
    case "${fw}" in
    /usr/lib/firmware/*) ;;
    *) die "${LAYOUT_ENV} declares BOARD_FIRMWARE_FILES entry '${fw}', which is not under /usr/lib/firmware/. The entries are INSTALLED paths -- the package stages each one at the path it declares, and the verification suite checks the image for the same" ;;
    esac
    fw_src="${BOARD_DIR}/rootfs/firmware/${fw##*/}"
    EXAMINED=$((EXAMINED + 1))
    [ -f "${fw_src}" ] || MISSING+=("error: ${LAYOUT_ENV} declares ${fw} and ${fw_src} does not exist.
Firmware is committed vendor content, not a build product: it lives in the bsp
SOURCE tree, so this one follows BOARD_DIR and not BSP_OUT. Point BOARD_DIR at a
tree that has it, e.g. BOARD_DIR=/srv/mos/boards/${MOS_BOARD}/bsp")
done

BOOT_CMD="${REPO_ROOT}/${BOOT_CMD_SOURCE}"
EXAMINED=$((EXAMINED + 1))
[ -f "${BOOT_CMD}" ] || MISSING+=("error: ${LAYOUT_ENV} declares BOOT_CMD_SOURCE=${BOOT_CMD_SOURCE} and ${BOOT_CMD} does not exist.")

# Before anything is written into the stage. The driver refuses a hook that
# leaves ${MOS_DEB_STAGE} empty, so exiting here leaves the producer refused
# with this message on the terminal and the build never reached.
if [ "${#MISSING[@]}" -gt 0 ]; then
    printf '%s\n\n' "${MISSING[@]}" >&2
    echo "render.sh: refusing to build mos-board-cx3576: ${#MISSING[@]} of ${EXAMINED} examined BSP inputs are missing (BOARD_DIR=${BOARD_DIR}, BSP_OUT=${BSP_OUT}). Nothing was staged and no container was started." >&2
    # The pre-flight contract on the FAILING side, which is the side whose
    # numbers get read: build-env/deb/preflight.sh adds them into its own
    # totals, and without them one producer's four missing files would arrive
    # there as one report and be counted once.
    #
    # preflight-warned is ZERO HERE AND ON THE OTHER PATH, and writing the zero
    # is the point. A BSP artefact is a kernel or a U-Boot compile: nothing in
    # `make os-debs` produces one, so every input this hook examines is either
    # present or missing and none of them is a cost the run could absorb. That
    # is a fact about this producer, and an omitted count would say instead
    # that this hook has not been taught the category.
    if [ "${MOS_DEB_PREFLIGHT:-0}" != 0 ]; then
        echo "preflight-examined: ${EXAMINED}" >&2
        echo "preflight-missing: ${#MISSING[@]}" >&2
        echo "preflight-warned: 0" >&2
    fi
    exit 1
fi

# THE PRE-FLIGHT CONTRACT. build-env/deb/preflight.sh runs this hook with
# MOS_DEB_PREFLIGHT=1 before `make os-debs` starts anything, so that a missing
# BSP artefact is reported beside every other producer's missing input instead
# of after the producers ahead of this one have already been packed.
#
# It stops HERE rather than repeating the checks in that script, and that is
# the point of the mode: which files this board needs is a function of
# board.env and of BOARD_DIR, both of which are read above. A second list of
# them somewhere else would be the copy that stayed green the day the board
# declared another one.
#
# The counts are the contract's other half; preflight.sh refuses a hook that
# claims success without them. Nothing is missing on this path, and nothing is
# ever warned by this hook -- see the refusal above for why.
if [ "${MOS_DEB_PREFLIGHT:-0}" != 0 ]; then
    echo "preflight-examined: ${EXAMINED}"
    echo "preflight-missing: 0"
    echo "preflight-warned: 0"
    echo "render.sh: pre-flight found all ${EXAMINED} BSP inputs of mos-board-cx3576 present (BOARD_DIR=${BOARD_DIR}, BSP_OUT=${BSP_OUT})"
    exit 0
fi

mkdir -p "${STAGE}/etc/rauc" "${STAGE}/firmware" "${STAGE}/boot"

# board.env travels with the staged inputs so the Dockerfile reads THE FILE
# rather than a set of build arguments this script would have had to transcribe
# key by key. A whole-file copy cannot disagree with its source.
cp "${LAYOUT_ENV}" "${STAGE}/board.env"

# The rendering, exactly as rootfs/build.sh does it. lower() and render()
# are that script's, including the refusal to emit a file with a placeholder
# left in it; DATA_LINE and VAR_OPTS are its values.
#
# PARTUUIDs are lowercased because udev derives /dev/disk/by-partuuid/ from
# libblkid's lowercase GUID formatting and systemd's fstab-generator resolves
# PARTUUID= through those symlinks without normalising case.
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
    chmod 0644 "${dst}"
    if grep -c '@[A-Z_]\+@' "${dst}" >/dev/null; then
        echo "error: unrendered placeholder left in ${dst}" >&2
        grep -n '@[A-Z_]\+@' "${dst}" >&2
        exit 1
    fi
}

OVERLAY_SRC="${REPO_ROOT}/rootfs/overlay"
DATA_LINE="PARTUUID=$(lower "${DATA_GUID}")	/mnt/data	ext4	noatime,x-systemd.growfs	0	2"
VAR_OPTS="noatime"
render "${OVERLAY_SRC}/etc/fstab.in" "${STAGE}/etc/fstab" \
    EPHEMERAL_GUID "$(lower "${EPHEMERAL_GUID}")" \
    STATE_GUID "$(lower "${STATE_GUID}")" \
    META_GUID "$(lower "${META_GUID}")" \
    VAR_OPTS "${VAR_OPTS}" \
    DATA_LINE "${DATA_LINE}"
render "${OVERLAY_SRC}/etc/fw_env.config.in" "${STAGE}/etc/fw_env.config" \
    UENV_A_GUID "$(lower "${UENV_A_GUID}")" \
    UENV_B_GUID "$(lower "${UENV_B_GUID}")" \
    UENV_SIZE_HEX "$(printf '0x%x' "${UENV_SIZE_BYTES}")"

# The RAUC system configuration is that renderer's output, not a second
# rendering of its template: it owns the statusfile placement, the boot-attempts
# radix range and the fw_env.config cross-checks, and every one of those is an
# assertion this producer wants run. SYSTEM_CONF_OUT is the script's own
# override, which keeps the generated file out of rootfs/overlay -- that
# copy belongs to the image build, and a package producer must not move it.
MOS_BOARD="${MOS_BOARD}" SYSTEM_CONF_OUT="${STAGE}/etc/rauc/system.conf" \
    bash "${REPO_ROOT}/pkgs/rauc/render-config.sh"
[ -s "${STAGE}/etc/rauc/system.conf" ] ||
    die "pkgs/rauc/render-config.sh produced no system.conf to stage"

for fw in ${BOARD_FIRMWARE_FILES}; do
    cp "${BOARD_DIR}/rootfs/firmware/${fw##*/}" "${STAGE}/firmware/${fw##*/}"
done
cp "${MODULES_TAR}" "${STAGE}/modules.tar"
cp "${KERNEL_CONFIG}" "${STAGE}/config"
cp "${KERNEL_RELEASE_FILE}" "${STAGE}/kernel.release"
for f in ${BOOT_INPUTS}; do
    cp "${BSP_OUT}/kernel/${f}" "${STAGE}/boot/${f}"
done
cp "${UBOOT_BIN}" "${STAGE}/boot/${UBOOT_BIN_NAME}"
cp "${BOOT_CMD}" "${STAGE}/boot/${BOOT_CMD_SOURCE##*/}"
chmod 0644 "${STAGE}"/firmware/* "${STAGE}"/boot/* "${STAGE}/modules.tar" \
    "${STAGE}/config" "${STAGE}/kernel.release" "${STAGE}/board.env"

echo "render.sh: staged BSP inputs from ${BOARD_DIR} and ${BSP_OUT} into ${STAGE}"
