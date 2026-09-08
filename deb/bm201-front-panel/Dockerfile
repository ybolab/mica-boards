# syntax=docker/dockerfile:1@sha256:ecfaec9ed6d810b56388c508f4121597bfbba70d41a6dfeee4d8cad5f295fc32
# check=skip=InvalidDefaultArgInFrom
ARG MOS_BUILD_DEB
FROM ${MOS_BUILD_DEB} AS pack
COPY --from=packer pack.sh /usr/local/bin/pack.sh
COPY --from=family copyright /in/copyright
COPY --from=panel . /stage/
COPY control/ /in/control/
ARG MOS_DEB_VERSION
ARG MOS_DEB_ARCH
ARG SOURCE_DATE_EPOCH
RUN set -eu; \
    rm /stage/usr/lib/systemd/system/multi-user.target.d/bm201-front-panel.conf; \
    rmdir /stage/usr/lib/systemd/system/multi-user.target.d; \
    install -d /stage/etc/systemd/system/multi-user.target.wants; \
    ln -s /usr/lib/systemd/system/bm201-front-panel.service /stage/etc/systemd/system/multi-user.target.wants/; \
    install -D -m 0644 /in/copyright /stage/usr/share/doc/mos-bm201-front-panel/copyright; \
    pack.sh --root /stage --control /in/control/mos-bm201-front-panel.control \
        --version "$MOS_DEB_VERSION" --arch "$MOS_DEB_ARCH" --out /out
FROM scratch AS out
COPY --from=pack /out/ /
