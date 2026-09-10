#!/usr/bin/env bash
# mos-build-side: container -- package independent board and radio selections.
set -euo pipefail
bash /in/render.sh /src /render
board=/stage/mos-board-s905x5m
install -D -m 0644 /render/fstab "$board/etc/fstab"
install -d "$board/etc/repart.d" "$board/etc/systemd/system"
cp /render/repart.d/*.conf "$board/etc/repart.d/"
cp -a /render/systemd-repart.service.d "$board/etc/systemd/system/"
for entry in 'mos-board-s905x5m audio' 'mos-s905x5m-wireless wireless'; do
    read -r package name <<< "$entry"
    root=/stage/$package
    install -D -m 0644 "/in/init/$name.conf" "$root/etc/mos/$name.conf"
    install -D -m 0755 "/in/hwinit/hwinit-$name" "$root/usr/lib/mos/hwinit-$name"
    install -D -m 0644 "/in/hwinit/mos-$name.service" "$root/usr/lib/systemd/system/mos-$name.service"
    install -d "$root/etc/systemd/system/multi-user.target.wants"
    ln -s "/usr/lib/systemd/system/mos-$name.service" "$root/etc/systemd/system/multi-user.target.wants/"
done
install -D -m 0644 /in/init/wifi.conf /stage/mos-s905x5m-wifi/etc/mos/wifi.conf
panel=/stage/mos-bm201-front-panel
mkdir -p "$panel"
cp -a /in/front-panel/. "$panel/"
chmod 0755 "$panel/usr/sbin/bm201-front-panel" "$panel/usr/lib/mos/bm201-front-panel-stop"
install -d "$panel/etc/systemd/system/multi-user.target.wants"
ln -s /usr/lib/systemd/system/bm201-front-panel.service "$panel/etc/systemd/system/multi-user.target.wants/"
for root in /stage/*; do
    package=${root##*/}
    install -D -m 0644 /in/copyright "$root/usr/share/doc/$package/copyright"
    pack.sh --root "$root" --control "/in/control/$package.control" \
        --version "$MOS_DEB_VERSION" --arch "$MOS_DEB_ARCH" --out /out
done
