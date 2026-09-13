# mica-x64

The x64 board (UEFI, systemd-boot, QEMU and generic PCs) of Mica OS: the board definition
(`board.env`), the BSP build (`bsp/`), the board packages (`deb/`) and the
board evidence (`evidence.json`). A repository of its own, standing on two
source pins fetched at their commits: `build-env/` (`mica-build-env`) and
`boot/` (`mica-boot`).

```
make deps            # build-env/ and boot/ at deps/sources/*.json
make build-env       # the builder images
make kernel          # the board kernel into _out/bsp/kernel (needs the trust certificate, see below)
make pool            # the board packages and mica-kernel-x64, indexed into _out/debs
make package-gate    # the gate over that pool
make publish         # the release build-<commit12> of this commit
```

The kernel embeds the dm-verity trust certificate of the deployment it will
boot: `VERITY_TRUST_CERT` (default `meta/verity/signer.cert.pem`, the
assembly's signing workspace or a copy of its certificate). `mica-kernel-x64`
ships that certificate beside the kernel, and the assembly
(`ybolab/mica-build`) refuses an archive built against another one. The
assembly imports the packages through `deps/packages/` and builds none of
them.
