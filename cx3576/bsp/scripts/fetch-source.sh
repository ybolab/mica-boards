#!/usr/bin/env bash
# mica-build-side: container -- this clones into the BSP builder image's own
# filesystem; no upstream source tree is fetched onto the host.
#
# Fetch one upstream tree at one commit, and prove it is that commit.
#
#   fetch-source.sh /ksrc https://github.com/armbian/linux-rockchip.git <sha>
#
# `git init` + `fetch --depth=1 <sha>` rather than `clone --branch`: a branch or
# a tag is a name upstream can move, and the answer to "which source produced
# this artefact" would then be the date of the build. The rev-parse afterwards is
# not redundant with the fetch -- a server that resolves the argument to
# something else still leaves a checkout here, and the assertion is what makes
# that a failure rather than a different kernel.
set -euo pipefail

[ "$#" -eq 3 ] || {
    echo "usage: fetch-source.sh <dir> <repo> <commit>" >&2
    exit 1
}
DIR="$1"
REPO="$2"
COMMIT="$3"

[ -n "${COMMIT}" ] || {
    echo "error: fetch-source.sh was given an empty commit for ${REPO}. An empty --build-arg reaches here as a fetch of nothing" >&2
    exit 1
}

git init -q "${DIR}"
git -C "${DIR}" remote add origin "${REPO}"
git -C "${DIR}" fetch --depth=1 origin "${COMMIT}"
git -C "${DIR}" checkout -q --detach FETCH_HEAD
got="$(git -C "${DIR}" rev-parse HEAD)"
[ "${got}" = "${COMMIT}" ] || {
    echo "error: ${REPO} was asked for ${COMMIT} and ${DIR} is at ${got}" >&2
    exit 1
}
