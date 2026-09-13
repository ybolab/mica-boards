# syntax=docker/dockerfile:1@sha256:ecfaec9ed6d810b56388c508f4121597bfbba70d41a6dfeee4d8cad5f295fc32
# check=skip=InvalidDefaultArgInFrom
# The x64 kernel: mainline stable, configured by this repository, built here.
#
#   make x64-kernel          -> _out/kernel/{bzImage,modules.tar,config,kernel.release}
#   make x64-kernel-config   -> rewrites config/x64.config from this build
#
# WHY THIS EXISTS. x64 used to depend on Debian's linux-image-amd64. That
# kernel has no CONFIG_DM_INIT, so the `dm-mod.create=` verity table
# rootfs/build.sh writes was silently ignored on this board and an initramfs
# had to re-implement it -- a second reader of the one boot contract, which is
# what made every x64 image unbootable for the length of one commit while
# cx3576, whose kernel takes the same cmdline directly, stayed green. PLAN-074
# carries the measurements and the decision.

# The builder image, injected from build-env/images.env by build-env/from.sh,
# which bsp/Makefile calls. Ubuntu 24.04 and not mica-build-c, the
# same choice boards/cx3576/bsp/kernel/Dockerfile makes and for the same
# structural reason: a BSP builder is pinned by digest and depends on nothing
# this repository has to build first, so `make x64-kernel` works on a fresh
# checkout without a forty-minute `make build-env` in front of it. Keeping both
# boards' kernels on one builder is also what makes a diff of the two
# Dockerfiles mean something. There is no default: without a value docker
# refuses before any stage runs, where a default would build green against an
# image nobody chose.
ARG MICA_IMAGE_UBUNTU_2404
FROM ${MICA_IMAGE_UBUNTU_2404} AS toolchain

ARG DEBIAN_FRONTEND=noninteractive
# No cross compiler and no device-tree compiler, which is the whole difference
# from the cx3576 builder: this is a native amd64 kernel for a UEFI machine.
RUN apt-get update && apt-get install -y --no-install-recommends \
        git ca-certificates build-essential bc bison flex \
        libssl-dev libelf-dev python3 kmod cpio xz-utils zstd \
    && rm -rf /var/lib/apt/lists/*

# --- the source ------------------------------------------------------------
FROM toolchain AS src
COPY kernel/versions.env /versions.env

# The tag is fetched and the TREE is hashed, not a tarball: a release tarball
# can be re-rolled and a tag can be moved, while `git archive` of the tag is a
# deterministic byte stream over the source that is actually compiled. This is
# Shared pinned source-fetch discipline.
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
        echo "error: the x64 kernel is pinned to ${KERNEL_VERSION} with no hash. Record KERNEL_SHA256=${got} in bsp/kernel/versions.env and run again; until then this build would compile whatever the tag points at today, which is a different fact from the source this tree agreed to ship" >&2; exit 1; \
    elif [ "${KERNEL_SHA256}" != "${got}" ]; then \
        echo "error: linux ${KERNEL_VERSION} hashes to ${got}, but bsp/kernel/versions.env pins ${KERNEL_SHA256}. Either the tag was moved upstream or the pin is stale; do not paste the new hash in without finding out which" >&2; exit 1; \
    else \
        echo "ok linux ${KERNEL_VERSION} ${got}"; \
    fi; \
    rm -rf /ksrc/.git

# --- the configuration -----------------------------------------------------
# Separated from the gate below so that `make x64-kernel-config` can export the
# resolved .config WITHOUT the diff that is about to refuse it. A refresh path
# that had to pass the check it exists to update would be no refresh path.
FROM src AS kconfig

# The shared mos runtime baseline, from boot/common/ -- requires the named
# build context: docker buildx build --build-context mos-common=../../common
# (wired in bsp/Makefile; a bare build without it fails here,
# loudly). Merged FIRST, so a board line that contradicted it would be the one
# reported as the override.
COPY --from=mos-common mos-required.fragment /mos-required.fragment
COPY kernel/config/x64.fragment /x64.fragment

# The verity content anchor, from the named build context `mos-trust`
# (`--build-context mos-trust=../meta/verity`, wired in
# bsp/Makefile, which mints it if it is absent). It is the
# file boot/common/mos-required.fragment names in CONFIG_SYSTEM_TRUSTED_KEYS,
# and certs/Makefile resolves that relative path against the source tree.
#
# PUBLIC MATERIAL. What lands here is an X.509 certificate; the private key
# stays in meta/ and no stage of this build has it. The build FAILS without the
# context rather than falling back to an empty keyring, for the same reason the
# fragment above is not optional: a kernel with CONFIG_SYSTEM_TRUSTED_KEYS=""
# accepts no root-hash signature at all, and would present as a boot failure
# far from here.
COPY --from=mos-trust signer.cert.pem /ksrc/certs/mos-verity-anchor.pem
RUN grep -q 'BEGIN CERTIFICATE' /ksrc/certs/mos-verity-anchor.pem || { \
        echo "error: the file the mos-trust build context supplied is not a PEM certificate. CONFIG_SYSTEM_TRUSTED_KEYS names it, and extract-cert would fail in the middle of the compile instead of here" >&2; exit 1; }

# x86_64_defconfig is the base and the two fragments are the delta. The
# alternative -- one recorded full config, which is what cx3576 keeps -- makes
# the reason a symbol is set unrecoverable: 6000 lines of generated text carry
# no argument. Here the argument is in the fragments and the RESULT is recorded
# beside them, so a kernel bump is reviewed as a diff of what upstream moved.
RUN set -eu; cd /ksrc; \
    make x86_64_defconfig; \
    scripts/kconfig/merge_config.sh -m .config /mos-required.fragment /x64.fragment; \
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
      > /x64.config.resolved; \
    echo "resolved config: $(grep -c . /x64.config.resolved) lines, $(grep -c '=y$' /x64.config.resolved) built in, $(grep -c '=m$' /x64.config.resolved) modules"

# The export target for `make x64-kernel-config`. Nothing downstream reads it;
# it exists so the recorded file is produced by the same run that would judge it.
FROM scratch AS config
COPY --from=kconfig /x64.config.resolved /x64.config

# --- the gate --------------------------------------------------------------
FROM kconfig AS gate
COPY kernel/config/x64.config /x64.config.recorded

# ASSERTION 1: the resolved config is the recorded one, symbol for symbol.
#
# This is what makes the defconfig-plus-fragment shape reviewable. Without it
# the build input would be whatever `olddefconfig` decided today over whatever
# `x86_64_defconfig` says today -- a file nobody wrote, nobody read, and
# nothing compares. The diff is printed rather than a hash compared, because a
# hash says only that something moved and every refusal in this repository is
# written to name the cause.
RUN set -eu; \
    if ! diff -u /x64.config.recorded /x64.config.resolved > /tmp/config.diff; then \
        echo "error: the resolved kernel config is not the one bsp/kernel/config/x64.config records. Either a fragment changed, or the pinned kernel's x86_64_defconfig moved underneath it. The difference is below; review it, and if it is intended run 'make x64-kernel-config' to re-record and commit the result." >&2; \
        sed 's/^/  /' /tmp/config.diff >&2; \
        exit 1; \
    fi; \
    echo "config: the resolved .config matches config/x64.config ($(grep -c . /x64.config.recorded) lines)"

# ASSERTION 2: every `=y` line of BOTH fragments survived olddefconfig.
#
# A symbol whose dependencies are not met is dropped silently by olddefconfig,
# so a fragment line can stop meaning anything without the build noticing.
# boards/cx3576/bsp/kernel/Dockerfile runs the same loop over the shared
# fragment; running it here over the shared one AND the board one is what makes
# boot/common/mos-required.fragment a floor both boards hold rather than a
# floor one board asserts.
RUN set -eu; cd /ksrc; n=0; \
    for line in $(sed -n 's/^\(CONFIG_[A-Z0-9_]*=y\)$/\1/p' /mos-required.fragment /x64.fragment); do \
        n=$((n + 1)); \
        grep -q "^${line}$" .config || { \
            echo "error: missing required option: ${line}. It is named =y in boot/common/mos-required.fragment or bsp/kernel/config/x64.fragment, and olddefconfig did not keep it -- which means its dependencies are no longer met in this kernel, not that the line is optional." >&2; \
            exit 1; \
        }; \
    done; \
    [ "$n" -gt 0 ] || { echo "error: zero =y lines were read from the fragments, so this loop asserted nothing" >&2; exit 1; }; \
    echo "config: all ${n} required =y options are set"

# ASSERTION 3: CONFIG_LSM, which the loop above cannot see.
#
# It is a string, not a tristate, and boot/common/mos-required.fragment says
# so at the line itself: SELinux compiled in but absent from the LSM boot list
# never registers selinuxfs, so the image ships a security module that is
# present and inactive. Debian's amd64 kernel carries a DIFFERENT string
# (...,apparmor,selinux,smack,tomoyo,bpf,ipe) and nothing ever compared them,
# which is one of the measurements PLAN-074 was written from.
RUN set -eu; cd /ksrc; \
    want="$(grep '^CONFIG_LSM=' /mos-required.fragment)"; \
    [ -n "${want}" ] || { echo "error: boot/common/mos-required.fragment declares no CONFIG_LSM, so this assertion has nothing to compare and would pass over anything" >&2; exit 1; }; \
    grep -q "^${want}$" .config || { \
        echo "error: the resolved config's LSM list is not the required one. Wanted ${want}, got $(grep '^CONFIG_LSM=' .config). SELinux that is compiled in but not in the boot list never registers selinuxfs, and the image ships a security module that is present and does nothing." >&2; exit 1; }; \
    echo "config: ${want}"

# ASSERTION 4: CONFIG_SYSTEM_TRUSTED_KEYS, the other string the loop cannot see.
#
# It is what makes signed dm-verity mean anything: with an empty value the
# kernel builds the .builtin_trusted_keys keyring with nothing in it, every
# root-hash signature fails to find an issuer, and the failure appears at the
# first boot of an image rather than here. The value is asserted as the
# fragment's, and the file it names is asserted to exist in the tree that is
# about to be compiled -- two different failures: a floor that changed, and a
# build context that did not arrive.
RUN set -eu; cd /ksrc; \
    want="$(grep '^CONFIG_SYSTEM_TRUSTED_KEYS=' /mos-required.fragment)"; \
    [ -n "${want}" ] || { echo "error: boot/common/mos-required.fragment declares no CONFIG_SYSTEM_TRUSTED_KEYS, so this assertion has nothing to compare and would pass over a kernel that trusts nothing" >&2; exit 1; }; \
    grep -q "^${want}$" .config || { \
        echo "error: the resolved config's trust anchor is not the required one. Wanted ${want}, got $(grep '^CONFIG_SYSTEM_TRUSTED_KEYS=' .config)." >&2; exit 1; }; \
    path="$(printf '%s' "${want}" | sed 's/^CONFIG_SYSTEM_TRUSTED_KEYS=//; s/^"//; s/"$//')"; \
    [ -s "${path}" ] || { echo "error: ${want} names ${path}, which does not exist in the kernel tree. certs/Makefile resolves that path against the source tree, so the compile would fail at extract-cert" >&2; exit 1; }; \
    echo "config: ${want} ($(stat -c%s "${path}") bytes)"

# ONE ENTRY OF THAT LIST IS NOT SATISFIED, ON EITHER BOARD. The list ends in
# `bpf` and neither this kernel nor cx3576's builds CONFIG_BPF_LSM, so systemd
# says "bpf-restrict-fs: BPF LSM hook not enabled in the kernel" at every boot
# on both. Debian's amd64 kernel DID have it, so x64 lost a capability by
# leaving that kernel and gained agreement with the board that ships.
#
# NOT switched on here, and the decision is not this file's: PLAN-073 *Left
# owed* found the same gap from the floor's side, carries the dependency
# analysis, and owns closing it. This comment is the flag at the assertion, so
# that a reader of the LSM check learns the list is not fully honoured without
# having to find that out from a boot log.

# --- the build -------------------------------------------------------------
FROM gate AS build

# The three strings the kernel stamps into its own image, pinned.
#
# Without them a bzImage carries the wall clock and the builder's hostname --
# `#1 SMP PREEMPT_DYNAMIC Thu Sep 3 19:43:59 UTC 2026` and `root@buildkitsandbox`
# -- so two builds of the identical pinned source differ, `uname -v` reports
# when the machine's kernel happened to be compiled, and the composed-root
# comparison gains a content difference at /boot/vmlinuz-* that no sanction
# could honestly explain. This board just removed the ONE non-reproducible path
# that gate had (the initrd, 182 of 183 cpio entries differing in inode number);
# introducing another in the same change would be a poor trade.
#
# 1577836800 is 2020-01-01T00:00:00Z, the same constant board.env
# pins as FILE_MTIME and E2FSPROGS_FAKE_TIME and the same one rootfs/build.sh
# passes as SOURCE_DATE_EPOCH. One instant across every artefact this
# repository produces, so a timestamp anywhere in an image is either that value
# or a defect.
ENV KBUILD_BUILD_TIMESTAMP="@1577836800" \
    KBUILD_BUILD_USER=mos \
    KBUILD_BUILD_HOST=mica-build

RUN set -eu; cd /ksrc; \
    make -j"$(nproc)" bzImage modules; \
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
    # DETERMINISTIC ARCHIVE PARAMETERS. A tar is a packaging step, and its
    # headers were carrying the wall clock: RFCT-343 measured a cx3576 pair
    # whose every member was byte-identical and whose every header held the
    # build's mtime, and this line was character-for-character the same one, so
    # the defect is shared rather than that board's. --mtime pins the clock to
    # the one instant this repository stamps everywhere;
    # --owner/--group/--numeric-owner keep the ids from describing the builder;
    # --sort=name makes member order a function of the names rather than of
    # readdir, which is promised by nothing.
    tar --sort=name --mtime=@1577836800 --owner=0 --group=0 --numeric-owner \
        -C /kmods -cf /modules.tar lib; \
    printf '%s\n' "${release}" > /kernel.release; \
    echo "kernel: bzImage $(stat -c%s arch/x86/boot/bzImage) bytes, $(find /kmods -name '*.ko*' | wc -l) module(s), modules.tar $(stat -c%s /modules.tar) bytes"

# The verity floor, asserted a second time against the COMPILED tree rather
# than against the .config. include/config/auto.conf is what the build actually
# used, which is the same shape boards/cx3576/bsp/kernel/Dockerfile checks its
# patches with: a config file states an intention, auto.conf states what was
# compiled.
RUN set -eu; cd /ksrc; \
    for option in DM_INIT DM_VERITY SQUASHFS; do \
        grep -q "^CONFIG_${option}=y" include/config/auto.conf || \
            { echo "error: CONFIG_${option} is not =y in the tree that was just compiled" >&2; exit 1; }; \
    done; \
    echo "kernel: dm-init, dm-verity and squashfs are in the compiled image"

FROM scratch AS artifact
COPY --from=build /ksrc/arch/x86/boot/bzImage /
COPY --from=build /ksrc/.config /config
COPY --from=build /modules.tar /
COPY --from=build /kernel.release /
