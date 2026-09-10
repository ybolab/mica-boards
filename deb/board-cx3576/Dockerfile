# syntax=docker/dockerfile:1@sha256:ecfaec9ed6d810b56388c508f4121597bfbba70d41a6dfeee4d8cad5f295fc32
# check=skip=InvalidDefaultArgInFrom
# Board hardware and storage policy are independent of kernel/firmware artifacts.
ARG MOS_BUILD_DEB
FROM ${MOS_BUILD_DEB} AS pack
COPY --from=packer pack.sh /usr/local/bin/pack.sh
COPY --from=boarddeb copyright render.sh /in/
COPY --from=boarddeb control/ /in/control/
COPY --from=board board.env /src/boards/cx3576/board.env
COPY --from=overlay etc/fstab.in /src/rootfs/overlay/etc/fstab.in
COPY --from=hwinit . /in/hwinit/
COPY --from=boardinit . /in/board-init/
COPY --from=boardoverlay . /in/board-overlay/
ARG MOS_DEB_VERSION
ARG MOS_DEB_ARCH
ARG SOURCE_DATE_EPOCH
RUN set -eu; \
    bash /in/render.sh /src /render; \
    . /src/boards/cx3576/board.env; \
    PKG="mos-board-${LAYOUT_BOARD}"; ROOT="/stage/${PKG}"; \
    install -d -m 0755 "${ROOT}/etc/repart.d" "${ROOT}/etc/mos" \
        "${ROOT}/etc/systemd/system/multi-user.target.wants" \
        "${ROOT}/usr/lib/mos" "${ROOT}/usr/lib/systemd/system" \
        "${ROOT}/usr/lib/udev/rules.d" "${ROOT}/usr/lib/systemd/network"; \
    install -m 0644 /render/fstab "${ROOT}/etc/fstab"; \
    cp /render/repart.d/*.conf "${ROOT}/etc/repart.d/"; \
    cp -a /render/systemd-repart.service.d "${ROOT}/etc/systemd/system/"; \
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
    install -D -m 0644 /in/board-overlay/etc/systemd/logind.conf.d/50-mos-console.conf "${ROOT}/etc/systemd/logind.conf.d/50-mos-console.conf"; \
    \
    # PRESETS, taken as a set for the same reason as the drop-ins above. This \
    # board ships 50-mos-getty.preset, which resolves getty@tty1 to disabled so \
    # HDMI shows PLAN-088's boot logo instead of a login prompt; mos-system \
    # ships the ssh and nftables ones the same way, in /usr/lib rather than \
    # /etc so an operator's /etc still outranks board policy. \
    # \
    # THE COUNT IS ASSERTED because the failure is silent in the worst \
    # direction: a glob that matched nothing would pack no preset, the unit \
    # would resolve to ENABLED through 90-systemd.preset, and the device would \
    # boot to a login prompt on the customer's screen with this build green. \
    presets=0; \
    install -d -m 0755 "${ROOT}/usr/lib/systemd/system-preset"; \
    for p in /in/board-overlay/usr/lib/systemd/system-preset/*.preset; do \
        [ -f "${p}" ] || continue; \
        install -m 0644 "${p}" "${ROOT}/usr/lib/systemd/system-preset/$(basename "${p}")"; \
        presets=$((presets + 1)); \
    done; \
    [ "${presets}" -gt 0 ] || { echo "error: boards/${LAYOUT_BOARD}/overlay/usr/lib/systemd/system-preset holds no *.preset, so this package would ship none. getty@tty1 would then resolve to enabled through 90-systemd.preset and the board would boot to a login prompt on HDMI" >&2; exit 1; }; \
    echo "presets: staged ${presets} board preset(s)"; \
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
        # ...and the systemd .link files beside them, same glob shape and same \
        # reason: a fact's udev-side payload ships with the fact rather than \
        # being named here. 60-mos-mac-stable.link is what stops systemd's own \
        # 99-default.link MACAddressPolicy=persistent from painting a \
        # machine-id-derived address over a port hwinit-mac is about to \
        # assign; without it that program is a no-op on this board, so the \
        # file is part of the mechanism and not decoration. \
        for l in /in/hwinit/*-mos-"${n}"-*.link; do \
            [ -e "${l}" ] || continue; \
            install -m 0644 "${l}" "${ROOT}/usr/lib/systemd/network/$(basename "${l}")"; \
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
    install -D -m 0644 /in/copyright "${ROOT}/usr/share/doc/${PKG}/copyright"; \
    pack.sh --root "${ROOT}" --control "/in/control/${PKG}.control" \
        --version "${MOS_DEB_VERSION}" --arch "${MOS_DEB_ARCH}" --out /out
FROM scratch AS out
COPY --from=pack /out/ /
