# syntax=docker/dockerfile:1@sha256:ecfaec9ed6d810b56388c508f4121597bfbba70d41a6dfeee4d8cad5f295fc32
# check=skip=InvalidDefaultArgInFrom
# The kernel-x64 producer: the `mos-kernel-x64` package.
#
#   bash build-env/deb/build.sh --producer kernel-x64 --arch amd64
#
# The kernel, its modules and the config it was built from arrive as the `bin`
# context, staged on the host by this producer's PREPARE hook, stage.sh.
#
# NOTHING IS COMPILED HERE. The kernel is boards/x64/bsp's output, built from
# the tag pinned in boards/x64/bsp/kernel/versions.env against the
# configuration recorded beside it. This file stages and packs, which is the
# rule PLAN-036 states for the whole producer family: composition does not
# compile a component, and neither does packaging.
#
# No default for the base, for the reason build-env/deb/Dockerfile gives: a
# driver that failed to pass the argument would otherwise build from a floating
# tag.
ARG MOS_BUILD_DEB

FROM ${MOS_BUILD_DEB} AS pack

# pack.sh comes over as a named context rather than out of the image. It is the
# packaging CONTRACT, shared by every producer, and build-env/deb/README.md
# requires this shape: an edit to the packer then takes effect without
# rebuilding the whole builder family.
COPY --from=packer pack.sh /usr/local/bin/pack.sh

COPY --from=kerneldeb copyright /in/copyright
COPY --from=kerneldeb control/ /in/control/
COPY --from=bin . /in/kernel/

ARG MOS_DEB_VERSION
ARG MOS_DEB_ARCH
ARG SOURCE_DATE_EPOCH

# THE RELEASE STRING IS READ, NEVER WRITTEN DOWN. Every payload path is named
# after it, and the kernel build is the only thing that knows it: a literal
# here would be a second answer to "which kernel is this", free to disagree
# with the one in the image the moment versions.env moves.
#
# /usr/lib/modules and not /lib/modules: trixie is merged-usr, so /lib is a
# symlink and a package that owned a path through it would own a path the
# ownership check cannot attribute. boards/cx3576/deb/board-cx3576 stages its
# modules the same way.
#
# NOT conffiles, and /boot/config-<release> is the one that would tempt it: it
# is configuration in name only -- a record of how the kernel beside it was
# built -- and this root is an immutable dm-verity squashfs, where a conffiles
# entry promises dpkg a three-way merge that can never happen on the device.
RUN set -eu; \
    release="$(cat /in/kernel/kernel.release)"; \
    [ -n "${release}" ] || { echo "error: the staged kernel.release is empty, so every payload path below would be named after nothing" >&2; exit 1; }; \
    install -D -m 0644 /in/kernel/bzImage "/stage/boot/vmlinuz-${release}"; \
    install -D -m 0644 /in/kernel/config  "/stage/boot/config-${release}"; \
    install -d -m 0755 /stage/usr/lib; \
    tar -C /stage/usr -xf /in/kernel/modules.tar; \
    [ -d "/stage/usr/lib/modules/${release}" ] || \
        { echo "error: modules.tar does not unpack to lib/modules/${release}. Either the tar was made from a different kernel than kernel.release names, or its top-level directory changed -- and the package would ship a module tree modprobe cannot find, silently" >&2; exit 1; }; \
    echo "kernel: staged vmlinuz-${release} ($(stat -c%s "/stage/boot/vmlinuz-${release}") bytes) and $(find "/stage/usr/lib/modules/${release}" -name '*.ko*' | wc -l) module(s)"

# What the payload has to be, asserted over the STAGED TREE rather than over
# the build that produced it. The BSP build already checked its own .config;
# these are about the bytes that are two lines away from being an archive.
RUN set -eu; \
    release="$(cat /in/kernel/kernel.release)"; \
    # A bzImage and not a vmlinux: GRUB's `linux` command loads the x86 boot \
    # protocol image, and an ELF here boots nothing while looking plausible. \
    case "$(file -b "/stage/boot/vmlinuz-${release}")" in \
    *"Linux kernel x86 boot executable, bzImage"*) ;; \
    *) echo "error: /boot/vmlinuz-${release} is not an x86 bzImage; file says: $(file -b "/stage/boot/vmlinuz-${release}"). GRUB's linux command would refuse it, or worse, load it and hand control to nothing" >&2; exit 1 ;; \
    esac; \
    # The no-initramfs floor, read off the config the image ships. This is the \
    # same set the BSP gate checks, re-asserted here because THIS is the file \
    # that ends up on the device and the one verify reads back out of it. \
    for option in DM_INIT BLK_DEV_DM DM_VERITY SQUASHFS SQUASHFS_ZSTD EFI_PARTITION; do \
        grep -q "^CONFIG_${option}=y$" "/stage/boot/config-${release}" || \
            { echo "error: the shipped /boot/config-${release} does not declare CONFIG_${option}=y. x64 boots root=/dev/dm-0 from a dm-mod.create= table with no initramfs; without this symbol built in the boot ends at rootwait with no device, days after this build reported success" >&2; exit 1; }; \
    done; \
    # modules.builtin is what makes `modprobe <builtin>` succeed and what \
    # verify/src/checks-kernel.ts resolves names against. A module index that \
    # is not in the payload turns every such lookup into an answer about an \
    # absent directory, which is green forever. \
    for index in modules.builtin modules.dep modules.order; do \
        [ -f "/stage/usr/lib/modules/${release}/${index}" ] || \
            { echo "error: /usr/lib/modules/${release}/${index} is not in the payload. modprobe and every check that walks that tree would resolve against a directory with no index in it, and report nothing missing" >&2; exit 1; }; \
    done; \
    # build/ and source/ are symlinks into the builder's own /ksrc. In an \
    # image they are dangling links into a path that never existed on the \
    # device, and the BSP build removes them; this is where that is proved \
    # about the bytes being packed. \
    for dangling in build source; do \
        [ ! -e "/stage/usr/lib/modules/${release}/${dangling}" ] && [ ! -L "/stage/usr/lib/modules/${release}/${dangling}" ] || \
            { echo "error: /usr/lib/modules/${release}/${dangling} is in the payload. It is a link into the kernel build tree, which does not exist on the device" >&2; exit 1; }; \
    done; \
    echo "kernel: the payload is an x86 bzImage, its config carries the no-initramfs verity floor, and its module indexes are present"

RUN set -eu; \
    install -D -m 0644 /in/copyright /stage/usr/share/doc/mos-kernel-x64/copyright; \
    pack.sh --root /stage --control /in/control/mos-kernel-x64.control \
        --version "${MOS_DEB_VERSION}" --arch "${MOS_DEB_ARCH}" --out /out

# The export stage: `-o type=local` writes this stage's filesystem into
# _out/debs/<arch>/pool/ and nothing here installs into a root.
FROM scratch AS out
COPY --from=pack /out/ /
