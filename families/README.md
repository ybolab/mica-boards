# Families

A family is what the boards of one SoC line share: the kernel and U-Boot
orchestration (the Dockerfiles), the configure and build scripts, and the
source pins. A board of the family owns only what is its own -- its
configuration, device tree, patches, firmware inputs and the hooks the family
calls -- and names the family in `board.env` (`BOARD_FAMILY`). Yocto's
`conf/machine/include/<soc>.inc` and Armbian's `config/sources/families/` are
the same idea; the point is that the twentieth Rockchip board is a
`board.env`, a defconfig and a device tree.

```
families/
  common/
    scripts/            apt-install.sh, fetch-source.sh, apply-patches.sh -- shared by the FIT families' builders
    kernel/             mklogo.py (the boot-logo renderer), floor-check.sh (the shared kernel floor, asserted)
  uefi/                 x64, virt-arm64: mainline stable, a signed UKI through systemd-boot
    family.env          KERNEL_SOURCE
    Makefile.inc        kernel, kernel-config; the architecture table (amd64, arm64)
    kernel/Dockerfile   one build for every architecture; context = boards/<board>/kernel
  rockchip/             cx3576: the Rockchip vendor tree, mainline U-Boot with rkbin, a signed FIT
    family.env          KERNEL_REPO, KERNEL_COMMIT, KERNEL_EXPECT, RKBIN_*, UBOOT_*
    Makefile.inc        kernel, uboot-mos
    kernel/             Dockerfile, configure.sh, build.sh; context = boards/<board>
    uboot/Dockerfile    context = boards/<board>/loader (the board's policy scripts, patches, tests, loader)
  amlogic/              s905x5m: the Hardkernel vendor tree, CoreELEC's U-Boot, a signed FIT
    family.env          KERNEL_REPO, KERNEL_COMMIT, KERNEL_EXPECT, UBOOT_*
    Makefile.inc        kernel, uboot
    kernel/             Dockerfile, configure.sh, build.sh; context = boards/<board>
    uboot/Dockerfile    context = boards/<board>/loader
```

A board's `Makefile` (`boards/<board>/Makefile`) sets `BOARD` and includes its family's
`Makefile.inc`; it keeps the targets that are the board's own (flashing, a
recovery package, a userland bridge). A FIT board names its files in
`bsp.env` (plain `KEY=value`, included by make and handed to the
Dockerfiles as build arguments): `KERNEL_CONFIG`, `KERNEL_DTB`,
`KERNEL_DTB_ARTIFACT`, and for rockchip `UBOOT_DEFCONFIG`, `DDR_BLOB`,
`BL31_BLOB`; for amlogic `KERNEL_FRAGMENTS`, the merge order of its config
fragments with `@mos-required` standing for the shared floor. A UEFI board
has no `bsp.env`: its `kernel/versions.env` pins the tag and its
`kernel/config/<board>.{fragment,config}` are the configuration.

## The hooks

The FIT families' kernel builds call these scripts from the board's
`kernel/hooks/` when they exist; a board with none builds the family's
plain kernel. Each receives the source tree first; CROSS_COMPILE is in the
environment where the family sets it.

| Hook | When | Arguments | For |
|---|---|---|---|
| `prepare.sh` | after the patches, before the configuration | `<src> <board-dir> <families/common/kernel>` | what a board derives into the tree (cx3576 renders its boot logo) |
| `configure.sh` | after `LOCALVERSION_AUTO` is disabled, before the floor is merged | `<src>` | the board's `scripts/config` edits |
| `assert.sh` | after `olddefconfig` and the shared floor check | `<src>` (amlogic: `<src> <config-dir>`) | the board's own required and refused options |
| `verify.sh` | after the build and the device tree | `<src> <dtb>` | source and device-tree assertions |
| `modules.sh` (amlogic) | after the in-tree modules are installed, before depmod | `<src> <install-root> <board-dir>` | the board's out-of-tree modules |
| `modules-verify.sh` (amlogic) | after depmod | `<module-dir>` | the indexed set carries them once |

Assertions live in hooks; the family's scripts never name a board. A change
to a family rebuilds every board of it, and the proof of a family change is
each board's kernel byte-identical to the build before it (the artefacts are
reproducible: `KBUILD_BUILD_*` and `SOURCE_DATE_EPOCH` are pinned).
