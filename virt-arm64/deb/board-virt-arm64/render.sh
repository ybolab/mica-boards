#!/usr/bin/env bash
# Render only the three-partition virt-arm64 runtime storage policy.
set -euo pipefail
src=${1:?source root required}
out=${2:?output directory required}
. "$src/board.env"
[ "$LAYOUT_VERSION" = 3 ] && [ "$LAYOUT_PARTITIONS" = 'ESP SYSTEM DATA' ]
mkdir -p "$out/repart.d"
data_guid=${DATA_GUID,,}
esp_guid=${ESP_GUID,,}
printf -v data_line 'PARTUUID=%s /mnt/data ext4 noatime,prjquota,x-systemd.growfs 0 2' "$data_guid"
sed "s|@DATA_LINE@|$data_line|g" "$src/common/fstab.in" >"$out/fstab"
sed "s|@ESP_GUID@|$esp_guid|g" "$src/overlay/etc/systemd/system/boot.mount.in" >"$out/boot.mount"
# Repart 257 matches partitions by type and order; only the final DATA grows.
for entry in ESP SYSTEM DATA; do
    var=${entry}_SIZE_MIB; size=${!var}
    var=${entry}_TYPECODE; type=${!var}
    var=${entry}_PARTNUM; number=${!var}
    {
        printf '[Partition]\nType=%s\n' "$type"
        if [ "$entry" = DATA ]; then printf 'Weight=1000\n';
        else printf 'SizeMaxBytes=%sM\nSizeMinBytes=%sM\nWeight=0\n' "$size" "$size"; fi
    } >"$out/repart.d/${number}0-${entry,,}.conf"
done
mkdir -p "$out/systemd-repart.service.d"
cat >"$out/systemd-repart.service.d/10-data.conf" <<EOF
[Unit]
Before=mnt-data.mount
[Service]
ExecStart=
ExecStart=/usr/lib/mica/mica-grow-data ${SYSTEM_GUID,,} ${DISK_GUID,,}
SuccessExitStatus=
TimeoutStartSec=30
EOF
if grep -R -E '@[A-Z_]+@' "$out"; then
    echo 'render: unexpanded layout placeholder' >&2; exit 1
fi
