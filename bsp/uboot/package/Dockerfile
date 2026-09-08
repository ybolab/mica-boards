# syntax=docker/dockerfile:1@sha256:ecfaec9ed6d810b56388c508f4121597bfbba70d41a6dfeee4d8cad5f295fc32
# Package the section-3 s905x5m U-Boot artifacts as an Amlogic v2 container.

ARG MOS_IMAGE_DEBIAN_TRIXIE
FROM --platform=linux/386 ${MOS_IMAGE_DEBIAN_TRIXIE} AS packer

ARG PACKER_URL=https://raw.githubusercontent.com/khadas/utils/09fd7ae034f340462cab1daf332a012924a1efa9/aml_image_v2_packer
ARG PACKER_SHA256=7511fb8d1a483d606d67bcb87ae20ab0821fbaff797ad6da958903e46fb4ed9a

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

RUN set -eu; \
    curl -fsSL "${PACKER_URL}" -o /usr/local/bin/aml_image_v2_packer; \
    echo "${PACKER_SHA256}  /usr/local/bin/aml_image_v2_packer" | sha256sum -c -; \
    chmod +x /usr/local/bin/aml_image_v2_packer

FROM packer AS package-base

COPY . /package
RUN /package/test-manifest.sh /package bootloader \
    && /package/test-manifest.sh /package emmc

WORKDIR /work
COPY config/aml_sdc_burn.ini /work/aml_sdc_burn.ini
COPY config/platform.conf /work/platform.conf
COPY blobs/usb_flow.aml /work/usb_flow.aml
COPY blobs/_aml_dtb.PARTITION /work/_aml_dtb.PARTITION
COPY blobs/SHA256SUMS /work/SHA256SUMS
COPY --from=uboot-artifacts DDR.USB /work/DDR.USB
COPY --from=uboot-artifacts u-boot.bin.signed /work/bootloader.PARTITION
COPY --from=uboot-artifacts u-boot.bin.sd.bin.signed /work/aml_sdc_burn.UBOOT

FROM package-base AS emmc-package

COPY config/emmc.cfg /work/image.cfg
COPY --from=emmc-payloads gpt.bin /work/gpt.bin
COPY --from=emmc-payloads uenv-a.PARTITION uenv-b.PARTITION /work/
COPY --from=emmc-payloads boot-a.PARTITION boot-b.PARTITION /work/
COPY --from=emmc-payloads rootfs-a.PARTITION rootfs-b.PARTITION /work/
COPY --from=emmc-payloads meta.PARTITION state.PARTITION /work/
COPY --from=emmc-payloads ephemeral.PARTITION data.PARTITION /work/
RUN /package/pack-and-verify.sh emmc /work /output

FROM scratch AS emmc-artifact
COPY --from=emmc-package /output/update.img /

FROM package-base AS bootloader-package

COPY config/bootloader.cfg /work/image.cfg
RUN /package/pack-and-verify.sh bootloader /work /output

# Keep the historical Dockerfile default as the bootloader-only RFCT-928
# artifact. Complete-package callers select emmc-artifact explicitly.
FROM scratch AS bootloader-artifact
COPY --from=bootloader-package /output/update.img /
COPY --from=bootloader-package /work/aml_sdc_burn.ini /

# Backward-compatible target name used by RFCT-928 callers.
FROM bootloader-artifact AS artifact
