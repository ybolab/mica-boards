# syntax=docker/dockerfile:1@sha256:ecfaec9ed6d810b56388c508f4121597bfbba70d41a6dfeee4d8cad5f295fc32
# The amlogic family's kernel: the Hardkernel vendor tree at the family's
# pin, the board's configuration and fragments, device tree and patches, and
# the board's hooks -- prepare.sh, configure.sh, assert.sh, modules.sh (the
# board's out-of-tree modules, built against the compiled tree before depmod)
# and verify.sh. Every hook is optional. The BUILD CONTEXT is the board's
# bsp/ directory; the family arrives through the named context `families`,
# the shared floor through `mos-common`, the verity anchor through
# `mos-trust`, all wired by families/amlogic/Makefile.inc.

# The builder image is injected from build-env/images.env by Makefile.inc.
# There is no default: an omitted pin must fail before the build can
# silently choose a mutable tag.
ARG MICA_IMAGE_UBUNTU_2404
FROM --platform=$BUILDPLATFORM ${MICA_IMAGE_UBUNTU_2404} AS build

ARG DEBIAN_FRONTEND=noninteractive
COPY --from=families common/scripts/ /bsp/scripts/

# Fetch the source before anything else. It is by far the slowest step -- the
# submodules come from git.odroid.com, which has stalled for minutes at a time
# -- and it depends only on KERNEL_REPO/KERNEL_COMMIT. Keeping it ahead of the
# package list and the config means editing either of those reuses the cached
# source instead of cloning several GB again. HTTP/1.1, because git over
# HTTP/2 stalls against this host (fetch-source.sh --http1).
RUN bash /bsp/scripts/apt-install.sh git ca-certificates
ARG KERNEL_REPO
ARG KERNEL_COMMIT
RUN bash /bsp/scripts/fetch-source.sh --http1 --submodules /ksrc "${KERNEL_REPO}" "${KERNEL_COMMIT}"

# On an arm64 builder the kernel is a native build, and Ubuntu ships no
# gcc-aarch64-linux-gnu cross package there; build-essential provides gcc.
ARG BUILDARCH
ARG CROSS_COMPILE_amd64=aarch64-linux-gnu-
ARG CROSS_COMPILE_arm64=
RUN bash /bsp/scripts/apt-install.sh \
        bc bison build-essential device-tree-compiler flex kmod libelf-dev \
        libssl-dev patch perl python3 rsync \
    && if [ "${BUILDARCH}" = "amd64" ]; then \
           bash /bsp/scripts/apt-install.sh gcc-aarch64-linux-gnu; \
       fi

COPY kernel/patches/ /patches/
RUN bash /bsp/scripts/apply-patches.sh /ksrc /patches patch

# The board's own inputs and the family's tools, then the prepare hook.
COPY . /bsp/board/
COPY --from=families common/kernel/ /bsp/common/kernel/
COPY --from=families amlogic/kernel/ /bsp/family/kernel/
COPY kernel/dts/ /ksrc/common_drivers/arch/arm64/boot/dts/amlogic/
RUN [ ! -f /bsp/board/kernel/hooks/prepare.sh ] || \
        bash /bsp/board/kernel/hooks/prepare.sh /ksrc /bsp/board /bsp/common/kernel

ARG KERNEL_CONFIG
ARG KERNEL_FRAGMENTS
COPY kernel/config/${KERNEL_CONFIG} /ksrc/.config
COPY kernel/config/ /bsp/board/kernel/config/
COPY --from=mos-common mos-required.fragment /mos-required.fragment
COPY --from=mos-trust signer.cert.pem /ksrc/certs/mos-verity-anchor.pem
RUN eval "export CROSS_COMPILE=\$CROSS_COMPILE_${BUILDARCH}"; \
    bash /bsp/family/kernel/configure.sh /ksrc /mos-required.fragment /bsp/board/kernel/config "${KERNEL_FRAGMENTS}" /bsp/board/kernel/hooks

ENV KBUILD_BUILD_TIMESTAMP="@1577836800" KBUILD_BUILD_USER=mos KBUILD_BUILD_HOST=mica-build SOURCE_DATE_EPOCH=1577836800

ARG KERNEL_EXPECT
ARG KERNEL_DTB
ARG KERNEL_DTB_ARTIFACT
RUN eval "export CROSS_COMPILE=\$CROSS_COMPILE_${BUILDARCH}"; \
    bash /bsp/family/kernel/build.sh /ksrc "${KERNEL_EXPECT}" "${KERNEL_DTB}" "/${KERNEL_DTB_ARTIFACT}" /bsp/board /bsp/board/kernel/hooks

COPY --from=mos-common export-regdb-certs.py /export-regdb-certs.py
RUN python3 /export-regdb-certs.py /ksrc /regdb-certs.pem

FROM scratch AS artifact
ARG KERNEL_DTB_ARTIFACT
COPY --from=build /ksrc/arch/arm64/boot/Image /
COPY --from=build /modules.tar /
COPY --from=build /${KERNEL_DTB_ARTIFACT} /
COPY --from=build /ksrc/.config /config
COPY --from=build /ksrc/include/config/kernel.release /kernel.release
COPY --from=build /ksrc/System.map /System.map
COPY --from=build /regdb-certs.pem /
