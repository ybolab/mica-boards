# The kernel producer of virt-arm64-proof: the BSP outputs prepare.sh staged, packed as
# mica-kernel-virt-arm64-proof under /usr/lib/mica/board/virt-arm64-proof/. Same shape as the board
# package's Dockerfile; the payload arrives through the `bin` context.
ARG MICA_BUILD_DEB
FROM ${MICA_BUILD_DEB} AS pack
COPY --from=packer pack.sh /usr/local/bin/pack.sh
COPY --from=common copyright /in/copyright
COPY control/ /in/control/
COPY --from=bin . /in/payload/

ARG MICA_DEB_VERSION
ARG MICA_DEB_ARCH
ARG SOURCE_DATE_EPOCH
# Provenance, written into the control file by pack.sh; see build-env/deb/README.md.
ARG MICA_DEB_SOURCE_REPO
ARG MICA_DEB_SOURCE_COMMIT

RUN set -eu; \
    install -d -m 0755 /stage/usr/lib/mica/board; \
    cp -a /in/payload /stage/usr/lib/mica/board/virt-arm64-proof; \
    find /stage/usr/lib/mica/board/virt-arm64-proof -type d -exec chmod 0755 {} +; \
    find /stage/usr/lib/mica/board/virt-arm64-proof -type f -exec chmod 0644 {} +; \
    install -D -m 0644 /in/copyright /stage/usr/share/doc/mica-kernel-virt-arm64-proof/copyright; \
    pack.sh --root /stage --control /in/control/mica-kernel-virt-arm64-proof.control \
        --version "${MICA_DEB_VERSION}" --arch "${MICA_DEB_ARCH}" --out /out

FROM scratch AS out
COPY --from=pack /out/ /
