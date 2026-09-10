# syntax=docker/dockerfile:1@sha256:ecfaec9ed6d810b56388c508f4121597bfbba70d41a6dfeee4d8cad5f295fc32
# Build the Hardkernel S905X5M kernel, modules, and M100 board DTB.

# The builder image is injected from build-env/images.env by the BSP
# Makefile. There is no default: an omitted pin must fail before the build can
# silently choose a mutable tag.
ARG MOS_IMAGE_UBUNTU_2404
FROM --platform=$BUILDPLATFORM ${MOS_IMAGE_UBUNTU_2404} AS build

ARG DEBIAN_FRONTEND=noninteractive

# Fetch the source before anything else. It is by far the slowest step -- the
# submodules come from git.odroid.com, which has stalled for minutes at a time
# -- and it depends only on KERNEL_REPO/KERNEL_COMMIT. Keeping it ahead of the
# package list and the config means editing either of those reuses the cached
# source instead of cloning several GB again.
RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

ARG KERNEL_REPO=https://github.com/hardkernel/linux.git
ARG KERNEL_COMMIT=9ea2aa831a585955dcb0e38a0bc3c63d2c690adc
# git over HTTP/2 stalls in this image: the TLS handshake completes and the
# stream opens, then the response never arrives and the fetch hangs for
# minutes. HTTP/1.1 returns immediately against the same host, and apt (also
# HTTP/1.1) was never affected. Pin the version rather than depend on whatever
# the network path does with HTTP/2.
RUN git config --global http.version HTTP/1.1 && \
    git init -q /ksrc && \
    git -C /ksrc remote add origin "${KERNEL_REPO}" && \
    git -C /ksrc fetch --depth=1 origin "${KERNEL_COMMIT}" && \
    git -C /ksrc checkout -q --detach FETCH_HEAD && \
    test "$(git -C /ksrc rev-parse HEAD)" = "${KERNEL_COMMIT}" && \
    git -C /ksrc submodule update --init --recursive --depth=1

# On an arm64 builder the kernel is a native build, and Ubuntu ships no
# gcc-aarch64-linux-gnu cross package there; build-essential provides gcc.
ARG BUILDARCH
ARG CROSS_COMPILE_amd64=aarch64-linux-gnu-
ARG CROSS_COMPILE_arm64=
RUN apt-get update && apt-get install -y --no-install-recommends \
        bc \
        bison \
        build-essential \
        device-tree-compiler \
        flex \
        kmod \
        libelf-dev \
        libssl-dev \
        patch \
        perl \
        python3 \
        rsync \
    && if [ "${BUILDARCH}" = "amd64" ]; then \
           apt-get install -y --no-install-recommends \
               gcc-aarch64-linux-gnu; \
       fi \
    && rm -rf /var/lib/apt/lists/*

COPY kernel/patches/ /patches/
# Pin the expected series length so a pattern that selects nothing cannot turn
# a missing COPY into a green zero-patch build. --dry-run reports a bad patch
# before anything in the tree has been touched; set -e stops on the first one.
RUN set -eu; \
    count="$(find /patches -maxdepth 1 -type f -name '*.patch' | wc -l)"; \
    [ "${count}" -eq 14 ] || { \
        echo "ERROR: expected 14 kernel patches, found ${count}" >&2; \
        exit 1; \
    }; \
    cd /ksrc; \
    for p in $(find /patches -maxdepth 1 -type f -name '*.patch' | sort); do \
        echo ">> applying $(basename "$p")"; \
        patch -p1 --dry-run --no-backup-if-mismatch < "$p" > /dev/null; \
        patch -p1 --no-backup-if-mismatch < "$p"; \
    done

COPY kernel/config/kernel-s905x5m.config /ksrc/.config
COPY kernel/config/runtime.fragment /runtime.fragment
COPY kernel/config/wireless.fragment /wireless.fragment
COPY kernel/config/signed-boot.fragment /signed-boot.fragment
COPY --from=mos-trust signer.cert.pem /ksrc/certs/mos-verity-anchor.pem
COPY kernel/dts/s7d_s905x5m_m100.dts /ksrc/common_drivers/arch/arm64/boot/dts/amlogic/
# Shared mos runtime baseline from boards/common/. The named context is
# wired by the BSP Makefile; a bare build without it fails at this COPY.
COPY --from=mos-common mos-required.fragment /mos-required.fragment

ENV KBUILD_BUILD_TIMESTAMP="@1577836800" KBUILD_BUILD_USER=mos KBUILD_BUILD_HOST=mos-build SOURCE_DATE_EPOCH=1577836800

ARG KERNEL_EXPECT=6.12.38-m100-arm64
# The first fixed-string lookup is a positive control against the final
# .config. Only after that succeeds does a missing requirement count as
# evidence rather than as a broken search.
RUN set -eu; \
    eval "export CROSS_COMPILE=\$CROSS_COMPILE_${BUILDARCH}"; \
    cd /ksrc; \
    scripts/config --disable LOCALVERSION_AUTO \
                   --disable IKHEADERS; \
    ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" \
        scripts/kconfig/merge_config.sh -m .config \
            /runtime.fragment /wireless.fragment /mos-required.fragment /signed-boot.fragment; \
    make ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" olddefconfig; \
    test -s certs/mos-verity-anchor.pem; \
    grep -Fqx 'CONFIG_SYSTEM_TRUSTED_KEYS="certs/mos-verity-anchor.pem"' .config; \
    grep -Fxf /signed-boot.fragment .config | grep -q '^CONFIG_CMDLINE='; \
    test -s .config; \
    grep -Fqx -- 'CONFIG_ARM64=y' .config || { \
        echo 'final .config grep control did not find CONFIG_ARM64=y' >&2; \
        exit 1; \
    }; \
    control_line="$(sed -n 's/^\(CONFIG_BLK_DEV_DM=y\)$/\1/p' /mos-required.fragment)"; \
    [ "${control_line}" = 'CONFIG_BLK_DEV_DM=y' ] || { \
        echo 'mos-required extraction control did not find CONFIG_BLK_DEV_DM=y' >&2; \
        exit 1; \
    }; \
    grep -Fqx -- "${control_line}" .config || { \
        echo "missing mos-required option: ${control_line}" >&2; \
        exit 1; \
    }; \
    for line in $(sed -n 's/^\(CONFIG_[A-Z0-9_]*=y\)$/\1/p' /mos-required.fragment); do \
        grep -Fqx -- "${line}" .config || { \
            echo "missing mos-required option: ${line}" >&2; \
            exit 1; \
        }; \
    done; \
    lsm_count="$(sed -n '/^CONFIG_LSM=/p' /mos-required.fragment | wc -l)"; \
    [ "${lsm_count}" -eq 1 ] || { \
        echo "expected one CONFIG_LSM line in mos-required.fragment, found ${lsm_count}" >&2; \
        exit 1; \
    }; \
    lsm_line="$(sed -n '/^CONFIG_LSM=/p' /mos-required.fragment)"; \
    grep -Fqx -- "${lsm_line}" .config || { \
        echo "missing mos-required LSM list: ${lsm_line}" >&2; \
        exit 1; \
    }; \
    for line in $(sed -n 's/^\(CONFIG_[A-Z0-9_]*=[ym]\)$/\1/p' \
                      /runtime.fragment /wireless.fragment /signed-boot.fragment); do \
        grep -Fqx -- "${line}" .config || { \
            echo "missing board-required option: ${line}" >&2; \
            exit 1; \
        }; \
    done; \
    for line in \
        CONFIG_DEVTMPFS=y CONFIG_SECCOMP=y CONFIG_CGROUPS=y \
        CONFIG_NF_TABLES=y CONFIG_CONFIGFS_FS=y; do \
        grep -Fqx -- "${line}" .config || { \
            echo "missing board kernel option: ${line}" >&2; \
            exit 1; \
        }; \
    done

RUN set -eu; \
    eval "export CROSS_COMPILE=\$CROSS_COMPILE_${BUILDARCH}"; \
    cd /ksrc; \
    if ! grep -Fq 'dtb-y += s7d_s905x5m_m100.dtb' \
        common_drivers/arch/arm64/boot/dts/amlogic/Makefile; then \
        printf '%s\n' 'dtb-y += s7d_s905x5m_m100.dtb' \
            >> common_drivers/arch/arm64/boot/dts/amlogic/Makefile; \
    fi; \
    make ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" -j"$(nproc)" \
        KCFLAGS=-Wno-error=enum-int-mismatch \
        Image modules amlogic/s7d_s905x5m_m100.dtb; \
    kernel_release="$(cat include/config/kernel.release)"; \
    echo "kernel release: ${kernel_release}"; \
    [ "${kernel_release}" = "${KERNEL_EXPECT}" ]; \
    make ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" \
        INSTALL_MOD_PATH=/kmods INSTALL_MOD_STRIP=1 DEPMOD=true modules_install; \
    cp common_drivers/arch/arm64/boot/dts/amlogic/s7d_s905x5m_m100.dtb \
        /s7d_s905x5m_m100.dtb; \
    compatible="$(fdtget /s7d_s905x5m_m100.dtb / compatible)"; \
    [ "${compatible}" = 's7d_s905x5m_bm201' ]; \
    [ "$(fdtget -t u /s7d_s905x5m_m100.dtb /soc/apb4@fe000000/watchdog@2100 amlogic,feed_watchdog_mode)" = 0 ]; \
    [ "$(fdtget -t u /s7d_s905x5m_m100.dtb /soc/apb4@fe000000/watchdog@2100 timeout-sec)" = 60 ]

# The vendor Android 5.15 tree carries an HT1628 driver for this exact panel,
# but it uses obsolete integer GPIO and character-device APIs.  Build the
# bounded 6.12 port as a separate module so it does not modify Amlogic's
# aggregate amlogic-led.ko for every board.
COPY kernel/front-panel /front-panel
RUN set -eu; \
    eval "export CROSS_COMPILE=\$CROSS_COMPILE_${BUILDARCH}"; \
    make -C /ksrc ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" \
        M=/front-panel clean; \
    make -C /ksrc ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" \
        M=/front-panel -j"$(nproc)" modules; \
    kver="$(cat /ksrc/include/config/kernel.release)"; \
    mkdir -p "/kmods/lib/modules/${kver}/extra"; \
    cp /front-panel/skykirin_ht1628.ko \
        "/kmods/lib/modules/${kver}/extra/skykirin_ht1628.ko"; \
    test -s "/kmods/lib/modules/${kver}/extra/skykirin_ht1628.ko"; \
    modinfo -F alias "/kmods/lib/modules/${kver}/extra/skykirin_ht1628.ko" \
        | grep -Fqx 'of:N*T*Cskykirin-ht1628C*'

# Seekwave SWT6621/EA6621QT combo: Wi-Fi over SDIO, Bluetooth sharing that same
# bus. The board DTS names brcm,bcm4329-fmac, inherited from the reference
# design, but the real part is this one and its driver lives out of tree.
#
# The sources are kept under kernel/third rather than fetched during the build,
# so the build does not depend on a third-party repository staying reachable
# and the code can be patched here. Its Makefile takes
# ARCH/CROSS_COMPILE/KERNEL_SRC/M from the caller; upstream's hardcodes
# CoreELEC's clang toolchain.
#
# gcc, not clang: CONFIG_GCC_PLUGINS=y cannot work under clang, and
# CONFIG_MODVERSIONS=y would reject a mismatched module at insmod time.
COPY kernel/third/seekwave /skw

# skwifi links against symbols exported by the platform driver, so the bsp half
# has to be built first and its Module.symvers handed to the second pass.
#
# Bluetooth here is not a UART HCI link: it shares the SDIO bus with Wi-Fi and
# surfaces as a character device under the driver's btcom class.
#
# CONFIG_SKW_BT is deliberately not set. It defines CONFIG_BT_SEEKWAVE, which
# selects skw_sdio_bind_btseekwave_driver() and hands HCI to Seekwave's own
# Bluetooth module -- code that is not in this repository, leaving only the
# BTBOOT port and no data channel. Leaving it unset takes the #else path,
# skw_sdio_bind_BT_driver(), which creates /dev/BTDATA for BlueZ to attach.
RUN set -eu; \
    eval "export CROSS_COMPILE=\$CROSS_COMPILE_${BUILDARCH}"; \
    make -C /skw ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" \
        KERNEL_SRC=/ksrc M=/skw -j"$(nproc)"; \
    kver="$(cat /ksrc/include/config/kernel.release)"; \
    mkdir -p "/kmods/lib/modules/${kver}/extra"; \
    find /skw/drivers -name '*.ko' \
        -exec cp {} "/kmods/lib/modules/${kver}/extra/" \; ; \
    ls -la "/kmods/lib/modules/${kver}/extra/"; \
    test -f "/kmods/lib/modules/${kver}/extra/skw_sdio.ko"; \
    test -f "/kmods/lib/modules/${kver}/extra/skw.ko"

# mos's rootfs stage deliberately does not run depmod: modules.tar is the BSP
# interface and must already carry indexes for the complete module set. Run it
# only after both out-of-tree builds have installed their modules.
RUN set -eu; \
    kver="$(cat /ksrc/include/config/kernel.release)"; \
    depmod -b /kmods "${kver}"; \
    module_dir="/kmods/lib/modules/${kver}"; \
    for index in modules.dep modules.dep.bin modules.alias modules.alias.bin; do \
        test -s "${module_dir}/${index}"; \
    done; \
    for index in modules.softdep modules.symbols; do \
        test -f "${module_dir}/${index}"; \
    done; \
    for module in skykirin_ht1628.ko skw_sdio.ko skw.ko; do \
        count="$(find "${module_dir}" -type f -name "${module}" | wc -l)"; \
        [ "${count}" -eq 1 ] || { \
            echo "expected one ${module} in modules.tar, found ${count}" >&2; \
            exit 1; \
        }; \
    done; \
    tar -C /kmods -cf /modules.tar lib

COPY --from=mos-common export-regdb-certs.py /export-regdb-certs.py
RUN python3 /export-regdb-certs.py /ksrc /regdb-certs.pem

FROM scratch AS artifact
COPY --from=build /ksrc/arch/arm64/boot/Image /
COPY --from=build /modules.tar /
COPY --from=build /s7d_s905x5m_m100.dtb /
COPY --from=build /ksrc/.config /config
COPY --from=build /ksrc/include/config/kernel.release /kernel.release
COPY --from=build /ksrc/System.map /System.map
COPY --from=build /regdb-certs.pem /
