# syntax=docker/dockerfile:1@sha256:ecfaec9ed6d810b56388c508f4121597bfbba70d41a6dfeee4d8cad5f295fc32
# Build CoreELEC/Hardkernel U-Boot for the S7D/S905X5M BM201 board.

# The base image is injected from build-env/images.env by the BSP Makefile.
# There is no default: omitting the repository pin must fail before the build
# can silently select a mutable image tag.
ARG MOS_IMAGE_UBUNTU_2404
FROM --platform=$BUILDPLATFORM ${MOS_IMAGE_UBUNTU_2404} AS build

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

# The ./mk wrapper only scans bl33/<version>/configs/amlogic/ (see
# fip/variables.sh DEFCFG_FOLDER3), so the overrides must land inside the
# bl33 tree, not at the repository root.
COPY config/s7d_bm201_defconfig /uboot/bl33/v2023/configs/amlogic/s7d_bm201_defconfig
COPY config/bm201_emmc_installer.h /uboot/bl33/v2023/board/amlogic/s7d_bm201/bm201_emmc_installer.h
COPY dts/meson-s7d-bm201.dts /uboot/bl33/v2023/arch/arm/dts/amlogic/meson-s7d-bm201.dts
COPY blobs/DDR.USB /DDR.USB
COPY patches/ /patches/
COPY tests/ /tests/

RUN set -eu; \
    cd /uboot; \
    patch_count="$(find /patches -maxdepth 1 -type f -name '*.patch' | wc -l)"; \
    [ "$patch_count" -eq 18 ] || { \
        echo "ERROR: expected 18 U-Boot patches, found $patch_count" >&2; \
        exit 1; \
    }; \
    for patch_file in $(find /patches -maxdepth 1 -name '*.patch' | sort); do \
        echo ">> applying $(basename "$patch_file")"; \
        git apply --check "$patch_file"; \
        git apply -v "$patch_file"; \
    done; \
    make -C bl33/v2023 CROSS_COMPILE= s7d_bm201_config

# Pin the runtime policy to the applied board source and to the exact upstream
# menu mechanics used by this U-Boot commit. Callback ordering is exercised by
# the host test below; these checks cover the integration around that seam.
RUN set -eu; \
    cd /uboot; \
    board_config=bl33/v2023/configs/amlogic/s7d_bm201_defconfig; \
    board_source=bl33/v2023/board/amlogic/s7d_bm201/s7d_bm201.c; \
    video_source=bl33/v2023/board/amlogic/s7d_bm201/video.c; \
    boot_source=bl33/v2023/board/amlogic/s7d_bm201/boot_source.c; \
    boot_logic=bl33/v2023/board/amlogic/s7d_bm201/boot_source_logic.h; \
    installer_source=bl33/v2023/board/amlogic/s7d_bm201/emmc_installer.c; \
    installer_header=bl33/v2023/board/amlogic/s7d_bm201/bm201_emmc_installer.h; \
    defenv_source=bl33/v2023/cmd/amlogic/defenv_without.c; \
    aml_board_source=bl33/v2023/board/amlogic/common/board.c; \
    cfgload_source=bl33/v2023/cmd/cfgload.c; \
    cfgload_logic=bl33/v2023/cmd/cfgload_logic.h; \
    bootmenu_source=bl33/v2023/cmd/bootmenu.c; \
    menu_source=bl33/v2023/common/menu.c; \
    autoboot_source=bl33/v2023/common/autoboot.c; \
    fs_source=bl33/v2023/fs/fs.c; \
    script_source=bl33/v2023/cmd/script.c; \
    hdmitx_source=bl33/v2023/drivers/amlogic/media/vout/hdmitx/hdmitx21/hdmitx_drv.c; \
    dolby_source=bl33/v2023/drivers/amlogic/media/osd/dv/dolby_vision.c; \
    bootloader_status=bl33/v2023/cmd/amlogic/bootloader_status.c; \
    generated_config=bl33/v2023/build/.config; \
    grep -qxF 'CONFIG_CMD_BOOTMENU=y' "$board_config"; \
    grep -qxF '# CONFIG_CMD_BOOTEFI_BOOTMGR is not set' "$board_config"; \
    ! grep -qxF 'CONFIG_AUTOBOOT_MENU_SHOW=y' "$board_config"; \
    ! grep -qxF 'CONFIG_BOOTMENU_DISABLE_UBOOT_CONSOLE=y' "$board_config"; \
    grep -qxF 'CONFIG_EFI_LOADER=y' "$generated_config"; \
    grep -qxF 'CONFIG_CMD_BOOTEFI=y' "$generated_config"; \
    grep -qxF 'CONFIG_CMD_CLS=y' "$generated_config"; \
    grep -qxF '# CONFIG_CMD_BOOTEFI_BOOTMGR is not set' "$generated_config"; \
    grep -qF '#include <amlogic/media/vout/aml_vout.h>' "$video_source"; \
    grep -qF 'vout_init();' "$video_source"; \
    grep -qF 'vinfo = vout_get_current_vinfo();' "$video_source"; \
    ! grep -qF 'env_get_ulong("display_width", 10, 0)' "$video_source"; \
    grep -qF '"Automatic boot=bm201_boot_source auto"' "$boot_logic"; \
    grep -qF '"Boot Linux from SD=bm201_boot_source sd"' "$boot_logic"; \
    grep -qF '"Boot Linux from eMMC=bm201_boot_source emmc"' "$boot_logic"; \
    grep -qF '"bootmenu 3"' "$boot_logic"; \
    ! grep -qF '"bootmenu_4"' "$boot_logic"; \
    grep -qF 'ops->set(context, "bootdelay", "-1")' "$boot_logic"; \
    grep -qF 'ops->set(context, "bootmenu_3", 0)' "$boot_logic"; \
    grep -qF 'ops->set(context, "bootmenu_default", "0")' "$boot_logic"; \
    grep -qF 'return ops->set(context, "bootdelay", "-2")' "$boot_logic"; \
    grep -qF 'return run_command("bm201_emmc_update", 0);' "$boot_source"; \
    grep -qF 'outcome->installer_status = ops->run_installer(context);' "$boot_logic"; \
    grep -qF 'outcome->cfgload_status = ops->run_cfgload(context, source);' "$boot_logic"; \
    grep -qF 'outcome->restore_status = ops->restore_console(context);' "$boot_logic"; \
    grep -qF 'installer gate failed (%d); Linux boot stopped' "$boot_source"; \
    grep -qF 'returned to recovery' "$boot_source"; \
    grep -qF 'if (source == BM201_LINUX_SOURCE_SD)' "$boot_source"; \
    grep -qF 'return run_command("cfgload sd", 0);' "$boot_source"; \
    grep -qF 'return bm201_run_emmc_boot_script(context);' "$boot_source"; \
    grep -qF '"fatload mmc 1:%u ${loadaddr} boot.scr"' "$boot_source"; \
    grep -qF 'return run_command("source ${loadaddr}", 0);' "$boot_source"; \
    ! grep -qF '"cfgload emmc"' "$boot_source"; \
    grep -qF 'BM201_EMMC_BOOT_SCRIPT_A = 5' "$boot_logic"; \
    grep -qF 'BM201_EMMC_BOOT_SCRIPT_B = 6' "$boot_logic"; \
    grep -qF 'bm201_emmc_boot_script_run' "$boot_logic"; \
    grep -qF 'fs_set_blk_dev("mmc", "0:1", FS_TYPE_ANY)' "$boot_source"; \
    grep -qF 'if (fs_size("/Image", &size) || size <= 0)' "$boot_source"; \
    grep -qF 'status = env_set("stdout", BM201_CONSOLE_SERIAL);' "$boot_source"; \
    grep -qF 'status |= env_set("stderr", BM201_CONSOLE_SERIAL);' "$boot_source"; \
    grep -qF 'status = run_command("cls", 0);' "$boot_source"; \
    grep -qF 'puts(ANSI_CURSOR_SHOW);' "$boot_source"; \
    grep -qF '#include <stdio_dev.h>' "$boot_source"; \
    grep -qF 'video_output && !stdio_get_by_name("vidconsole")' "$boot_source"; \
    grep -qF 'bm201_installer_enable_progress_console();' "$installer_source"; \
    grep -qF 'env_get("bm201_console_out")' "$installer_source"; \
    grep -qF 'stdio_get_by_name("vidconsole")' "$installer_source"; \
    grep -qF 'env_set("stdout", output)' "$installer_source"; \
    grep -qF 'env_set("stderr", output)' "$installer_source"; \
    grep -qF 'run_command("cls", 0)' "$installer_source"; \
    grep -qF 'Do not power off or remove the SD card.' "$installer_source"; \
    grep -qF 'The vendor write progress is mirrored below.' "$installer_source"; \
    grep -qF 'if (argc == 2) {' "$cfgload_source"; \
    grep -qF 'if (argc != 1)' "$cfgload_source"; \
    grep -qF 'env_set("cfgload_devnum", NULL);' "$cfgload_source"; \
    grep -Eq '^[[:space:]]*cfgload,[[:space:]]*2,' "$cfgload_source"; \
    grep -qF 'no fallback' "$cfgload_source"; \
    grep -qF 'returned status %ld; no fallback' "$cfgload_source"; \
    grep -qF 'cfgload_source_run(&ops, &context, source)' "$cfgload_source"; \
    test "$(grep -cF 'if (cfgload_reselect_source(context))' "$cfgload_source")" -eq 3; \
    grep -qF 'sprintf(cmd, "script %p %lx 1", script, size);' "$cfgload_source"; \
    grep -qF 'sprintf(cmd, "script %p %lx 1", p, strlen(p));' "$cfgload_source"; \
    grep -qF 'if (run_command(cmd, 0))' "$cfgload_source"; \
    test "$(sha256sum "$fs_source" | cut -d ' ' -f 1)" = \
        3815903a783cc986d93a64a98c924ac6970ab1dad02a13beb73682aa08b49353; \
    test "$(sha256sum "$script_source" | cut -d ' ' -f 1)" = \
        43b30d711649fdc4bfee96be8aa124752142cd84208ca99f412a0e0c5959191c; \
    grep -qF 'ret = info->exists(filename);' "$fs_source"; \
    grep -qF 'ret = info->size(filename, size);' "$fs_source"; \
    grep -qF 'simple_strtoul(argv[2], NULL, 16)' "$script_source"; \
    test "$(grep -cF 'run_command("saveenv", 0);' "$hdmitx_source")" -eq 1; \
    grep -B1 -A1 -F 'run_command("saveenv", 0);' "$hdmitx_source" \
        | grep -qF '#if !defined(CONFIG_S7D_BM201)'; \
    test "$(grep -cF 'run_command("saveenv", 0);' "$dolby_source")" -eq 1; \
    test "$(grep -cF 'persist_dolby_vision_state();' "$dolby_source")" -eq 9; \
    grep -B1 -A1 -F 'run_command("saveenv", 0);' "$dolby_source" \
        | grep -qF '#if !defined(CONFIG_S7D_BM201)'; \
    grep -qF 'after recovery update, need update uboot env' "$bootloader_status"; \
    grep -qF 'defenv_reserv; setenv upgrade_step 2; saveenv;' "$bootloader_status"; \
    grep -qxF '#define BM201_INSTALLER_RECEIPT_ENV "bm201_installed_package"' "$installer_header"; \
    grep -qF 'BM201_INSTALLER_RECEIPT_ENV' "$installer_source"; \
    grep -qF '_board_env_reserv_array0' "$defenv_source"; \
    grep -qF 'BIT_ENV_RESERV_ARRAY_BOARD_DEFINE0' "$defenv_source"; \
    grep -qF 'const char * const _aml_env_reserv_array[] = {' "$aml_board_source"; \
    reserve_contract="$(sed -n \
        '/^const char \* const _board_env_reserv_array0\[\] = {$/,/^};$/p' \
        "$board_source" | tr -d '[:space:]')"; \
    test "$reserve_contract" = \
        'constchar*const_board_env_reserv_array0[]={BM201_INSTALLER_RECEIPT_ENV,NULL};'; \
    board_receipt_count="$(grep -cF 'BM201_INSTALLER_RECEIPT_ENV' \
        "$board_source" || true)"; \
    test "$board_receipt_count" -eq 1; \
    normal_defenv_count="$(grep -cF \
        'env_set("defenv_para", "-c -b0");' "$board_source" || true)"; \
    default_defenv_count="$(grep -cF \
        'env_set("defenv_para", "-c0 -b0");' "$board_source" || true)"; \
    legacy_normal_count="$(grep -cF \
        'env_set("defenv_para", "-c");' "$board_source" || true)"; \
    legacy_default_count="$(grep -cF \
        'env_set("defenv_para", "-c0");' "$board_source" || true)"; \
    test "$normal_defenv_count" -eq 1; \
    test "$default_defenv_count" -eq 1; \
    test "$legacy_normal_count" -eq 0; \
    test "$legacy_default_count" -eq 0; \
    common_receipt_count="$(grep -Ec \
        'BM201_INSTALLER_RECEIPT_ENV|bm201_installed_package' \
        "$aml_board_source" || true)"; \
    test "$common_receipt_count" -eq 0; \
    installer_upgrade_count="$(grep -cF 'upgrade_step' \
        "$installer_source" || true)"; \
    test "$installer_upgrade_count" -eq 0; \
    printf '%s\n' \
        "ok: BM201 board-local defenv reserve contract board-receipt=$board_receipt_count shared-receipt=$common_receipt_count installer-upgrade-step=$installer_upgrade_count normal=$normal_defenv_count default=$default_defenv_count legacy-normal=$legacy_normal_count legacy-default=$legacy_default_count"; \
    grep -qF 'env_set("stdin", "serial,usbkbd")' "$board_source"; \
    grep -qF 'BM201_CONSOLE_VIDEO' "$board_source"; \
    grep -qF 'stdio_get_by_name("vidconsole")' "$board_source"; \
    grep -qF 'stdio_get_by_name("usbkbd")' "$board_source"; \
    grep -qF 'ret = bm201_setup_boot_menu();' "$board_source"; \
    grep -qF 'ret = bm201_menu_activate(&bm201_menu_ops, NULL);' "$board_source"; \
    ! grep -qF 'bm201_emmc_update' "$board_source" "$bootmenu_source"; \
    grep -qF '/* Add U-Boot console entry at the end */' "$bootmenu_source"; \
    grep -qF 'entry->title = strdup("U-Boot console");' "$bootmenu_source"; \
    grep -qF 'entry->command = strdup("");' "$bootmenu_source"; \
    grep -qF 'if (!bootmenu)' "$bootmenu_source"; \
    grep -qF 'if (!menu)' "$bootmenu_source"; \
    grep -qF 'menu_default_set(menu, "0");' "$bootmenu_source"; \
    grep -qF 'for (i = 0; i < menu->active; ++i)' "$bootmenu_source"; \
    grep -qF 'case KEY_QUIT:' "$bootmenu_source"; \
    grep -qF 'while (iter->next)' "$bootmenu_source"; \
    grep -qF '#if (CONFIG_IS_ENABLED(CMD_BOOTEFI_BOOTMGR)) && (CONFIG_IS_ENABLED(CMD_EFICONFIG))' "$bootmenu_source"; \
    grep -qF 'for (i = 0; i < 100; ++i)' "$menu_source"; \
    grep -qF 'mdelay(10);' "$menu_source"; \
    grep -qF 'if (menu->delay == 0)' "$menu_source"; \
    grep -qF '*key = KEY_SELECT;' "$menu_source"; \
    grep -qF "case '\\e':" "$menu_source"; \
    grep -qF 'case 0x3: /* ^C */' "$menu_source"; \
    grep -qF '*key = KEY_QUIT;' "$menu_source"; \
    grep -qF 'if (s && (stored_bootdelay == -2 ||' "$autoboot_source"; \
    grep -qF '(stored_bootdelay != -1 && !abortboot(stored_bootdelay)))) {' "$autoboot_source"; \
    grep -qF 'run_command_list(s, -1, 0);' "$autoboot_source"; \
    grep -qF '#if defined(CONFIG_AMLOGIC_MODIFY) && !defined(CONFIG_S7D_BM201)' "$autoboot_source"; \
    if grep -Eq '(^|[^[:alnum:]_])(saveenv|env_save)([^[:alnum:]_]|$)' \
        "$board_source" "$boot_source" "$boot_logic" \
        "$cfgload_source" "$cfgload_logic"; then \
        echo 'boot-source policy must remain runtime-only' >&2; \
        exit 1; \
    fi; \
    if grep -Eq 'sdc_burn|mmc[[:space:]]+write|fatwrite' \
        "$board_source" "$boot_source" "$boot_logic" \
        "$cfgload_source" "$cfgload_logic"; then \
        echo 'boot-source policy added a storage-write path outside the installer' >&2; \
        exit 1; \
    fi; \
    grep -qF 'usb_clear_halt(udev, pipe)' \
        bl33/v2023/drivers/usb/host/xhci-ring.c; \
    grep -qF 'if (ep_state == EP_STATE_HALTED)' \
        bl33/v2023/drivers/usb/host/xhci-ring.c

RUN set -eu; \
    cd /uboot; \
    cc -std=c11 -Wall -Wextra -Werror \
        -I bl33/v2023/board/amlogic/s7d_bm201 \
        /tests/emmc_installer_test.c -o /tmp/emmc-installer-test; \
    /tmp/emmc-installer-test; \
    cc -std=c11 -Wall -Wextra -Werror \
        -I bl33/v2023/board/amlogic/s7d_bm201 \
        /tests/bm201_env_reserve_test.c -o /tmp/bm201-env-reserve-test; \
    /tmp/bm201-env-reserve-test; \
    cc -std=c11 -Wall -Wextra -Werror \
        -I bl33/v2023/board/amlogic/s7d_bm201 \
        /tests/emmc_boot_script_test.c -o /tmp/emmc-boot-script-test; \
    /tmp/emmc-boot-script-test; \
    stub_dir=/tmp/bm201-host-stubs; \
    mkdir -p "$stub_dir/linux"; \
    touch "$stub_dir/common.h" "$stub_dir/command.h" "$stub_dir/fs.h" \
        "$stub_dir/ansi.h" "$stub_dir/env.h" "$stub_dir/stdio_dev.h" \
        "$stub_dir/mapmem.h" "$stub_dir/malloc.h" "$stub_dir/mmc.h" \
        "$stub_dir/linux/ctype.h" "$stub_dir/linux/sizes.h"; \
    cc -std=c11 -Wall -Wextra -Werror \
        -DBM201_INSTALLER_PRODUCTION_FAT_SEAM \
        -I "$stub_dir" \
        -I bl33/v2023/board/amlogic/s7d_bm201 \
        /tests/emmc_installer_test.c \
        -o /tmp/emmc-installer-production-fat-test; \
    /tmp/emmc-installer-production-fat-test; \
    cc -std=c11 -Wall -Wextra -Werror \
        -I "$stub_dir" \
        -I bl33/v2023/cmd \
        -I bl33/v2023/board/amlogic/s7d_bm201 \
        /tests/boot_source_menu_test.c -o /tmp/boot-source-menu-test; \
    /tmp/boot-source-menu-test fat; \
    /tmp/boot-source-menu-test script; \
    /tmp/boot-source-menu-test video; \
    /tmp/boot-source-menu-test; \
    for header in charset.h ansi.h efi_config.h efi_variable.h env.h log.h \
                  menu.h watchdog.h cli.h linux/delay.h linux/string.h \
                  linux/list.h; do \
        touch "$stub_dir/$header"; \
    done; \
    generated_config=bl33/v2023/build/.config; \
    bootmgr=0; \
    eficonfig=0; \
    console_disabled=0; \
    efi_loader=0; \
    cmd_bootefi=0; \
    grep -qxF 'CONFIG_CMD_BOOTEFI_BOOTMGR=y' "$generated_config" && bootmgr=1; \
    grep -qxF 'CONFIG_CMD_EFICONFIG=y' "$generated_config" && eficonfig=1; \
    grep -qxF 'CONFIG_BOOTMENU_DISABLE_UBOOT_CONSOLE=y' "$generated_config" && console_disabled=1; \
    grep -qxF 'CONFIG_EFI_LOADER=y' "$generated_config" && efi_loader=1; \
    grep -qxF 'CONFIG_CMD_BOOTEFI=y' "$generated_config" && cmd_bootefi=1; \
    production_hashes="$(sha256sum \
        bl33/v2023/common/menu.c bl33/v2023/cmd/bootmenu.c)"; \
    cc -std=c11 -Wall -Wextra -Werror \
        -DBM201_BOOTMENU_PRODUCTION_SEAM \
        -DBM201_CONFIG_CMD_BOOTEFI_BOOTMGR="$bootmgr" \
        -DBM201_CONFIG_CMD_EFICONFIG="$eficonfig" \
        -DBM201_CONFIG_BOOTMENU_DISABLE_UBOOT_CONSOLE="$console_disabled" \
        -DBM201_CONFIG_EFI_LOADER="$efi_loader" \
        -DBM201_CONFIG_CMD_BOOTEFI="$cmd_bootefi" \
        -I "$stub_dir" \
        -I bl33/v2023/common \
        -I bl33/v2023/cmd \
        /tests/boot_source_menu_test.c \
        -o /tmp/bootmenu-production-seam-test; \
    /tmp/bootmenu-production-seam-test; \
    test "$production_hashes" = "$(sha256sum \
        bl33/v2023/common/menu.c bl33/v2023/cmd/bootmenu.c)"

# The last step asserts that the compressed BL33 made it into the FIP. When
# fip/tools/zstd fails, build.sh carries on regardless and the region where
# U-Boot belongs is zeros: right magic, right header, every earlier stage
# present, and no U-Boot. Such a blob boots as far as BL32 and then resets
# forever, and it satisfies every structural check including a pack/unpack
# round trip through the Amlogic packer. That is what bricked a board.
RUN set -eu; \
    export PATH="$(tr '\n' ':' < /toolchain-paths)$PATH"; \
    cd /uboot; \
    if ! ./fip/tools/zstd --version >/dev/null 2>&1; then \
        echo "fip/tools/zstd cannot run on $(uname -m); substituting the system zstd"; \
        command -v zstd >/dev/null || { echo "error: no system zstd to substitute" >&2; exit 1; }; \
        cp "$(command -v zstd)" fip/tools/zstd; \
    fi; \
    ./fip/tools/zstd --version >/dev/null 2>&1 || true; \
    if [ -x ./mk ]; then \
        ./mk s7d_bm201; \
    else \
        make s7d_bm201_defconfig; \
        make -j"$(nproc)" CROSS_COMPILE=aarch64-linux-gnu-; \
    fi; \
    test -f bl33/v2023/build/.config; \
    for opt in CONFIG_CMD_CFGLOAD=y \
               CONFIG_CMD_BOOTMENU=y \
               CONFIG_CMD_CLS=y \
               CONFIG_CMD_CONSOLE=y \
               CONFIG_VIDEO=y \
               CONFIG_VIDEO_BPP16=y \
               CONFIG_VIDEO_ANSI=y \
               CONFIG_CONSOLE_NORMAL=y \
               CONFIG_SYS_WHITE_ON_BLACK=y \
               CONFIG_CONSOLE_MUX=y \
               CONFIG_SYS_CONSOLE_IS_IN_ENV=y \
               CONFIG_USB_KEYBOARD=y \
               CONFIG_DM_KEYBOARD=y \
               CONFIG_SYS_USB_EVENT_POLL=y \
               CONFIG_EFI_LOADER=y \
               CONFIG_CMD_BOOTEFI=y \
               CONFIG_FAT_WRITE=y \
               'CONFIG_BOOTCOMMAND="run boot_default"' \
               'CONFIG_DEFAULT_DEVICE_TREE="meson-s7d-bm201"'; do \
        grep -qxF "$opt" bl33/v2023/build/.config || { \
            echo "injected defconfig not applied: missing $opt" >&2; exit 1; }; \
    done; \
    grep -qxF '# CONFIG_AUTOBOOT_MENU_SHOW is not set' \
        bl33/v2023/build/.config; \
    ! grep -qxF 'CONFIG_BOOTMENU_DISABLE_UBOOT_CONSOLE=y' \
        bl33/v2023/build/.config; \
    grep -qxF '# CONFIG_CMD_BOOTEFI_BOOTMGR is not set' \
        bl33/v2023/build/.config; \
    for opt in CONFIG_VIDEO_LOGO CONFIG_VIDEO_MESON CONFIG_VIDEO_SIMPLE \
               CONFIG_USB_STORAGE CONFIG_SYS_USB_EVENT_POLL_VIA_CONTROL_EP \
               CONFIG_VIDEO_BPP8 CONFIG_VIDEO_BPP32; do \
        grep -qxF "# $opt is not set" bl33/v2023/build/.config || { \
            echo "injected defconfig not applied: $opt must remain disabled" >&2; exit 1; }; \
    done; \
    mkdir -p /artifact; \
    sd_blob=""; \
    for candidate in \
        build/u-boot.bin.sd.bin.signed \
        u-boot.bin.sd.bin.signed \
        build/u-boot.bin.sd.bin \
        u-boot.bin.sd.bin; do \
        if [ -f "$candidate" ]; then sd_blob="$candidate"; break; fi; \
    done; \
    emmc_blob=""; \
    for candidate in \
        build/u-boot.bin.signed \
        u-boot.bin.signed \
        build/u-boot.bin \
        u-boot.bin; do \
        if [ -f "$candidate" ]; then emmc_blob="$candidate"; break; fi; \
    done; \
    test -n "$sd_blob" || { echo "no SD bootloader output found" >&2; find . -maxdepth 3 -type f -name 'u-boot*.bin*' -print >&2; exit 1; }; \
    cp "$sd_blob" /artifact/u-boot.bin.sd.bin.signed; \
    if [ -n "$emmc_blob" ]; then cp "$emmc_blob" /artifact/u-boot.bin.signed; fi; \
    cp /DDR.USB /artifact/DDR.USB; \
    for blob in /artifact/u-boot.bin.signed /artifact/u-boot.bin.sd.bin.signed; do \
        [ -f "$blob" ] || continue; \
        nz="$(dd if="$blob" bs=4096 skip=416 count=224 status=none \
            | od -An -v -tu1 -w1 | grep -cvx ' *0')"; \
        [ "$nz" -gt 65536 ] || { \
            echo "error: $(basename "$blob") has ${nz} non-zero bytes where BL33 belongs" >&2; \
            echo "  fip/tools/zstd most likely failed; look for a bl33.bin.zstd that was never written." >&2; \
            exit 1; }; \
        echo "ok: $(basename "$blob") carries ${nz} bytes of BL33 sha256=$(sha256sum "$blob" | cut -c1-32)"; \
    done; \
    ls -la /artifact

# Section 5 is a contract over the produced config, never the input defconfig.
# Keep the build available as `--target build` for diagnosis. Board-owned gaps
# refuse artifact export; the separately tracked FIT signing debt is measured
# and reported loudly without pretending the board verifies its kernel.
FROM build AS contract
RUN set -eu; \
    config=/uboot/bl33/v2023/build/.config; \
    test -s "$config"; \
    positive_count="$(grep -cFx -- 'CONFIG_CMD_CFGLOAD=y' "$config" || true)"; \
    echo "section 5 positive control: CONFIG_CMD_CFGLOAD=y matches=$positive_count"; \
    [ "$positive_count" -eq 1 ] || { \
        echo "ERROR: positive control CONFIG_CMD_CFGLOAD=y must match exactly once; section 5 search evidence is invalid" >&2; \
        exit 1; \
    }; \
    board_failures=0; \
    fit_tree_debt=0; \
    bootcount_limit_count="$(grep -cFx -- 'CONFIG_BOOTCOUNT_LIMIT=y' "$config" || true)"; \
    bootcount_env_count="$(grep -cFx -- 'CONFIG_BOOTCOUNT_ENV=y' "$config" || true)"; \
    saveenv_count="$(grep -cFx -- 'CONFIG_CMD_SAVEENV=y' "$config" || true)"; \
    bootcount_observed="$(grep -E '^CONFIG_BOOTCOUNT_(LIMIT|ENV)=|^CONFIG_CMD_SAVEENV=|^# CONFIG_(BOOTCOUNT_LIMIT|BOOTCOUNT_ENV|CMD_SAVEENV) is not set$' "$config" || true)"; \
    [ -n "$bootcount_observed" ] || bootcount_observed='<absent>'; \
    echo "section 5: bootcount limit=$bootcount_limit_count backend=$bootcount_env_count saveenv=$saveenv_count observed=$bootcount_observed"; \
    if [ "$bootcount_limit_count" -ne 1 ] || [ "$bootcount_env_count" -ne 1 ] || [ "$saveenv_count" -ne 1 ]; then \
        echo "ERROR: CONFIG_BOOTCOUNT_LIMIT requires the persistent CONFIG_BOOTCOUNT_ENV backend and CONFIG_CMD_SAVEENV" >&2; \
        board_failures=$((board_failures + 1)); \
    fi; \
    boot_script_positive_count="$(grep -cFx -- 'CONFIG_CMD_SETEXPR=y' "$config" || true)"; \
    echo "section 5 boot-script positive control: CONFIG_CMD_SETEXPR=y matches=$boot_script_positive_count"; \
    [ "$boot_script_positive_count" -eq 1 ] || { \
        echo "ERROR: boot-script positive control CONFIG_CMD_SETEXPR=y must match exactly once; script-command evidence is invalid" >&2; \
        exit 1; \
    }; \
    display_positive_count="$(grep -cFx -- 'CONFIG_AML_VOUT=y' "$config" || true)"; \
    echo "section 5 display positive control: CONFIG_AML_VOUT=y matches=$display_positive_count"; \
    [ "$display_positive_count" -eq 1 ] || { \
        echo "ERROR: display positive control CONFIG_AML_VOUT=y must match exactly once; display-command evidence is invalid" >&2; \
        exit 1; \
    }; \
    boot_script_observed="$(grep -E '^CONFIG_(CMD_SETEXPR|CMD_SOURCE|CMD_IMPORTENV|CMD_FAT|FS_FAT|CMD_BOOTI|CMD_FDT|OF_LIBFDT|LEGACY_IMAGE_FORMAT|HUSH_PARSER|AML_VOUT|AML_HDMITX|AML_HDMITX21|AML_DISABLE_DEV_CMDS)=|^# CONFIG_(CMD_SETEXPR|CMD_SOURCE|CMD_IMPORTENV|CMD_FAT|FS_FAT|CMD_BOOTI|CMD_FDT|OF_LIBFDT|LEGACY_IMAGE_FORMAT|HUSH_PARSER|AML_VOUT|AML_HDMITX|AML_HDMITX21|AML_DISABLE_DEV_CMDS) is not set$' "$config" || true)"; \
    [ -n "$boot_script_observed" ] || boot_script_observed='<absent>'; \
    boot_script_ok=1; \
    for line in \
        CONFIG_CMD_SETEXPR=y \
        CONFIG_CMD_SOURCE=y \
        CONFIG_CMD_IMPORTENV=y \
        CONFIG_CMD_FAT=y \
        CONFIG_FS_FAT=y \
        CONFIG_CMD_BOOTI=y \
        CONFIG_CMD_FDT=y \
        CONFIG_OF_LIBFDT=y \
        CONFIG_LEGACY_IMAGE_FORMAT=y \
        CONFIG_HUSH_PARSER=y \
        CONFIG_AML_VOUT=y \
        CONFIG_AML_HDMITX=y \
        CONFIG_AML_HDMITX21=y; do \
        matches="$(grep -cFx -- "$line" "$config" || true)"; \
        if [ "$matches" -ne 1 ]; then \
            echo "ERROR: production boot.scr requires $line, found $matches match(es) in the built .config" >&2; \
            boot_script_ok=0; \
        fi; \
    done; \
    aml_dev_cmds_disabled_count="$(grep -cFx -- '# CONFIG_AML_DISABLE_DEV_CMDS is not set' "$config" || true)"; \
    if [ "$aml_dev_cmds_disabled_count" -ne 1 ]; then \
        echo "ERROR: CONFIG_AML_DISABLE_DEV_CMDS must remain disabled; enabling it removes production fatload despite CONFIG_CMD_FAT=y" >&2; \
        boot_script_ok=0; \
    fi; \
    echo "section 5: production boot script commands aml-dev-commands-disabled=$aml_dev_cmds_disabled_count observed=$boot_script_observed"; \
    if [ "$boot_script_ok" -ne 1 ]; then \
        echo "ERROR: production boot.scr command/config contract is incomplete" >&2; \
        board_failures=$((board_failures + 1)); \
    fi; \
    env_mmc_count="$(grep -cFx -- 'CONFIG_ENV_IS_IN_MMC=y' "$config" || true)"; \
    env_storage_enabled_count="$(grep -cFx -- 'CONFIG_ENV_IS_IN_STORAGE=y' "$config" || true)"; \
    env_redundancy_count="$(grep -cFx -- 'CONFIG_SYS_REDUNDAND_ENVIRONMENT=y' "$config" || true)"; \
    env_primary_count="$(grep -cFx -- 'CONFIG_ENV_OFFSET=0x7800000' "$config" || true)"; \
    env_redund_count="$(grep -cFx -- 'CONFIG_ENV_OFFSET_REDUND=0x7C00000' "$config" || true)"; \
    env_size_count="$(grep -cFx -- 'CONFIG_ENV_SIZE=0x10000' "$config" || true)"; \
    env_dev_count="$(grep -cFx -- 'CONFIG_SYS_MMC_ENV_DEV=1' "$config" || true)"; \
    env_part_count="$(grep -cFx -- 'CONFIG_SYS_MMC_ENV_PART=0' "$config" || true)"; \
    env_observed="$(grep -E '^CONFIG_(ENV_IS_IN_MMC|SYS_REDUNDAND_ENVIRONMENT|ENV_OFFSET|ENV_OFFSET_REDUND|ENV_SIZE|SYS_MMC_ENV_DEV|SYS_MMC_ENV_PART)=|^# CONFIG_ENV_IS_IN_STORAGE is not set$' "$config" || true)"; \
    [ -n "$env_observed" ] || env_observed='<absent>'; \
    env_dtb="$(find /uboot/bl33/v2023/build -type f -name 'meson-s7d-bm201.dtb' -print -quit)"; \
    env_dtb_ok=1; \
    env_dtb_override_count=0; \
    if [ -z "$env_dtb" ]; then \
        echo 'ERROR: built U-Boot DTB is missing; cannot verify MMC environment overrides' >&2; \
        env_dtb_ok=0; \
    else \
        for prop in u-boot,mmc-env-partition u-boot,mmc-env-offset u-boot,mmc-env-offset-redundant; do \
            if grep -aFq -- "$prop" "$env_dtb"; then \
                echo "ERROR: built U-Boot DTB carries $prop, which overrides the pinned MMC environment offsets" >&2; \
                env_dtb_override_count=$((env_dtb_override_count + 1)); \
                env_dtb_ok=0; \
            fi; \
        done; \
    fi; \
    echo "section 5: redundant MMC environment mmc=$env_mmc_count storage-enabled=$env_storage_enabled_count redundant=$env_redundancy_count primary=$env_primary_count redundant-offset=$env_redund_count size=$env_size_count dev=$env_dev_count part=$env_part_count dtb=$env_dtb dt-overrides=$env_dtb_override_count observed=$env_observed"; \
    if [ "$env_mmc_count" -ne 1 ] || [ "$env_storage_enabled_count" -ne 0 ] || \
       [ "$env_redundancy_count" -ne 1 ] || [ "$env_primary_count" -ne 1 ] || \
       [ "$env_redund_count" -ne 1 ] || [ "$env_size_count" -ne 1 ] || \
       [ "$env_dev_count" -ne 1 ] || [ "$env_part_count" -ne 1 ] || \
       [ "$env_dtb_ok" -ne 1 ]; then \
        echo "ERROR: redundant MMC environment must use the approved uenv-a/uenv-b offsets and no DT override" >&2; \
        board_failures=$((board_failures + 1)); \
    fi; \
    fit_count="$(grep -cFx -- 'CONFIG_FIT=y' "$config" || true)"; \
    fit_signature_count="$(grep -cFx -- 'CONFIG_FIT_SIGNATURE=y' "$config" || true)"; \
    fit_observed="$(grep -E '^CONFIG_FIT=|^# CONFIG_FIT is not set$' "$config" || true)"; \
    fit_signature_observed="$(grep -E '^CONFIG_FIT_SIGNATURE=|^# CONFIG_FIT_SIGNATURE is not set$' "$config" || true)"; \
    [ -n "$fit_observed" ] || fit_observed='<absent>'; \
    [ -n "$fit_signature_observed" ] || fit_signature_observed='<absent>'; \
    echo "section 5: CONFIG_FIT=y matches=$fit_count observed=$fit_observed"; \
    echo "section 5: CONFIG_FIT_SIGNATURE=y matches=$fit_signature_count observed=$fit_signature_observed"; \
    if [ "$fit_count" -ne 1 ] || [ "$fit_signature_count" -ne 1 ]; then \
        fit_tree_debt=1; \
        echo "WARNING: TREE-WIDE FIT SECURITY DEBT: FIT signature is absent or disabled; CONFIG_FIT=$fit_observed CONFIG_FIT_SIGNATURE=$fit_signature_observed" >&2; \
        echo "WARNING: s905x5m does NOT verify its kernel; its U-Boot chain of trust is incomplete. RFCT-925 owns the mainline FIT signing decision." >&2; \
    fi; \
    bootm_count="$(grep -cE '^CONFIG_SYS_BOOTM_LEN=' "$config" || true)"; \
    bootm_observed="$(grep -E '^CONFIG_SYS_BOOTM_LEN=' "$config" || true)"; \
    [ -n "$bootm_observed" ] || bootm_observed='<absent>'; \
    bootm_expected=0x4000000; \
    bootm_expected_bytes=$((bootm_expected)); \
    bootm_value='<unusable>'; \
    bootm_ok=0; \
    if [ "$bootm_count" -eq 1 ] && \
       printf '%s\n' "$bootm_observed" | grep -Eq '^CONFIG_SYS_BOOTM_LEN=(0[xX][0-9a-fA-F]+|0|[1-9][0-9]*)$'; then \
        bootm_raw="${bootm_observed#*=}"; \
        bootm_value=$((bootm_raw)); \
        if [ "$bootm_value" -eq "$bootm_expected_bytes" ]; then bootm_ok=1; fi; \
    fi; \
    echo "section 5: CONFIG_SYS_BOOTM_LEN matches=$bootm_count observed=$bootm_observed bytes=$bootm_value expected=$bootm_expected derived-for=s905x5m"; \
    if [ "$bootm_ok" -ne 1 ]; then \
        echo "ERROR: CONFIG_SYS_BOOTM_LEN must equal s905x5m's derived $bootm_expected" >&2; \
        board_failures=$((board_failures + 1)); \
    fi; \
    if [ "$board_failures" -ne 0 ]; then \
        echo "ERROR: U-Boot section 5 contract failed in $board_failures board-owned requirement group(s); refusing artifact export" >&2; \
        exit 1; \
    fi; \
    if [ "$fit_tree_debt" -ne 0 ]; then \
        echo "WARNING: artifact export continues with the tree-wide FIT security debt above; do not treat this artifact as kernel-verified" >&2; \
        echo 'section 5: board-owned U-Boot requirements pass; tree-wide FIT security debt remains'; \
    else \
        echo 'section 5: all U-Boot requirements pass'; \
    fi

FROM scratch AS artifact
COPY --from=contract /artifact/ /
