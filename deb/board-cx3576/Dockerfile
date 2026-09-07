# syntax=docker/dockerfile:1@sha256:ecfaec9ed6d810b56388c508f4121597bfbba70d41a6dfeee4d8cad5f295fc32
# check=skip=InvalidDefaultArgInFrom
# The cx3576 board producer: the `mos-board-cx3576` package.
#
#   bash build-env/deb/build.sh --producer board-cx3576 --arch arm64
#
# The BOARD_DIR-selected BSP inputs and the rendered configuration arrive as the
# `bin` context, staged on the host by this producer's PREPARE hook, render.sh.
#
# This file only STAGES and PACKS. Nothing is compiled here: the kernel modules
# and the boot inputs are the BSP's output, the firmware is a committed vendor
# drop, and the hwinit programs, units and board overlay are committed content
# copied byte for byte out of the trees the image build reads today.
#
# WHAT IS DERIVED, AND FROM WHAT. Every set below is read out of board.env at
# build time -- BOARD_HWINIT_CONFS decides the hwinit set, BOARD_FIRMWARE_FILES
# the firmware set, BOARD_HAS_STATUS_LED whether the indicator ships. A list
# written out here would be a second answer to a question the board file
# already answers, and the two would diverge silently: the board would gain a
# fact and the package would keep shipping yesterday's set with every gate
# green.
#
# No default for the base, for the reason build-env/deb/Dockerfile gives: a
# driver that failed to pass the argument would otherwise build from a floating
# tag.
ARG MOS_BUILD_DEB

FROM ${MOS_BUILD_DEB} AS pack

# pack.sh comes over as a named context rather than out of the image. It is the
# packaging CONTRACT, shared by every producer, and build-env/deb/README.md
# requires this shape: an edit to the packer then takes effect without
# rebuilding the whole builder family.
COPY --from=packer pack.sh /usr/local/bin/pack.sh

# This board's own copyright and control template, from beside this Dockerfile.
COPY --from=boarddeb copyright /in/copyright
COPY --from=boarddeb control/ /in/control/
# The BOARD_DIR-selected inputs and the rendered configuration, from PREPARE.
COPY --from=bin . /in/stage/
# Committed trees, at the paths the image build reads them from today.
COPY --from=hwinit . /in/hwinit/
COPY --from=boardinit . /in/board-init/
COPY --from=boardoverlay . /in/board-overlay/

ARG MOS_DEB_VERSION
ARG MOS_DEB_ARCH
ARG SOURCE_DATE_EPOCH

RUN set -eu; \
    . /in/stage/board.env; \
    PKG="mos-board-${LAYOUT_BOARD}"; \
    ROOT="/stage/${PKG}"; \
    install -d -m 0755 "${ROOT}/etc/rauc" "${ROOT}/etc/repart.d" "${ROOT}/etc/mos" \
        "${ROOT}/etc/systemd/system/multi-user.target.wants" \
        "${ROOT}/usr/lib/mos" "${ROOT}/usr/lib/systemd/system" \
        "${ROOT}/usr/lib/udev/rules.d" "${ROOT}/usr/lib/modules" \
        "${ROOT}/usr/lib/firmware" "${ROOT}/usr/lib/mos/board/${LAYOUT_BOARD}"; \
    \
    # The rendered configuration. /etc is ordinary payload and carries no \
    # conffiles entry: this root is an immutable dm-verity squashfs, so a \
    # conffiles entry would promise dpkg a three-way merge that can never \
    # happen on the device. \
    install -m 0644 /in/stage/etc/fstab "${ROOT}/etc/fstab"; \
    install -m 0644 /in/stage/etc/fw_env.config "${ROOT}/etc/fw_env.config"; \
    install -m 0644 /in/stage/etc/rauc/system.conf "${ROOT}/etc/rauc/system.conf"; \
    \
    # The board's repart definitions, byte for byte. rootfs/build.sh \
    # derives the required definition COUNT from the layout's linux-generic \
    # partitions, so a definition dropped here does not fail the package -- it \
    # fails the image build that composes it, which is where that invariant \
    # lives. Taken as a directory rather than named one by one for the same \
    # reason every other set here is derived. \
    for c in /in/board-overlay/etc/repart.d/*.conf; do \
        install -m 0644 "${c}" "${ROOT}/etc/repart.d/$(basename "${c}")"; \
    done; \
    \
    # Systemd drop-ins from the board overlay, wholesale. A board that must \
    # amend a GENERIC unit for its own hardware -- ttyFIQ0's carrier-less \
    # serial console needs agetty told --local-line -- records the amendment \
    # as overlay content, and the package ships every such directory rather \
    # than naming them: same derivation rule as the repart set above, and the \
    # glob takes only drop-in directories, never the units themselves. \
    for d in /in/board-overlay/etc/systemd/system/*.d; do \
        [ -d "${d}" ] || continue; \
        install -d -m 0755 "${ROOT}/etc/systemd/system/$(basename "${d}")"; \
        for f in "${d}"/*; do \
            install -m 0644 "${f}" "${ROOT}/etc/systemd/system/$(basename "${d}")/$(basename "${f}")"; \
        done; \
    done; \
    \
    # Hardware init, and THE SPLIT. Every fact in BOARD_HWINIT_CONFS ships as \
    # /etc/mos/<n>.conf, bt.conf included: the UART, the protocol and the \
    # firmware node of the Bluetooth part are facts about this BOARD. The \
    # program and unit that consume it, hwinit-bt and mos-bt.service, are \
    # generic and belong to mos-bluetooth, so a board with a different radio \
    # ships a different conf and the same application package. That is why the \
    # skip below is on the program/unit half only, and why removing it would \
    # leave a Bluetooth service inside a board package -- and make two \
    # packages own one path. \
    # \
    # The installation otherwise mirrors rootfs/scripts/hwinit-install.sh, \
    # including its udev-rule glob and its refusal of a fact with no program. \
    for n in ${BOARD_HWINIT_CONFS}; do \
        conf="/in/board-init/${n}.conf"; \
        [ -f "${conf}" ] || { echo "error: ${LAYOUT_BOARD} declares '${n}' in BOARD_HWINIT_CONFS and boards/${LAYOUT_BOARD}/bsp/init/${n}.conf does not exist; the unit that reads it would find no fact on the device" >&2; exit 1; }; \
        install -m 0644 "${conf}" "${ROOT}/etc/mos/${n}.conf"; \
        [ "${n}" != bt ] || continue; \
        script="/in/hwinit/hwinit-${n}"; unit="/in/hwinit/mos-${n}.service"; \
        [ -f "${script}" ] || { echo "error: /etc/mos/${n}.conf is a board fact that no hwinit script reads (there is no boards/${LAYOUT_BOARD}/hwinit/hwinit-${n}); a fact nothing consumes is a silent no-op on the device" >&2; exit 1; }; \
        [ -f "${unit}" ] || { echo "error: boards/${LAYOUT_BOARD}/hwinit/hwinit-${n} has no unit to run it (there is no boards/${LAYOUT_BOARD}/hwinit/mos-${n}.service)" >&2; exit 1; }; \
        install -m 0755 "${script}" "${ROOT}/usr/lib/mos/hwinit-${n}"; \
        install -m 0644 "${unit}" "${ROOT}/usr/lib/systemd/system/mos-${n}.service"; \
        # ENABLEMENT IS A FILE THIS PACKAGE OWNS. The image creates exactly \
        # this symlink today; a postinst `systemctl enable` would write it \
        # into a root that is sealed read-only before the device ever boots. \
        ln -s "/usr/lib/systemd/system/mos-${n}.service" \
            "${ROOT}/etc/systemd/system/multi-user.target.wants/mos-${n}.service"; \
        for r in /in/hwinit/*-mos-"${n}"-*.rules; do \
            [ -e "${r}" ] || continue; \
            install -m 0644 "${r}" "${ROOT}/usr/lib/udev/rules.d/$(basename "${r}")"; \
        done; \
    done; \
    \
    # The status indicator, from the board overlay, byte for byte including the \
    # wants symlink cp -a preserves. Gated on the board's own declaration: x64 \
    # has no /sys/class/leds and the unit failed on every boot there, which is \
    # the difference BOARD_HAS_STATUS_LED exists to record. \
    if [ "${BOARD_HAS_STATUS_LED:-0}" = 1 ]; then \
        install -m 0755 /in/board-overlay/usr/lib/mos/mos-status-led "${ROOT}/usr/lib/mos/mos-status-led"; \
        install -m 0644 /in/board-overlay/usr/lib/systemd/system/mos-status-led.service "${ROOT}/usr/lib/systemd/system/mos-status-led.service"; \
        cp -a /in/board-overlay/etc/systemd/system/multi-user.target.wants/mos-status-led.service \
            "${ROOT}/etc/systemd/system/multi-user.target.wants/mos-status-led.service"; \
    fi; \
    \
    # Firmware: exactly BOARD_FIRMWARE_FILES, which holds INSTALLED paths. The \
    # vendor drop under the BSP holds ~32 files for other AIC parts and other \
    # silicon revisions and only the confirmed runtime set may enter a signed \
    # root, so the declared list selects and render.sh copied only those. The \
    # staged-versus-declared count is asserted the way \
    # rootfs/scripts/firmware-install.sh asserts it: a difference means the \
    # image would carry firmware no board fact names. \
    declared=0; \
    for fw in ${BOARD_FIRMWARE_FILES}; do \
        src="/in/stage/firmware/${fw##*/}"; \
        [ -f "${src}" ] || { echo "error: the board declares ${fw} and ${src} was not staged. boards/${LAYOUT_BOARD}/deb/board-${LAYOUT_BOARD}/render.sh stages exactly the declared set out of BOARD_DIR" >&2; exit 1; }; \
        install -D -m 0644 "${src}" "${ROOT}${fw}"; \
        declared=$((declared + 1)); \
    done; \
    staged="$(find /in/stage/firmware -type f | wc -l)"; \
    [ "${staged}" = "${declared}" ] || { echo "error: the board declares ${declared} firmware file(s) in BOARD_FIRMWARE_FILES and ${staged} were staged; the package would carry firmware no board fact names" >&2; exit 1; }; \
    \
    # Kernel modules, unpacked with the same lib/modules/. prefix handling \
    # rootfs/scripts/kernel-and-initramfs.sh uses on this architecture. \
    # They are relocatable ELF and are NOT handed to dpkg-shlibdeps: the \
    # control template asks for no ${shlibs:Depends}, which is what keeps \
    # pack.sh's ELF scan from running at all. A module's dependencies are \
    # other modules and a kernel version, and neither is a shared library. \
    # \
    # THE /ksrc SYMLINKS ARE KEPT, and this is the ruling. modules_install \
    # writes `build` and `source` beside each release's modules pointing at \
    # the kernel source tree it compiled in, which in \
    # boards/cx3576/bsp/kernel/Dockerfile is /ksrc -- a path inside that \
    # builder that no image ships. Both therefore dangle on the device. \
    # \
    # WHAT DECIDED IT: byte-identity. The cp -a below is character for \
    # character what rootfs/scripts/kernel-and-initramfs.sh does today, so \
    # the payload this package composes is the payload the stage chain \
    # installs. PLAN-036's switch-over has to account for every difference \
    # between those two roots; a difference invented HERE is one the dual-build \
    # gate would have to be taught to expect for no gain, and it would move the \
    # deb gate's payload-path count -- a figure that is watched, where an \
    # unexplained move is indistinguishable from a check that stopped looking. \
    # \
    # AGAINST, and it is a real argument: a dangling symlink in a signed \
    # read-only root is a claim about a tree that is not there. It is inert -- \
    # nothing on the device builds out-of-tree modules, and depmod reads the \
    # modules.dep in the tarball rather than these -- and if it should go, it \
    # should go where it is CREATED, in the BSP kernel build, rather than be \
    # post-processed out here by a packaging step that would then stop \
    # shipping what the vendor build produced. \
    mkdir -p /tmp/mods; \
    tar -xf /in/stage/modules.tar -C /tmp/mods; \
    cp -a /tmp/mods/lib/modules/. "${ROOT}/usr/lib/modules/"; \
    rm -rf /tmp/mods; \
    [ -n "$(ls -A "${ROOT}/usr/lib/modules")" ] || { echo "error: /in/stage/modules.tar unpacked to no lib/modules content; the package would ship a kernel with no modules" >&2; exit 1; }; \
    \
    # THE RESOLVED KERNEL CONFIG, shipped at the path the image contract reads. \
    # Until RFCT-343 this board exported none, so boards/common/mos-required.fragment \
    # was enforced at kernel-BUILD time and nowhere else -- and the BSP output is \
    # an input to this package, not something it rebuilds. A stale one therefore \
    # shipped a kernel predating whatever the fragment had gained since, with no \
    # check red anywhere: measured, an Image from 2026-08-31 rode every image built \
    # until 2026-09-07 while the fragment gained dm-crypt, the eBPF/firewall/bridge \
    # floor and NF_CONNTRACK_MARK/NF_NAT_MASQUERADE. verify/src/checks-kernel.ts \
    # reads /boot/config-<release> off the packed root, which is what makes the \
    # floor an assertion about the artefact instead of about the build that is \
    # not being run. \
    # \
    # NOT a conffile, for the reason boards/x64/deb/kernel-x64/Dockerfile gives: \
    # it is a record of how the kernel beside it was built, and this root is an \
    # immutable dm-verity squashfs where dpkg could never perform the three-way \
    # merge a conffiles entry promises. \
    release="$(cat /in/stage/kernel.release)"; \
    [ -n "${release}" ] || { echo "error: the staged kernel.release is empty, so the shipped config would be named after nothing and verify would find no /boot/config-* to read" >&2; exit 1; }; \
    # THE BINDING, and it is the point of staging kernel.release at all. The \
    # config and the module tree are two files copied out of the same BSP output, \
    # and nothing until here proved they came from the same build of it. A tree \
    # whose modules are ${release} beside a config from another kernel is a root \
    # where every symbol the contract reads describes something the device does \
    # not run -- green, and about the wrong kernel. \
    [ -d "${ROOT}/usr/lib/modules/${release}" ] || \
        { echo "error: modules.tar unpacked to no lib/modules/${release}, though the staged kernel.release names it. The config and the modules in /in/stage came from different builds of the BSP kernel, and the package would ship a kernel config describing a kernel whose modules are not beside it" >&2; exit 1; }; \
    install -D -m 0644 /in/stage/config "${ROOT}/boot/config-${release}"; \
    # The floor this board BOOTS through, re-asserted over the bytes being \
    # packed rather than over the build that produced them -- the same shape and \
    # the same reason as x64's. cx3576 assembles /dev/dm-0 from dm-mod.create= \
    # with no initramfs, so a symbol that is not built in is not a degraded \
    # feature, it is a boot that ends at rootwait days after this build was \
    # green. \
    for option in DM_INIT BLK_DEV_DM DM_VERITY SQUASHFS SQUASHFS_ZSTD OVERLAY_FS; do \
        grep -q "^CONFIG_${option}=y$" "${ROOT}/boot/config-${release}" || \
            { echo "error: the shipped /boot/config-${release} does not declare CONFIG_${option}=y. This board boots root=/dev/dm-0 from a dm-mod.create= table with no initramfs; without this symbol built in there is nothing to load it from and the boot ends at rootwait" >&2; exit 1; }; \
    done; \
    echo "kernel: staged /boot/config-${release} ($(grep -c . "${ROOT}/boot/config-${release}") lines) beside $(find "${ROOT}/usr/lib/modules/${release}" -name '*.ko*' | wc -l) module(s)"; \
    \
    # THE BOOT INPUTS, AND WHY THEY ARE IN A ROOTFS PACKAGE. Nothing here is \
    # ever executed on the device: the kernel Image, the device tree and the \
    # U-Boot binary are consumed by the image FINALIZER, which writes them into \
    # the boot slots and the loader region of the disk, and boot.cmd is \
    # compiled into that slot's boot.scr. They ride in the payload because \
    # PLAN-036 section 3 has the finalizer export the SELECTED board's boot \
    # artifacts from the installed package rather than reach back into \
    # boards -- so which blobs an image was assembled from is a property of \
    # the package set that composed it, recorded and versioned like every \
    # other file, instead of a directory the build happened to be run beside. \
    for b in /in/stage/boot/*; do \
        install -m 0644 "${b}" "${ROOT}/usr/lib/mos/board/${LAYOUT_BOARD}/$(basename "${b}")"; \
    done; \
    \
    install -D -m 0644 /in/copyright "${ROOT}/usr/share/doc/${PKG}/copyright"; \
    \
    pack.sh --root "${ROOT}" --control "/in/control/${PKG}.control" \
        --version "${MOS_DEB_VERSION}" --arch "${MOS_DEB_ARCH}" --out /out

# The export stage, the shape pkgs/mosd/deb/mosd/Dockerfile ends in:
# `-o type=local` writes this stage's filesystem into _out/debs/<arch>/pool/
# and nothing here installs into a root.
FROM scratch AS out
COPY --from=pack /out/ /
