#!/usr/bin/env bash
# tools/publish-boards.sh against a real registry: a board's bundle is pushed
# as <owner>/mica-boards:board.<board>.build-<commit12>, read back at its
# digest, and a tag that already names another bundle -- other bytes, another
# identity, another layer set -- is refused by name.
#
#   bash tests/publish-boards-test.sh          (docker on the host)
#
# The registry is the image build-env/images.env pins, a sibling container
# spoken to over plain HTTP. The script runs in a clone of HEAD (it publishes
# only a clean tree) with build-env/ copied in, or MICA_TEST_BUILD_ENV, and a
# fixture mica-kernel-x64 archive built from that commit in its pool.
set -euo pipefail
cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"
for t in curl sha256sum jq docker git python3; do
    command -v "${t}" >/dev/null 2>&1 || { echo "error: ${t} is required" >&2; exit 1; }
done
BUILD_ENV="${MICA_TEST_BUILD_ENV:-${REPO_ROOT}/build-env}"
[ -f "${BUILD_ENV}/deb/registry.sh" ] || { echo "error: ${BUILD_ENV} holds no deb/registry.sh; run make deps" >&2; exit 1; }
mkdir -p "${REPO_ROOT}/_out"
WORK="$(mktemp -d "${REPO_ROOT}/_out/publish-boards-test.XXXXXX")"
NAME="ai-agent-publish-boards-test-$$"
cleanup() { docker rm -f "${NAME}" >/dev/null 2>&1 || true; rm -rf "${WORK}"; }
trap cleanup EXIT
PASS_N=0; FAIL_N=0
pass() { PASS_N=$((PASS_N + 1)); echo "PASS: $1"; }
fail() { FAIL_N=$((FAIL_N + 1)); echo "FAIL: $1"; }
says() { grep -c -- "$2" "$1" >/dev/null; }

IMAGE="$(bash build-env/from.sh --ref IMAGE_REGISTRY_2)"
docker run -d --rm --label ai-agent=true --name "${NAME}" --network "${MICA_TEST_NETWORK:-traefik}" "${IMAGE}" >/dev/null
for _ in $(seq 1 30); do curl -sf -o /dev/null "http://${NAME}:5000/v2/" && break; sleep 1; done
curl -sf -o /dev/null "http://${NAME}:5000/v2/" || { echo "error: the registry ${NAME} did not answer" >&2; exit 1; }
REG="http://${NAME}:5000/v2"
MT='application/vnd.oci.image.manifest.v1+json'

CLONE="${WORK}/repo"
git clone -q "${REPO_ROOT}" "${CLONE}"
git -C "${CLONE}" remote set-url origin https://example.invalid/testorg/mica-boards.git
# The working tree's tracked files, so an uncommitted change is what is tested.
git ls-files -z | tar --null -T - -cf - | tar -xf - -C "${CLONE}"
[ -z "$(git -C "${CLONE}" status --porcelain)" ] || git -C "${CLONE}" -c user.name=test -c user.email=test@example.invalid commit -qam "the working tree under test"
cp -a "${BUILD_ENV}" "${CLONE}/build-env"
HEAD="$(git -C "${CLONE}" rev-parse HEAD)"; C12="${HEAD:0:12}"

# A mica-kernel-x64 archive: control fields from <commit>, the bundle under
# usr/lib/mica/board/x64/.
fixture_deb() { # <out> <commit>
    python3 - "$1" "$2" <<'PY'
import io, sys, tarfile
out, commit = sys.argv[1], sys.argv[2]
def tgz(files):
    b = io.BytesIO()
    with tarfile.open(fileobj=b, mode='w:gz') as t:
        for name, data in files:
            i = tarfile.TarInfo(name); i.size = len(data); t.addfile(i, io.BytesIO(data))
    return b.getvalue()
control = (f'Package: mica-kernel-x64\nVersion: 0.1.0+git{commit[:12]}-1\nArchitecture: amd64\n'
           f'Mica-Source-Repo: mica-boards\nMica-Source-Commit: {commit}\n').encode()
p = './usr/lib/mica/board/x64/'
data = [(p + 'board.env', b'MICA_ARCH=amd64\n'), (p + 'manifests/board.pkgs', b'mica-board-x64\n'),
        (p + 'kernel/kernel.release', b'6.12.0-fixture\n'), (p + 'kernel/vmlinuz', b'fixture kernel'),
        (p + 'trust/verity-signer.cert.pem', b'fixture cert\n'), (p + 'firmware/vendor/a.bin', b'fixture firmware')]
with open(out, 'wb') as f:
    f.write(b'!<arch>\n')
    for n, d in [('debian-binary', b'2.0\n'), ('control.tar.gz', tgz([('./control', control)])), ('data.tar.gz', tgz(data))]:
        f.write(f'{n + "/":<16}{0:<12}{0:<6}{0:<6}{"100644":<8}{len(d):<10}`\n'.encode() + d + (b'\n' if len(d) % 2 else b''))
PY
}
POOL="${CLONE}/_out/debs/amd64/pool"
mkdir -p "${POOL}"
DEB="${POOL}/mica-kernel-x64_0.1.0+git${C12}-1_amd64.deb"
fixture_deb "${DEB}" "${HEAD}"

# publish <owner> <log>: the script in the clone, against <registry>/<owner>.
publish() {
    cat >"${WORK}/registry.env" <<ENV
MICA_REGISTRY=${NAME}:5000/$1
MICA_REGISTRY_USER=nobody
MICA_RELEASE_TOKEN_VAR=PUBLISH_TEST_TOKEN
MICA_SOURCE_URL=https://example.invalid/testorg
ENV
    (cd "${CLONE}" && MICA_REGISTRY_ENV="${WORK}/registry.env" MICA_REGISTRY_PLAIN_HTTP=1 MICA_RELEASE_NO_GH=1 PUBLISH_TEST_TOKEN=fixture \
        bash tools/publish-boards.sh) >"$2" 2>&1
}
REF="board.x64.build-${C12}"
manifest() { curl -sf -H "Accept: ${MT}" "${REG}/$1/mica-boards/manifests/${REF}"; } # <owner>
# retag <owner> <jq filter>: overwrite the tag with the existing manifest, edited.
retag() {
    manifest "$1" | jq -c "$2" >"${WORK}/edited.json"
    [ "$(curl -s -o /dev/null -w '%{http_code}' -X PUT -H "Content-Type: ${MT}" --data-binary "@${WORK}/edited.json" "${REG}/$1/mica-boards/manifests/${REF}")" = 201 ]
}

# 1. A first publish: the tag, the identity, the layers, the read-back.
if publish testorg "${WORK}/first.log"; then pass "a first publish succeeds"; else fail "a first publish failed: $(tail -n3 "${WORK}/first.log")"; fi
if M="$(manifest testorg)"; then
    pass "the bundle is <owner>/mica-boards:${REF}"
    [ "$(printf '%s' "${M}" | jq -r '.artifactType')" = application/vnd.mica.board ] && pass "artifactType application/vnd.mica.board" || fail "artifactType is $(printf '%s' "${M}" | jq -r '.artifactType')"
    got="$(printf '%s' "${M}" | jq -r '[.annotations["mica.source-repo"], .annotations["mica.source-commit"], .annotations["mica.board"], .annotations["mica.arch"]] | join(" ")')"
    [ "${got}" = "mica-boards ${HEAD} x64 amd64" ] && pass "annotated mica-boards, the commit, x64, amd64" || fail "annotations are ${got}"
    got="$(printf '%s' "${M}" | jq -r '[.layers[] | .annotations["org.opencontainers.image.title"] + "=" + .mediaType] | sort | join(" ")')"
    [ "${got}" = "board.env=application/vnd.mica.board.env firmware.tar=application/vnd.mica.board.file kernel/kernel.release=application/vnd.mica.board.kernel kernel/vmlinuz=application/vnd.mica.board.kernel manifests/board.pkgs=application/vnd.mica.board.manifest trust/verity-signer.cert.pem=application/vnd.mica.board.trust" ] \
        && pass "one layer per bundle file, the kind in its media type" || fail "layers are ${got}"
    digest="sha256:$(curl -sf -H "Accept: ${MT}" "${REG}/testorg/mica-boards/manifests/${REF}" | sha256sum | cut -d' ' -f1)"
    says "${WORK}/first.log" "${REF} ${digest}" && pass "the read-back names the served manifest digest" || fail "the log does not name ${digest}"
else
    fail "<owner>/mica-boards:${REF} is not in the registry"
fi
[ "$(curl -sf "${REG}/testorg/mica-boards/tags/list" | jq -c .tags)" = "[\"${REF}\"]" ] && pass "the package holds that one tag" || fail "tags: $(curl -s "${REG}/testorg/mica-boards/tags/list")"
[ "$(curl -s -o /dev/null -w '%{http_code}' "${REG}/testorg/mica-board/tags/list")" = 404 ] && pass "nothing lands in the retired mica-board package" || fail "mica-board exists"

# 2. The same bundle again: found, nothing pushed.
if publish testorg "${WORK}/again.log" && says "${WORK}/again.log" "exists with this bundle" && says "${WORK}/again.log" "0 board(s) pushed, 1 already present"; then
    pass "a rerun finds the same bundle and pushes nothing"
else fail "a rerun: $(tail -n3 "${WORK}/again.log")"; fi

# 3-5. The tag names another bundle: refused, whatever differs.
refused() { # <owner> <what> <jq filter> <expected message>
    publish "$1" "${WORK}/$1.seed.log" || { fail "$2: seeding failed: $(tail -n2 "${WORK}/$1.seed.log")"; return; }
    retag "$1" "$3" || { fail "$2: could not overwrite the tag"; return; }
    if publish "$1" "${WORK}/$1.log"; then fail "$2: published over it";
    elif says "${WORK}/$1.log" "$4"; then pass "$2: refused"
    else fail "$2: refused without naming it: $(tail -n2 "${WORK}/$1.log")"; fi
}
refused otherbytes "a layer at other bytes" '(.layers[] | select(.annotations["org.opencontainers.image.title"] == "board.env")) as $o | (.layers[] | select(.annotations["org.opencontainers.image.title"] == "kernel/vmlinuz")) |= (.digest = $o.digest | .size = $o.size)' "kernel/vmlinuz"
refused otherarch "another mica.arch" '.annotations["mica.arch"] = "arm64"' "mica.arch"
refused othercommit "another mica.source-commit" '.annotations["mica.source-commit"] = ("f" * 40)' "mica.source-commit"
refused extralayer "an extra layer" '.layers += [.layers[0] | .annotations["org.opencontainers.image.title"] = "extra"]' "extra"

# 6. An archive built from another commit is not this commit's bundle.
rm -f "${DEB}"; fixture_deb "${POOL}/mica-kernel-x64_0.1.0+gitffffffffffff-1_amd64.deb" "$(printf 'f%.0s' $(seq 40))"
if publish fromelsewhere "${WORK}/elsewhere.log"; then fail "an archive from another commit was published"
elif says "${WORK}/elsewhere.log" "was built from"; then pass "an archive from another commit: refused"
else fail "an archive from another commit: $(tail -n2 "${WORK}/elsewhere.log")"; fi

echo "publish-boards-test: ${PASS_N} passed, ${FAIL_N} failed"
[ "${FAIL_N}" -eq 0 ]
