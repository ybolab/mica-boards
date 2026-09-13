# Changelog

## 2026-09-13 17:00 [progress]

Created from `boards/s905x5m/` of `ybolab/mica-build` (kept through `git subtree
split`, then the tree at the Mica OS rename). The BSP build under `bsp/`
takes the boot tooling from the `mica-boot` source pin at `boot/` and the
shared inputs from `boot/common`; a new `mica-kernel-s905x5m` producer packs the
BSP outputs for the assembly. Published as `build-<commit12>`
(`20260913-1600-split-boot-and-boards`).
