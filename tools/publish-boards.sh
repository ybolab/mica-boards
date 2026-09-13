#!/usr/bin/env bash
# Publish every board's bundle as its OCI artifact.
#
#   bash tools/publish-boards.sh            every board whose kernel archive the pool holds
#
#   reads   _out/debs/<arch>/pool/mica-kernel-<board>_*.deb   (the bundle, packed by the kernel producer)
#           <board>/board.env                                  (which boards, and each one's architecture)
#   writes  <registry>/mica-board/<board>:build-<commit12>, one layer per bundle
#           file (application/vnd.mica.board.<kind>, titled with the file's
#           path under the bundle), annotated mica.board, mica.arch,
#           mica.verity-cert-sha256, mica.source-commit
#
# The bundle is what mica:docs/boards/contract.md section 3 lists: board.env,
# evidence.json, manifests/, kernel/, firmware/, uboot/, trust/. The kernel
# archive stays in the pool for the package gate; the assembly reads the
# board out of this artifact (deps/boards/<board>.json pins its digest) and
# never unpacks the archive. firmware/ is one tar layer: it is hundreds of
# blobs, and a manifest is not a filesystem.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${HERE}/.." && pwd)"
# shellcheck disable=SC1091
. "${REPO_ROOT}/build-env/deb/registry.sh"

for t in curl sha256sum python3 git jq tar; do
    command -v "${t}" >/dev/null 2>&1 || { echo "error: ${t} is required and not on PATH" >&2; exit 1; }
done
registry_load
registry_repo_name
registry_token --write
[ -z "$(git -C "${REPO_ROOT}" status --porcelain)" ] || { echo "error: ${REPO_ROOT} has uncommitted changes; a bundle is published as the output of one commit" >&2; exit 1; }
HEAD_COMMIT="$(git -C "${REPO_ROOT}" rev-parse HEAD)"
HEAD_CREATED="$(git -C "${REPO_ROOT}" show -s --format=%cI HEAD)"
TAG="$(release_tag "${HEAD_COMMIT}")"
POOL_ROOT="${MICA_POOL_DIR:-${REPO_ROOT}/_out/debs}"
FIELDS="python3 ${REPO_ROOT}/build-env/deb/control-fields.py"

WORK="$(mktemp -d "${REPO_ROOT}/_out/.publish-boards.XXXXXX")"
trap 'rm -rf "${WORK}"' EXIT

# The media type of a bundle file, by the directory it is under.
kind_of() { case "$1" in board.env) echo env ;; evidence.json) echo evidence ;; manifests/*) echo manifest ;; kernel/*) echo kernel ;; uboot/*) echo uboot ;; trust/*) echo trust ;; *) echo file ;; esac; }

published=0
present=0
for env in "${REPO_ROOT}"/boards/*/board.env; do
    board="$(basename "$(dirname "${env}")")"
    arch="$(sed -n 's/^MICA_ARCH=//p' "${env}")"
    debs=("${POOL_ROOT}/${arch}/pool/mica-kernel-${board}_"*"_${arch}.deb")
    [ -e "${debs[0]}" ] || { echo "publish-boards.sh: ${board}: no mica-kernel-${board} archive in the ${arch} pool; not published"; continue; }
    [ "${#debs[@]}" -eq 1 ] || { echo "error: ${board}: ${#debs[@]} kernel archives in the ${arch} pool" >&2; exit 1; }
    deb="${debs[0]}"
    mapfile -t got < <(${FIELDS} "${deb}" Version Mica-Source-Commit)
    case "${got[0]:-}" in *.dirty-*) echo "error: ${deb##*/} is a dirty archive; commit, rebuild, publish" >&2; exit 1 ;; esac
    [ "${got[1]:-}" = "${HEAD_COMMIT}" ] || { echo "error: ${deb##*/} was built from ${got[1]:-(none)}, and HEAD is ${HEAD_COMMIT}" >&2; exit 1; }

    # The bundle, out of the archive, into <work>/<board>/.
    stage="${WORK}/${board}"
    mkdir -p "${stage}"
    python3 - "${deb}" "usr/lib/mica/board/${board}/" "${stage}" <<'PY'
import io, os, sys, tarfile
archive, prefix, dest = sys.argv[1], sys.argv[2], sys.argv[3]
data = open(archive, 'rb').read()
assert data[:8] == b'!<arch>\n'
at = 8
while at + 60 <= len(data):
    name = data[at:at + 16].decode('ascii', 'replace').strip().rstrip('/')
    size = int(data[at + 48:at + 58].decode('ascii').strip())
    body = data[at + 60:at + 60 + size]
    at += 60 + size + (size & 1)
    if not name.startswith('data.tar'): continue
    with tarfile.open(fileobj=io.BytesIO(body), mode='r:*') as tar:
        for m in tar.getmembers():
            rel = m.name.lstrip('./')
            if not rel.startswith(prefix): continue
            out = os.path.join(dest, rel[len(prefix):])
            if m.isdir(): os.makedirs(out, exist_ok=True); continue
            if not m.isfile(): raise SystemExit(f'error: {rel} is not a regular file in {archive}')
            os.makedirs(os.path.dirname(out), exist_ok=True)
            with open(out, 'wb') as f: f.write(tar.extractfile(m).read())
    break
PY
    for f in board.env manifests/board.pkgs kernel/kernel.release trust/verity-signer.cert.pem; do
        [ -e "${stage}/${f}" ] || { echo "error: ${deb##*/} carries no ${f}; it is not a board bundle (mica:docs/boards/contract.md section 3)" >&2; exit 1; }
    done
    # firmware/ as one reproducible tar: sorted, owned by root, epoch mtime.
    if [ -d "${stage}/firmware" ]; then
        (cd "${stage}" && find firmware -type f | LC_ALL=C sort | tar --owner=0 --group=0 --numeric-owner --mtime='@0' --no-recursion -cf firmware.tar -T -)
        rm -rf "${stage}/firmware"
    fi
    : >"${WORK}/${board}.layers.tsv"
    while IFS= read -r f; do
        printf '%s\t%s\t%s\n' "${stage}/${f}" "application/vnd.mica.board.$(kind_of "${f}")" "${f}" >>"${WORK}/${board}.layers.tsv"
    done < <(cd "${stage}" && find . -type f -printf '%P\n' | LC_ALL=C sort)
    cert_sha="$(sha256sum "${stage}/trust/verity-signer.cert.pem" | cut -d' ' -f1)"
    jq -n --arg repo "${REPO_NAME}" --arg commit "${HEAD_COMMIT}" --arg created "${HEAD_CREATED}" --arg board "${board}" --arg arch "${arch}" --arg cert "${cert_sha}" \
        '{"org.opencontainers.image.revision": $commit, "org.opencontainers.image.created": $created, "org.opencontainers.image.source": $repo,
          "mica.source-repo": $repo, "mica.source-commit": $commit, "mica.board": $board, "mica.arch": $arch, "mica.verity-cert-sha256": $cert}' >"${WORK}/${board}.annotations.json"

    artifact="$(oci_repo board "${board}")"
    status="$(oci_manifest_get "${artifact}" "${TAG}" "${WORK}/${board}.existing.json")"
    case "${status}" in
    200)
        while IFS=$'\t' read -r file media title; do
            sha="sha256:$(sha256sum "${file}" | cut -d' ' -f1)"
            have="$(jq -r --arg t "${title}" '.layers[] | select(.annotations["org.opencontainers.image.title"] == $t) | .digest' "${WORK}/${board}.existing.json")"
            [ "${have}" = "${sha}" ] || { echo "error: ${OCI_HOST}/${artifact}:${TAG} exists and carries ${title} at ${have:-nothing}, and this bundle has ${sha}; under one name the registry holds other bytes" >&2; exit 1; }
        done <"${WORK}/${board}.layers.tsv"
        present=$((present + 1))
        echo "publish-boards.sh: ${OCI_HOST}/${artifact}:${TAG} exists with this bundle"
        ;;
    404)
        digest="$(oci_push "${artifact}" "${TAG}" application/vnd.mica.board "${WORK}/${board}.annotations.json" "${WORK}/${board}.layers.tsv")" || exit 1
        published=$((published + 1))
        echo "publish-boards.sh: ${board} (${arch}, $(wc -l <"${WORK}/${board}.layers.tsv") layers) pushed as ${OCI_HOST}/${artifact}:${TAG} (${digest})"
        ;;
    401 | 403) echo "error: the registry answered ${status} for ${OCI_HOST}/${artifact}; ${MICA_RELEASE_TOKEN_VAR} does not grant access" >&2; exit 1 ;;
    000) echo "error: ${OCI_HOST} could not be reached (transport failure)" >&2; exit 1 ;;
    *) echo "error: reading ${OCI_HOST}/${artifact}:${TAG} answered HTTP ${status}" >&2; exit 1 ;;
    esac
    # Read back: the manifest by tag resolves to what was pushed, every layer at its digest.
    status="$(oci_manifest_get "${artifact}" "${TAG}" "${WORK}/${board}.back.json")"
    [ "${status}" = 200 ] || { echo "error: reading ${OCI_HOST}/${artifact}:${TAG} back answered HTTP ${status}" >&2; exit 1; }
    while IFS=$'\t' read -r file media title; do
        sha="sha256:$(sha256sum "${file}" | cut -d' ' -f1)"
        [ "$(jq -r --arg t "${title}" '.layers[] | select(.annotations["org.opencontainers.image.title"] == $t) | .digest' "${WORK}/${board}.back.json")" = "${sha}" ] || { echo "error: ${OCI_HOST}/${artifact}:${TAG} serves ${title} at another digest than ${sha}" >&2; exit 1; }
    done <"${WORK}/${board}.layers.tsv"
    echo "publish-boards.sh: ${board}: ${OCI_HOST}/${artifact}:${TAG} $(oci_manifest_digest "${WORK}/${board}.back.json")"
done
echo "publish-boards.sh: ${published} board(s) pushed, ${present} already present"
