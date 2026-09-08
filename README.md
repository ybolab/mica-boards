# S905X5M mainline port

This is the BM201 / X88 Pro X5M board port on the package-based mainline.
See the [board dossier](../../docs/bsp/s905x5m.md) for provenance and hardware
qualification limits, and [U-Boot operations](bsp/uboot/README.md) for the
separate eMMC package and installer flows.

## Build

Build the pinned toolchain images first as described in
[build design](../../docs/design/build.md). The shared Rust package producer
currently requires the amd64 builder family even when targeting arm64.

```bash
make build-env
# Also build the cross-compilation family when the host is arm64.
MOS_BUILD_PLATFORM=linux/amd64 make build-env
make s905x5m-kernel s905x5m-uboot s905x5m-userland
```

The resulting BSP lives under `_out/boards/s905x5m/`. It includes the resolved
kernel config, kernel release and System.map in addition to Image, DTB and
modules. The board package preflight refuses any missing input.

Build the local producers selected for this board, without requiring BSP
artifacts from unrelated boards:

```bash
selected=$(bash rootfs/packages/resolve.sh --board s905x5m --profile dev \
    --radios 'wifi bluetooth' --without '' --components "${MOS_ROOTFS_COMPONENTS:-}")
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
make os-image-s905x5m-sd
make os-verify-s905x5m-sd
```

The composer uses the locked Debian dependencies and local package pool.
The SD assembler and RAUC bundle producer consume the selected package's
boot export in `_out/s905x5m/boot/`.

The image named `s905x5m-mos-sd-latest.img` is **SD-only**: partition 1 is a
cfgload bridge. Do not use that image as an eMMC whole-disk image. Dedicated
file producers are `os-emmc-package-s905x5m` and
`os-emmc-installer-s905x5m EMMC_INSTALLER_PACKAGE=/path/to/update.img`.

## Optional components and radios

Run `export MOS_ROOTFS_COMPONENTS='bm201-front-panel mqtt-reference'` before package
selection and composition to include those default-off packages. The MQTT
reference requires the dev profile and the shared MQTT packages.

`MOS_ROOTFS_WITHOUT=bluetooth` omits the Bluetooth userland and initializer.
`MOS_ROOTFS_WITHOUT=wifi` omits the Wi-Fi services while retaining the shared
SDIO transport if Bluetooth still needs it. Apply the same decline selection
to the resolver's `--without` argument when building a reduced package pool.

## Host and hardware checks

`make os-rootfs-manifest-test`, `make os-layout-lint`, `make os-build-test`
and `make os-verify-test` cover the package, layout and image contracts.
`bash verify/run.sh --runtime HOST --help` describes the separate SSH runtime
acceptance command and explicit active probes. It requires host Bun and
mtools; it refuses automatic container fallback.

New mainline configuration uses `/mos/config` documents and
`time.ntp.servers`. This port preserves the current mainline model and does
not migrate an existing device's legacy settings file. New-image hardware
qualification remains separate from source builds and automated tests.
