#!/usr/bin/env bash
# The kernel producer's PREPARE hook: put this board's BSP outputs in
# MICA_DEB_STAGE for build-env/deb/build.sh to hand the packaging build as
# its `bin` context. See producer.env for what is staged and why nothing is
# built here.
set -euo pipefail

PREFLIGHT="${MICA_DEB_PREFLIGHT:-0}"
for v in MICA_DEB_REPO_ROOT MICA_DEB_ARCH MICA_DEB_PRODUCER; do
    [ -n "${!v:-}" ] || { echo "error: ${v} is not set. This script is deb/kernel/producer.env's PREPARE hook and is run by build-env/deb/build.sh, which sets it; it is not a standalone command" >&2; exit 1; }
done
[ "${PREFLIGHT}" != 0 ] || [ -n "${MICA_DEB_STAGE:-}" ] || { echo "error: MICA_DEB_STAGE is not set. This script is deb/kernel/producer.env's PREPARE hook and is run by build-env/deb/build.sh, which sets it" >&2; exit 1; }

REPO_ROOT="${MICA_DEB_REPO_ROOT}"
STAGE="${MICA_DEB_STAGE:-}"
OUT="${REPO_ROOT}/_out/bsp"
BOARD="s905x5m"
# The verity trust certificate the kernel embeds (bsp/Makefile's
# VERITY_TRUST_CERT): shipped beside the kernel so the assembly can refuse an
# archive built against another trust domain than the one it signs with.
TRUST_CERT="${VERITY_TRUST_CERT:-${REPO_ROOT}/meta/verity/signer.cert.pem}"

# What the kernel directory must hold, by the board's own board.env.
KERNEL_FILES=(config kernel.release modules.tar)
case "${BOARD}" in
x64) KERNEL_FILES+=(bzImage) ;;
*) KERNEL_FILES+=(Image) ;;
esac

examined=0; missing=0; warned=0
present() { examined=$((examined + 1)); [ -e "$1" ] && return 0; missing=$((missing + 1)); echo "missing: $1 -- $2" >&2; return 1; }
for f in "${KERNEL_FILES[@]}"; do present "${OUT}/kernel/${f}" "run \`make kernel\` (an hour of compiling; not started from a packaging hook)" || true; done
present "${TRUST_CERT}" "the verity trust certificate the kernel was built against; set VERITY_TRUST_CERT or put the signing workspace at meta/" || true
present "${REPO_ROOT}/board.env" "the board definition" || true
# evidence.json is a board record some boards carry; it is staged when present
# and its absence is not a missing input.

for t in uboot uboot-package; do present "${OUT}/${t}" "run `make uboot` and `make uboot-package`" || true; done
if [ "${PREFLIGHT}" != 0 ]; then
    printf 'preflight-examined: %s\npreflight-missing: %s\npreflight-warned: %s\n' "${examined}" "${missing}" "${warned}"
    [ "${missing}" -eq 0 ]
    exit
fi
[ "${missing}" -eq 0 ] || { echo "error: ${missing} of ${examined} inputs are missing (above); nothing was staged" >&2; exit 1; }

stage_tree() { mkdir -p "$2"; cp -a "$1"/. "$2"/; }
stage_tree "${OUT}/kernel" "${STAGE}/kernel"
install -m 0644 "${REPO_ROOT}/board.env" "${STAGE}/board.env"
[ ! -f "${REPO_ROOT}/evidence.json" ] || install -m 0644 "${REPO_ROOT}/evidence.json" "${STAGE}/evidence.json"
install -D -m 0644 "${TRUST_CERT}" "${STAGE}/trust/verity-signer.cert.pem"
# The firmware files the support image carries and the component copyright
# that names their licences (build/src/kernel-package.ts in the assembly reads
# BOARD_FIRMWARE_FILES out of board.env and takes them from here).
firmware="$(sed -n 's/^BOARD_FIRMWARE_FILES="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' "${REPO_ROOT}/board.env" | head -1)"
if [ -n "${firmware}" ]; then
    mkdir -p "${STAGE}/firmware"
    for f in ${firmware}; do
        name="${f#/usr/lib/firmware/}"
        install -m 0644 "${REPO_ROOT}/bsp/rootfs/firmware/${name}" "${STAGE}/firmware/${name}"
    done
fi
[ ! -f "${REPO_ROOT}/bsp/component-copyright" ] || install -m 0644 "${REPO_ROOT}/bsp/component-copyright" "${STAGE}/component-copyright"
# The board's build-time container switch, when it declares one: the
# composer reads it beside board.env (rootfs/build.sh in the assembly).
[ ! -f "${REPO_ROOT}/bsp/containers.env" ] || install -m 0644 "${REPO_ROOT}/bsp/containers.env" "${STAGE}/containers.env"
# The signed U-Boot, its tools and the recovery package (bsp/Makefile uboot,
# uboot-package).
stage_tree "${OUT}/uboot" "${STAGE}/uboot"
stage_tree "${OUT}/uboot-package" "${STAGE}/uboot-package"

echo "prepare: staged the ${BOARD} kernel directory, board.env, evidence.json and the trust certificate into ${STAGE}"
