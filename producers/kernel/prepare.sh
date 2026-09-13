#!/usr/bin/env bash
# The kernel producer's PREPARE hook: put this board's BSP outputs in
# MICA_DEB_STAGE for build-env/deb/build.sh to hand the packaging build as
# its `bin` context. See producer.env for what is staged and why nothing is
# built here.
set -euo pipefail

PREFLIGHT="${MICA_DEB_PREFLIGHT:-0}"
for v in MICA_DEB_REPO_ROOT MICA_DEB_ARCH MICA_DEB_PRODUCER; do
    [ -n "${!v:-}" ] || { echo "error: ${v} is not set. This script is producers/kernel/producer.env's PREPARE hook and is run by build-env/deb/build.sh, which sets it; it is not a standalone command" >&2; exit 1; }
done
[ "${PREFLIGHT}" != 0 ] || [ -n "${MICA_DEB_STAGE:-}" ] || { echo "error: MICA_DEB_STAGE is not set. This script is producers/kernel/producer.env's PREPARE hook and is run by build-env/deb/build.sh, which sets it" >&2; exit 1; }

REPO_ROOT="${MICA_DEB_REPO_ROOT}"
STAGE="${MICA_DEB_STAGE:-}"
# The instance: which board's bundle this run stages (build-env/deb/build.sh
# sets it from the FOR_EACH row, boards/<board>/board.env).
BOARD="${MICA_DEB_INSTANCE:?MICA_DEB_INSTANCE is not set; this hook runs once per board through the FOR_EACH producer}"
OUT="${REPO_ROOT}/_out/${BOARD}"
. "${REPO_ROOT}/boards/${BOARD}/board.env"
# The verity trust certificate the kernel embeds (bsp/Makefile's
# VERITY_TRUST_CERT): shipped beside the kernel so the assembly can refuse an
# archive built against another trust domain than the one it signs with.
TRUST_CERT="${VERITY_TRUST_CERT:-${REPO_ROOT}/meta/verity/signer.cert.pem}"

# What the kernel directory must hold, by the board's architecture.
KERNEL_FILES=(config kernel.release modules.tar)
case "${MICA_ARCH}" in
amd64) KERNEL_FILES+=(bzImage) ;;
*) KERNEL_FILES+=(Image) ;;
esac

examined=0; missing=0; warned=0
present() { examined=$((examined + 1)); [ -e "$1" ] && return 0; missing=$((missing + 1)); echo "missing: $1 -- $2" >&2; return 1; }
for f in "${KERNEL_FILES[@]}"; do present "${OUT}/kernel/${f}" "run \`make kernel\` (an hour of compiling; not started from a packaging hook)" || true; done
present "${TRUST_CERT}" "the verity trust certificate the kernel was built against; set VERITY_TRUST_CERT or put the signing workspace at meta/" || true
present "${REPO_ROOT}/boards/${BOARD}/board.env" "the board definition" || true
present "${REPO_ROOT}/boards/${BOARD}/manifests/board.pkgs" "the board package manifest" || true
# evidence.json is a board record some boards carry; it is staged when present
# and its absence is not a missing input. The loader outputs, by the firmware
# format the board declares.
case "${FIRMWARE_FORMAT:-efi}" in
rockchip-loader) present "${OUT}/uboot-mos" "run 'make ${BOARD}-firmware'" || true ;;
amlogic-boot0) for t in uboot uboot-package; do present "${OUT}/${t}" "run 'make ${BOARD}-firmware'" || true; done ;;
esac


if [ "${PREFLIGHT}" != 0 ]; then
    printf 'preflight-examined: %s\npreflight-missing: %s\npreflight-warned: %s\n' "${examined}" "${missing}" "${warned}"
    [ "${missing}" -eq 0 ]
    exit
fi
[ "${missing}" -eq 0 ] || { echo "error: ${missing} of ${examined} inputs are missing (above); nothing was staged" >&2; exit 1; }

stage_tree() { mkdir -p "$2"; cp -a "$1"/. "$2"/; }
stage_tree "${OUT}/kernel" "${STAGE}/kernel"
# The loader the image writes, by the firmware format the board declares:
# a rockchip loader is the family's uboot-mos build, an amlogic boot0 the
# signed U-Boot with its tools and the recovery package; a UEFI board ships none.
case "${FIRMWARE_FORMAT:-efi}" in
rockchip-loader) stage_tree "${OUT}/uboot-mos" "${STAGE}/uboot" ;;
amlogic-boot0) stage_tree "${OUT}/uboot" "${STAGE}/uboot"; stage_tree "${OUT}/uboot-package" "${STAGE}/uboot-package" ;;
efi) ;;
*) echo "error: ${BOARD} declares FIRMWARE_FORMAT=${FIRMWARE_FORMAT}, which this hook does not stage" >&2; exit 1 ;;
esac
install -m 0644 "${REPO_ROOT}/boards/${BOARD}/board.env" "${STAGE}/board.env"
[ ! -f "${REPO_ROOT}/boards/${BOARD}/evidence.json" ] || install -m 0644 "${REPO_ROOT}/boards/${BOARD}/evidence.json" "${STAGE}/evidence.json"
install -D -m 0644 "${TRUST_CERT}" "${STAGE}/trust/verity-signer.cert.pem"
# The firmware files the support image carries and the component copyright
# that names their licences (build/src/kernel-package.ts in the assembly reads
# BOARD_FIRMWARE_FILES out of board.env and takes them from here).
firmware="$(sed -n 's/^BOARD_FIRMWARE_FILES="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' "${REPO_ROOT}/boards/${BOARD}/board.env" | head -1)"
if [ -n "${firmware}" ]; then
    mkdir -p "${STAGE}/firmware"
    for f in ${firmware}; do
        name="${f#/usr/lib/firmware/}"
        install -m 0644 "${REPO_ROOT}/boards/${BOARD}/firmware/${name}" "${STAGE}/firmware/${name}"
    done
fi
[ ! -f "${REPO_ROOT}/boards/${BOARD}/firmware/component-copyright" ] || install -m 0644 "${REPO_ROOT}/boards/${BOARD}/firmware/component-copyright" "${STAGE}/component-copyright"
# The board's package manifests (manifests/board.pkgs, radio-<r>.pkgs,
# component-<c>.pkgs): the assembly's resolver reads them out of the bundle,
# so what a board installs travels with the board.
stage_tree "${REPO_ROOT}/boards/${BOARD}/manifests" "${STAGE}/manifests"

echo "prepare: staged the ${BOARD} kernel directory, board.env, evidence.json, manifests/ and the trust certificate into ${STAGE}"
