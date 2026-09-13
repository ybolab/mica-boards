# Changelog

## 2026-09-13 07:40 [progress]

Phase 1 of `mica:20260913-0416-board-product-build-architecture`, board
contract v2 and the family layer. Every `board.env` declares
`BOARD_FEATURES`, `BOARD_FAMILY` and `IMAGE_KINDS`; the package manifests
moved here from the assembly as `<board>/manifests/` and travel in the
`mica-kernel-<board>` bundle; `bsp/containers.env` is gone (the product
decides features). `families/` holds what the boards of one SoC line
share: `uefi` (x64, virt-arm64: one kernel Dockerfile), `rockchip`
(cx3576) and `amlogic` (s905x5m), each with its Dockerfiles, configure and
build scripts and source pins; a board keeps its configuration, device
tree, patches, firmware and the hooks the family calls, and names its
files in `bsp/bsp.env` (`families/README.md`). Proof: every board's kernel
rebuilt through its family byte-identical to a build of the same pins
before the change (config, release, modules, System.map, DTB; the
s905x5m `Image` carries a 25-byte vendor build stamp that differs between
any two builds, and its `modules.tar` now pins mtimes and order like the
other families'); cx3576 and s905x5m U-Boot likewise.
`tests/board-contract-test.sh` asserts the contract in `make check`.

## 2026-09-13 19:30 [progress]

Created from `boards/{x64,virt-arm64,cx3576,s905x5m}/` of `ybolab/mica-build`
(each kept through `git subtree split`, briefly a repository of its own,
then brought in here with that history under `<board>/`). The BSP builds
take the boot tooling from the `mica-boot` source pin at `boot/` and the
shared inputs from `boot/common`; a `mica-kernel-<board>` producer per board
packs the BSP outputs for the assembly. Published together as
`build-<commit12>` (`20260913-1600-split-boot-and-boards`).
