#!/usr/bin/env bash
# The shared kernel floor, asserted over a RESOLVED .config: every =y line of
# boot/common/mos-required.fragment survived olddefconfig, the LSM boot list
# is exactly the required one, and the verity trust anchor the fragment names
# is a PEM certificate in the tree. Run by the FIT families' configure.sh
# after olddefconfig; the uefi family's Dockerfile carries the same three
# checks inline.
#
#   floor-check.sh <source-tree> <mos-required-fragment>
set -euo pipefail
[ "$#" -eq 2 ] || { echo "usage: floor-check.sh <source-tree> <mos-required-fragment>" >&2; exit 1; }
SRC="$1"
FRAGMENT="$2"
cd "${SRC}"

trusted_keys="$(grep '^CONFIG_SYSTEM_TRUSTED_KEYS=' "${FRAGMENT}")"
[ -n "${trusted_keys}" ] || {
    echo "error: ${FRAGMENT} declares no CONFIG_SYSTEM_TRUSTED_KEYS, so this assertion has nothing to compare and would pass over a kernel that trusts nothing" >&2
    exit 1
}
grep -q "^${trusted_keys}$" .config || {
    echo "error: the resolved config's trust anchor is not the required one. Wanted ${trusted_keys}, got $(grep '^CONFIG_SYSTEM_TRUSTED_KEYS=' .config || echo none)." >&2
    exit 1
}
anchor="$(printf '%s' "${trusted_keys}" | sed 's/^CONFIG_SYSTEM_TRUSTED_KEYS=//; s/^"//; s/"$//')"
[ -s "${anchor}" ] || {
    echo "error: ${trusted_keys} names ${anchor}, which does not exist in the kernel tree. certs/Makefile resolves that path against the source tree; the compile would fail at extract-cert" >&2
    exit 1
}
grep -q 'BEGIN CERTIFICATE' "${anchor}" || {
    echo "error: ${anchor} is not a PEM certificate. The mos-trust build context delivered something else, and extract-cert would refuse it in the middle of the compile" >&2
    exit 1
}
echo "config: ${trusted_keys} ($(stat -c%s "${anchor}") bytes)"

lsm="$(grep '^CONFIG_LSM=' "${FRAGMENT}")"
[ -n "${lsm}" ] || { echo "error: ${FRAGMENT} declares no CONFIG_LSM, so this assertion has nothing to compare" >&2; exit 1; }
grep -q "^${lsm}$" .config || {
    echo "error: the resolved config's LSM list is not the required one. Wanted ${lsm}, got $(grep '^CONFIG_LSM=' .config || echo none). SELinux that is compiled in but not in the boot list never registers selinuxfs, and the image ships a security module that is present and does nothing." >&2
    exit 1
}
echo "config: ${lsm}"

n=0
for line in $(sed -n 's/^\(CONFIG_[A-Z0-9_]*=y\)$/\1/p' "${FRAGMENT}"); do
    n=$((n + 1))
    grep -q "^${line}$" .config || {
        echo "missing mos-required option: ${line}" >&2
        exit 1
    }
done
[ "${n}" -gt 0 ] || { echo "error: zero =y lines were read from ${FRAGMENT}, so the loop above asserted nothing" >&2; exit 1; }
echo "config: all ${n} required =y options of the shared floor are set"
