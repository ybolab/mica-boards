#!/usr/bin/env bash
# The board bundle contract (mica:docs/boards/contract.md, C1 of plan
# 20260913-0416): every board directory declares what the assembly reads
# out of its bundle, and nothing the bundle no longer carries.
#
#   - board.env declares BOARD_FEATURES (a subset of the vocabulary below),
#     BOARD_FAMILY (an existing family, included by the board's Makefile,
#     with a bsp.env for the FIT families) and IMAGE_KINDS (a subset of its
#     vocabulary), as plain KEY=value lines;
#   - manifests/board.pkgs exists and names at least one package; every
#     manifest is one package per line and names only packages a producer
#     of this repository emits (build-env/deb/producers.sh);
#   - manifests/radio-<r>.pkgs names a radio in BOARD_FEATURES,
#     manifests/component-<c>.pkgs a word; any other manifest name is refused;
#   - a board carries no producer: producers/board and producers/kernel run over every board;
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
for dir in boards/*/; do
    board="$(basename "${dir}")"
    [ -f "boards/${board}/board.env" ] || continue
    boards=$((boards + 1))

    for key in BOARD_FEATURES BOARD_FAMILY IMAGE_KINDS; do
        if ! value="$(plain_value "boards/${board}/board.env" "${key}")"; then
            fail "boards/${board}/board.env declares no ${key} (or not as a plain KEY=value line)"
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
            grep -c "include ../../families/${value}/Makefile.inc" "boards/${board}/Makefile" >/dev/null || fail "boards/${board}/Makefile does not include families/${value}/Makefile.inc"
            [ "${value}" = uefi ] || [ -f "boards/${board}/bsp.env" ] || fail "boards/${board}/bsp.env is missing; a FIT family board names its kernel and U-Boot inputs there" ;;
        esac
        pass
    done
    features="$(plain_value "boards/${board}/board.env" BOARD_FEATURES || true)"

    if [ ! -f "boards/${board}/manifests/board.pkgs" ]; then
        fail "boards/${board}/manifests/board.pkgs is missing; the bundle would carry no board package manifest"
    fi
    shopt -s nullglob
    for m in "boards/${board}"/manifests/*.pkgs; do
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

    # The authenticated boot facts the assembly's kernel component and
    # firmware package read (plan 20260913-0416, C4): the firmware format
    # agrees with the boot backend, a FIT board names its device tree, its
    # watchdog symbol, its three load addresses and its loader, and every
    # board's command line carries the signed-boot floor.
    backend="$(plain_value "boards/${board}/board.env" BOOT_BACKEND || true)"
    format="$(plain_value "boards/${board}/board.env" FIRMWARE_FORMAT || true)"
    case "${backend}:${format}" in
    systemd-boot:efi | uboot-fit:rockchip-loader | uboot-fit:amlogic-boot0) pass ;;
    *) fail "${board}: BOOT_BACKEND=${backend:-unset} with FIRMWARE_FORMAT=${format:-unset}; systemd-boot boots efi, uboot-fit a rockchip-loader or an amlogic-boot0" ;;
    esac
    if [ "${backend}" = uboot-fit ]; then
        for key in FIT_DTB FIT_WATCHDOG FIT_LOAD_ADDRESSES UBOOT_BIN_NAME UBOOT_MAX_BYTES; do
            v="$(plain_value "boards/${board}/board.env" "${key}" || true)"
            [ -n "${v}" ] || fail "${board}: a FIT board declares ${key}"
        done
        addrs="$(plain_value "boards/${board}/board.env" FIT_LOAD_ADDRESSES || true)"
        [ "$(printf '%s\n' ${addrs} | grep -cE '^0x[0-9a-fA-F]+$')" -eq 3 ] || fail "${board}: FIT_LOAD_ADDRESSES is three hexadecimal addresses (kernel, initramfs, device tree), not '${addrs}'"
        case "${format}" in
        amlogic-boot0) for key in UBOOT_MIN_BYTES UBOOT_PAYLOAD_OFFSET_BYTES; do [ -n "$(plain_value "boards/${board}/board.env" "${key}" || true)" ] || fail "${board}: an amlogic-boot0 board declares ${key}"; done ;;
        rockchip-loader) for key in UBOOT_SEEK_SECTOR LOADER_MAGIC_HEX; do [ -n "$(plain_value "boards/${board}/board.env" "${key}" || true)" ] || fail "${board}: a rockchip-loader board declares ${key}"; done ;;
        esac
    fi
    cmdline="$(plain_value "boards/${board}/board.env" BOARD_CMDLINE_ARGS || true)"
    for arg in dm_verity.require_signatures=1 rdinit=/init; do
        case " ${cmdline} " in *" ${arg} "*) ;; *) fail "${board}: BOARD_CMDLINE_ARGS is the authenticated command line and lacks ${arg}" ;; esac
    done

    # BOARD_FEATURES is the one capability declaration; the readings it used
    # to be paired with (BOARD_RADIOS, BOARD_HAS_STATUS_LED, BOARD_HAS_DISPLAY)
    # are gone, and a board that still carries one has two places to disagree.
    for key in BOARD_RADIOS BOARD_HAS_STATUS_LED BOARD_HAS_DISPLAY; do
        ! grep -q "^${key}=" "boards/${board}/board.env" || fail "${board}: board.env still declares ${key}; BOARD_FEATURES is the capability set and its readers read it"
    done

    # The board is data: no producer of its own (producers/board and
    # producers/kernel run over every board), and the two control templates
    # it does carry are the package's and the bundle's.
    stray="$(find "boards/${board}" -path "boards/${board}/extras" -prune -o -name producer.env -print)"
    [ -z "${stray}" ] || fail "boards/${board} carries a producer.env outside extras/ (${stray}); a board is data, the producers are under producers/"
    [ -f "boards/${board}/package/control/mica-board-${board}.control" ] || fail "boards/${board}/package/control/mica-board-${board}.control is missing; the board package's control template"
    [ -f "boards/${board}/kernel/control/mica-kernel-${board}.control" ] || fail "boards/${board}/kernel/control/mica-kernel-${board}.control is missing; the bundle's control template"
    grep -q '^BOARD_PACKAGE_ENABLEMENT=[0-9]\+$' "boards/${board}/board.env" || fail "${board}: board.env declares no BOARD_PACKAGE_ENABLEMENT (how many units the board package enables; the gate holds it)"
    pass
    [ ! -e "boards/${board}/containers.env" ] || fail "boards/${board}/containers.env exists; that switch moved to the product"
done
[ "${boards}" -gt 0 ] || { echo "FAIL: no directory with a board.env; the loop above checked nothing" >&2; exit 1; }

echo "board-contract-test: ${boards} board(s), ${PASS_N} passed, ${FAIL_N} failed"
[ "${FAIL_N}" -eq 0 ]
