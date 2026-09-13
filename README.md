# mica-cx3576

The cx3576 board (Rockchip RK3576, signed FIT boot through U-Boot) of Mica OS: the board definition
(`board.env`), the BSP build (`bsp/`), the board packages (`deb/`) and the
board evidence (`evidence.json`). A repository of its own, standing on two
source pins fetched at their commits: `build-env/` (`mica-build-env`) and
`boot/` (`mica-boot`).

```
make deps            # build-env/ and boot/ at deps/sources/*.json
make build-env       # the builder images
make kernel          # the board kernel into _out/bsp/kernel (needs the trust certificate, see below)
make pool            # the board packages and mica-kernel-cx3576, indexed into _out/debs
make package-gate    # the gate over that pool
make publish         # the release build-<commit12> of this commit
```

The kernel embeds the dm-verity trust certificate of the deployment it will
boot: `VERITY_TRUST_CERT` (default `meta/verity/signer.cert.pem`, the
assembly's signing workspace or a copy of its certificate). `mica-kernel-cx3576`
ships that certificate beside the kernel, and the assembly
(`ybolab/mica-build`) refuses an archive built against another one. The
assembly imports the packages through `deps/packages/` and builds none of
them.
