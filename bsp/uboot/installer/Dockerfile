# syntax=docker/dockerfile:1@sha256:ecfaec9ed6d810b56388c508f4121597bfbba70d41a6dfeee4d8cad5f295fc32
# Produce a regular-file-only reusable eMMC installer card for s905x5m.

ARG MOS_IMAGE_DEBIAN_TRIXIE
FROM --platform=linux/386 ${MOS_IMAGE_DEBIAN_TRIXIE} AS assemble

ARG DEBIAN_FRONTEND=noninteractive
ARG PACKER_URL=https://raw.githubusercontent.com/khadas/utils/09fd7ae034f340462cab1daf332a012924a1efa9/aml_image_v2_packer
ARG PACKER_SHA256=7511fb8d1a483d606d67bcb87ae20ab0821fbaff797ad6da958903e46fb4ed9a

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl dosfstools mtools parted \
    && rm -rf /var/lib/apt/lists/*

RUN set -eu; \
    curl -fsSL "${PACKER_URL}" -o /usr/local/bin/aml_image_v2_packer; \
    echo "${PACKER_SHA256}  /usr/local/bin/aml_image_v2_packer" | sha256sum -c -; \
    chmod +x /usr/local/bin/aml_image_v2_packer

COPY installer/ /installer/
COPY config/bm201_emmc_installer.h /input/bm201_emmc_installer.h
COPY package/config/emmc.cfg /input/emmc.cfg
COPY --from=uboot-artifacts u-boot.bin.sd.bin.signed /input/u-boot.bin.sd.bin.signed
COPY --from=emmc-package update.img /input/update.img

RUN /installer/test-config.sh \
        /input/bm201_emmc_installer.h \
        /installer/config/bm201upd.ini \
        /installer/complete-package-files.txt \
        /input/emmc.cfg \
    && /installer/build-image.sh \
        /input/bm201_emmc_installer.h \
        /installer/config/bm201upd.ini \
        /installer/complete-package-files.txt \
        /input/update.img \
        /input/u-boot.bin.sd.bin.signed \
        /output

FROM scratch AS artifact
COPY --from=assemble /output/disk.img /
