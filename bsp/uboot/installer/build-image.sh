#!/usr/bin/env bash
# mos-build-side: container -- the pinned installer Dockerfile assembles regular image files
set -euo pipefail

# Build a regular-file installer image and prove its contents by reading the
# final image back. This script has no block-device argument by design.

header=${1:?usage: build-image.sh HEADER CONFIG COMPLETE_PACKAGE_FILES UPDATE_IMG SD_UBOOT OUTPUT_DIR}
config=${2:?usage: build-image.sh HEADER CONFIG COMPLETE_PACKAGE_FILES UPDATE_IMG SD_UBOOT OUTPUT_DIR}
expected_package_files=${3:?usage: build-image.sh HEADER CONFIG COMPLETE_PACKAGE_FILES UPDATE_IMG SD_UBOOT OUTPUT_DIR}
package_input=${4:?usage: build-image.sh HEADER CONFIG COMPLETE_PACKAGE_FILES UPDATE_IMG SD_UBOOT OUTPUT_DIR}
bootloader_input=${5:?usage: build-image.sh HEADER CONFIG COMPLETE_PACKAGE_FILES UPDATE_IMG SD_UBOOT OUTPUT_DIR}
output_dir=${6:?usage: build-image.sh HEADER CONFIG COMPLETE_PACKAGE_FILES UPDATE_IMG SD_UBOOT OUTPUT_DIR}

boot_start_mib=4
disk_tail_mib=16
minimum_free_mib=240
bytes_per_mib=1048576
sector_bytes=512

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

for file in "$header" "$config" "$expected_package_files" "$package_input" "$bootloader_input"; do
    [ -f "$file" ] || fail "missing installer input: $file"
done

header_value() {
    local name=$1
    local -a values=()

    mapfile -t values < <(
        awk -v name="$name" '
            $1 == "#define" && $2 == name {
                value = $3
                gsub(/"/, "", value)
                print value
            }
        ' "$header"
    )
    [ "${#values[@]}" -eq 1 ] || fail "header must define ${name} exactly once"
    printf '%s\n' "${values[0]}"
}

fat_mib="$(header_value BM201_INSTALLER_FAT_MIB)"
max_package_mib="$(header_value BM201_INSTALLER_MAX_PACKAGE_MIB)"
request_file="$(header_value BM201_INSTALLER_REQUEST_FILE)"
request_content="$(header_value BM201_INSTALLER_REQUEST_CONTENT)"
identity_file="$(header_value BM201_INSTALLER_IDENTITY_FILE)"
sha256_hex_bytes="$(header_value BM201_INSTALLER_SHA256_HEX_BYTES)"
identity_bytes="$(header_value BM201_INSTALLER_IDENTITY_BYTES)"
config_name="$(header_value BM201_INSTALLER_CONFIG)"
package_name="$(header_value BM201_INSTALLER_PACKAGE)"

for value in "$fat_mib" "$max_package_mib" "$sha256_hex_bytes" "$identity_bytes"; do
    case "$value" in
    ''|*[!0-9]*) fail "installer header contains a non-numeric capacity or identity value" ;;
    esac
done

[ "$request_file" = emmc-system-install.request ] || fail "unexpected request file: ${request_file}"
[ "$request_content" = 'BM201_INSTALL_V2\n' ] || fail "unexpected request content"
[ "$identity_file" = update.img.sha256 ] || fail "unexpected identity file: ${identity_file}"
[ "$sha256_hex_bytes" -eq 64 ] || fail "unexpected SHA-256 identity length: ${sha256_hex_bytes}"
[ "$identity_bytes" -eq 65 ] || fail "unexpected identity byte count: ${identity_bytes}"
[ "$config_name" = bm201upd.ini ] || fail "unexpected private config name: ${config_name}"
[ "$config_name" != aml_sdc_burn.ini ] || fail "private config must not use the vendor magic name"
[ "$package_name" = update.img ] || fail "unexpected package name: ${package_name}"
[ "$(basename "$config")" = "$config_name" ] || fail "private config filename does not match the installer header"
[ "$(basename "$package_input")" = "$package_name" ] || fail "installer package must be named ${package_name}"

package_size="$(stat -c %s "$package_input")"
max_package_bytes=$((max_package_mib * bytes_per_mib))
[ "$package_size" -gt 0 ] || fail "installer package is empty"
[ "$package_size" -le "$max_package_bytes" ] ||
    fail "installer package is ${package_size} bytes; U-Boot accepts at most ${max_package_bytes} bytes"

bootloader_size="$(stat -c %s "$bootloader_input")"
[ "$bootloader_size" -gt 0 ] || fail "SD U-Boot artifact is empty"
[ "$bootloader_size" -le $((boot_start_mib * bytes_per_mib - sector_bytes)) ] ||
    fail "SD U-Boot does not fit before the FAT partition"

work_dir=/work
unpack_dir="$work_dir/package-check"
fat_image="$work_dir/installer-fat.img"
disk_image="$output_dir/disk.img"
mkdir -p "$unpack_dir" "$output_dir"

aml_image_v2_packer -c "$package_input"
aml_image_v2_packer -d "$package_input" "$unpack_dir" >/dev/null
[ -f "$unpack_dir/image.cfg" ] || fail "Amlogic package did not unpack its manifest"
find "$unpack_dir" -mindepth 1 -type f -printf '%P\n' | awk '$0 != "image.cfg"' | LC_ALL=C sort -u > "$work_dir/unpacked-payload-files"
if ! cmp -s "$expected_package_files" "$work_dir/unpacked-payload-files"; then
    diff -u "$expected_package_files" "$work_dir/unpacked-payload-files" >&2 || true
    fail "installer input is not the 18-file complete Amlogic package"
fi
sed -n 's/^[[:space:]]*file="\([^"]*\)".*/\1/p' "$unpack_dir/image.cfg" | LC_ALL=C sort -u > "$work_dir/unpacked-manifest-files"
cmp -s "$expected_package_files" "$work_dir/unpacked-manifest-files" ||
    fail "unpacked Amlogic manifest is not the 18-file complete package"
[ "$(stat -c %s "$unpack_dir/gpt.bin")" -eq 34304 ] ||
    fail "complete package gpt.bin is not the required 34304-byte Amlogic GPT payload"

printf '%b' "$request_content" > "$work_dir/$request_file"
[ "$(stat -c %s "$work_dir/$request_file")" -eq 17 ] || fail "request marker is not exactly 17 bytes"
package_identity="$(sha256sum "$package_input" | awk '{ print $1 }')"
printf '%s\n' "$package_identity" > "$work_dir/$identity_file"
[ "$(stat -c %s "$work_dir/$identity_file")" -eq "$identity_bytes" ] ||
    fail "package identity is not ${identity_bytes} bytes"
LC_ALL=C grep -qxE "[0-9a-f]{${sha256_hex_bytes}}" "$work_dir/$identity_file" ||
    fail "package identity is not a lowercase SHA-256 digest"

fat_bytes=$((fat_mib * bytes_per_mib))
truncate -s "$fat_bytes" "$fat_image"
mkfs.vfat --invariant -F 32 -n EMMCUPDATE "$fat_image" >/dev/null
mcopy -i "$fat_image" "$package_input" "::/$package_name"
mcopy -i "$fat_image" "$config" "::/$config_name"
mcopy -i "$fat_image" "$work_dir/$request_file" "::/$request_file"
mcopy -i "$fat_image" "$work_dir/$identity_file" "::/$identity_file"

fat_start_sector=$((boot_start_mib * bytes_per_mib / sector_bytes))
fat_sectors=$((fat_bytes / sector_bytes))
fat_end_sector=$((fat_start_sector + fat_sectors - 1))
disk_mib=$((boot_start_mib + fat_mib + disk_tail_mib))
disk_bytes=$((disk_mib * bytes_per_mib))
truncate -s "$disk_bytes" "$disk_image"
parted -s -a none "$disk_image" mklabel msdos
parted -s -a none "$disk_image" unit s mkpart primary fat32 "${fat_start_sector}s" "${fat_end_sector}s"
parted -s "$disk_image" set 1 lba on
dd if="$bootloader_input" of="$disk_image" bs=512 seek=1 conv=notrunc status=none
dd if="$fat_image" of="$disk_image" bs=1M seek="$boot_start_mib" conv=notrunc status=none

[ "$(stat -c %s "$disk_image")" -eq "$disk_bytes" ] || fail "disk image has the wrong size"
mapfile -t partition_lines < <(parted -ms "$disk_image" unit s print | awk -F: '$1 ~ /^[0-9]+$/ { print }')
[ "${#partition_lines[@]}" -eq 1 ] || fail "installer image must contain exactly one partition"
IFS=: read -r partition_number partition_start partition_end partition_size partition_fs partition_name partition_flags <<< "${partition_lines[0]}"
[ "$partition_number" = 1 ] || fail "installer FAT is not partition 1"
[ "$partition_start" = "${fat_start_sector}s" ] || fail "installer FAT starts at ${partition_start}, not ${fat_start_sector}s"
[ "$partition_end" = "${fat_end_sector}s" ] || fail "installer FAT ends at ${partition_end}, not ${fat_end_sector}s"
[ "$partition_size" = "${fat_sectors}s" ] || fail "installer FAT has ${partition_size}, not ${fat_sectors}s"
[ "$partition_fs" = fat32 ] || fail "installer partition is not FAT32"
case "$partition_flags" in
*lba*) ;;
*) fail "installer FAT partition is missing the LBA flag" ;;
esac

dd if="$disk_image" bs=1 skip="$sector_bytes" count="$bootloader_size" status=none \
    of="$work_dir/bootloader.readback"
cmp -s "$bootloader_input" "$work_dir/bootloader.readback" ||
    fail "LBA-1 U-Boot does not round-trip through the installer image"

fat_device="${disk_image}@@$((boot_start_mib * bytes_per_mib))"
mcopy -i "$fat_device" "::/$package_name" "$work_dir/update.readback"
mcopy -i "$fat_device" "::/$config_name" "$work_dir/config.readback"
mcopy -i "$fat_device" "::/$request_file" "$work_dir/request.readback"
mcopy -i "$fat_device" "::/$identity_file" "$work_dir/identity.readback"
cmp -s "$package_input" "$work_dir/update.readback" || fail "package did not round-trip through FAT"
cmp -s "$config" "$work_dir/config.readback" || fail "private config did not round-trip through FAT"
cmp -s "$work_dir/$request_file" "$work_dir/request.readback" || fail "request marker did not round-trip through FAT"
cmp -s "$work_dir/$identity_file" "$work_dir/identity.readback" || fail "package identity did not round-trip through FAT"
[ "$(stat -c %s "$work_dir/identity.readback")" -eq "$identity_bytes" ] ||
    fail "read-back package identity is not ${identity_bytes} bytes"
LC_ALL=C grep -qxE "[0-9a-f]{${sha256_hex_bytes}}" "$work_dir/identity.readback" ||
    fail "read-back package identity is not a lowercase SHA-256 digest"
readback_identity="$(sha256sum "$work_dir/update.readback" | awk '{ print $1 }')"
printf '%s\n' "$readback_identity" > "$work_dir/update.readback.sha256"
cmp -s "$work_dir/update.readback.sha256" "$work_dir/identity.readback" ||
    fail "read-back package identity does not match the package"

printf '%s\n' "$package_name" "$config_name" "$request_file" "$identity_file" | LC_ALL=C sort > "$work_dir/expected-fat-files"
LC_ALL=C mdir -/ -b -i "$fat_device" ::/ | sed 's#^::/##' | LC_ALL=C sort -u > "$work_dir/fat-files"
cmp -s "$work_dir/expected-fat-files" "$work_dir/fat-files" ||
    fail "installer FAT does not contain exactly the four required files"
# The receipt is a U-Boot environment variable and has not been a file since
# RFCT-940, but a card carrying the old file would still be wrong: the receipt
# belongs to one eMMC, not to a card that installs many.
for forbidden in boot.ini boot.scr Image s7d_s905x5m_m100.dtb \
                 aml_sdc_burn.ini aml_sdc_burn.auto.ini \
                 emmc-system-installed.sha256; do
    if mcopy -i "$fat_device" "::/$forbidden" "$work_dir/forbidden.readback" 2>/dev/null; then
        fail "installer media unexpectedly contains ${forbidden}"
    fi
done

fat_listing="$(LC_ALL=C mdir -i "$fat_device" ::/)"
free_bytes="$(printf '%s\n' "$fat_listing" | sed -n 's/^[[:space:]]*\([0-9][0-9, ]*\)[[:space:]]*bytes free$/\1/p' | tr -d ' ,')"
case "$free_bytes" in
''|*[!0-9]*) fail "could not read FAT free space from the final image" ;;
esac
[ "$free_bytes" -ge $((minimum_free_mib * bytes_per_mib)) ] ||
    fail "installer FAT has ${free_bytes} free bytes; need at least ${minimum_free_mib} MiB"

disk_sha256="$(sha256sum "$disk_image" | awk '{ print $1 }')"
printf '>> installer image=%s bytes=%s sha256=%s\n' "$disk_image" "$disk_bytes" "$disk_sha256"
printf '>> installer FAT start=%ss sectors=%s size=%sMiB free=%s bytes package=%s bytes\n' \
    "$fat_start_sector" "$fat_sectors" "$fat_mib" "$free_bytes" "$package_size"
printf '%s\n' "$fat_listing"
