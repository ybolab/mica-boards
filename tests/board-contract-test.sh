#!/usr/bin/env bash
# The board bundle contract (mica:docs/boards/contract.md, C1 of plan
# 20260913-0416): every board directory declares what the assembly reads
# out of its bundle, and nothing the bundle no longer carries.
#
#   - board.env declares BOARD_FEATURES (a subset of the vocabulary below),
#     BOARD_FAMILY (an existing family, included by the board's bsp/Makefile,
#     with a bsp.env for the FIT families) and IMAGE_KINDS (a subset of its
#     vocabulary), as plain KEY=value lines;
#   - manifests/board.pkgs exists and names at least one package; every
#     manifest is one package per line and names only packages a producer
#     of this repository emits (build-env/deb/producers.sh);
#   - manifests/radio-<r>.pkgs names a radio in BOARD_FEATURES,
#     manifests/component-<c>.pkgs a word; any other manifest name is refused;
#   - deb/kernel-<board>/prepare.sh stages manifests/ into the bundle;
#   - bsp/containers.env is gone: the product decides features, not the board.
#
# Discovered, not listed: a board is a directory with a board.env.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

FEATURE_VOCABULARY="wifi bluetooth display status-led can usb-gadget audio containers"
IMAGE_KIND_VOCABULARY="disk rockchip-update"

FAIL_N=0
PASS_N=0
fail() { FAIL_N=$((FAIL_N + 1)); echo "FAIL: $*" >&2; }
pass() { PASS_N=$((PASS_N + 1)); }
in_list() { local n="$1"; shift; local i; for i in "$@"; do [ "$i" != "$n" ] || return 0; done; return 1; }

# KEY=value or KEY="value", nothing else; the value without its quotes.
plain_value() {
    local line
    line="$(grep -E "^$2=" "$1" | head -1 || true)"
    [ -n "${line}" ] || return 1
    case "${line}" in *'$('* | *'`'* | *'${'*) return 2 ;; esac
    line="${line#*=}"
    line="${line#\"}"
    printf '%s\n' "${line%\"}"
}

declared=""
while read -r _producer _dir _arches packages _enablement; do
    declared="${declared} ${packages//,/ }"
done < <(bash build-env/deb/producers.sh)
[ -n "${declared// /}" ] || { echo "FAIL: build-env/deb/producers.sh named no package" >&2; exit 1; }

boards=0
for dir in */; do
    board="${dir%/}"
    [ -f "${board}/board.env" ] || continue
    boards=$((boards + 1))

    for key in BOARD_FEATURES BOARD_FAMILY IMAGE_KINDS; do
        if ! value="$(plain_value "${board}/board.env" "${key}")"; then
            fail "${board}/board.env declares no ${key} (or not as a plain KEY=value line)"
            continue
        fi
        case "${key}" in
        BOARD_FEATURES)
            for f in ${value}; do in_list "${f}" ${FEATURE_VOCABULARY} || fail "${board}: BOARD_FEATURES names '${f}', not in: ${FEATURE_VOCABULARY}"; done ;;
        IMAGE_KINDS)
            [ -n "${value}" ] || fail "${board}: IMAGE_KINDS is empty; a board with no image kind produces nothing"
            for k in ${value}; do in_list "${k}" ${IMAGE_KIND_VOCABULARY} || fail "${board}: IMAGE_KINDS names '${k}', not in: ${IMAGE_KIND_VOCABULARY}"; done ;;
        BOARD_FAMILY)
            [[ "${value}" =~ ^[a-z0-9-]+$ ]] || fail "${board}: BOARD_FAMILY '${value}' is not one lowercase word"
            [ -f "families/${value}/Makefile.inc" ] || fail "${board}: BOARD_FAMILY names '${value}', and families/${value}/Makefile.inc does not exist"
            grep -c "include ../../families/${value}/Makefile.inc" "${board}/bsp/Makefile" >/dev/null || fail "${board}/bsp/Makefile does not include families/${value}/Makefile.inc"
            [ "${value}" = uefi ] || [ -f "${board}/bsp/bsp.env" ] || fail "${board}/bsp/bsp.env is missing; a FIT family board names its kernel and U-Boot inputs there" ;;
        esac
        pass
    done
    features="$(plain_value "${board}/board.env" BOARD_FEATURES || true)"

    if [ ! -f "${board}/manifests/board.pkgs" ]; then
        fail "${board}/manifests/board.pkgs is missing; the bundle would carry no board package manifest"
    fi
    shopt -s nullglob
    for m in "${board}"/manifests/*.pkgs; do
        base="$(basename "${m}" .pkgs)"
        case "${base}" in
        board) ;;
        radio-*) in_list "${base#radio-}" ${features} || fail "${m} names a radio the board's BOARD_FEATURES does not (${features:-none})" ;;
        component-?*) ;;
        *) fail "${m} belongs to no manifest family (board, radio-<r>, component-<c>)" ;;
        esac
        n=0
        lineno=0
        while IFS= read -r line || [ -n "${line}" ]; do
            lineno=$((lineno + 1))
            line="${line%%#*}"
            # shellcheck disable=SC2086
            set -- ${line}
            [ "$#" -gt 0 ] || continue
            [ "$#" -eq 1 ] || { fail "${m}:${lineno} names $# packages on one line"; continue; }
            in_list "$1" ${declared} || fail "${m}:${lineno} names '$1', which no producer of this repository emits"
            n=$((n + 1))
        done <"${m}"
        [ "${n}" -gt 0 ] || fail "${m} names no package"
        pass
    done
    shopt -u nullglob

    hook="${board}/deb/kernel-${board}/prepare.sh"
    if [ -f "${hook}" ]; then
        grep -c 'manifests' "${hook}" >/dev/null || fail "${hook} does not stage manifests/ into the bundle"
        ! grep -c 'containers.env' "${hook}" >/dev/null || fail "${hook} still stages containers.env; the product decides features"
        pass
    else
        fail "${hook} is missing"
    fi
    [ ! -e "${board}/bsp/containers.env" ] || fail "${board}/bsp/containers.env exists; that switch moved to the product"
done
[ "${boards}" -gt 0 ] || { echo "FAIL: no directory with a board.env; the loop above checked nothing" >&2; exit 1; }

echo "board-contract-test: ${boards} board(s), ${PASS_N} passed, ${FAIL_N} failed"
[ "${FAIL_N}" -eq 0 ]
