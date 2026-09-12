# syntax=docker/dockerfile:1@sha256:ecfaec9ed6d810b56388c508f4121597bfbba70d41a6dfeee4d8cad5f295fc32
# check=skip=InvalidDefaultArgInFrom
# Board storage policy is independent of kernel and boot firmware artifacts.
ARG MOS_BUILD_DEB
FROM ${MOS_BUILD_DEB} AS pack
COPY --from=packer pack.sh /usr/local/bin/pack.sh
COPY --from=board deb/board-x64/copyright deb/board-x64/render.sh /in/
COPY --from=board deb/board-x64/control/ /in/control/
COPY --from=board board.env /src/boards/x64/board.env
COPY --from=board overlay/etc/systemd/system/boot.mount.in /src/boards/x64/overlay/etc/systemd/system/boot.mount.in
COPY --from=overlay etc/fstab.in /src/rootfs/overlay/etc/fstab.in
ARG MOS_DEB_VERSION
ARG MOS_DEB_ARCH
ARG SOURCE_DATE_EPOCH
# Provenance, written into the control file by pack.sh; see build-env/deb/README.md.
ARG MOS_DEB_SOURCE_REPO
ARG MOS_DEB_SOURCE_COMMIT
RUN set -eu; \
    bash /in/render.sh /src /render; \
    install -D -m 0644 /render/fstab /stage/etc/fstab; \
    install -D -m 0644 /render/boot.mount /stage/etc/systemd/system/boot.mount; \
    install -d -m 0755 /stage/etc/repart.d /stage/boot /stage/etc/systemd/system/local-fs.target.wants; \
    cp /render/repart.d/*.conf /stage/etc/repart.d/; \
    cp -a /render/systemd-repart.service.d /stage/etc/systemd/system/; \
    ln -s /etc/systemd/system/boot.mount /stage/etc/systemd/system/local-fs.target.wants/boot.mount; \
    install -D -m 0644 /in/copyright /stage/usr/share/doc/mos-board-x64/copyright; \
    pack.sh --root /stage --control /in/control/mos-board-x64.control \
        --version "${MOS_DEB_VERSION}" --arch "${MOS_DEB_ARCH}" --out /out
FROM scratch AS out
COPY --from=pack /out/ /
