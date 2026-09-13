# ONE producer for every board's bundle, mica-kernel-<board>: the BSP outputs
# prepare.sh staged arrive through the `bin` context and are packed under
# /usr/lib/mica/board/<board>/ (MICA_DEB_INSTANCE names the board). Same
# shape as the board package's Dockerfile.
ARG MICA_BUILD_DEB
FROM ${MICA_BUILD_DEB} AS pack
COPY --from=packer pack.sh /usr/local/bin/pack.sh
COPY --from=common copyright /in/copyright
COPY --from=board kernel/control/ /in/control/
COPY --from=bin . /in/payload/

ARG MICA_DEB_VERSION
ARG MICA_DEB_ARCH
ARG SOURCE_DATE_EPOCH
# Provenance, written into the control file by pack.sh; see build-env/deb/README.md.
ARG MICA_DEB_SOURCE_REPO
ARG MICA_DEB_SOURCE_COMMIT
ARG MICA_DEB_INSTANCE

RUN set -eu; \
    board="${MICA_DEB_INSTANCE:?the instance names the board}"; \
    install -d -m 0755 /stage/usr/lib/mica/board; \
    cp -a /in/payload "/stage/usr/lib/mica/board/${board}"; \
    find "/stage/usr/lib/mica/board/${board}" -type d -exec chmod 0755 {} +; \
    find "/stage/usr/lib/mica/board/${board}" -type f -exec chmod 0644 {} +; \
    install -D -m 0644 /in/copyright "/stage/usr/share/doc/mica-kernel-${board}/copyright"; \
    pack.sh --root /stage --control "/in/control/mica-kernel-${board}.control" \
        --version "${MICA_DEB_VERSION}" --arch "${MICA_DEB_ARCH}" --out /out

FROM scratch AS out
COPY --from=pack /out/ /
