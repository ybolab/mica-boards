#!/usr/bin/env bash
set -euo pipefail
. /in/stage/board.env
board=/stage/mos-board-s905x5m
radio=/stage/mos-s905x5m-radio
bt=/stage/mos-s905x5m-bluetooth
install -d "$board/etc/repart.d" "$board/etc/mos" "$board/usr/lib/modules" \
    "$board/usr/lib/mos/board/s905x5m"
for f in fstab fw_env.config rauc/system.conf; do install -D -m 0644 "/in/stage/etc/$f" "$board/etc/$f"; done
for f in /in/board-overlay/etc/repart.d/*.conf; do install -m 0644 "$f" "$board/etc/repart.d/"; done
for f in $BOARD_FIRMWARE_FILES; do install -D -m 0644 "/in/stage/firmware/${f##*/}" "$board$f"; done
mkdir -p /tmp/mods
tar -xf /in/stage/modules.tar -C /tmp/mods
cp -a /tmp/mods/lib/modules/. "$board/usr/lib/modules/"
release=$(cat /in/stage/kernel.release)
[[ "$release" =~ ^[A-Za-z0-9._+-]+$ ]] || { echo 'error: invalid kernel.release' >&2; exit 1; }
[ -d "$board/usr/lib/modules/$release" ] || { echo 'error: kernel.release and modules disagree' >&2; exit 1; }
install -D -m 0644 /in/stage/config "$board/boot/config-$release"
for option in DM_INIT BLK_DEV_DM DM_VERITY SQUASHFS SQUASHFS_ZSTD OVERLAY_FS; do
    grep -qx "CONFIG_${option}=y" /in/stage/config || { echo "error: kernel lacks CONFIG_${option}=y" >&2; exit 1; }
done
for f in /in/stage/boot/*; do install -m 0644 "$f" "$board/usr/lib/mos/board/s905x5m/"; done

hwinit() {
    local root=$1 name=$2
    install -D -m 0644 "/in/board-init/$name.conf" "$root/etc/mos/$name.conf"
    install -D -m 0755 "/in/hwinit/hwinit-$name" "$root/usr/lib/mos/hwinit-$name"
    install -D -m 0644 "/in/hwinit/mos-$name.service" "$root/usr/lib/systemd/system/mos-$name.service"
    install -d "$root/etc/systemd/system/multi-user.target.wants"
    ln -s "/usr/lib/systemd/system/mos-$name.service" "$root/etc/systemd/system/multi-user.target.wants/"
}
hwinit "$board" audio
hwinit "$radio" wireless
hwinit "$bt" bluetooth
for f in $BOARD_USERLAND_FILES; do
    mode=0644
    case "$f" in /usr/sbin/* | *.so) mode=0755 ;; esac
    install -D -m "$mode" "/in/stage/userland$f" "$bt$f"
done
# Use BlueZ's explicit config path; Debian retains ownership of main.conf.
install -d "$bt/etc/systemd/system/bluetooth.service.d"
install -d "$bt/usr/lib/mos"
printf '[General]\nClass = %s\n' "$BOARD_BLUEZ_CLASS" >"$bt/usr/lib/mos/s905x5m-bluez.conf"
printf '[Service]\nExecStart=\nExecStart=/usr/libexec/bluetooth/bluetoothd --configfile=/usr/lib/mos/s905x5m-bluez.conf\n' \
    >"$bt/etc/systemd/system/bluetooth.service.d/20-s905x5m.conf"
for pkg in mos-board-s905x5m mos-s905x5m-radio mos-s905x5m-bluetooth; do
    install -D -m 0644 /in/copyright "/stage/$pkg/usr/share/doc/$pkg/copyright"
    pack.sh --root "/stage/$pkg" --control "/in/control/$pkg.control" \
        --version "$MOS_DEB_VERSION" --arch "$MOS_DEB_ARCH" --out /out
done
