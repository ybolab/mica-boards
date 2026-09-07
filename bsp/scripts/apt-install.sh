#!/usr/bin/env bash
# mos-build-side: container -- this runs inside the BSP builder image, where apt
# is the image's own package manager; there is no apt step on the host.
#
# Install the build dependencies a BSP component names, and leave no apt lists
# behind.
#
#   apt-install.sh git ca-certificates build-essential ...
#
# The package LIST stays in the Dockerfile that needs it: it is the one part of
# this step that differs between the kernel and U-Boot builders, and a reader
# asking "what toolchain built this artefact" should find the answer in the file
# that declares the base image rather than one directory away. What is shared is
# the step -- update, --no-install-recommends, and the cleanup that keeps the
# lists out of the layer.
set -euo pipefail

[ "$#" -gt 0 ] || {
    echo "error: apt-install.sh was called with no packages. A call with none would run apt-get update, install nothing and exit 0, which reads exactly like a dependency list that arrived" >&2
    exit 1
}

apt-get update
apt-get install -y --no-install-recommends "$@"
rm -rf /var/lib/apt/lists/*
