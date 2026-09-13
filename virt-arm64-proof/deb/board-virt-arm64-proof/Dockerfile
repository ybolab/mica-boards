# syntax=docker/dockerfile:1@sha256:ecfaec9ed6d810b56388c508f4121597bfbba70d41a6dfeee4d8cad5f295fc32
# check=skip=InvalidDefaultArgInFrom
# Board storage policy is independent of kernel and boot firmware artifacts.
ARG MICA_BUILD_DEB
FROM ${MICA_BUILD_DEB} AS pack
COPY --from=packer pack.sh /usr/local/bin/pack.sh
COPY --from=board deb/board-virt-arm64-proof/copyright deb/board-virt-arm64-proof/render.sh /in/
COPY --from=board deb/board-virt-arm64-proof/control/ /in/control/
COPY --from=board board.env /src/board.env
COPY --from=board overlay/etc/systemd/system/boot.mount.in /src/overlay/etc/systemd/system/boot.mount.in
COPY --from=common fstab.in /src/common/fstab.in
ARG MICA_DEB_VERSION
ARG MICA_DEB_ARCH
ARG SOURCE_DATE_EPOCH
# Provenance, written into the control file by pack.sh; see build-env/deb/README.md.
ARG MICA_DEB_SOURCE_REPO
ARG MICA_DEB_SOURCE_COMMIT
RUN set -eu; \
    bash /in/render.sh /src /render; \
    install -D -m 0644 /render/fstab /stage/etc/fstab; \
    install -D -m 0644 /render/boot.mount /stage/etc/systemd/system/boot.mount; \
    install -d -m 0755 /stage/etc/repart.d /stage/boot /stage/etc/systemd/system/local-fs.target.wants; \
    cp /render/repart.d/*.conf /stage/etc/repart.d/; \
    cp -a /render/systemd-repart.service.d /stage/etc/systemd/system/; \
    ln -s /etc/systemd/system/boot.mount /stage/etc/systemd/system/local-fs.target.wants/boot.mount; \
    install -D -m 0644 /in/copyright /stage/usr/share/doc/mica-board-virt-arm64-proof/copyright; \
    pack.sh --root /stage --control /in/control/mica-board-virt-arm64-proof.control \
        --version "${MICA_DEB_VERSION}" --arch "${MICA_DEB_ARCH}" --out /out
FROM scratch AS out
COPY --from=pack /out/ /
