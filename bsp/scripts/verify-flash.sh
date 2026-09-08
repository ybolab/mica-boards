#!/usr/bin/env bash
# Read the WHOLE written image back off the board and compare it, byte for
# byte, with the file that was written.
#
#   RKDEVELOPTOOL=<path> bash scripts/verify-flash.sh <image>
#
# It runs while the board is still in loader mode -- BEFORE `rkdeveloptool rd`
# -- because that is the only moment at which a bad write is still actionable:
# the board has not booted from it, the host still owns the link, and a
# re-write is one command away. A verification after the reset is a post-mortem.
#
# It compares against THE FILE THAT WAS WRITTEN, not against a checksum
# recomputed from it. A hash the flashing host derives from the bytes it just
# sent proves the host's arithmetic; what is in question is the transfer and the
# medium.
#
# WHY THE WHOLE FILE AND NOT A PREFIX. This read back the first 16 MiB and said
# so, and everything that decides whether the machine runs sits past that
# window: boards/cx3576/board.env puts boot-a at 18 MiB and rootfs-a at 146
# MiB. A cx3576 flash reported success and left the kernel in boot-a as a
# mixture of two builds -- the current build at file offset 0x31da8, the
# previous build's bytes at 0x1e87800 -- and the board died in paging_init. The
# read-back could not see it: the hole was ~22 MiB past the last byte it read.
# docs/task/RFCT-351.md is the diagnosis, docs/task/RFCT-353.md this change.
#
# Cost, measured on the build host (RFCT-353): the comparison reads the image
# and the read-back once each, 180-1160 MB/s off this NVMe, so 15 s at worst
# for the 1.38 GB product image. What it cannot measure is the USB side, which
# has no board here -- but `rkdeveloptool wl` already pushes exactly these bytes
# over exactly this link, so reading them back at most doubles a transfer the
# flash already accepts.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAYOUT_ENV="${HERE}/../../board.env"

# Relative paths stay relative: the caller's working directory is the BSP
# directory, where `tools/rkdeveloptool` and `$(BSP_OUT)/disk.img` both resolve,
# so this script must not cd anywhere.
RKDEVELOPTOOL="${RKDEVELOPTOOL:-rkdeveloptool}"

if [ "$#" -ne 1 ]; then
    echo "usage: RKDEVELOPTOOL=<path> bash scripts/verify-flash.sh <image>" >&2
    exit 2
fi
IMAGE="$1"

if [ ! -f "${IMAGE}" ]; then
    echo "error: there is no image at ${IMAGE} to verify the board against" >&2
    exit 1
fi
if [ ! -f "${LAYOUT_ENV}" ]; then
    echo "error: ${LAYOUT_ENV} not found; the head area cannot be derived" >&2
    exit 1
fi
# shellcheck source=../../board.env
. "${LAYOUT_ENV}"

# WHERE THE HEAD AREA ENDS, derived from the layout three ways rather than
# written here as a number. The three are independent statements in
# boards/cx3576/board.env and they must agree; when a constant moves and they
# stop agreeing, this refuses rather than reading back a window it cannot
# justify. tests/cx3576-flash-verify-test.sh asserts the same identity from
# outside, against the arguments this script actually builds.
head_sectors=$((LOADER_START_SECTOR + LOADER_SIZE_SECTORS))
head_from_uenv="${UENV_A_START_SECTOR}"
head_from_mib=$((IMAGE_HEAD_MIB * MIB_BYTES / SECTOR_SIZE))
if [ "${head_sectors}" -ne "${head_from_uenv}" ] || [ "${head_sectors}" -ne "${head_from_mib}" ]; then
    echo "error: ${LAYOUT_ENV} disagrees with itself about where the head area ends:" >&2
    echo "       LOADER_START_SECTOR + LOADER_SIZE_SECTORS = ${head_sectors}" >&2
    echo "       UENV_A_START_SECTOR                       = ${head_from_uenv}" >&2
    echo "       IMAGE_HEAD_MIB * MIB_BYTES / SECTOR_SIZE  = ${head_from_mib}" >&2
    exit 1
fi
head_bytes=$((head_sectors * SECTOR_SIZE))

# GNU stat and BSD stat spell this differently and the macOS flash path is
# supported (`make rkdeveloptool-macos`), so both spellings are tried.
file_size() { stat -c %s "$1" 2>/dev/null || stat -f %z "$1"; }

size="$(file_size "${IMAGE}")"
# The board reads and writes whole sectors; the image need not be a multiple of
# one. Round the request UP so the last partial sector is fetched, and compare
# only the bytes the file has -- what the medium holds past the end of the file
# was never written by this flash and is not this check's business.
sectors=$(( (size + SECTOR_SIZE - 1) / SECTOR_SIZE ))
if [ "${size}" -le "${head_bytes}" ]; then
    echo "error: ${IMAGE} is ${size} bytes, which is not larger than the ${head_bytes}-byte head area." >&2
    echo "       An image this small is not one of this board's: refusing rather than verifying a prefix." >&2
    exit 1
fi
tail_sectors=$((sectors - head_sectors))
tail_bytes=$((size - head_bytes))

SCRATCH="$(dirname "${IMAGE}")/.verify-flash.img"

# On success the read-back is deleted; on failure it is KEPT and named, because
# it is the board's copy of the image and the only evidence of what the medium
# actually holds.
compare_range() {
    local offset="$1" length="$2" what="$3"
    local out rc=0
    out="$(cmp <(tail -c "+$((offset + 1))" "${IMAGE}" | head -c "${length}") \
               <(head -c "${length}" "${SCRATCH}") 2>&1)" || rc=$?
    if [ "${rc}" -eq 0 ]; then
        return 0
    fi
    # cmp counts bytes from 1 within what it was given, which here starts at
    # ${offset} in the image; report the offset a reader can seek to.
    local byte absolute=""
    byte="$(printf %sn "${out}" | sed -nE 's/.*differ: byte ([0-9]+).*/\1/p' | head -n 1)"
    if [ -n "${byte}" ]; then
        absolute=$((offset + byte - 1))
    fi
    echo "error: the board's copy of ${IMAGE} differs from the file that was written." >&2
    echo "       range: ${what}, image bytes ${offset}..$((offset + length - 1))" >&2
    echo "       cmp:   ${out}" >&2
    if [ -n "${absolute}" ]; then
        echo "       first difference at image byte ${absolute} (0x$(printf %x "${absolute}"))" >&2
    fi
    echo "       the board's copy is kept at ${SCRATCH}; do NOT boot this board." >&2
    return 1
}

# Read back the raw boot area (GPT + idblock + u-boot.itb, first 16 MiB) and
# compare it against the source image; a partial or corrupt write here is the
# one failure that bricks the board past the recovery key.
#
# It is read FIRST, and on its own, for that reason: the region that can brick
# the board is answered in the first second rather than after the whole image
# has come back over USB. The split is about which failure is reported first
# and nothing else -- the second read below covers every remaining byte, so no
# range falls between them.
"${RKDEVELOPTOOL}" rl 0 "${head_sectors}" "${SCRATCH}"
compare_range 0 "${head_bytes}" "boot area (loader + u-boot.itb)"

"${RKDEVELOPTOOL}" rl "${head_sectors}" "${tail_sectors}" "${SCRATCH}"
compare_range "${head_bytes}" "${tail_bytes}" "everything past the boot area"

rm -f "${SCRATCH}"
echo "Verified ${size} bytes (${sectors} sectors) of ${IMAGE} against the board: the whole written image, boot area first."
