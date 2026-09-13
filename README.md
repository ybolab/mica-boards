# mica-boards

The boards of Mica OS, one directory each: `x64/`, `virt-arm64/`, `cx3576/`,
`s905x5m/` -- the board definition (`board.env`), the package manifests
(`manifests/`), the BSP inputs (`bsp/`: configuration, device tree, patches,
firmware, hooks), the board packages (`deb/`), the board evidence and the
board's own tests -- and under `families/` what the boards of one SoC line
share: the kernel and U-Boot builds and their source pins (`families/README.md`).
One repository, standing on three source pins fetched at their commits:
`build-env/` (`mica-build-env`), `boot/` (`mica-boot`) and `debian/`
(`mica-debian`).

```
make deps                 # the three pins
make build-env            # the builder images
make x64-kernel           # a board's kernel into _out/x64/kernel (cx3576-uboot-mos, s905x5m-uboot ... likewise)
make pool                 # every board package and every mica-kernel-<board>, both architectures, indexed
make package-gate         # the gate over that pool
make publish              # the release build-<commit12> of this commit
```

A kernel embeds the dm-verity trust certificate of the deployment it will
boot (`VERITY_TRUST_CERT`, default `meta/verity/signer.cert.pem`) and a
U-Boot the FIT boot certificate (`FIT_TRUST_CERT`); `mica-kernel-<board>`
ships the certificate beside the kernel and the assembly
(`ybolab/mica-build`) refuses an archive built against another one. The
assembly imports every package here through `deps/packages/` and builds
none of them.
