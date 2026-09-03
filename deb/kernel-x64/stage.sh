#!/usr/bin/env bash
# Stage the x64 BSP's kernel output into ${MOS_DEB_STAGE}.
#
# This is the producer's PREPARE hook, named in
# boards/x64/deb/kernel-x64/producer.env and run by the driver -- it is not an
# entry point and it builds nothing:
#
#   bash build-env/deb/build.sh --producer kernel-x64 --arch amd64
#
# The driver empties ${MOS_DEB_STAGE}, exports the hook environment
# build-env/deb/README.md documents, runs this on the HOST before any container
# is started, and hands the directory to the build as the `bin` context.
#
# One thing forces a host-side step: a missing kernel has to be refused BEFORE
# buildkit has resolved a base image, transferred the contexts and started a
# stage. boards/x64/bsp/out is gitignored, so a fresh worktree has none.
#
# NO BOARD_DIR HERE, unlike the cx3576 board producer. That variable is one
# global honoured by whichever producers read it, so a second reader makes
# `BOARD_DIR=<a cx3576 bsp tree>` mean two incompatible things in one run --
# and tests/deb-preflight-test.sh sets exactly that while driving the whole
# aggregate. x64's escape is simpler and needs no variable: out/kernel/ is
# gitignored, so copying a built kernel into it is the same act.
set -euo pipefail

die() {
    echo "stage.sh: error: $*" >&2
    exit 1
}

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Two hops to the board, for the reason the cx3576 hook spells out: a
# producer's name is its directory's basename, so this producer is
# boards/<board>/deb/kernel-<board>/ and the board directory is its
# grandparent.
BOARD_ROOT="$(cd "${HERE}/../.." && pwd)"
MOS_BOARD="$(basename "${BOARD_ROOT}")"
VERSIONS_ENV="${BOARD_ROOT}/bsp/kernel/versions.env"

STAGE="${MOS_DEB_STAGE:-}"
if [ "${MOS_DEB_PREFLIGHT:-0}" = 0 ]; then
    [ -n "${STAGE}" ] ||
        die "MOS_DEB_STAGE is unset. This is a PREPARE hook: build-env/deb/build.sh exports the directory to stage into and passes it to the build as the 'bin' context. Run the producer through the driver -- bash build-env/deb/build.sh --producer kernel-${MOS_BOARD} --arch amd64"
    [ -d "${STAGE}" ] || die "MOS_DEB_STAGE=${STAGE} is not a directory"
fi

[ -f "${VERSIONS_ENV}" ] ||
    die "${VERSIONS_ENV} does not exist. It is the pin -- which kernel source this board compiles -- and the release string staged below is asserted against it"

OUT="${BOARD_ROOT}/bsp/out/kernel"

# Every missing input reported TOGETHER, and the count of what was examined
# reported beside it. A run that found nothing missing because it looked at
# nothing prints the same "all present" as a complete one.
MISSING=()
EXAMINED=0
require() {
    local path="$1"
    EXAMINED=$((EXAMINED + 1))
    [ ! -f "${path}" ] || return 0
    MISSING+=("error: ${path} not found.
Build it with 'make -C boards/${MOS_BOARD}/bsp kernel', or copy a built one in:
boards/${MOS_BOARD}/bsp/out/kernel/ is gitignored and this reads it directly.")
}

# The four artefacts boards/x64/bsp/kernel/Dockerfile's `artifact` stage
# exports, named here rather than globbed: a glob over an incomplete out/kernel
# stages whatever survived a failed build and packs it.
require "${OUT}/bzImage"
require "${OUT}/config"
require "${OUT}/modules.tar"
require "${OUT}/kernel.release"

if [ "${#MISSING[@]}" -gt 0 ]; then
    printf '%s\n\n' "${MISSING[@]}" >&2
    echo "stage.sh: refusing to build mos-kernel-${MOS_BOARD}: ${#MISSING[@]} of ${EXAMINED} examined kernel artefacts are missing. Nothing was staged and no container was started." >&2
    # The pre-flight contract on the failing side. preflight-warned is zero
    # here and on the other path, and the zero is written rather than omitted:
    # `make os-debs` compiles no kernel, so every input this hook examines is
    # either present or missing and none of them is a cost the run could
    # absorb. An omitted count would say instead that this hook has not been
    # taught the category.
    if [ "${MOS_DEB_PREFLIGHT:-0}" != 0 ]; then
        echo "preflight-examined: ${EXAMINED}" >&2
        echo "preflight-missing: ${#MISSING[@]}" >&2
        echo "preflight-warned: 0" >&2
    fi
    exit 1
fi

if [ "${MOS_DEB_PREFLIGHT:-0}" != 0 ]; then
    echo "preflight-examined: ${EXAMINED}"
    echo "preflight-missing: 0"
    echo "preflight-warned: 0"
    echo "stage.sh: pre-flight found all ${EXAMINED} kernel artefacts of mos-kernel-${MOS_BOARD} present"
    exit 0
fi

# THE RELEASE STRING AGREES WITH THE PIN, checked here rather than in the
# container. The package's payload paths are all named after the release, and
# the pin is what says which source produced it; an out/kernel/ left over from
# a previous KERNEL_VERSION stages cleanly and packs a kernel this tree no
# longer claims to build. out/ is gitignored and never cleaned by a git
# operation, so that is the ordinary case rather than a hypothetical one.
release="$(cat "${OUT}/kernel.release")"
# shellcheck source=../../bsp/kernel/versions.env
. "${VERSIONS_ENV}"
want="${KERNEL_VERSION#v}"
[ "${release}" = "${want}" ] ||
    die "${OUT} holds kernel ${release}, but ${VERSIONS_ENV} pins ${KERNEL_VERSION}. These artefacts are from a different source than the one this tree records; rebuild with 'make -C boards/${MOS_BOARD}/bsp kernel'"

cp "${OUT}/bzImage" "${OUT}/config" "${OUT}/modules.tar" "${OUT}/kernel.release" "${STAGE}/"
echo "stage.sh: staged kernel ${release} from ${OUT} ($(stat -c%s "${OUT}/bzImage") bytes of bzImage, $(stat -c%s "${OUT}/modules.tar") bytes of modules)"
