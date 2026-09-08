# syntax=docker/dockerfile:1@sha256:ecfaec9ed6d810b56388c508f4121597bfbba70d41a6dfeee4d8cad5f295fc32
# Build Linux 6.1.115, modules, and the CX3576-Z device tree.
#
# ORCHESTRATION ONLY. Every step is a file: ../scripts/ for what the kernel and
# U-Boot builders share, kernel/configure.sh for the resolved configuration and
# its floor, kernel/build.sh for the compile and packaging, kernel/patches/ for
# the vendor-source edits.

# Digest-pinned from build-env/images.env via build-env/from.sh. Ubuntu rather
# than mos-build-c: this cross-compiles a vendor tree against the toolchain
# versions that tree was tested with, and mos-build-c would be a BSP rebuilt
# under a toolchain nobody has booted on the hardware. No default, so a build
# without the value is refused rather than built against an image nobody chose.
ARG MOS_IMAGE_UBUNTU_2404
FROM --platform=$BUILDPLATFORM ${MOS_IMAGE_UBUNTU_2404} AS build

COPY scripts/ /bsp/scripts/

# The package list stays here rather than in a file: it is what this builder is,
# and it belongs beside the FROM that says which image it is installed into.
ARG DEBIAN_FRONTEND=noninteractive
RUN bash /bsp/scripts/apt-install.sh \
        git ca-certificates build-essential bc bison flex \
        libssl-dev libelf-dev python3 kmod patch \
        gcc-aarch64-linux-gnu device-tree-compiler

ARG KERNEL_REPO=https://github.com/armbian/linux-rockchip.git
ARG KERNEL_COMMIT=c6157104418d012823413c02f9222f3fe123dd25
RUN bash /bsp/scripts/fetch-source.sh /ksrc "${KERNEL_REPO}" "${KERNEL_COMMIT}"

# The .dts lands beside the patches so the tree is coherent from the moment
# patches/0004 registers it in the rockchip dts Makefile.
COPY kernel/patches/ /patches/
COPY kernel/dts/rk3576-cx3576z.dts /ksrc/arch/arm64/boot/dts/rockchip/
RUN bash /bsp/scripts/apply-patches.sh /ksrc /patches patch

# Needs the named build context: `--build-context mos-common=../../common`,
# wired in the board Makefile. A bare build without it fails here, loudly.
COPY kernel/config/kernel-cx3576z.config /ksrc/.config
COPY --from=mos-common mos-required.fragment /mos-required.fragment
COPY kernel/configure.sh /bsp/kernel/configure.sh
RUN bash /bsp/kernel/configure.sh /ksrc /mos-required.fragment

# FOUR PINS, AND ALL FOUR ARE LOAD-BEARING. The first three are what Kbuild
# stamps into the image; without them it carries the wall clock and
# `root@buildkitsandbox`. SOURCE_DATE_EPOCH is not redundant with them: Kbuild
# never reads it, but gcc honours it for `__DATE__` and `__TIME__`, which the
# vendor Mali driver compiles in and which no KBUILD_BUILD_* can reach.
#
# A fifth thing is needed and is not here: `BUILD_DATE=$(shell date)` in the
# Mali Kbuild is a make-time shell call no environment variable reaches, pinned
# by kernel/patches/0003. Removing either that patch or SOURCE_DATE_EPOCH makes
# this kernel non-reproducible again, and neither alone is enough. RFCT-343
# carries the measurement; `-j$(nproc)` and CONFIG_DEBUG_INFO were suspected and
# are not implicated.
#
# 1577836800 is 2020-01-01T00:00:00Z, the same instant board.env pins as
# FILE_MTIME and rootfs/build.sh passes as SOURCE_DATE_EPOCH, so a timestamp
# anywhere in an image is either that value or a defect.
#
# Stays below configure.sh and above build.sh: nothing in the configuration step
# reads a clock, and every artefact these values stabilise is produced below.
ENV KBUILD_BUILD_TIMESTAMP="@1577836800" \
    KBUILD_BUILD_USER=mos \
    KBUILD_BUILD_HOST=mos-build \
    SOURCE_DATE_EPOCH=1577836800

ARG KERNEL_EXPECT=6.1.115
COPY kernel/build.sh /bsp/kernel/build.sh
RUN bash /bsp/kernel/build.sh /ksrc "${KERNEL_EXPECT}"

# THE RESOLVED CONFIG IS AN ARTIFACT, as it already is on x64 and virt-arm64:
# what olddefconfig decided over the board config merged with the common
# fragment, and the only form of the `=y` floor the image contract can read back
# out of a packed root. Before RFCT-343 this board exported none, so a stale
# _out/boards/cx3576/kernel shipped a kernel predating symbols the fragment had
# gained, with no check going red. kernel.release names the config downstream so
# it and the modules beside it cannot come from different kernels unnoticed.
#
# SYSTEM.MAP IS PART OF THAT PROVENANCE, and it is here because its absence cost
# a campaign. This kernel BUGs in paging_init on the hardware and the console
# prints addresses -- `pc : ...+0x518`, `x19 : ffffffc009e96d20` -- which nobody
# could turn into a symbol, because the only two files holding the link-time
# symbol table, vmlinux and System.map, were left in the build stage and thrown
# away with it. 6.5 MiB of text beside a 42.4 MiB Image, and it is what makes a
# register dump readable without the board in front of you. RFCT-351 named all
# three of that crash's addresses from it within a minute of it existing.
#
# NOT vmlinux, which is the other half of the same answer. It is 173.7 MiB with
# this config's CONFIG_DEBUG_INFO=y -- four times the Image, and 26 times this
# file -- for line numbers over a symbol name. It stays in the build stage;
# build.sh sizes both in the log, and a tree that wants it rebuilds with this
# Dockerfile and reads it out of the cached build stage in seconds.
#
# NOT SHIPPED TO THE DEVICE. boards/cx3576/deb/board-cx3576/render.sh stages
# named files -- the boot slot's own list, modules.tar, config, kernel.release
# -- so a new file in this export reaches the package only when that list names
# it, and this one is not in it.
FROM scratch AS artifact
COPY --from=build /ksrc/arch/arm64/boot/Image /
COPY --from=build /ksrc/.config /config
COPY --from=build /ksrc/System.map /
COPY --from=build /kernel.release /
COPY --from=build /modules.tar /
COPY --from=build /rk3576-src.dtb /
