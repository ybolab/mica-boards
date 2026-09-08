# U-Boot

This directory builds the S7D/S905X5M BM201 U-Boot path described by the m100
reference tree.

Default source:

- repository: `https://github.com/CoreELEC/u-boot.git`
- commit: `5f7ac2b1dc4df2f466ed88c3958a8675873f8a1a`
- build target: `./mk s7d_bm201`

The Dockerfile injects the local `s7d_bm201_defconfig` and
`meson-s7d-bm201.dts` into `bl33/v2023/configs/amlogic/` and
`bl33/v2023/arch/arm/dts/amlogic/` before the build. `./mk` only scans the
bl33 tree for board configs, so files placed at the repository root are
ignored. The build asserts that `CONFIG_CMD_CFGLOAD=y` and
`CONFIG_BOOTCOMMAND="run boot_default"` reached the generated `.config`.
`cfgload sd` remains the SD-card compatibility bridge only. The BM201 source
routes an eMMC selection to p5's `boot.scr`, using the identical p6 copy only
when p5 cannot load it, so the script itself selects the RAUC slot from the
redundant environment instead of a fixed `mmc 1:1` `boot.ini` path.

The final-config contract also requires `setexpr`, `source`, `env import`, FAT
load support, `booti`, `fdt`, the legacy script image format, hush, and the
Amlogic VOUT/HDMI stack (`CONFIG_AML_VOUT`, `CONFIG_AML_HDMITX`, and
`CONFIG_AML_HDMITX21`). Those are the command-level prerequisites for the
production boot script; each is checked after the generated configuration's
dependency resolution, not against the defconfig alone. It also rejects
`CONFIG_AML_DISABLE_DEV_CMDS=y`, which would compile the Amlogic `fatload`
implementation out despite `CMD_FAT`.

`make -C boards/s905x5m/bsp uboot` is the board artifact interface. Its
default stage audits the produced `bl33/v2023/build/.config` against the U-Boot
requirements in `docs/design/boards.md` section 5 and refuses to populate
`out/uboot` while any requirement is missing. `--target build` remains
available for diagnosing the known-good baseline before that gate.

The upstream build embeds its wall-clock build time before compression and
signing, so the two signed-image SHA-256 values change between otherwise
identical builds. Treat the fetched commit check, produced `.config`, artifact
sizes, and BL33-content assertion as the stable controls; do not promote one
diagnostic run's signed-image hash into a source pin.

The canonical eMMC replacement payload is `u-boot.bin.signed`. It is not a raw
`boot0` image: an Amlogic package step makes the target generate the
target-specific `storage_emmc_boot_info` sector. Nothing in this directory
writes a device.

## Amlogic bootloader package

The package consumer is deliberately separate from the producer interface:

```bash
make s905x5m-uboot
make s905x5m-uboot-package
```

The second target reads only the three files in `out/uboot/` and exports:

```text
out/uboot-package/update.img
out/uboot-package/update.img.sha256
out/uboot-package/aml_sdc_burn.ini
```

`update.img` is an Amlogic v2 container, not a raw block image. It is suitable
for host USB burning: the manifest carries one `DDR.USB` payload under both
`USB/DDR` and `USB/UBOOT`, so the BootROM can train DRAM before it loads the
burn-protocol U-Boot. It also supports the established manual card path through
a currently running vendor U-Boot: the package and its external
`aml_sdc_burn.ini` sidecar are the inputs to a manually selected `sdc_burn`
operation.

The package deliberately does not ship a GPT and does not name `bootloader_a`.
It names only the special `bootloader` target, which is what lets the target
frame its hardware boot area rather than reusing an unframed user-area payload.
It also carries the board's required Amlogic multi-DTB and USB-flow blobs; it
does not contain a Linux rootfs or a complete system image.

It does not create an automatic installer card. At the measured vendor
`s7d_bm201#` prompt, `sdc_burn [sdc_burn_cfg_file]` is available and
`sdcburncfg=aml_sdc_burn.ini`, which establishes the manual path this package
uses. `/bm201upd.ini` is instead the private configuration and request/receipt
wrapper that the replacement BM201 installer U-Boot understands. Do not infer
support for that automatic protocol from this package.

The package build checks the packer binary, static board blobs, manifest shape,
BL33 presence, container format, and a byte-for-byte seven-input unpack round
trip. Those checks establish package construction and preservation only. They
do not prove hardware bootability, perform a device write, or authorize the
owner-gated first bootloader update.

## Complete eMMC USB package

The complete recovery package extends the same package consumer rather than
creating a second GPT or filesystem producer:

```bash
make os-emmc-package-s905x5m-v2
```

The top-level target builds the normal SD-only image, then has the host-side
extractor read that completed image back. It verifies the GPT against
`boards/s905x5m/board.env` and exports the exact `gpt.bin` plus the
mos-owned p3..p12 bytes to the shared Amlogic package stage. A caller with
already-built inputs may run `make s905x5m-emmc-package` instead; its input SD
image defaults to `_out/s905x5m/s905x5m-mos-sd-latest.img` and can be
overridden with `EMMC_SD_IMAGE=...`.

The output is deliberately limited to:

```text
boards/s905x5m/bsp/out/emmc-package/update.img
boards/s905x5m/bsp/out/emmc-package/update.img.sha256
```

It is a host USB-burning artifact; it does not export a manual-card
configuration and its build never invokes `sdc_burn`. The manifest retains
the BootROM `USB/DDR` and `USB/UBOOT` bootstrap entries, the special hardware
boot-area `bootloader` target, and the special reserved-DTB `_aml_dtb` target.
`gpt` is also vendor-special: the target's GPT writer applies the package
table to the real eMMC capacity before the normal partition targets run.

The extracted normal destinations are `uenv-a`, `uenv-b`, `boot-a`, `boot-b`,
`rootfs-a`, `rootfs-b`, `meta`, `state`, `ephemeral`, and `data`. `rootfs-b`
and the two environment ranges are intentionally zero-filled factory state.
The SD-only p1 cfgload bridge is never exported, and neither is p2 `env`:
those ranges remain vendor-owned on eMMC. There is no `bootloader_a` entry
because the mos GPT intentionally has no such partition; adding Alpine's
user-area staging target would make the vendor normal-partition lookup fail.

Burning this package later replaces the eMMC user-area GPT. It therefore
destroys the stock Android partition layout and its data, by design. The
package's format check and 18-input byte-for-byte unpack comparison establish
only container validity and payload fidelity. They do not prove that a board
will accept a burn, boot the resulting system, recover from failure, or make
the separately owner-gated first write authorized.

## Reusable eMMC installer card

This is not a protocol port. The replacement BM201 U-Boot already carries the
private request/receipt state machine imported from the Alpine reference; the
only U-Boot source change for this card is its two shared capacity constants
and their host-test expectations. The producer is a regular-file-only target:

```bash
make s905x5m-uboot
make os-emmc-installer-s905x5m-v2 \
  EMMC_INSTALLER_PACKAGE=/path/to/update.img
```

It requires a caller-selected file named `update.img` and writes only:

```text
boards/s905x5m/bsp/out/emmc-installer/disk.img
boards/s905x5m/bsp/out/emmc-installer/disk.img.sha256
```

The target first verifies that its input is the exact 18-file complete Amlogic
package, so a bootloader-only package cannot receive the full-flash sidecar. It
does not pin a package artifact, invoke a burner, open a block device, or write
an SD card, eMMC user area, boot area, or `bootloader_a`.

The shared limits are a 1,792 MiB FAT32 partition and a 1,536 MiB accepted
package bound. They are derived from the 1,369,400,096-byte complete package:
the bound leaves 241,212,640 bytes (230.038300 MiB) of package growth, and the
FAT leaves 256 MiB before filesystem metadata at that bound. The final-image
gate requires at least 240 MiB of measured free FAT space. The whole image is
`4 + 1792 + 16 = 1812 MiB`: the FAT starts at sector 8192 and occupies
3,670,016 sectors.

The FAT contains exactly `update.img`, `bm201upd.ini`,
`emmc-system-install.request`, and `update.img.sha256`. `bm201upd.ini` is the
private 8.3-compatible name and deliberately differs from the vendor magic
`aml_sdc_burn.ini`, so the vendor autoburn path cannot bypass the request and
receipt gate. Its complete-package configuration has `erase_bootloader = 1`,
`erase_flash = 1`, and `reboot = 3`; it is not the bootloader-only manual
sidecar, whose `erase_flash = 0` remains intentionally separate.

The producer unpacks and validates the package before use, reads the LBA-1
U-Boot and all four FAT files back from the finished disk image, compares the
package and configuration byte-for-byte, verifies the request and SHA-256
identity, checks partition geometry and measured free space, and rejects
`boot.ini`, `boot.scr`, `Image`, the board DTB, vendor magic configurations,
and any receipt. It prints the resulting image path, size, SHA-256, FAT
geometry, and free bytes.

The runtime gate is unchanged: no card continues normal boot; an unreadable
selected FAT partition stops normal boot; losing the source after a valid
request stops; a matching eMMC receipt skips the burn; and a non-zero burn or
receipt write/readback failure stops without accepting the installation.

The installed eMMC U-Boot must already contain both this private protocol and
the enlarged bounds. A vendor U-Boot lacks the protocol, while an earlier mos
U-Boot has the protocol but rejects packages above 640 MiB. Host USB burning of
a newly built complete package is therefore required once for that bootstrap;
the card's LBA-1 U-Boot cannot alter the normal eMMC-first BootROM path.
