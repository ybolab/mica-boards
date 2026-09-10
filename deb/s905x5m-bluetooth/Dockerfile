# syntax=docker/dockerfile:1@sha256:ecfaec9ed6d810b56388c508f4121597bfbba70d41a6dfeee4d8cad5f295fc32
# check=skip=InvalidDefaultArgInFrom
ARG MOS_BUILD_DEB
FROM ${MOS_BUILD_DEB} AS pack
COPY --from=packer pack.sh /usr/local/bin/pack.sh
COPY --from=board bsp/component-copyright /in/copyright
COPY --from=bin . /stage/
COPY --from=board hwinit/hwinit-bluetooth hwinit/mos-bluetooth.service bsp/init/bluetooth.conf /in/
COPY control/mos-s905x5m-bluetooth.control /in/control
ARG MOS_DEB_VERSION
ARG MOS_DEB_ARCH
ARG SOURCE_DATE_EPOCH
RUN set -eu; \
    install -D -m 0755 /in/hwinit-bluetooth /stage/usr/lib/mos/hwinit-bluetooth; \
    install -D -m 0644 /in/bluetooth.conf /stage/etc/mos/bluetooth.conf; \
    install -D -m 0644 /in/mos-bluetooth.service /stage/usr/lib/systemd/system/mos-bluetooth.service; \
    install -d /stage/etc/systemd/system/multi-user.target.wants; \
    ln -s /usr/lib/systemd/system/mos-bluetooth.service /stage/etc/systemd/system/multi-user.target.wants/; \
    install -D -m 0644 /in/copyright /stage/usr/share/doc/mos-s905x5m-bluetooth/copyright; \
    pack.sh --root /stage --control /in/control --version "$MOS_DEB_VERSION" --arch "$MOS_DEB_ARCH" --out /out
FROM scratch AS out
COPY --from=pack /out/ /
