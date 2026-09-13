# cx3576

The cx3576 board (Rockchip RK3576, signed FIT boot through U-Boot) of Mica OS: the board definition
(`board.env`), the BSP build (`bsp/`), the board packages (`deb/`) and the
board evidence (`evidence.json`). One board of `ybolab/mica-boards`; `make cx3576-kernel`, `make pool` and
`make publish` at the repository root build, pack and release it.


The kernel embeds the dm-verity trust certificate of the deployment it will
boot: `VERITY_TRUST_CERT` (default `meta/verity/signer.cert.pem`, the
assembly's signing workspace or a copy of its certificate). `mica-kernel-cx3576`
ships that certificate beside the kernel, and the assembly
(`ybolab/mica-build`) refuses an archive built against another one. The
assembly imports the packages through `deps/packages/` and builds none of
them.
