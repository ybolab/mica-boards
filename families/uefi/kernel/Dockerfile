# syntax=docker/dockerfile:1@sha256:ecfaec9ed6d810b56388c508f4121597bfbba70d41a6dfeee4d8cad5f295fc32
# check=skip=InvalidDefaultArgInFrom
# The uefi family's kernel: mainline stable, configured by this repository,
# built here -- one Dockerfile for every board that boots a signed UKI through
# systemd-boot. The BUILD CONTEXT is the board's bsp/kernel/ directory (its
# versions.env pins the tag and the tree hash; config/<board>.fragment and
# config/<board>.config are its configuration), and the family's Makefile.inc
# hands in what differs per architecture as build arguments:
#
#   BOARD                 the board's name: its config files and its messages
#   KERNEL_SOURCE         the repository versions.env's tag is fetched from (family.env)
#   KERNEL_DEFCONFIG      x86_64_defconfig | defconfig -- the base the fragments are the delta to
#   KERNEL_IMAGE          bzImage | Image -- the Kbuild target and the artifact's name
#   KERNEL_IMAGE_PATH     where Kbuild leaves it
#   KERNEL_MAKE_ENV       `ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-` when crossing, empty when native
#   KERNEL_CROSS_PACKAGES the cross toolchain packages, empty when native
#
#   make kernel          -> _out/<board>/kernel/{bzImage|Image,modules.tar,config,kernel.release}
#   make kernel-config   -> rewrites config/<board>.config from this build
#
# WHY THIS EXISTS. x64 used to depend on Debian's linux-image-amd64. That
# kernel has no CONFIG_DM_INIT, so the `dm-mod.create=` verity table the
# composer writes was silently ignored on this board and an initramfs had to
# re-implement it -- a second reader of the one boot contract. PLAN-074
# carries the measurements and the decision. This producer embeds the explicit
# public content anchor and configures signature-required verity, storage and
# watchdog support for native early init.
#
# CROSS-COMPILED, NOT EMULATED. `FROM --platform=$BUILDPLATFORM` pins this to
# the builder's own architecture and the toolchain does the crossing, exactly
# as the FIT families do. Compiling an arm64 kernel under user-mode emulation
# would work and would take many times longer for an identical result; nothing
# in this stage needs to RUN a target binary.

# The builder image, injected from build-env/images.env by build-env/from.sh,
# which Makefile.inc calls. Ubuntu 24.04 and not mica-build-c, the choice every
# family makes and for the same structural reason: a BSP builder is pinned by
# digest and depends on nothing this repository has to build first, so `make
# <board>-kernel` works on a fresh checkout without a forty-minute `make
# build-env` in front of it. There is no default: without a value docker
# refuses before any stage runs, where a default would build green against an
# image nobody chose.
ARG MICA_IMAGE_UBUNTU_2404
FROM --platform=$BUILDPLATFORM ${MICA_IMAGE_UBUNTU_2404} AS toolchain

ARG DEBIAN_FRONTEND=noninteractive
# No device-tree compiler: a UEFI machine's firmware describes the hardware,
# so there is no .dts in this family and nothing to compile. The cross
# toolchain is installed only when the board's architecture is not the
# builder's; an empty KERNEL_CROSS_PACKAGES installs nothing more.
ARG KERNEL_CROSS_PACKAGES
RUN apt-get update && apt-get install -y --no-install-recommends \
        git ca-certificates build-essential bc bison flex \
        libssl-dev libelf-dev python3 kmod cpio xz-utils zstd \
        ${KERNEL_CROSS_PACKAGES} \
    && rm -rf /var/lib/apt/lists/*

# THE SOURCE, at the tag versions.env pins, hashed as a tree and compared
# against the hash recorded beside the tag. `git archive` of the tag is
# hashed rather than a tarball: a release tarball can be re-rolled and a tag
# can be moved, while the archive is a deterministic byte stream over the
# source that is actually compiled. PENDING prints the hash and refuses, so
# recording it is an act rather than a copy from a page nobody re-checked.
FROM toolchain AS src
ARG BOARD
ARG KERNEL_SOURCE
COPY versions.env /versions.env
RUN set -eu; . /versions.env; \
    git clone --quiet --depth 1 --branch "${KERNEL_VERSION}" "${KERNEL_SOURCE}" /ksrc; \
    got="$(git -C /ksrc archive --format=tar "${KERNEL_VERSION}" | sha256sum | cut -d' ' -f1)"; \
    if [ "${KERNEL_SHA256}" = "PENDING" ]; then \
        echo "HASH linux ${KERNEL_VERSION} ${got}"; \
        echo "error: the ${BOARD} kernel is pinned to ${KERNEL_VERSION} with no hash. Record KERNEL_SHA256=${got} in bsp/kernel/versions.env and run again; until then this build would compile whatever the tag points at today, which is a different fact from the source this tree agreed to ship" >&2; exit 1; \
    elif [ "${KERNEL_SHA256}" != "${got}" ]; then \
        echo "error: linux ${KERNEL_VERSION} hashes to ${got}, but bsp/kernel/versions.env pins ${KERNEL_SHA256}. Either the tag was moved upstream or the pin is stale; do not paste the new hash in without finding out which" >&2; exit 1; \
    else \
        echo "ok linux ${KERNEL_VERSION} ${got}"; \
    fi; \
    rm -rf /ksrc/.git

# THE CONFIGURATION, resolved. Separated from the gate below so that `make
# kernel-config` can export the resolved .config WITHOUT the diff that is
# about to refuse it: a refresh path that had to pass the check it exists to
# update would be no refresh path.
#
# The defconfig is the base and the two fragments are the delta: the shared
# floor every board holds (boot/common/mos-required.fragment, through the named
# build context `mos-common`) and the board's own. `make` runs under
# KERNEL_MAKE_ENV throughout -- `mk` below is that prefix -- so a cross build
# and a native one differ in one variable and nowhere in this file.
FROM src AS kconfig
ARG BOARD
ARG KERNEL_DEFCONFIG
ARG KERNEL_MAKE_ENV
COPY --from=mos-common mos-required.fragment /mos-required.fragment
COPY config/${BOARD}.fragment /board.fragment
# The verity content anchor, from the named build context `mos-trust`
# (Makefile.inc stages it). It is the file the shared fragment names in
# CONFIG_SYSTEM_TRUSTED_KEYS, and certs/Makefile resolves that relative path
# against the source tree. Public material only.
COPY --from=mos-trust signer.cert.pem /ksrc/certs/mos-verity-anchor.pem
RUN grep -q 'BEGIN CERTIFICATE' /ksrc/certs/mos-verity-anchor.pem || { \
        echo "error: the file the mos-trust build context supplied is not a PEM certificate. CONFIG_SYSTEM_TRUSTED_KEYS names it, and extract-cert would fail in the middle of the compile instead of here" >&2; exit 1; }
RUN set -eu; cd /ksrc; mk() { env ${KERNEL_MAKE_ENV} make "$@"; }; \
    mk "${KERNEL_DEFCONFIG}"; \
    env ${KERNEL_MAKE_ENV} scripts/kconfig/merge_config.sh -m .config /mos-required.fragment /board.fragment; \
    mk olddefconfig; \
    echo "kernel release: $(mk -s kernelrelease)"
# The resolved config, without the lines that record the toolchain rather
# than the configuration: those differ per builder image and are not what a
# reviewer of config/<board>.config is asked to agree to.
RUN set -eu; \
    grep -E '^(CONFIG_[A-Za-z0-9_]+=|# CONFIG_[A-Za-z0-9_]+ is not set$)' /ksrc/.config \
      | grep -vE '^CONFIG_(CC_VERSION_TEXT|GCC_VERSION|AS_VERSION|LD_VERSION|LLD_VERSION|CLANG_VERSION|PAHOLE_VERSION|RUSTC_VERSION|RUSTC_LLVM_VERSION)=' \
      > /board.config.resolved; \
    echo "resolved config: $(grep -c . /board.config.resolved) lines, $(grep -c '=y$' /board.config.resolved) built in, $(grep -c '=m$' /board.config.resolved) modules"

# The export target for `make kernel-config`. Nothing downstream reads it; it
# exists so the recorded file is produced by the same run that would judge it.
FROM scratch AS config
ARG BOARD
COPY --from=kconfig /board.config.resolved /${BOARD}.config

# THE GATE: the resolved configuration is the recorded one, the floor is
# held, the LSM boot list and the trust anchor are the required ones.
FROM kconfig AS gate
ARG BOARD
COPY config/${BOARD}.config /board.config.recorded
# A resolution that differs from the recorded file is refused with the diff:
# either a fragment changed, or the pinned kernel's defconfig moved underneath
# it. A committed config that nobody re-derives is a file nobody wrote,
# nobody read, and nothing checks.
RUN set -eu; \
    if ! diff -u /board.config.recorded /board.config.resolved > /tmp/config.diff; then \
        echo "error: the resolved kernel config is not the one bsp/kernel/config/${BOARD}.config records. Either a fragment changed, or the pinned kernel's ${KERNEL_DEFCONFIG} moved underneath it. The difference is below; review it, and if it is intended run 'make ${BOARD}-kernel-config' to re-record and commit the result." >&2; \
        sed 's/^/  /' /tmp/config.diff >&2; \
        exit 1; \
    fi; \
    echo "config: the resolved .config matches config/${BOARD}.config ($(grep -c . /board.config.recorded) lines)"
# Every =y line of both fragments survived olddefconfig. Running the loop over
# the shared fragment AND the board one is what makes
# boot/common/mos-required.fragment a floor every board holds rather than a
# suggestion; a symbol olddefconfig dropped is one whose dependencies are no
# longer met in this kernel, not an optional line.
RUN set -eu; cd /ksrc; n=0; \
    for line in $(sed -n 's/^\(CONFIG_[A-Z0-9_]*=y\)$/\1/p' /mos-required.fragment /board.fragment); do \
        n=$((n + 1)); \
        grep -q "^${line}$" .config || { \
            echo "error: missing required option: ${line}. It is named =y in boot/common/mos-required.fragment or bsp/kernel/config/${BOARD}.fragment, and olddefconfig did not keep it -- which means its dependencies are no longer met in this kernel, not that the line is optional." >&2; \
            exit 1; \
        }; \
    done; \
    [ "$n" -gt 0 ] || { echo "error: zero =y lines were read from the fragments, so this loop asserted nothing" >&2; exit 1; }; \
    echo "config: all ${n} required =y options are set"
# The LSM boot list, exactly. SELinux that is compiled in but not in the boot
# list never registers selinuxfs, and the image ships a security module that
# is present and inactive. ONE ENTRY OF THAT LIST IS NOT SATISFIED, ON ANY
# BOARD: the list ends in `bpf` and no kernel in this tree builds
# CONFIG_BPF_LSM, so systemd says "bpf-restrict-fs: BPF LSM hook not enabled
# in the kernel" at every boot. Not switched on here; PLAN-073 *Left owed*
# carries the dependency analysis and owns closing it.
RUN set -eu; cd /ksrc; \
    want="$(grep '^CONFIG_LSM=' /mos-required.fragment)"; \
    [ -n "${want}" ] || { echo "error: boot/common/mos-required.fragment declares no CONFIG_LSM, so this assertion has nothing to compare and would pass over anything" >&2; exit 1; }; \
    grep -q "^${want}$" .config || { \
        echo "error: the resolved config's LSM list is not the required one. Wanted ${want}, got $(grep '^CONFIG_LSM=' .config). SELinux that is compiled in but not in the boot list never registers selinuxfs, and the image ships a security module that is present and does nothing." >&2; exit 1; }; \
    echo "config: ${want}"
RUN set -eu; cd /ksrc; \
    want="$(grep '^CONFIG_SYSTEM_TRUSTED_KEYS=' /mos-required.fragment)"; \
    [ -n "${want}" ] || { echo "error: boot/common/mos-required.fragment declares no CONFIG_SYSTEM_TRUSTED_KEYS, so this assertion has nothing to compare and would pass over a kernel that trusts nothing" >&2; exit 1; }; \
    grep -q "^${want}$" .config || { \
        echo "error: the resolved config's trust anchor is not the required one. Wanted ${want}, got $(grep '^CONFIG_SYSTEM_TRUSTED_KEYS=' .config)." >&2; exit 1; }; \
    path="$(printf '%s' "${want}" | sed 's/^CONFIG_SYSTEM_TRUSTED_KEYS=//; s/^"//; s/"$//')"; \
    [ -s "${path}" ] || { echo "error: ${want} names ${path}, which does not exist in the kernel tree. certs/Makefile resolves that path against the source tree, so the compile would fail at extract-cert" >&2; exit 1; }; \
    echo "config: ${want} ($(stat -c%s "${path}") bytes)"

# THE BUILD. Three pins make the image reproducible: without them it carries
# the wall clock and the builder's hostname (`#1 SMP PREEMPT_DYNAMIC Thu Sep 3
# 19:43:59 UTC 2026`, `root@buildkitsandbox`), so two builds of the identical
# pinned source differ and any composed-root comparison gains a content
# difference no sanction could honestly explain. 1577836800 is
# 2020-01-01T00:00:00Z, the same constant board.env pins as FILE_MTIME and
# E2FSPROGS_FAKE_TIME and the same one the composer passes as
# SOURCE_DATE_EPOCH: one instant across every artefact this repository
# produces, so a timestamp anywhere in an image is either that value or a
# defect. Every board is byte-reproducible and may be compared by sha256.
FROM gate AS build
ARG KERNEL_IMAGE
ARG KERNEL_IMAGE_PATH
ARG KERNEL_MAKE_ENV
ENV KBUILD_BUILD_TIMESTAMP="@1577836800" \
    KBUILD_BUILD_USER=mos \
    KBUILD_BUILD_HOST=mica-build
RUN set -eu; cd /ksrc; mk() { env ${KERNEL_MAKE_ENV} make "$@"; }; \
    mk -j"$(nproc)" "${KERNEL_IMAGE}" modules; \
    mk INSTALL_MOD_PATH=/kmods INSTALL_MOD_STRIP=1 modules_install; \
    release="$(cat include/config/kernel.release)"; \
    echo "kernel release: ${release}"; \
    [ -f "/kmods/lib/modules/${release}/modules.builtin" ] || \
        { echo "error: modules_install wrote no modules.builtin for ${release}. Every builtin symbol would then resolve to nothing at modprobe time, and any check that walks that index would report green over an empty directory." >&2; exit 1; }; \
    [ -f "/kmods/lib/modules/${release}/modules.dep" ] || \
        { echo "error: modules_install wrote no modules.dep for ${release}" >&2; exit 1; }; \
    rm -f "/kmods/lib/modules/${release}/build" "/kmods/lib/modules/${release}/source"; \
    tar --sort=name --mtime=@1577836800 --owner=0 --group=0 --numeric-owner \
        -C /kmods -cf /modules.tar lib; \
    printf '%s\n' "${release}" > /kernel.release; \
    echo "kernel: ${KERNEL_IMAGE} $(stat -c%s "${KERNEL_IMAGE_PATH}") bytes, $(find /kmods -name '*.ko*' | wc -l) module(s), modules.tar $(stat -c%s /modules.tar) bytes"
# What was compiled, read out of auto.conf rather than out of a config file:
# a config file states an intention, auto.conf states what was compiled.
RUN set -eu; cd /ksrc; \
    for option in DM_INIT DM_VERITY SQUASHFS; do \
        grep -q "^CONFIG_${option}=y" include/config/auto.conf || \
            { echo "error: CONFIG_${option} is not =y in the tree that was just compiled" >&2; exit 1; }; \
    done; \
    echo "kernel: dm-init, dm-verity and squashfs are in the compiled image"

# Export kernel and support inputs independently from userspace. The
# assembly's kernel component signs the resulting UKI and binds the matching
# support identity.
FROM scratch AS artifact
ARG KERNEL_IMAGE_PATH
COPY --from=build /ksrc/${KERNEL_IMAGE_PATH} /
COPY --from=build /ksrc/.config /config
COPY --from=build /modules.tar /
COPY --from=build /kernel.release /
