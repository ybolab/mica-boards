# syntax=docker/dockerfile:1@sha256:ecfaec9ed6d810b56388c508f4121597bfbba70d41a6dfeee4d8cad5f295fc32
# Build Linux 6.1.115, modules, and the CX3576-Z device tree.
#
# ORCHESTRATION ONLY. Every step below is a file in this repository that a reader
# can open on its own -- ../scripts/ for what the kernel and U-Boot builders
# share, kernel/configure.sh for the resolved configuration and its floor, and
# kernel/build.sh for the compile, the per-patch assertions and the packaging.
# The vendor-source edits are kernel/patches/, listed in kernel/patches/series.
# RFCT-345 moved them out of here and gated the move on the eleven BSP artefacts
# coming back byte-identical.

# The builder image is injected from build-env/images.env by
# build-env/from.sh, which boards/cx3576/bsp/Makefile calls. A bare tag like
# `ubuntu:24.04` is one Canonical repoints on every point release, so the answer
# to "which toolchain produced this artefact" would be the date of the build.
# Ubuntu and not mos-build-c: the BSP builders get digest pins only, because
# this cross-compiles a vendor tree against gcc-aarch64-linux-gnu,
# python3-pyelftools, swig and device-tree-compiler at the versions that tree
# was tested with, and mos-build-c would be a BSP rebuilt under a toolchain
# nobody has booted on the hardware. There is no default: without a value docker
# refuses before any stage runs, where a default would build green against an
# image nobody chose.
ARG MOS_IMAGE_UBUNTU_2404
FROM --platform=$BUILDPLATFORM ${MOS_IMAGE_UBUNTU_2404} AS build

COPY scripts/ /bsp/scripts/

# The package LIST stays here rather than in a file: it is what this builder is,
# and it belongs beside the FROM that says which image it is installed into.
ARG DEBIAN_FRONTEND=noninteractive
RUN bash /bsp/scripts/apt-install.sh \
        git ca-certificates build-essential bc bison flex \
        libssl-dev libelf-dev python3 kmod patch \
        gcc-aarch64-linux-gnu device-tree-compiler

ARG KERNEL_REPO=https://github.com/armbian/linux-rockchip.git
ARG KERNEL_COMMIT=c6157104418d012823413c02f9222f3fe123dd25
RUN bash /bsp/scripts/fetch-source.sh /ksrc "${KERNEL_REPO}" "${KERNEL_COMMIT}"

# The .dts is copied in beside the patches, so the tree is coherent from the
# moment patches/0004 registers the file in the rockchip dts Makefile.
COPY kernel/patches/ /patches/
COPY kernel/dts/rk3576-cx3576z.dts /ksrc/arch/arm64/boot/dts/rockchip/
RUN bash /bsp/scripts/apply-patches.sh /ksrc /patches patch

# Shared mos runtime baseline from boards/common/ -- requires the named build
# context: docker buildx build --build-context mos-common=../../common ...
# (wired in the board Makefile; a bare build without it fails here, loudly).
COPY kernel/config/kernel-cx3576z.config /ksrc/.config
COPY --from=mos-common mos-required.fragment /mos-required.fragment
COPY kernel/configure.sh /bsp/kernel/configure.sh
RUN bash /bsp/kernel/configure.sh /ksrc /mos-required.fragment

# The three strings the kernel stamps into its own image, pinned -- the same
# three values boards/x64/bsp/kernel/Dockerfile pins, for the same reason, and
# not a second convention.
#
# Without them the Image carries the wall clock and the builder's hostname
# (`#1 SMP ... <date>` and `root@buildkitsandbox`), so two builds of one
# unchanged tree differ. RFCT-304 measured exactly that on this board: equal
# size, different sha256, and had to compare the kernel by size because of it.
#
# 1577836800 is 2020-01-01T00:00:00Z, the constant boards/cx3576/board.env pins
# as FILE_MTIME and E2FSPROGS_FAKE_TIME and rootfs/build.sh passes as
# SOURCE_DATE_EPOCH. One instant across every artefact this repository
# produces, so a timestamp anywhere in an image is either that value or a
# defect.
# SOURCE_DATE_EPOCH is the FOURTH pin, and it is not redundant with the three
# above. RFCT-320 set those; RFCT-343 then ran the experiment they were never
# checked against -- two `--no-cache` builds of this target, same tree, back to
# back -- and the Image still differed. Twenty-four bytes at equal size, in two
# clusters. Five of them are `__DATE__` and `__TIME__` compiled into the vendor
# Mali driver, which prints "Compiled: %s, time: %s"
# (drivers/gpu/arm/mali400/mali/linux/mali_kernel_linux.c:404 and :410-411).
# No KBUILD_BUILD_* reaches those: they are cpp builtins that read the wall
# clock while preprocessing, and mainline's `-Werror=date-time` -- which is why
# no in-tree source can do this -- does not cover a vendor tree carrying its own
# build system. The other nineteen are the GNU build-id, which is a hash OF the
# linked image and moved only because the five did.
#
# gcc honours SOURCE_DATE_EPOCH for both macros, which is what pins them. Kbuild
# reads none of it -- it takes KBUILD_BUILD_TIMESTAMP -- so this variable's whole
# effect here is on `__DATE__`/`__TIME__` in the vendor drivers.
#
# IT IS NOT THE WHOLE FIX, and the second experiment is what said so. With
# SOURCE_DATE_EPOCH set, one of the two Mali sites came out pinned at
# `Jan  1 2020 / 00:00:00` in both builds and the Image STILL differed -- by 24
# bytes again, in a different place. The remaining four are
# `BUILD_DATE=$(shell date)` in drivers/gpu/arm/mali400/mali/Kbuild, a MAKE-time
# shell call that no compiler variable can reach, and the other twenty were the
# build-id following it. kernel/patches/0003 pins that one; the two together are
# what make this kernel byte-reproducible.
#
# `-j"$(nproc)"` in kernel/build.sh was the other suspect and is NOT implicated:
# every differing byte in both experiments was a date string or a hash of one,
# and nothing about parallelism produces those. CONFIG_DEBUG_INFO was the third
# and is not implicated either, for the same reason.
#
# THE ENV STAYS BELOW kernel/configure.sh AND ABOVE kernel/build.sh, where the
# Dockerfile put it. Nothing in the configuration step reads the wall clock, and
# moving the pins above it would change which layers see them for no measured
# reason -- the artefacts these values exist to stabilise are all produced below.
ENV KBUILD_BUILD_TIMESTAMP="@1577836800" \
    KBUILD_BUILD_USER=mos \
    KBUILD_BUILD_HOST=mos-build \
    SOURCE_DATE_EPOCH=1577836800

ARG KERNEL_EXPECT=6.1.115
COPY kernel/build.sh /bsp/kernel/build.sh
RUN bash /bsp/kernel/build.sh /ksrc "${KERNEL_EXPECT}"

# THE RESOLVED CONFIG IS AN ARTIFACT, the shape x64 and virt-arm64 already
# export. It is what `olddefconfig` decided over kernel/config/kernel-cx3576z.config
# merged with boards/common/mos-required.fragment -- an OUTPUT of this build, and
# the only form of the floor that the image contract can read back out of a
# packed root. Before RFCT-343 this board exported none, so its `=y` floor was
# enforced at kernel-build time and nowhere else, and an image assembled from a
# STALE _out/boards/cx3576/kernel shipped a kernel predating symbols the fragment had since
# gained with no check going red. kernel.release names the file downstream, so
# that the config and the modules beside it cannot be from different kernels
# without the packaging step noticing.
FROM scratch AS artifact
COPY --from=build /ksrc/arch/arm64/boot/Image /
COPY --from=build /ksrc/.config /config
COPY --from=build /kernel.release /
COPY --from=build /modules.tar /
COPY --from=build /rk3576-src.dtb /
