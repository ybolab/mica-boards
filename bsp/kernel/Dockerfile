# syntax=docker/dockerfile:1@sha256:ecfaec9ed6d810b56388c508f4121597bfbba70d41a6dfeee4d8cad5f295fc32
# check=skip=InvalidDefaultArgInFrom
# The virt-arm64 kernel: mainline stable, configured by this repository, built here.
#
#   make virt-arm64-kernel         -> boards/virt-arm64/bsp/out/kernel/{Image,modules.tar,config,kernel.release}
#   make virt-arm64-kernel-config  -> rewrites config/virt-arm64.config from this build
#
# WHY THIS EXISTS. The boot contract is `dm-mod.create=` on the kernel command
# line with no initrd, which needs CONFIG_DM_INIT. Debian's linux-image-arm64
# does not set it, so that kernel would accept the verity table GRUB writes and
# ignore it silently, leaving no root at all -- and the usual repair is an
# initramfs that re-parses the very line GRUB just wrote, which is a second
# implementation of the one boot contract. x64 shipped exactly that until
# PLAN-074; this board is built so as never to acquire it. PLAN-085 decides.
#
# CROSS-COMPILED, NOT EMULATED. `FROM --platform=$BUILDPLATFORM` pins this to
# the builder's own architecture and the toolchain does the crossing, exactly as
# boards/cx3576/bsp/kernel/Dockerfile does. Compiling an arm64 kernel under
# user-mode emulation would work and would take many times longer for an
# identical result; nothing in this stage needs to RUN an aarch64 binary.

# The builder image, injected from build-env/images.env by build-env/from.sh,
# which boards/virt-arm64/bsp/Makefile calls. Ubuntu 24.04 and not mos-build-c,
# the choice both other boards make and for the same structural reason: a BSP
# builder is pinned by digest and depends on nothing this repository has to
# build first, so `make virt-arm64-kernel` works on a fresh checkout without a
# forty-minute `make build-env` in front of it. Keeping every board's kernel on
# one builder is also what makes a diff of the three Dockerfiles mean something.
# There is no default: without a value docker refuses before any stage runs,
# where a default would build green against an image nobody chose.
ARG MOS_IMAGE_UBUNTU_2404
FROM --platform=$BUILDPLATFORM ${MOS_IMAGE_UBUNTU_2404} AS toolchain

ARG DEBIAN_FRONTEND=noninteractive
# The cross compiler is the difference from the x64 builder. No device-tree
# compiler, which is the difference from the cx3576 one: QEMU's `virt` machine
# generates its own device tree and hands it to the firmware, so there is no
# .dts in this tree and nothing to compile.
RUN apt-get update && apt-get install -y --no-install-recommends \
        git ca-certificates build-essential bc bison flex \
        gcc-aarch64-linux-gnu libc6-dev-arm64-cross \
        libssl-dev libelf-dev python3 kmod cpio xz-utils zstd \
    && rm -rf /var/lib/apt/lists/*

# --- the source ------------------------------------------------------------
FROM toolchain AS src
COPY kernel/versions.env /versions.env

# The tag is fetched and the TREE is hashed, not a tarball: a release tarball
# can be re-rolled and a tag can be moved, while `git archive` of the tag is a
# deterministic byte stream over the source that is actually compiled. This is
# pkgs/rauc/Dockerfile's discipline, reused rather than reinvented.
#
# A PENDING pin prints the hash it computed and fails, with deliberately no
# environment variable that softens it: a pin that only warns floats for as
# long as nobody reads a log.
RUN set -eu; . /versions.env; \
    git clone --quiet --depth 1 --branch "${KERNEL_VERSION}" \
        https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git /ksrc; \
    got="$(git -C /ksrc archive --format=tar "${KERNEL_VERSION}" | sha256sum | cut -d' ' -f1)"; \
    if [ "${KERNEL_SHA256}" = "PENDING" ]; then \
        echo "HASH linux ${KERNEL_VERSION} ${got}"; \
        echo "error: the virt-arm64 kernel is pinned to ${KERNEL_VERSION} with no hash. Record KERNEL_SHA256=${got} in boards/virt-arm64/bsp/kernel/versions.env and run again; until then this build would compile whatever the tag points at today, which is a different fact from the source this tree agreed to ship" >&2; exit 1; \
    elif [ "${KERNEL_SHA256}" != "${got}" ]; then \
        echo "error: linux ${KERNEL_VERSION} hashes to ${got}, but boards/virt-arm64/bsp/kernel/versions.env pins ${KERNEL_SHA256}. Either the tag was moved upstream or the pin is stale; do not paste the new hash in without finding out which" >&2; exit 1; \
    else \
        echo "ok linux ${KERNEL_VERSION} ${got}"; \
    fi; \
    rm -rf /ksrc/.git

# --- the configuration -----------------------------------------------------
# Separated from the gate below so that `make virt-arm64-kernel-config` can
# export the resolved .config WITHOUT the diff that is about to refuse it. A
# refresh path that had to pass the check it exists to update would be no
# refresh path.
FROM src AS kconfig

# The shared mos runtime baseline, from boards/common/ -- requires the named
# build context: docker buildx build --build-context mos-common=../../common
# (wired in boards/virt-arm64/bsp/Makefile; a bare build without it fails here,
# loudly). Merged FIRST, so a board line that contradicted it would be the one
# reported as the override.
COPY --from=mos-common mos-required.fragment /mos-required.fragment
COPY kernel/config/virt-arm64.fragment /virt-arm64.fragment

# arm64's `defconfig` is the base and the two fragments are the delta. The
# alternative -- one recorded full config, which is what cx3576 keeps -- makes
# the reason a symbol is set unrecoverable: 6000 lines of generated text carry
# no argument. Here the argument is in the fragments and the RESULT is recorded
# beside them, so a kernel bump is reviewed as a diff of what upstream moved.
#
# `defconfig` and not `virt_defconfig`: arm64 has no per-machine defconfigs.
# One `defconfig` covers every arm64 platform, which is why the fragment beside
# this can be short -- it names what the machine needs, not what it lacks.
ENV ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
RUN set -eu; cd /ksrc; \
    make defconfig; \
    scripts/kconfig/merge_config.sh -m .config /mos-required.fragment /virt-arm64.fragment; \
    make olddefconfig; \
    echo "kernel release: $(make -s kernelrelease)"

# The recorded form: set symbols and explicit `is not set` lines, minus the
# toolchain-derived version strings. Those name the BUILDER rather than the
# configuration -- CONFIG_CC_VERSION_TEXT is literally gcc's --version output --
# so leaving them in would make every builder-image bump land as a config diff
# whose every line is about something else. The builder is pinned by digest one
# level up; this file is the configuration.
RUN set -eu; \
    grep -E '^(CONFIG_[A-Za-z0-9_]+=|# CONFIG_[A-Za-z0-9_]+ is not set$)' /ksrc/.config \
      | grep -vE '^CONFIG_(CC_VERSION_TEXT|GCC_VERSION|AS_VERSION|LD_VERSION|LLD_VERSION|CLANG_VERSION|PAHOLE_VERSION|RUSTC_VERSION|RUSTC_LLVM_VERSION)=' \
      > /virt-arm64.config.resolved; \
    echo "resolved config: $(grep -c . /virt-arm64.config.resolved) lines, $(grep -c '=y$' /virt-arm64.config.resolved) built in, $(grep -c '=m$' /virt-arm64.config.resolved) modules"

# The export target for `make virt-arm64-kernel-config`. Nothing downstream
# reads it; it exists so the recorded file is produced by the same run that
# would judge it.
FROM scratch AS config
COPY --from=kconfig /virt-arm64.config.resolved /virt-arm64.config

# --- the gate --------------------------------------------------------------
FROM kconfig AS gate
COPY kernel/config/virt-arm64.config /virt-arm64.config.recorded

# ASSERTION 1: the resolved config is the recorded one, symbol for symbol.
#
# This is what makes the defconfig-plus-fragment shape reviewable. Without it
# the build input would be whatever `olddefconfig` decided today over whatever
# arm64's `defconfig` says today -- a file nobody wrote, nobody read, and
# nothing compares. The diff is printed rather than a hash compared, because a
# hash says only that something moved and every refusal in this repository is
# written to name the cause.
RUN set -eu; \
    if ! diff -u /virt-arm64.config.recorded /virt-arm64.config.resolved > /tmp/config.diff; then \
        echo "error: the resolved kernel config is not the one boards/virt-arm64/bsp/kernel/config/virt-arm64.config records. Either a fragment changed, or the pinned kernel's arm64 defconfig moved underneath it. The difference is below; review it, and if it is intended run 'make virt-arm64-kernel-config' to re-record and commit the result." >&2; \
        sed 's/^/  /' /tmp/config.diff >&2; \
        exit 1; \
    fi; \
    echo "config: the resolved .config matches config/virt-arm64.config ($(grep -c . /virt-arm64.config.recorded) lines)"

# ASSERTION 2: every `=y` line of BOTH fragments survived olddefconfig.
#
# A symbol whose dependencies are not met is dropped silently by olddefconfig,
# so a fragment line can stop meaning anything without the build noticing.
# Running it over the shared fragment AND the board one is what makes
# boards/common/mos-required.fragment a floor every board holds rather than a
# floor one board asserts.
RUN set -eu; cd /ksrc; n=0; \
    for line in $(sed -n 's/^\(CONFIG_[A-Z0-9_]*=y\)$/\1/p' /mos-required.fragment /virt-arm64.fragment); do \
        n=$((n + 1)); \
        grep -q "^${line}$" .config || { \
            echo "error: missing required option: ${line}. It is named =y in boards/common/mos-required.fragment or boards/virt-arm64/bsp/kernel/config/virt-arm64.fragment, and olddefconfig did not keep it -- which means its dependencies are no longer met in this kernel, not that the line is optional." >&2; \
            exit 1; \
        }; \
    done; \
    [ "$n" -gt 0 ] || { echo "error: zero =y lines were read from the fragments, so this loop asserted nothing" >&2; exit 1; }; \
    echo "config: all ${n} required =y options are set"

# ASSERTION 3: CONFIG_LSM, which the loop above cannot see.
#
# It is a string, not a tristate, and boards/common/mos-required.fragment says
# so at the line itself: SELinux compiled in but absent from the LSM boot list
# never registers selinuxfs, so the image ships a security module that is
# present and inactive.
RUN set -eu; cd /ksrc; \
    want="$(grep '^CONFIG_LSM=' /mos-required.fragment)"; \
    [ -n "${want}" ] || { echo "error: boards/common/mos-required.fragment declares no CONFIG_LSM, so this assertion has nothing to compare and would pass over anything" >&2; exit 1; }; \
    grep -q "^${want}$" .config || { \
        echo "error: the resolved config's LSM list is not the required one. Wanted ${want}, got $(grep '^CONFIG_LSM=' .config). SELinux that is compiled in but not in the boot list never registers selinuxfs, and the image ships a security module that is present and does nothing." >&2; exit 1; }; \
    echo "config: ${want}"

# ONE ENTRY OF THAT LIST IS NOT SATISFIED, ON ANY BOARD. The list ends in `bpf`
# and no kernel in this tree builds CONFIG_BPF_LSM, so systemd says
# "bpf-restrict-fs: BPF LSM hook not enabled in the kernel" at every boot on all
# three. NOT switched on here, and the decision is not this file's: PLAN-073
# *Left owed* found the same gap from the floor's side, carries the dependency
# analysis, and owns closing it. This comment is the flag at the assertion, so a
# reader of the LSM check learns the list is not fully honoured without having
# to find that out from a boot log.

# --- the build -------------------------------------------------------------
FROM gate AS build

# The three strings the kernel stamps into its own image, pinned.
#
# Without them an Image carries the wall clock and the builder's hostname, so
# two builds of the identical pinned source differ, `uname -v` reports when the
# machine's kernel happened to be compiled, and any composed-root comparison
# gains a content difference at /boot/vmlinuz-* that no sanction could honestly
# explain.
#
# 1577836800 is 2020-01-01T00:00:00Z, the same constant
# boards/virt-arm64/board.env pins as FILE_MTIME and E2FSPROGS_FAKE_TIME and the
# same one rootfs/build.sh passes as SOURCE_DATE_EPOCH. One instant across every
# artefact this repository produces, so a timestamp anywhere in an image is
# either that value or a defect.
#
# NOTE, and it is a real difference from cx3576: that board's kernel is NOT
# reproducible -- its Dockerfile pins no KBUILD_BUILD_* at all, so its Image is
# compared by size rather than by sha256. This board follows x64 instead, which
# does pin them, so this kernel is expected to be byte-reproducible and may be
# compared as such.
ENV KBUILD_BUILD_TIMESTAMP="@1577836800" \
    KBUILD_BUILD_USER=mos \
    KBUILD_BUILD_HOST=mos-build

RUN set -eu; cd /ksrc; \
    make -j"$(nproc)" Image modules; \
    make INSTALL_MOD_PATH=/kmods INSTALL_MOD_STRIP=1 modules_install; \
    release="$(cat include/config/kernel.release)"; \
    echo "kernel release: ${release}"; \
    # modules_install writes modules.builtin and modules.dep whether or not any
    # module was built. Both are read on the device by modprobe and off the
    # image by verify/src/checks-kernel.ts, and a check that resolves names
    # against a directory that does not exist passes forever -- so their
    # presence is asserted here, where the tree that should contain them was
    # just written.
    [ -f "/kmods/lib/modules/${release}/modules.builtin" ] || \
        { echo "error: modules_install wrote no modules.builtin for ${release}. Every builtin symbol would then resolve to nothing at modprobe time, and any check that walks that index would report green over an empty directory." >&2; exit 1; }; \
    [ -f "/kmods/lib/modules/${release}/modules.dep" ] || \
        { echo "error: modules_install wrote no modules.dep for ${release}" >&2; exit 1; }; \
    rm -f "/kmods/lib/modules/${release}/build" "/kmods/lib/modules/${release}/source"; \
    tar -C /kmods -cf /modules.tar lib; \
    printf '%s\n' "${release}" > /kernel.release; \
    echo "kernel: Image $(stat -c%s arch/arm64/boot/Image) bytes, $(find /kmods -name '*.ko*' | wc -l) module(s), modules.tar $(stat -c%s /modules.tar) bytes"

# The verity floor, asserted a second time against the COMPILED tree rather
# than against the .config. include/config/auto.conf is what the build actually
# used: a config file states an intention, auto.conf states what was compiled.
RUN set -eu; cd /ksrc; \
    for option in DM_INIT DM_VERITY SQUASHFS; do \
        grep -q "^CONFIG_${option}=y" include/config/auto.conf || \
            { echo "error: CONFIG_${option} is not =y in the tree that was just compiled" >&2; exit 1; }; \
    done; \
    echo "kernel: dm-init, dm-verity and squashfs are in the compiled image"

# The artifact is named `Image`, which is what the arm64 kernel build produces
# and what boards/virt-arm64/deb/kernel-virt-arm64/stage.sh copies. The name it
# takes ON THE BOOT PARTITION is `vmlinuz`, from SLOT_KERNEL_NAME in
# boards/virt-arm64/board.env -- a layout fact read by the same grub.cfg shape
# x64 uses, and deliberately not this artifact path.
FROM scratch AS artifact
COPY --from=build /ksrc/arch/arm64/boot/Image /
COPY --from=build /ksrc/.config /config
COPY --from=build /modules.tar /
COPY --from=build /kernel.release /
