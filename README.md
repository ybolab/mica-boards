# S905X5M signed-file development port

BM201 / X88 Pro X5M, Amlogic S7D, arm64. The current delivery boots a signed
MOS deployment from SD using the paired MOS U-Boot installed in eMMC boot0.
The SD image is not a standalone bootloader image. Physical qualification is
pending; `BOARD_RELEASE_TARGET=0` remains set. See the
[board dossier](../../docs/bsp/s905x5m.md) and [firmware operations](bsp/uboot/README.md).

## Build inputs

Use the pinned builder images described in [build design](../../docs/design/build.md).
Generate development keys explicitly, or supply existing signing material:

```bash
make os-devkeys MOS_SIGNING_OUTPUT="$PWD/tmp/s905x5m-keys"
make s905x5m-kernel VERITY_TRUST_CERT="$PWD/tmp/s905x5m-keys/verity/signer.cert.pem"
make s905x5m-uboot FIT_TRUST_CERT="$PWD/tmp/s905x5m-keys/boot/signer.cert.pem"
make s905x5m-fit-tools
```

Kernel and firmware builders receive only public certificates. BSP outputs are
under `_out/boards/s905x5m/{kernel,uboot,userland}`. U-Boot exports the final
control DTB and FIT tools; its gate verifies that the required key is embedded
in the BL33 bytes recovered from the exported FIP.

Build the selected root packages, then compose the independent root:

```bash
selected=$(bash rootfs/packages/resolve.sh --board s905x5m --profile dev \
    --radios 'wifi bluetooth' --without "${MOS_ROOTFS_WITHOUT:-}" \
    --components "${MOS_ROOTFS_COMPONENTS:-}")
selected=${selected//$'\n'/ }
while read -r producer directory arches packages enablement; do
    wanted=0
    for package in ${packages//,/ }; do
        case " $selected " in *" $package "*) wanted=1 ;; esac
    done
    [ "$wanted" = 1 ] || continue
    case ",$arches," in *,all,*) arch=all ;; *,arm64,*) arch=arm64 ;; *) continue ;; esac
    bash build-env/deb/build.sh --producer "$producer" --arch "$arch"
done < <(bash build-env/deb/producers.sh)
bash build-env/deb/repo.sh --arch arm64
make os-rootfs-s905x5m MOS_META_DIR="$PWD/tmp/s905x5m-keys"
```

The Bluetooth producer builds its own bridge; the board package contains only
root-side hardware/storage policy. Kernel modules and radio firmware belong to
the authenticated kernel support image. Build `mos-init` using
`pkgs/mos-deploy/hack/build-deb.sh --producer init --bins mos-init --arch arm64 --stage DIR`.

Use `bash build/run.sh --components --help` to package `root`, `kernel`,
`firmware`, two distinct `deployment` generations, and an `archive`. Set
`--board s905x5m` for kernel and firmware; the firmware input is
`_out/boards/s905x5m/uboot/u-boot.bin.signed`. Each image record contains its
signed envelope and absolute kernel/root component directories.

```bash
make os-image-s905x5m-sd \
    MOS_IMAGE_RECORDS=/absolute/path/records.json \
    MOS_METADATA_PUBLIC_KEYS="$(cat tmp/s905x5m-keys/updates/public.key)" \
    MOS_FIRMWARE_PACKAGE=/absolute/path/firmware-component \
    MOS_IMAGE_OUT=/absolute/path/new-image-directory
make os-verify-s905x5m-sd \
    MOS_VERIFY_IMAGE=/absolute/path/mos-s905x5m-YYYYMMDD-HHmmss.img \
    MOS_METADATA_PUBLIC_KEY_FILES="$PWD/tmp/s905x5m-keys/updates/public.key"
```

Keep `firmware.bin` and its signed `firmware.json` beside the timestamped image.
Offline verification checks this paired artifact; boot0 installation is checked
separately by native device readback. Ordinary component updates never write it.

## Layout and boot

The GPT contains FIRMWARE (sector 64 through 128 MiB), SYSTEM (128–1152 MiB),
and DATA (1152 MiB onward, initially 256 MiB). DATA alone grows. Native 64 KiB
records are at absolute 120 and 124 MiB. The SD FIRMWARE partition contains
records and zero padding; the bootloader stays outside the SD system image.

A one-second native countdown permits serial/USB keyboard console entry without
consuming an attempt. Automatic boot requires eMMC boot0 firmware and SD `mmc 0`,
arms the Meson watchdog for 60 seconds, persists and reads back the selected
attempt, verifies its FIT, and supplies `mos,deployment-id` to native init.

## Radios and optional panel

`MOS_ROOTFS_WITHOUT=bluetooth` omits the bridge. `MOS_ROOTFS_WITHOUT=wifi`
omits the station driver/services while preserving Bluetooth SDIO transport.
Declining both leaves the radio rail initializer unselected. Bluetooth pairing
keys and the derived controller address use protected `DATA/state/bluetooth`,
mounted at `/var/lib/bluetooth` by the shared Bluetooth package.

`MOS_ROOTFS_COMPONENTS=bm201-front-panel` includes the optional executable
clock/link-status service. It is off by default and reads `/run/mos/timezone`.

## Verification

```bash
make os-build-test os-verify-test os-rootfs-manifest-test
make os-fit-records-test os-s905x5m-hwinit-test
make os-repart-test MOS_BOARD=s905x5m \
    MOS_VERIFY_IMAGE=/absolute/path/factory.img \
    MOS_VERIFY_ROOT_IMAGE=/absolute/path/rootfs.img
make docs-verify
```

The repart gate uses an isolated loop image. Current physical acceptance still
requires cold boot, watchdog handoff, serial/HDMI, Ethernet, USB, Wi-Fi, Bluetooth,
DATA quotas and persistence, signed updates/fallback, and shutdown on a BM201.
