# Changelog

## 2026-09-13 19:30 [progress]

Created from `boards/{x64,virt-arm64,cx3576,s905x5m}/` of `ybolab/mica-build`
(each kept through `git subtree split`, briefly a repository of its own,
then brought in here with that history under `<board>/`). The BSP builds
take the boot tooling from the `mica-boot` source pin at `boot/` and the
shared inputs from `boot/common`; a `mica-kernel-<board>` producer per board
packs the BSP outputs for the assembly. Published together as
`build-<commit12>` (`20260913-1600-split-boot-and-boards`).
