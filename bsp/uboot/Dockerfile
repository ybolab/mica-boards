# syntax=docker/dockerfile:1@sha256:ecfaec9ed6d810b56388c508f4121597bfbba70d41a6dfeee4d8cad5f295fc32
# Build U-Boot v2026.07 with RK3576 DDR v1.12 and BL31 v1.24.
# Recovery enters RockUSB; failed boot falls back to RockUSB.
#
# Two targets:
#   make uboot      (default artifact)      debug variant, ENV_IS_NOWHERE
#   make uboot-mos  (--target artifact-mos) mos A/B variant: persistent redundant
#     env + boot.scr contract (docs/design/uboot-ab-handshake.md); pairs with the
#     mos image only — its env offsets fall inside the alpine image boot partition.

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
        libssl-dev python3 python3-setuptools python3-pyelftools \
        device-tree-compiler swig python3-dev \
        gcc-aarch64-linux-gnu libgnutls28-dev uuid-dev \
    && rm -rf /var/lib/apt/lists/*

ARG RKBIN_REPO=https://github.com/rockchip-linux/rkbin.git
ARG RKBIN_COMMIT=ecb4fcbe954edf38b3ae037d5de6d9f5bccf81f4
RUN git init -q /rkbin && \
    git -C /rkbin remote add origin "${RKBIN_REPO}" && \
    git -C /rkbin fetch --depth=1 origin "${RKBIN_COMMIT}" && \
    git -C /rkbin checkout -q --detach FETCH_HEAD && \
    test "$(git -C /rkbin rev-parse HEAD)" = "${RKBIN_COMMIT}"

ARG UBOOT_REPO=https://github.com/u-boot/u-boot.git
ARG UBOOT_COMMIT=ece349ade2973e220f524ce59e59711cc919263f
RUN git init -q /uboot && \
    git -C /uboot remote add origin "${UBOOT_REPO}" && \
    git -C /uboot fetch --depth=1 origin "${UBOOT_COMMIT}" && \
    git -C /uboot checkout -q --detach FETCH_HEAD && \
    test "$(git -C /uboot rev-parse HEAD)" = "${UBOOT_COMMIT}"

COPY patches/ /patches/
# set -e catches a failing git apply, but `$(ls ...)` runs in a command
# substitution, so an empty glob (a lost COPY, a renamed directory) escapes it
# and applies zero patches green. The count pins the expected series length
# and must move with patches/ whenever a patch is added or removed.
RUN set -e; \
    count=$(ls /patches/*.patch | wc -l); \
    [ "$count" -eq 6 ] || { echo "ERROR: expected 6 U-Boot patches, found $count" >&2; exit 1; }; \
    cd /uboot && for patch in $(ls /patches/*.patch | sort); do \
        echo ">> applying $(basename "$patch")" && git apply -v "$patch"; \
    done

ARG DDR_BLOB=rk3576_ddr_lp4_2112MHz_lp5_2736MHz_v1.12.bin
ARG BL31_BLOB=rk3576_bl31_v1.24.elf
ARG BOARD=generic-rk3576
RUN cd /uboot && \
    DDR=/rkbin/bin/rk35/${DDR_BLOB} && BL31=/rkbin/bin/rk35/${BL31_BLOB} && \
    [ -f "$DDR" ] && [ -f "$BL31" ] && \
    make "${BOARD}_defconfig" && \
    DTSNAME=$(sed -n 's/^CONFIG_DEFAULT_DEVICE_TREE="\(.*\)"/\1/p' .config) && \
    DTSFILE=$(find dts arch -name "${DTSNAME}.dts" | head -1) && \
    echo ">> patching $DTSFILE (adc-keys: recovery key -> rockusb)" && \
    printf '%s\n' \
      '' \
      '/ {' \
      '	adc-keys {' \
      '		compatible = "adc-keys";' \
      '		io-channels = <&saradc 1>;' \
      '		io-channel-names = "buttons";' \
      '		keyup-threshold-microvolt = <1800000>;' \
      '		poll-interval = <100>;' \
      '		button-recovery {' \
      '			label = "recovery";' \
      '			linux,code = <0x73>;' \
      '			press-threshold-microvolt = <17000>;' \
      '		};' \
      '	};' \
      '};' \
      '' \
      '&saradc {' \
      '	status = "okay";' \
      '	/* Use the always-on 1.8 V rail when no regulator is described. */' \
      '	vdd-microvolts = <1800000>;' \
      '};' >> "$DTSFILE" && \
    scripts/config --enable CMD_ROCKUSB \
                   --enable USB_GADGET \
                   --enable USB_FUNCTION_ROCKUSB \
                   --enable ADC \
                   --enable ADC_ROCKCHIP \
                   --enable BUTTON \
                   --enable BUTTON_ADC \
                   --enable CMD_BUTTON \
                   --enable CMD_ADC \
                   --enable FIT \
                   --set-val BOOTDELAY 1 \
                   --set-val SYS_BOOTM_LEN 0x8000000 \
                   --enable USE_PREBOOT \
                   --set-str PREBOOT "led status-blue off; led status-red on; led work on; if button recovery; then echo RECOVERY KEY - entering rockusb; rockusb 0 mmc 0; fi" \
                   --set-str BOOTCOMMAND "setenv boot_targets; bootflow scan -lb; echo BOOT FAILED - entering rockusb; rockusb 0 mmc 0" && \
    make olddefconfig && \
    grep -E "^CONFIG_PREBOOT=|^CONFIG_BUTTON_ADC=|^CONFIG_CMD_ROCKUSB=" .config && \
    grep -q '^CONFIG_ADC=y' .config && \
    grep -q '^CONFIG_BUTTON_ADC=y' .config && \
    grep -q '^CONFIG_CMD_ROCKUSB=y' .config && \
    grep -q '^CONFIG_USB_FUNCTION_ROCKUSB=y' .config && \
    grep -q '^CONFIG_FIT=y' .config && \
    grep -q '^CONFIG_BOOTDELAY=1$' .config && \
    grep -q '^CONFIG_SYS_BOOTM_LEN=0x8000000$' .config && \
    grep -q '^CONFIG_USE_PREBOOT=y' .config && \
    grep -q '^CONFIG_PREBOOT="led status-blue off; led status-red on; led work on; if button recovery; then echo RECOVERY KEY - entering rockusb; rockusb 0 mmc 0; fi"' .config && \
    grep -q '^CONFIG_BOOTCOMMAND="setenv boot_targets; bootflow scan -lb; echo BOOT FAILED - entering rockusb; rockusb 0 mmc 0"' .config && \
    grep -q '^CONFIG_SPL_GPIO=y' .config && \
    grep -q '^CONFIG_SPL_DM_GPIO=y' .config && \
    grep -q '^CONFIG_SPL_DM_REGULATOR=y' .config && \
    grep -q '^CONFIG_SPL_DM_REGULATOR_FIXED=y' .config && \
    grep -Eq '^CONFIG_ROCKCHIP_BOOT_MODE_REG=0x[1-9a-fA-F][0-9a-fA-F]*$' .config && \
    grep -q '^CONFIG_CMD_USB=y' .config && \
    grep -q '^CONFIG_USB_STORAGE=y' .config && \
    grep -q '^CONFIG_USB_XHCI_HCD=y' .config && \
    grep -q '^CONFIG_GPIO_HOG=y' .config && \
    grep -q '^CONFIG_CMD_LED=y' .config && \
    grep -q '^CONFIG_LED_GPIO=y' .config && \
    make -j"$(nproc)" \
        CROSS_COMPILE=aarch64-linux-gnu- \
        ROCKCHIP_TPL="$DDR" BL31="$BL31" && \
    grep -q 'case BOOT_LOADER:' arch/arm/mach-rockchip/boot_mode.c && \
    grep -A4 'status = usb_add_function' drivers/usb/gadget/f_rockusb.c | \
        grep -q 'free(f_rkusb->write_cache)' && \
    test "$(fdtget spl/u-boot-spl.dtb /sdmmc-regulator regulator-name)" = "vcc_sd" && \
    fdtget spl/u-boot-spl.dtb /soc/mmc@2a310000 vmmc-supply >/dev/null && \
    test "$(fdtget spl/u-boot-spl.dtb /chosen u-boot,spl-boot-order)" = \
         "same-as-spl /soc/mmc@2a310000 /soc/mmc@2a330000 /soc/ufshc@2a2d0000" && \
    # Textual check only: it pins the DT property, not that the mmc0 alias
    # resolves to the eMMC controller. Binding alias to controller needs a
    # semantic check on hardware — recorded no-action.
    test "$(fdtget u-boot.dtb /bootstd bootdev-order)" = "mmc0 mmc1 usb" && \
    test "$(fdtget u-boot.dtb /soc/usb@23400000 dr_mode)" = "host" && \
    test "$(fdtget u-boot.dtb /leds/led-work label)" = "work" && \
    test "$(fdtget u-boot.dtb /leds/led-status-red label)" = "status-red" && \
    test "$(fdtget u-boot.dtb /leds/led-status-red default-state)" = "on" && \
    test "$(fdtget -t x u-boot.dtb /leds/led-status-red gpios | awk '{print $3}')" = "1" && \
    test "$(fdtget u-boot.dtb /leds/led-status-blue label)" = "status-blue" && \
    test "$(fdtget u-boot.dtb /leds/led-status-blue default-state)" = "off" && \
    test "$(fdtget -t x u-boot.dtb /leds/led-status-blue gpios | awk '{print $3}')" = "0" && \
    ls -la u-boot-rockchip.bin spl/u-boot-spl.bin u-boot.itb

# mos A/B variant — reconfigures the already-built tree with the env/boot
# contract of docs/design/uboot-ab-handshake.md §3.2/§10 and rebuilds:
# · redundant env pair pinned at uenv-a 0x1000000 / uenv-b 0x1100000, 64 KiB
#   each, eMMC user area (ENV_SIZE must stay 0x10000: the Rockchip default
#   0x1f000 would overrun into uenv-b)
# · ENV_MMC_USE_DT / ENV_MMC_USE_SW_PARTITION / PARTITION_TYPE_GUID stay off,
#   or env/mmc.c relocates the env to a partition END instead of the offsets
# · boot.scr is the only auto-discoverable entry: bootmeth order pinned to
#   script; the rockusb rescue tail and PREBOOT recovery key are preserved
# · BOOTCOMMAND clears boot_targets first. A non-empty boot_targets overrides
#   the device-tree bootdev-order, and unlike the ENV_IS_NOWHERE variant above
#   this stage's env persists in eMMC, so a value left behind by a saveenv or
#   by hand at the U-Boot prompt would outlive the reboot and silently undo
#   the eMMC-first order. The assertion below pins this stage's own string.
FROM build AS build-mos
ARG DDR_BLOB=rk3576_ddr_lp4_2112MHz_lp5_2736MHz_v1.12.bin
ARG BL31_BLOB=rk3576_bl31_v1.24.elf
RUN cd /uboot && \
    scripts/config --disable ENV_IS_NOWHERE \
                   --enable ENV_IS_IN_MMC \
                   --set-val ENV_OFFSET 0x1000000 \
                   --set-val ENV_SIZE 0x10000 \
                   --enable ENV_REDUNDANT \
                   --set-val ENV_OFFSET_REDUND 0x1100000 \
                   --set-val ENV_MMC_DEVICE_INDEX 0 \
                   --set-val ENV_MMC_EMMC_HW_PARTITION 0 \
                   --enable SAVEENV --enable CMD_SAVEENV \
                   --enable CMD_SETEXPR --enable CMD_SOURCE --enable CMD_IMPORTENV \
                   --enable CMD_FS_GENERIC --enable CMD_FAT --enable CMD_BOOTI --enable CMD_PART \
                   --enable LEGACY_IMAGE_FORMAT --enable HUSH_PARSER \
                   --disable ENV_MMC_USE_DT --disable ENV_MMC_USE_SW_PARTITION \
                   --disable PARTITION_TYPE_GUID \
                   --set-str BOOTCOMMAND "setenv boot_targets; bootmeth order script; bootflow scan -lb; echo BOOT FAILED - entering rockusb; rockusb 0 mmc 0" && \
    make olddefconfig && \
    # The two ENV_MMC_* values place the redundant env on eMMC user area; if
    # olddefconfig ever drops them (v2026.07 spellings per
    # docs/design/uboot-ab-handshake.md §1.2, env/Kconfig:738,748) the env
    # silently lands on the default MMC device — so their absence must be red.
    for line in \
        CONFIG_ENV_IS_IN_MMC=y \
        CONFIG_ENV_OFFSET=0x1000000 \
        CONFIG_ENV_SIZE=0x10000 \
        CONFIG_ENV_REDUNDANT=y \
        CONFIG_ENV_OFFSET_REDUND=0x1100000 \
        CONFIG_ENV_MMC_DEVICE_INDEX=0 \
        CONFIG_ENV_MMC_EMMC_HW_PARTITION=0 \
        CONFIG_CMD_SETEXPR=y \
        CONFIG_CMD_SAVEENV=y \
        CONFIG_HUSH_PARSER=y; do \
        grep -q "^${line}$" .config || { echo "ERROR: ${line} missing from mos .config" >&2; exit 1; }; \
    done && \
    grep -q '^CONFIG_BOOTCOMMAND="setenv boot_targets; bootmeth order script; bootflow scan -lb; echo BOOT FAILED - entering rockusb; rockusb 0 mmc 0"' .config && \
    for sym in CONFIG_ENV_IS_NOWHERE CONFIG_ENV_MMC_USE_DT \
               CONFIG_ENV_MMC_USE_SW_PARTITION CONFIG_PARTITION_TYPE_GUID; do \
        if grep -q "^${sym}=y" .config; then \
            echo "ERROR: ${sym}=y would relocate the env off the pinned offsets" >&2; exit 1; \
        fi; \
    done && \
    make -j"$(nproc)" \
        CROSS_COMPILE=aarch64-linux-gnu- \
        ROCKCHIP_TPL=/rkbin/bin/rk35/${DDR_BLOB} BL31=/rkbin/bin/rk35/${BL31_BLOB} && \
    # Textual check only, as in the build stage above: it does not bind the
    # mmc0 alias to the eMMC controller (needs hardware; recorded no-action).
    # This stage rebuilds u-boot.dtb, so bootdev-order is re-asserted here: the
    # one property mos deliberately diverges from upstream on (eMMC first, SD as
    # fallback) and the one that ships in the mos A/B image. The LED and SD-power
    # assertions of the build stage are not repeated, because this stage edits no
    # DTS and the nodes they cover are unchanged by scripts/config.
    test "$(fdtget u-boot.dtb /bootstd bootdev-order)" = "mmc0 mmc1 usb" && \
    ls -la u-boot-rockchip.bin spl/u-boot-spl.bin u-boot.itb

FROM scratch AS artifact-mos
COPY --from=build-mos /uboot/u-boot-rockchip.bin /
COPY --from=build-mos /uboot/spl/u-boot-spl.bin /
COPY --from=build-mos /uboot/u-boot.itb /

FROM scratch AS artifact
COPY --from=build /uboot/u-boot-rockchip.bin /
COPY --from=build /uboot/spl/u-boot-spl.bin /
COPY --from=build /uboot/u-boot.itb /
