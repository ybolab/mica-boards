#!/usr/bin/env bash
set -euo pipefail

package_dir=${1:-"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"}
profile=${2:-bootloader}
package_dir=$(cd "${package_dir}" && pwd -P)
burn_config="${package_dir}/config/aml_sdc_burn.ini"

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

require_pattern() {
    local pattern=$1 file=$2 description=$3
    grep -Eq "${pattern}" "${file}" || fail "${description}"
}

case "${profile}" in
bootloader)
    manifest="${package_dir}/config/bootloader.cfg"
    expected_files=(
        DDR.USB
        _aml_dtb.PARTITION
        aml_sdc_burn.UBOOT
        aml_sdc_burn.ini
        bootloader.PARTITION
        platform.conf
        usb_flow.aml
    )
    ;;
emmc)
    manifest="${package_dir}/config/emmc.cfg"
    expected_files=(
        DDR.USB
        _aml_dtb.PARTITION
        aml_sdc_burn.UBOOT
        aml_sdc_burn.ini
        boot-a.PARTITION
        boot-b.PARTITION
        bootloader.PARTITION
        data.PARTITION
        ephemeral.PARTITION
        gpt.bin
        meta.PARTITION
        platform.conf
        rootfs-a.PARTITION
        rootfs-b.PARTITION
        state.PARTITION
        uenv-a.PARTITION
        uenv-b.PARTITION
        usb_flow.aml
    )
    ;;
*)
    fail "unknown package profile: ${profile}"
    ;;
esac

[ -f "${manifest}" ] || fail "missing manifest: ${manifest}"
[ -f "${burn_config}" ] || fail "missing manual burn config: ${burn_config}"

mapfile -t manifest_files < <(
    sed -n 's/^[[:space:]]*file="\([^"]*\)".*/\1/p' "${manifest}" | LC_ALL=C sort -u
)

has_manifest_file() {
    local wanted=$1 candidate
    for candidate in "${manifest_files[@]}"; do
        [ "${candidate}" = "${wanted}" ] && return 0
    done
    return 1
}

[ "${#manifest_files[@]}" -eq "${#expected_files[@]}" ] ||
    fail "manifest has ${#manifest_files[@]} distinct files; expected ${#expected_files[@]}"
for index in "${!expected_files[@]}"; do
    [ "${manifest_files[${index}]}" = "${expected_files[${index}]}" ] ||
        fail "manifest file ${index} is ${manifest_files[${index}]}; expected ${expected_files[${index}]}"
done

[ "$(grep -c '^file="DDR\.USB"' "${manifest}")" -eq 2 ] ||
    fail "manifest must carry DDR.USB under exactly two USB identities"
require_pattern '^file="DDR\.USB"[[:space:]]+main_type="USB"[[:space:]]+sub_type="DDR"' \
    "${manifest}" "manifest is missing USB/DDR"
require_pattern '^file="DDR\.USB"[[:space:]]+main_type="USB"[[:space:]]+sub_type="UBOOT"' \
    "${manifest}" "manifest is missing USB/UBOOT"
require_pattern '^file="aml_sdc_burn\.UBOOT"[[:space:]]+main_type="UBOOT"[[:space:]]+sub_type="aml_sdc_burn"' \
    "${manifest}" "manifest is missing the burn-protocol U-Boot"
require_pattern '^file="bootloader\.PARTITION"[[:space:]]+main_type="PARTITION"[[:space:]]+sub_type="bootloader"' \
    "${manifest}" "manifest is missing the special bootloader destination"
require_pattern '^file="_aml_dtb\.PARTITION"[[:space:]]+main_type="dtb"[[:space:]]+sub_type="meson1"' \
    "${manifest}" "manifest is missing the DTB preload entry"
require_pattern '^file="_aml_dtb\.PARTITION"[[:space:]]+main_type="PARTITION"[[:space:]]+sub_type="_aml_dtb"' \
    "${manifest}" "manifest is missing the reserved DTB destination"
! grep -Eq 'sub_type="bootloader_a"' "${manifest}" ||
    fail "bootloader_a is absent from the mos GPT and must not be packaged"
! has_manifest_file 'bm201upd.ini' ||
    fail "automatic installer configuration is outside this package"

if [ "${profile}" = bootloader ]; then
    ! has_manifest_file 'gpt.bin' ||
        fail "bootloader-only package must not carry gpt.bin"
    require_pattern '^[[:space:]]*erase_bootloader[[:space:]]*=[[:space:]]*1[[:space:]]*$' \
        "${burn_config}" "manual burn config must erase the old bootloader"
    require_pattern '^[[:space:]]*erase_flash[[:space:]]*=[[:space:]]*0[[:space:]]*$' \
        "${burn_config}" "manual burn config must not erase the user area"
    require_pattern '^[[:space:]]*reboot[[:space:]]*=[[:space:]]*0[[:space:]]*$' \
        "${burn_config}" "manual burn config must leave reboot under operator control"
    require_pattern '^[[:space:]]*package[[:space:]]*=[[:space:]]*update\.img[[:space:]]*$' \
        "${burn_config}" "manual burn config must name update.img"
else
    require_pattern '^file="gpt\.bin"[[:space:]]+main_type="bin"[[:space:]]+sub_type="gpt"' \
        "${manifest}" "complete package is missing the special GPT destination"
    for partition in uenv-a uenv-b boot-a boot-b rootfs-a rootfs-b meta state ephemeral data; do
        require_pattern "^file=\"${partition}\\.PARTITION\"[[:space:]]+main_type=\"PARTITION\"[[:space:]]+sub_type=\"${partition}\"" \
            "${manifest}" "complete package is missing the ${partition} GPT destination"
    done
    ! has_manifest_file 'reserved.PARTITION' ||
        fail "the SD-only p1 bridge must never enter an eMMC package"
    ! has_manifest_file 'env.PARTITION' ||
        fail "the vendor-owned env range must never enter an eMMC package"
fi

(
    cd "${package_dir}/blobs"
    sha256sum -c SHA256SUMS
)

printf 'ok: %s manifest has %s distinct files and DDR.USB has 2 USB identities\n' \
    "${profile}" "${#expected_files[@]}"
printf 'ok: static Amlogic flow blobs match their recorded SHA-256 values\n'
