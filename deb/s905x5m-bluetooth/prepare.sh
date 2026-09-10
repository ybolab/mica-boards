#!/usr/bin/env bash
# Compile the board-owned bridge with the pinned target userspace toolchain.
set -euo pipefail
[ "$MOS_DEB_ARCH" = arm64 ]
make -C "$MOS_DEB_REPO_ROOT/boards/s905x5m/bsp" userland
cp -a "$MOS_DEB_REPO_ROOT/_out/boards/s905x5m/userland/." "$MOS_DEB_STAGE/"
