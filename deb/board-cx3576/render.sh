#!/usr/bin/env bash
# Render the fresh FIRMWARE/SYSTEM/DATA runtime storage policy.
set -euo pipefail
src=${1:?source root required}
out=${2:?output directory required}
. "$src/boards/cx3576/board.env"
[ "$LAYOUT_VERSION" = 3 ] && [ "$LAYOUT_PARTITIONS" = 'FIRMWARE SYSTEM DATA' ]
mkdir -p "$out/repart.d" "$out/systemd-repart.service.d"
printf -v data_line 'PARTUUID=%s /mnt/data ext4 noatime,prjquota,x-systemd.growfs 0 2' "${DATA_GUID,,}"
sed "s|@DATA_LINE@|$data_line|g" "$src/rootfs/overlay/etc/fstab.in" > "$out/fstab"
for entry in FIRMWARE SYSTEM DATA; do
    var=${entry}_TYPECODE; type=${!var}
    var=${entry}_PARTNUM; number=${!var}
    if [ "$entry" = FIRMWARE ]; then size=$((FIRMWARE_SIZE_SECTORS * 512));
    else var=${entry}_SIZE_MIB; size=$(( ${!var} * 1048576 )); fi
    {
        printf '[Partition]\nType=%s\n' "$type"
        if [ "$entry" = DATA ]; then printf 'Weight=1000\n';
        else printf 'SizeMinBytes=%s\nSizeMaxBytes=%s\nWeight=0\n' "$size" "$size"; fi
    } > "$out/repart.d/${number}0-${entry,,}.conf"
done
cat > "$out/systemd-repart.service.d/10-data.conf" <<EOF
[Unit]
Before=mnt-data.mount
[Service]
ExecStart=
ExecStart=/usr/lib/mos/mos-grow-data ${SYSTEM_GUID,,} ${DISK_GUID,,}
SuccessExitStatus=
TimeoutStartSec=30
EOF
if grep -R -E '@[A-Z_]+@' "$out"; then
    echo 'render: unexpanded layout placeholder' >&2; exit 1
fi
