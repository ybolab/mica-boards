#!/usr/bin/env bash
# A new board, from one that exists: the directory copied, every name
# rewritten, fresh identities minted, nothing else decided.
#
#   bash tools/new-board.sh <new> --from <existing>
#
# What it does: copies <existing>/ to <new>/ (not its outputs, evidence or
# the signing symlink), renames the files and directories that carry the
# board's name (deb/board-<b>, deb/kernel-<b>, the control files, the
# kernel configuration), rewrites the name as a word inside every file,
# mints a fresh identity code for the GPT and filesystem identities
# (board.env: the 4-hex segment of every 5AC35760-XXXX-... GUID and UUID), a
# fresh ESP volume id where there is one, and sets BOARD_RELEASE_TARGET=0 --
# a new board is not a release target until it is qualified. What it does
# not do: decide the hardware. BOARD_FEATURES, the command line, the
# firmware files, the hwinit facts and the kernel configuration are the
# port's work (mica:docs/boards/porting.md), and tests/board-contract-test.sh
# holds the result to the contract.
#
# A board of a FIT family clones the same way; bsp/bsp.env comes along and
# names the files to change (the defconfig, the device tree, the loader).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
NEW="${1:-}"; [ "${2:-}" = --from ] && FROM="${3:-}" || FROM=""
[ -n "${NEW}" ] && [ -n "${FROM}" ] || { echo "usage: bash tools/new-board.sh <new> --from <existing>" >&2; exit 1; }
[[ "${NEW}" =~ ^[a-z0-9][a-z0-9-]{0,31}$ ]] || { echo "error: '${NEW}' is not a board name (lowercase letters, digits and hyphens)" >&2; exit 1; }
[ -f "${FROM}/board.env" ] || { echo "error: ${FROM} is not a board here; the boards are: $(for d in */; do [ -f "${d}board.env" ] && printf '%s ' "${d%/}"; done)" >&2; exit 1; }
[ ! -e "${NEW}" ] || { echo "error: ${NEW}/ exists" >&2; exit 1; }
command -v uuidgen >/dev/null || { echo "error: uuidgen is required to mint the board's identities" >&2; exit 1; }

# 1. The copy, without what is not source.
mkdir "${NEW}"
(cd "${FROM}" && find . -mindepth 1 \( -path ./_out -o -path ./meta -o -path ./tmp -o -name evidence.json \) -prune -o -print0) |
    (cd "${FROM}" && cpio -0 -pdm --quiet "../${NEW}")
# 2. Paths carrying the name, deepest first so a directory is renamed after its contents.
while IFS= read -r p; do
    d="$(dirname "${p}")"; b="$(basename "${p}")"
    mv "${p}" "${d}/${b//${FROM}/${NEW}}"
done < <(find "${NEW}" -mindepth 1 -depth -name "*${FROM}*")
# 3. The name inside every file, as a word.
while IFS= read -r f; do
    if grep -qE "\b${FROM}\b" "${f}"; then sed -i -E "s/\b${FROM}\b/${NEW}/g" "${f}"; fi
done < <(find "${NEW}" -type f)
# 4. Fresh identities. Every board's GUIDs and filesystem UUIDs share the
#    prefix 5AC35760 and a per-board 4-hex code; the code is what changes.
old_code="$(sed -n 's/^DISK_GUID=[0-9A-Fa-f]\{8\}-\([0-9A-Fa-f]\{4\}\)-.*/\1/p' "${NEW}/board.env" | head -1)"
[ -n "${old_code}" ] || { echo "error: ${NEW}/board.env has no DISK_GUID of the form XXXXXXXX-CCCC-...; the identity code could not be replaced" >&2; exit 1; }
new_code="$(uuidgen | tr -d '-' | cut -c1-4 | tr 'a-f' 'A-F')"
sed -i -E "s/^(([A-Z_]+_GUID)=[0-9A-F]{8})-${old_code}-/\1-${new_code}-/; s/^(([A-Z_]+_FS_UUID)=[0-9a-f]{8})-$(printf '%s' "${old_code}" | tr 'A-F' 'a-f')-/\1-$(printf '%s' "${new_code}" | tr 'A-F' 'a-f')-/" "${NEW}/board.env"
if grep -q '^ESP_FAT_VOLUME_ID=' "${NEW}/board.env"; then
    sed -i -E "s/^ESP_FAT_VOLUME_ID=.*/ESP_FAT_VOLUME_ID=$(uuidgen | tr -d '-' | cut -c1-8 | tr 'a-f' 'A-F')/" "${NEW}/board.env"
fi
sed -i -E 's/^BOARD_RELEASE_TARGET=.*/BOARD_RELEASE_TARGET=0/' "${NEW}/board.env"
grep -c "${new_code}" "${NEW}/board.env" >/dev/null || { echo "error: no identity was rewritten in ${NEW}/board.env" >&2; exit 1; }
# 5. Nothing to route: the Makefile discovers a board by its board.env.
cat <<MSG
new-board: ${NEW}/ created from ${FROM}/ with identity code ${new_code} (was ${old_code}); BOARD_RELEASE_TARGET=0.
  next: edit ${NEW}/board.env (BOARD_FEATURES, the command line, the firmware, hwinit) and ${NEW}/README.md;
        make check                  the contract over every board, ${NEW} included
        make ${NEW}-kernel        the kernel, through the ${NEW}'s family
        make pool && make package-gate && make publish
  then, in the assembly:  make board-add BOARD=${NEW}  and  make product PRODUCT=${NEW}-minimal
MSG
