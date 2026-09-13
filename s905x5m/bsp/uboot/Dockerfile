# syntax=docker/dockerfile:1@sha256:ecfaec9ed6d810b56388c508f4121597bfbba70d41a6dfeee4d8cad5f295fc32
# Build CoreELEC/Hardkernel U-Boot for the S7D/S905X5M BM201 board.

# The base image is injected from build-env/images.env by the BSP Makefile.
# There is no default: omitting the repository pin must fail before the build
# can silently select a mutable image tag.
ARG MICA_IMAGE_UBUNTU_2404
FROM --platform=$BUILDPLATFORM ${MICA_IMAGE_UBUNTU_2404} AS build

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        autoconf \
        automake \
        bc \
        bison \
        build-essential \
        ca-certificates \
        cmake \
        curl \
        flex \
        gawk \
        zstd \
        gcc-aarch64-linux-gnu \
        git \
        gperf \
        libexpat-dev \
        libglib2.0-dev \
        libgmp-dev \
        libmpc-dev \
        libmpfr-dev \
        libslirp-dev \
        libssl-dev \
        libtool \
        ninja-build \
        patchutils \
        python3 \
        python3-pip \
        python3-tomli \
        swig \
        texinfo \
        vim-common \
        xxd \
        xz-utils \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

ARG UBOOT_REPO=https://github.com/CoreELEC/u-boot.git
ARG UBOOT_COMMIT=5f7ac2b1dc4df2f466ed88c3958a8675873f8a1a
# git over HTTP/2 stalls in this image: the TLS handshake completes and the
# stream opens, then the response never arrives and the fetch hangs for
# minutes. HTTP/1.1 returns immediately against the same host, and apt (also
# HTTP/1.1) was never affected. Pin the version rather than depend on whatever
# the network path does with HTTP/2.
RUN git config --global http.version HTTP/1.1 && \
    git init -q /uboot && \
    git -C /uboot remote add origin "${UBOOT_REPO}" && \
    git -C /uboot fetch --depth=1 origin "${UBOOT_COMMIT}" && \
    git -C /uboot checkout -q --detach FETCH_HEAD && \
    test "$(git -C /uboot rev-parse HEAD)" = "${UBOOT_COMMIT}"

# fip/tools/zstd is a prebuilt x86-64 binary. On an arm64 builder it runs under
# emulation, fails to find /lib64/ld-linux-x86-64.so.2, and dies with a SIGTRAP
# -- and fip/s7d/build.sh line 179 does not check the exit status. It goes on to
# cat a file that was never produced, so the compressed BL33 that should go into
# the FIP is empty.
#
# The result is a bootloader with correct magic, correct header, every earlier
# stage present, and no U-Boot: it boots as far as BL32 and then resets forever.
# It also round-trips through the Amlogic packer unchanged, so nothing
# downstream notices. This is what bricked a board.
#
# The output is ordinary zstd, so the native tool is a drop-in. Substitute it
# only when the shipped one cannot run, which leaves an amd64 builder untouched.
RUN set -eu; \
    cd /uboot; \
    if ./fip/tools/zstd --version >/dev/null 2>&1; then \
        echo "fip/tools/zstd runs natively; leaving it alone"; \
    else \
        echo "fip/tools/zstd cannot run on $(uname -m); substituting the system zstd"; \
        command -v zstd >/dev/null || { echo "error: no system zstd to substitute" >&2; exit 1; }; \
        mv fip/tools/zstd fip/tools/zstd.prebuilt-x86_64; \
        ln -s "$(command -v zstd)" fip/tools/zstd; \
    fi; \
    ./fip/tools/zstd --version

# Host-architecture-specific toolchains. BUILDARCH is amd64 or arm64; each
# toolchain has a per-arch URL and checksum, selected at build time.
ARG BUILDARCH

ARG ARM_GNU_TOOLCHAIN_URL_amd64=https://developer.arm.com/-/media/Files/downloads/gnu/13.2.rel1/binrel/arm-gnu-toolchain-13.2.rel1-x86_64-aarch64-none-elf.tar.xz
ARG ARM_GNU_TOOLCHAIN_URL_arm64=https://developer.arm.com/-/media/Files/downloads/gnu/13.2.rel1/binrel/arm-gnu-toolchain-13.2.rel1-aarch64-aarch64-none-elf.tar.xz
ARG ARM_GNU_TOOLCHAIN_DIR_amd64=arm-gnu-toolchain-13.2.Rel1-x86_64-aarch64-none-elf
ARG ARM_GNU_TOOLCHAIN_DIR_arm64=arm-gnu-toolchain-13.2.Rel1-aarch64-aarch64-none-elf
ARG ARM_GNU_TOOLCHAIN_SHA256_amd64=7fe7b8548258f079d6ce9be9144d2a10bd2bf93b551dafbf20fe7f2e44e014b8
ARG ARM_GNU_TOOLCHAIN_SHA256_arm64=f3871c0d91a7375834eb43eb758f4df6d8dadf20ad9deca2eb569d5599d98e89

ARG ARM_LINUX_TOOLCHAIN_URL_amd64=https://developer.arm.com/-/media/Files/downloads/gnu-a/10.2-2020.11/binrel/gcc-arm-10.2-2020.11-x86_64-aarch64-none-linux-gnu.tar.xz
# ARM publishes no aarch64-host build of this toolchain: on arm64 the target is
# native, so an empty URL selects the system compiler instead (see below).
ARG ARM_LINUX_TOOLCHAIN_URL_arm64=
ARG ARM_LINUX_TOOLCHAIN_DIR_amd64=gcc-arm-10.2-2020.11-x86_64-aarch64-none-linux-gnu
ARG ARM_LINUX_TOOLCHAIN_DIR_arm64=
ARG ARM_LINUX_TOOLCHAIN_SHA256_amd64=fe7f72330216612de44891ebe5e228eed7c0c051ac090c395b2b33115c6f5408
ARG ARM_LINUX_TOOLCHAIN_SHA256_arm64=

# The RISC-V toolchain builds bl30 (AOCPU RTOS). There is no aarch64-host build
# of the original 8.2.0-2.2 release, so arm64 uses the closest xPack release.
# Both land in the path hardcoded by
# bl30/rtos_sdk/soc/riscv/s7d/toolchain_path.cmake.
# bl33/v2023/Makefile falls back to these exact /opt paths (the names carry a
# literal x86_64 regardless of host arch) when prebuild_gcc is unset, so both
# toolchains must be reachable there.
ARG ARM_GNU_EXPECT_DIR=/opt/arm-gnu-toolchain-13.2.Rel1-x86_64-aarch64-none-elf
ARG ARM_LINUX_EXPECT_DIR=/opt/gcc-arm-10.2-2020.11-x86_64-aarch64-none-linux-gnu
# bl33z is built by a separate makefile that hardcodes a Linaro 7.3.1 toolchain
# with an i686 host. Linaro's release server is gone and a 32-bit x86 host build
# is unusable on arm64 anyway, so alias the bare-metal ARM GNU toolchain under
# the expected aarch64-elf- prefix.
ARG BL33Z_TOOLCHAIN_DIR=/opt/gcc-linaro-7.3.1-2018.05-i686_aarch64-elf
ARG RISCV_TOOLCHAIN_DIR=/opt/riscv-none-gcc/8.2.0-2.2-20190521-0004
ARG RISCV_TOOLCHAIN_URL_amd64=https://github.com/ilg-archived/riscv-none-gcc/releases/download/v8.2.0-2.2-20190521/gnu-mcu-eclipse-riscv-none-gcc-8.2.0-2.2-20190521-0004-centos64.tgz
ARG RISCV_TOOLCHAIN_SHA256_amd64=3b9d585f6851b137b3938fb288c5e95d13d0580002fa6ca82b754fcffbff508c
ARG RISCV_TOOLCHAIN_STRIP_amd64=3
ARG RISCV_TOOLCHAIN_SUBDIR_amd64=gnu-mcu-eclipse/riscv-none-gcc/8.2.0-2.2-20190521-0004
ARG RISCV_TOOLCHAIN_URL_arm64=https://github.com/xpack-dev-tools/riscv-none-embed-gcc-xpack/releases/download/v8.3.0-2.3/xpack-riscv-none-embed-gcc-8.3.0-2.3-linux-arm64.tar.gz
ARG RISCV_TOOLCHAIN_SHA256_arm64=7bd7fdeb93481f60271f7d3fb39e41ed7599c9a2f7d03cd1313585ca1f75952d
ARG RISCV_TOOLCHAIN_STRIP_arm64=1
ARG RISCV_TOOLCHAIN_SUBDIR_arm64=

RUN set -eu; \
    eval "arm_gnu_url=\$ARM_GNU_TOOLCHAIN_URL_${BUILDARCH}"; \
    eval "arm_gnu_dir=\$ARM_GNU_TOOLCHAIN_DIR_${BUILDARCH}"; \
    eval "arm_gnu_sha=\$ARM_GNU_TOOLCHAIN_SHA256_${BUILDARCH}"; \
    eval "arm_linux_url=\$ARM_LINUX_TOOLCHAIN_URL_${BUILDARCH}"; \
    eval "arm_linux_dir=\$ARM_LINUX_TOOLCHAIN_DIR_${BUILDARCH}"; \
    eval "arm_linux_sha=\$ARM_LINUX_TOOLCHAIN_SHA256_${BUILDARCH}"; \
    eval "riscv_url=\$RISCV_TOOLCHAIN_URL_${BUILDARCH}"; \
    eval "riscv_sha=\$RISCV_TOOLCHAIN_SHA256_${BUILDARCH}"; \
    eval "riscv_strip=\$RISCV_TOOLCHAIN_STRIP_${BUILDARCH}"; \
    eval "riscv_subdir=\$RISCV_TOOLCHAIN_SUBDIR_${BUILDARCH}"; \
    test -n "$arm_gnu_url" || { echo "unsupported build arch: ${BUILDARCH}" >&2; exit 1; }; \
    mkdir -p /opt "$RISCV_TOOLCHAIN_DIR"; \
    curl -L --fail --retry 3 -o /tmp/arm-toolchain.tar.xz "$arm_gnu_url"; \
    echo "${arm_gnu_sha}  /tmp/arm-toolchain.tar.xz" | sha256sum -c -; \
    tar -C /opt -xf /tmp/arm-toolchain.tar.xz; \
    test -x "/opt/${arm_gnu_dir}/bin/aarch64-none-elf-gcc"; \
    if [ "/opt/${arm_gnu_dir}" != "$ARM_GNU_EXPECT_DIR" ]; then \
        ln -sfn "/opt/${arm_gnu_dir}" "$ARM_GNU_EXPECT_DIR"; \
    fi; \
    test -x "$ARM_GNU_EXPECT_DIR/bin/aarch64-none-elf-gcc"; \
    if [ -n "$arm_linux_url" ]; then \
        curl -L --fail --retry 3 -o /tmp/arm-linux-toolchain.tar.xz "$arm_linux_url"; \
        echo "arm-none-linux-gnu sha256: $(sha256sum /tmp/arm-linux-toolchain.tar.xz | cut -d" " -f1)"; \
        echo "${arm_linux_sha}  /tmp/arm-linux-toolchain.tar.xz" | sha256sum -c -; \
        tar -C /opt -xf /tmp/arm-linux-toolchain.tar.xz; \
        test -x "/opt/${arm_linux_dir}/bin/aarch64-none-linux-gnu-gcc"; \
        if [ "/opt/${arm_linux_dir}" != "$ARM_LINUX_EXPECT_DIR" ]; then \
            ln -sfn "/opt/${arm_linux_dir}" "$ARM_LINUX_EXPECT_DIR"; \
        fi; \
    fi; \
    curl -L --fail --retry 3 -o /tmp/riscv-toolchain.tgz "$riscv_url"; \
    echo "${riscv_sha}  /tmp/riscv-toolchain.tgz" | sha256sum -c -; \
    if [ -n "$riscv_subdir" ]; then \
        tar -C "$RISCV_TOOLCHAIN_DIR" -xzf /tmp/riscv-toolchain.tgz \
            --strip-components="$riscv_strip" "$riscv_subdir"; \
    else \
        tar -C "$RISCV_TOOLCHAIN_DIR" -xzf /tmp/riscv-toolchain.tgz \
            --strip-components="$riscv_strip"; \
    fi; \
    test -x "$RISCV_TOOLCHAIN_DIR/bin/riscv-none-embed-gcc"; \
    rm -f /tmp/arm-toolchain.tar.xz /tmp/arm-linux-toolchain.tar.xz /tmp/riscv-toolchain.tgz

# Toolchain aliases, kept in their own layer so they can be reworked without
# re-downloading. Every target is removed first: these paths may already hold a
# symlink into the real toolchain, and redirecting onto a symlink would write
# through it and clobber the linker it points at.
RUN set -eu; \
    eval "arm_linux_url=\$ARM_LINUX_TOOLCHAIN_URL_${BUILDARCH}"; \
    if [ -z "$arm_linux_url" ]; then \
        mkdir -p "$ARM_LINUX_EXPECT_DIR/bin"; \
        for t in gcc g++ cpp ar as ld ld.bfd nm objcopy objdump ranlib \
                 readelf strip size strings gcov; do \
            if [ -x "/usr/bin/aarch64-linux-gnu-$t" ]; then \
                ln -sf "/usr/bin/aarch64-linux-gnu-$t" \
                    "$ARM_LINUX_EXPECT_DIR/bin/aarch64-none-linux-gnu-$t"; \
            elif [ -x "/usr/bin/$t" ]; then \
                ln -sf "/usr/bin/$t" \
                    "$ARM_LINUX_EXPECT_DIR/bin/aarch64-none-linux-gnu-$t"; \
            fi; \
        done; \
        echo "using native $("$ARM_LINUX_EXPECT_DIR/bin/aarch64-none-linux-gnu-gcc" -dumpmachine) gcc for aarch64-none-linux-gnu"; \
    fi; \
    test -x "$ARM_LINUX_EXPECT_DIR/bin/aarch64-none-linux-gnu-gcc"; \
    mkdir -p "$BL33Z_TOOLCHAIN_DIR/bin"; \
    for t in gcc g++ cpp ar as nm objcopy objdump ranlib \
             readelf strip size strings gcov; do \
        if [ -x "$ARM_GNU_EXPECT_DIR/bin/aarch64-none-elf-$t" ]; then \
            ln -sf "$ARM_GNU_EXPECT_DIR/bin/aarch64-none-elf-$t" \
                "$BL33Z_TOOLCHAIN_DIR/bin/aarch64-elf-$t"; \
        fi; \
    done; \
    for l in ld ld.bfd; do \
        w="$BL33Z_TOOLCHAIN_DIR/bin/aarch64-elf-$l"; \
        rm -f "$w"; \
        printf '#!/bin/sh\nexec %s --no-warn-rwx-segments "$@"\n' \
            "$ARM_GNU_EXPECT_DIR/bin/aarch64-none-elf-$l" > "$w"; \
        chmod +x "$w"; \
    done; \
    test "$(readlink -f "$ARM_GNU_EXPECT_DIR/bin/aarch64-none-elf-ld")" \
        != "$(readlink -f "$BL33Z_TOOLCHAIN_DIR/bin/aarch64-elf-ld")"; \
    "$BL33Z_TOOLCHAIN_DIR/bin/aarch64-elf-ld" --version | head -1; \
    "$BL33Z_TOOLCHAIN_DIR/bin/aarch64-elf-ld" /nonexistent-probe.o 2>&1 \
        | grep -q nonexistent-probe \
        || { echo "ld wrapper does not forward its arguments" >&2; exit 1; }; \
    printf '%s\n' \
        "$ARM_GNU_EXPECT_DIR/bin" \
        "$ARM_LINUX_EXPECT_DIR/bin" \
        "$RISCV_TOOLCHAIN_DIR/bin" \
        > /toolchain-paths

# The Amlogic build scripts locate cross compilers through PATH as a fallback,
# so expose all three toolchains there.
ENV PATH=/opt/riscv-none-gcc/8.2.0-2.2-20190521-0004/bin:$PATH

# Native MOS boot uses the platform/display fixes and the signed-file policy.
ENV SOURCE_DATE_EPOCH=1577836800
RUN apt-get update && apt-get install -y --no-install-recommends device-tree-compiler && rm -rf /var/lib/apt/lists/*
COPY config/s7d_bm201_defconfig /uboot/bl33/v2023/configs/amlogic/s7d_bm201_defconfig
COPY dts/meson-s7d-bm201.dts /uboot/bl33/v2023/arch/arm/dts/amlogic/meson-s7d-bm201.dts
COPY blobs/DDR.USB /DDR.USB
COPY patches/000[1-7]-*.patch patches/0019-*.patch patches/0020-*.patch /patches/
COPY mos-file-boot.c /uboot/bl33/v2023/common/
COPY --from=mos-common mos-records.h /uboot/bl33/v2023/common/
COPY --from=mos-common embed-fit-trust.sh /bsp/embed-fit-trust.sh
COPY --from=mos-boot-trust signer.cert.pem /mos-boot-trust.crt
COPY build-mos.sh /bsp/build-mos.sh
RUN bash /bsp/build-mos.sh

FROM scratch AS artifact
COPY --from=build /artifact/ /
