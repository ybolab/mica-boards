#!/usr/bin/env bash
# The shared kernel floor over every board's committed configuration, the
# boards discovered and each read through its family: a uefi board's config
# is <board>/bsp/kernel/config/<board>.config and its post-olddefconfig gate
# the family's Dockerfile; a FIT board names its config in bsp/bsp.env
# (KERNEL_CONFIG) and its gate is the family's configure.sh.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
n=0
for env in */board.env; do
    board="${env%/board.env}"
    family="$(sed -n 's/^BOARD_FAMILY=//p' "${env}" | head -1)"
    [ -n "${family}" ] || { echo "error: ${env} declares no BOARD_FAMILY" >&2; exit 1; }
    if [ "${family}" = uefi ]; then
        config="${board}/bsp/kernel/config/${board}.config"; gate="families/uefi/kernel/Dockerfile"
    else
        name="$(sed -n 's/^KERNEL_CONFIG=//p' "${board}/bsp/bsp.env" | head -1)"
        [ -n "${name}" ] || { echo "error: ${board}/bsp/bsp.env declares no KERNEL_CONFIG" >&2; exit 1; }
        config="${board}/bsp/kernel/config/${name}"; gate="families/${family}/kernel/configure.sh"
    fi
    bash boot/common/kernel-config-test.sh "${board}" "${config}" "${gate}"
    n=$((n + 1))
done
[ "${n}" -gt 0 ] || { echo "error: no board.env found; the loop above checked nothing" >&2; exit 1; }
echo "kernel-config-test: ${n} board(s)"
