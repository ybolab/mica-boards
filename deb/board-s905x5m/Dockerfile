# syntax=docker/dockerfile:1@sha256:ecfaec9ed6d810b56388c508f4121597bfbba70d41a6dfeee4d8cad5f295fc32
# check=skip=InvalidDefaultArgInFrom
ARG MOS_BUILD_DEB
FROM ${MOS_BUILD_DEB} AS pack
COPY --from=packer pack.sh /usr/local/bin/pack.sh
COPY --from=boarddeb copyright /in/copyright
COPY --from=boarddeb control/ /in/control/
COPY --from=boarddeb install.sh /in/install.sh
COPY --from=bin . /in/stage/
COPY --from=hwinit . /in/hwinit/
COPY --from=boardinit . /in/board-init/
COPY --from=boardoverlay . /in/board-overlay/
ARG MOS_DEB_VERSION
ARG MOS_DEB_ARCH
ARG SOURCE_DATE_EPOCH
RUN bash /in/install.sh
FROM scratch AS out
COPY --from=pack /out/ /
