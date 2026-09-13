# mica-boards

The boards of Mica OS, one directory each under `boards/` -- the board
definition (`board.env`), the package manifests (`manifests/`), the kernel
inputs (`kernel/`: configuration, device tree, patches, hooks), the loader
inputs (`loader/`), the support firmware (`firmware/`), the board package's
inputs (`package/`: control, copyright, overlay, hwinit, init), the board
evidence and the board's own tests -- and under `families/` what the boards
of one SoC line share: the kernel and U-Boot builds and their source pins
(`families/README.md`). A board is data; `tools/new-board.sh <name> --from
<nearest>` copies one.
One repository, standing on two source pins fetched at their commits:
`build-env/` (`mica-build-env`) and `boot/` (`mica-boot`). The Debian
base is the assembly's concern; nothing here composes a root.

```
make deps                 # the two pins
make build-env            # the builder images
make <board>-kernel       # a board's kernel into _out/<board>/kernel; <board>-firmware its loader; make kernels firmware for every board
make pool                 # every board package and every mica-kernel-<board>, both architectures, indexed
make package-gate         # the gate over that pool
make publish              # the pool artifacts and every board's bundle artifact, tagged build-<commit12>
```

A kernel embeds the dm-verity trust certificate of the deployment it will
boot (`VERITY_TRUST_CERT`, default `meta/verity/signer.cert.pem`) and a
U-Boot the FIT boot certificate (`FIT_TRUST_CERT`); `mica-kernel-<board>`
ships the certificate beside the kernel and the assembly
(`ybolab/mica-build`) refuses an archive built against another one. The
assembly imports every package here through `deps/packages/` and builds
none of them.
