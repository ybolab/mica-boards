# bsp — CX3576-Z (Rockchip RK3576)

The board's bootloader and kernel are built here. Each component is an
independent buildkit Dockerfile producing finished artifacts under `out/`;
nothing here builds or modifies the mos rootfs, which `rootfs/` owns.

`Makefile` in this directory drives every target. The repo root delegates to it:
`make cx3576-<target>` runs `make -C boards/cx3576/bsp <target>`.

## Layout

- `uboot/` — mainline U-Boot v2026.07 + rkbin blobs -> `u-boot-rockchip.bin` (eMMC sector 64).
  `make uboot` builds the v1/Alpine debug variant into `out/uboot/`; `make uboot-mos`
  builds the A/B variant with the redundant environment and the `boot.scr` contract
  into `out/uboot-mos/`, which is the one the mos image takes
- `kernel/` — armbian rk-6.1-rkr5.1 (6.1.115): config baseline, in-tree dts, patches -> `Image`, `modules.tar`, `rk3576-src.dtb`.
  The config must satisfy `boards/common/mos-required.fragment`
- `rootfs/` — Alpine demo rootfs (overlay under `alpine/rootfs/`, installed onto `/`)
  + WiFi firmware blobs (AP6275S / AIC8800 dual SKU); the demo image itself
  ships only the verified AIC8800D80 U02 blobs
- `init/` — board hardware facts consumed by the `boards/cx3576/hwinit`
  systemd units
- `Dockerfile.alpine` — assembles the flashable Alpine debug/demo disk image (extlinux boot)

The Alpine image is the board smoke-test path. The mos image consumes
`out/uboot-mos/` and `out/kernel/` from here, defaulting to this directory and
overridable with `BOARD_DIR`.

## Flashing

Five ways onto the board, and which one applies is decided by the state the
board is already in, not by preference.

| Method | Use when | Command | Writes |
|---|---|---|---|
| **Loader** | U-Boot boots and its rockusb gadget enumerates | `make flash` | the whole disk |
| **Maskrom** | U-Boot is absent or broken, board enumerates as Maskrom | `make flash-maskrom` | the whole disk, after pushing the pinned vendor loader |
| **rootfs only** | kernel and partition layout unchanged | `make flash-rootfs-offline` | `out/rootfs/rootfs.img` at sector 163840 |
| **`ums`** | you are at the U-Boot console | `ums 0 mmc 0`, then `dd` from the host | whatever the host writes |
| **raw `dd`** | the eMMC or SD is reachable directly | `dd` to the block device | whatever you write |

`make flash` writes `out/disk.img` with `rkdeveloptool wl 0`, verifies the boot
area by reading it back, and only then issues `rd` to reboot. **Keep power and
USB connected until `rd` returns** — every flash target says so, because a
board interrupted mid-write comes back in Maskrom.

`make flash-maskrom` is the recovery path: it checks `uboot/MiniLoaderAll.bin`
against its committed sha256, pushes it with `rkdeveloptool db`, and then
flashes exactly as above. The loader is pinned rather than rebuilt, so recovery
does not depend on the build that broke.

**`ums` runs from U-Boot only, never from Maskrom.** The BootROM speaks the
0x471/0x472 protocol and nothing else, so there is no mass-storage mode to
enter before U-Boot is running. `CONFIG_CMD_USB_MASS_STORAGE=y` is set in
`generic-rk3576_defconfig`, so the command is present once U-Boot is.

**There is no `update.img`, deliberately.** The RK packaging format would need
`afptool` and `rkImageMaker`, which are closed-source SDK binaries this tree
would have to vendor, and it buys nothing: `out/disk.img` is a whole-disk image
carrying every partition, and `rkdeveloptool wl 0` writes it in one step from
both Loader and Maskrom.

Upstream provenance and the deliberate deviations from it are recorded in
`docs/design/bsp-cx3576-sync.md`.
