# syntax=docker/dockerfile:1@sha256:ecfaec9ed6d810b56388c508f4121597bfbba70d41a6dfeee4d8cad5f295fc32
# Build Linux 6.1.115, modules, and the CX3576-Z device tree.

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

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        git ca-certificates build-essential bc bison flex \
        libssl-dev libelf-dev python3 kmod patch \
        gcc-aarch64-linux-gnu device-tree-compiler \
    && rm -rf /var/lib/apt/lists/*

ARG KERNEL_REPO=https://github.com/armbian/linux-rockchip.git
ARG KERNEL_COMMIT=c6157104418d012823413c02f9222f3fe123dd25
RUN git init -q /ksrc && \
    git -C /ksrc remote add origin "${KERNEL_REPO}" && \
    git -C /ksrc fetch --depth=1 origin "${KERNEL_COMMIT}" && \
    git -C /ksrc checkout -q --detach FETCH_HEAD && \
    test "$(git -C /ksrc rev-parse HEAD)" = "${KERNEL_COMMIT}"

COPY kernel/patches/ /patches/
COPY kernel/dts/rk3576-cx3576z.dts /ksrc/arch/arm64/boot/dts/rockchip/
# A for loop's status is that of its last iteration and the old `ls
# 2>/dev/null` glob made an empty or missing /patches a green zero-patch run —
# so a reject in any patch but the last (or a lost COPY) still produced an
# artifact built from a partially patched or unpatched tree. set -e aborts on
# the first failing patch; the count pins the expected series length and must
# move with kernel/patches/ whenever a patch is added or removed. Each patch's
# effect is additionally asserted in the compiled tree after `make` below.
RUN set -e; \
    count=$(ls /patches/*.patch | wc -l); \
    [ "$count" -eq 4 ] || { echo "ERROR: expected 4 kernel patches, found $count" >&2; exit 1; }; \
    cd /ksrc && for p in $(ls /patches/*.patch | sort); do \
        echo ">> applying $(basename "$p")" && patch -p1 --no-backup-if-mismatch < "$p"; \
    done

COPY kernel/config/kernel-cx3576z.config /ksrc/.config
# Shared mos runtime baseline from boards/common/ — requires the named build
# context: docker buildx build --build-context mos-common=../../common ...
# (wired in the board Makefile; a bare build without it fails here, loudly).
COPY --from=mos-common mos-required.fragment /mos-required.fragment

ARG KERNEL_EXPECT=6.1.115
RUN cd /ksrc && \
    scripts/config --disable LOCALVERSION_AUTO \
                   --disable WL_ROCKCHIP --disable WIFI_BUILD_MODULE \
                   --disable AP6XXX --disable BCMDHD \
                   --disable BCMDHD_SDIO --disable BCMDHD_PCIE \
                   --enable RFKILL_RK \
                   --enable RTC_DRV_HYM8563 \
                   --enable LEDS_TRIGGERS \
                   --enable LEDS_TRIGGER_HEARTBEAT \
                   --set-str AIC_FW_PATH "/lib/firmware" && \
    ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
        scripts/kconfig/merge_config.sh -m .config /mos-required.fragment && \
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig && \
    grep -q "^CONFIG_SQUASHFS_ZSTD=y" .config && \
    grep -q "^CONFIG_OVERLAY_FS=y" .config && \
    grep -q "^CONFIG_MEMCG=y" .config && \
    grep -q "^CONFIG_FRAMEBUFFER_CONSOLE=y" .config && \
    grep -q "^CONFIG_DRM_FBDEV_EMULATION=y" .config && \
    grep -q "^CONFIG_AIC_WLAN_SUPPORT=y" .config && \
    grep -q '^CONFIG_AIC_FW_PATH="/lib/firmware"' .config && \
    grep -q '^CONFIG_RFKILL_RK=y' .config && \
    grep -q '^CONFIG_RTC_DRV_HYM8563=y' .config && \
    grep -q '^CONFIG_LEDS_TRIGGER_HEARTBEAT=y' .config && \
    grep -q '^# CONFIG_WL_ROCKCHIP is not set' .config && \
    ! grep -q '^CONFIG_AP6XXX=' .config && \
    ! grep -q '^CONFIG_BCMDHD=' .config && \
    # THE BOARD'S OWN OPTIONS, AND NOTHING ELSE. This loop used to restate 19
    # symbols that boards/common/mos-required.fragment now pins -- BRIDGE,
    # VETH, the NF_TABLES and NFT_* core, CGROUP_BPF and the NFT_FIB family --
    # and the fragment loop below asserts every one of them against the same
    # built .config, on both boards. Two lists free to disagree are one list
    # that is not enforced, so the duplicates are gone and what is left is what
    # no shared floor could state:
    #
    #   * this hardware -- an RK3576 with a USB gadget controller and a gadget
    #     serial console, and eMMC/USB storage. A QEMU machine has none of it.
    #   * the arm64 accelerated AES. The shared floor carries the generic
    #     xts(aes) the crypt target resolves through and says why that is
    #     capability rather than a feature; CE_BLK is this architecture's fast
    #     path for it and exists on no other, which is why the floor cannot
    #     name it. x64 carries CRYPTO_AES_NI_INTEL for the same reason.
    #
    # THE FIREWALL REMAINDER IS GONE FROM HERE TOO, and it left by two
    # different routes (RFCT-304). The seven xt matches and targets moved into
    # the shared fragment, because the measurement made them an
    # engine-and-tooling fact rather than policy: the shipped iptables stores
    # every extension as an nft_compat `xt` expression, and on a kernel without
    # the module the rule is refused outright. They were =y here and absent or
    # =m on x64, which is why `iptables -j REDIRECT` worked on this board and
    # not on that one. The ten legacy IP_NF_*/IP6_NF_* entries are simply gone:
    # iptables-nft builds its raw and nat tables in nf_tables and needs none of
    # them -- measured, on a kernel with IP_NF_RAW unset, `iptables -t raw -A
    # PREROUTING -j ACCEPT` succeeds and stores a native rule -- and the only
    # front-end that does need them is iptables-legacy, which nothing in this
    # tree selects. Asserting them here made this board's legacy surface look
    # like a requirement when it is a leftover of the vendor config.
    for option in \
        BLK_DEV_SD CONFIGFS_FS HID_GENERIC INPUT_EVDEV \
        SCSI USB_CONFIGFS USB_CONFIGFS_ACM USB_DWC3 \
        USB_DWC3_DUAL_ROLE USB_F_ACM USB_GADGET USB_HID \
        USB_LIBCOMPOSITE USB_OTG USB_STORAGE USB_U_SERIAL \
        CRYPTO_AES_ARM64_CE_BLK; do \
        grep -q "^CONFIG_${option}=y" .config || { \
            echo "missing cx3576 board kernel option: CONFIG_${option}=y" >&2; \
            exit 1; \
        }; \
    done && \
    n=0; \
    for line in $(sed -n 's/^\(CONFIG_[A-Z0-9_]*=y\)$/\1/p' /mos-required.fragment); do \
        n=$((n + 1)); \
        grep -q "^${line}$" .config || { \
            echo "missing mos-required option: ${line}" >&2; \
            exit 1; \
        }; \
    done; \
    # The count, because this loop is now the ONLY assertion for the 28 symbols
    # the board loop above stopped restating. A fragment that failed to arrive
    # would make it iterate zero times and report nothing; an assertion over an
    # empty list is green whatever the kernel does.
    [ "$n" -gt 0 ] || { echo "zero =y lines were read from /mos-required.fragment; the shared floor asserted nothing" >&2; exit 1; }; \
    echo "config: all ${n} mos-required options are set"

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
# `-j"$(nproc)"` below was the other suspect and is NOT implicated: every
# differing byte in both experiments was a date string or a hash of one, and
# nothing about parallelism produces those. CONFIG_DEBUG_INFO was the third and
# is not implicated either, for the same reason.
ENV KBUILD_BUILD_TIMESTAMP="@1577836800" \
    KBUILD_BUILD_USER=mos \
    KBUILD_BUILD_HOST=mos-build \
    SOURCE_DATE_EPOCH=1577836800

RUN cd /ksrc && \
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j"$(nproc)" Image modules && \
    # The patch loop proves the series applied without rejects; these prove the
    # tree that was just compiled carries each patch's effect (one distinctive
    # added line per patch, same shape as the uboot Dockerfile's post-build
    # BOOT_LOADER/write_cache greps): 0001's yt8531_stock_init module param and
    # 0002's AIC_WLAN_SUPPORT gate on the aic8800_sdio directory.
    grep -qF 'module_param(yt8531_stock_init, bool, 0444);' drivers/net/phy/motorcomm.c && \
    grep -qF 'obj-$(CONFIG_AIC_WLAN_SUPPORT) += aic8800_sdio/' drivers/net/wireless/Makefile && \
    grep -qF 'BUILD_DATE=$(shell date -u -d' drivers/gpu/arm/mali400/mali/Kbuild && \
    grep -qF 'dtb-$(CONFIG_ARCH_ROCKCHIP) += rk3576-cx3576z.dtb' \
        arch/arm64/boot/dts/rockchip/Makefile && \
    grep -q '^CONFIG_LEDS_TRIGGER_HEARTBEAT=y' include/config/auto.conf && \
    echo "kernel release: $(cat include/config/kernel.release)" && \
    [ "$(cat include/config/kernel.release)" = "${KERNEL_EXPECT}" ] && \
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
         INSTALL_MOD_PATH=/kmods INSTALL_MOD_STRIP=1 modules_install && \
    # DETERMINISTIC ARCHIVE PARAMETERS, and this is a packaging fix rather than
    # a compile one -- separable from the Image above and measured separately.
    # RFCT-343 compared two modules.tar from two --no-cache builds: every member
    # was byte-identical, the member ORDER was identical, and every header
    # carried the wall clock of its build. So the archive, not its contents, was
    # the whole difference. --mtime pins that clock to the one instant this
    # repository stamps everywhere; --owner/--group/--numeric-owner keep the ids
    # from describing the builder; --sort=name makes the order a function of the
    # names rather than of readdir, which agreed across the two runs measured and
    # is promised by nothing.
    tar --sort=name --mtime=@1577836800 --owner=0 --group=0 --numeric-owner \
        -C /kmods -cf /modules.tar lib && \
    printf '%s\n' "$(cat include/config/kernel.release)" > /kernel.release && \
    ls /kmods/lib/modules/

# Build the board DTB directly from the maintained source. The Makefile entry
# that makes this target exist is kernel/patches/0004, applied with the rest of
# the series above -- it was an `echo ... >>` here until RFCT-343, which is an
# edit to the kernel source performed by a shell redirection in the middle of a
# build, invisible to the series-length assertion and to review. The .dts itself
# is copied in beside the patches, above, so that the tree is coherent from the
# moment 0004 names the file rather than only by the time this stage runs.
RUN cd /ksrc && \
    grep -qF 'dtb-$(CONFIG_ARCH_ROCKCHIP) += rk3576-cx3576z.dtb' \
        arch/arm64/boot/dts/rockchip/Makefile && \
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- rockchip/rk3576-cx3576z.dtb && \
    cp arch/arm64/boot/dts/rockchip/rk3576-cx3576z.dtb /rk3576-src.dtb && \
    test "$(fdtget /rk3576-src.dtb /leds/status-red label)" = "status-red" && \
    test "$(fdtget /rk3576-src.dtb /leds/status-red default-state)" = "on" && \
    test "$(fdtget -t x /rk3576-src.dtb /leds/status-red gpios | awk '{print $3}')" = "1" && \
    test "$(fdtget /rk3576-src.dtb /leds/status-blue label)" = "status-blue" && \
    test "$(fdtget /rk3576-src.dtb /leds/status-blue default-state)" = "off" && \
    test "$(fdtget -t x /rk3576-src.dtb /leds/status-blue gpios | awk '{print $3}')" = "0"

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
