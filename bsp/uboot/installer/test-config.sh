#!/usr/bin/env bash
set -euo pipefail

# Assert the source-level contract shared by the BM201 installer wrapper and
# the file-only card producer. The runtime state machine is intentionally not
# represented here: it remains covered by emmc_installer_test.c.

header=${1:?usage: test-config.sh HEADER CONFIG COMPLETE_PACKAGE_FILES EMMC_MANIFEST}
config=${2:?usage: test-config.sh HEADER CONFIG COMPLETE_PACKAGE_FILES EMMC_MANIFEST}
expected_files=${3:?usage: test-config.sh HEADER CONFIG COMPLETE_PACKAGE_FILES EMMC_MANIFEST}
manifest=${4:?usage: test-config.sh HEADER CONFIG COMPLETE_PACKAGE_FILES EMMC_MANIFEST}

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

for file in "$header" "$config" "$expected_files" "$manifest"; do
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

config_value() {
    local name=$1
    local -a values=()

    mapfile -t values < <(
        awk -F= -v name="$name" '
            {
                key = $1
                gsub(/[[:space:]]/, "", key)
                if (key == name) {
                    value = $2
                    gsub(/[[:space:]]/, "", value)
                    print value
                }
            }
        ' "$config"
    )
    [ "${#values[@]}" -eq 1 ] || fail "private config must define ${name} exactly once"
    printf '%s\n' "${values[0]}"
}

fat_mib="$(header_value BM201_INSTALLER_FAT_MIB)"
max_package_mib="$(header_value BM201_INSTALLER_MAX_PACKAGE_MIB)"
request_file="$(header_value BM201_INSTALLER_REQUEST_FILE)"
request_content="$(header_value BM201_INSTALLER_REQUEST_CONTENT)"
identity_file="$(header_value BM201_INSTALLER_IDENTITY_FILE)"
receipt_env="$(header_value BM201_INSTALLER_RECEIPT_ENV)"
sha256_hex_bytes="$(header_value BM201_INSTALLER_SHA256_HEX_BYTES)"
identity_bytes="$(header_value BM201_INSTALLER_IDENTITY_BYTES)"
config_name="$(header_value BM201_INSTALLER_CONFIG)"
package_name="$(header_value BM201_INSTALLER_PACKAGE)"

[ "$fat_mib" = 1792 ] || fail "installer FAT must be 1792 MiB; got ${fat_mib}"
[ "$max_package_mib" = 1536 ] || fail "installer package bound must be 1536 MiB; got ${max_package_mib}"
[ "$request_file" = emmc-system-install.request ] || fail "unexpected request file: ${request_file}"
[ "$request_content" = 'BM201_INSTALL_V2\n' ] || fail "unexpected request content"
[ "$identity_file" = update.img.sha256 ] || fail "unexpected identity file: ${identity_file}"
[ "$receipt_env" = bm201_installed_package ] || fail "unexpected receipt variable: ${receipt_env}"
[ "$sha256_hex_bytes" = 64 ] || fail "unexpected SHA-256 identity length: ${sha256_hex_bytes}"
[ "$identity_bytes" = 65 ] || fail "unexpected identity byte count: ${identity_bytes}"
[ "$config_name" = bm201upd.ini ] || fail "unexpected private config name: ${config_name}"
[ "$config_name" != aml_sdc_burn.ini ] || fail "private config must not use the vendor magic name"
[[ "$config_name" =~ ^[[:alnum:]]{1,8}\.[[:alnum:]]{1,3}$ ]] ||
    fail "private config is not 8.3-compatible: ${config_name}"
[ "$package_name" = update.img ] || fail "unexpected package name: ${package_name}"
[ "$(basename "$config")" = "$config_name" ] ||
    fail "private config filename does not match the installer header"
[ "$(printf '%b' "$request_content" | wc -c | tr -d ' ')" = 17 ] ||
    fail "request marker is not exactly 17 bytes"

[ "$(config_value erase_bootloader)" = 1 ] ||
    fail "private config must erase the old bootloader for a complete package"
[ "$(config_value erase_flash)" = 1 ] ||
    fail "private config must erase the eMMC user area for a complete package"
[ "$(config_value reboot)" = 3 ] ||
    fail "private config must leave reset to the receipt wrapper"
[ "$(config_value package)" = "$package_name" ] ||
    fail "private config package does not match the installer header"

[ "$(wc -l < "$expected_files" | tr -d ' ')" = 18 ] ||
    fail "complete package list must contain 18 entries"
LC_ALL=C sort -cu "$expected_files" ||
    fail "complete package list must be sorted and contain no duplicate names"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
sed -n 's/^[[:space:]]*file="\([^"]*\)".*/\1/p' "$manifest" | LC_ALL=C sort -u > "$tmp_dir/manifest-files"
cmp -s "$expected_files" "$tmp_dir/manifest-files" ||
    fail "complete package list diverges from config/emmc.cfg"
grep -Eq '^file="gpt\.bin"[[:space:]]+main_type="bin"[[:space:]]+sub_type="gpt"' "$manifest" ||
    fail "complete package manifest is missing the special GPT destination"

printf 'ok: private installer contract uses %s MiB FAT, %s MiB package bound, and 18 complete-package entries\n' \
    "$fat_mib" "$max_package_mib"
