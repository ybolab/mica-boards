## Project Development

This repository follows the PMA workflow. The actual rules live in the `/pma`
skill — do not duplicate them here. If a rule in this file ever conflicts
with `/pma`, treat `/pma` as the source of truth and update this file.

### Skill stack

- `/pma` — workflow control, three-phase gate, task and plan tracking

The tree is bash, Dockerfiles, kernel configuration and board policy; no
stack skill covers it, and `/pma`'s *Delivery* rules apply directly.

### Triggers

Any feature, bug fix, refactor, planning, progress tracking, or multi-agent
execution goes through `/pma` (investigate → proposal → implement). Ceremony
is tiered by complexity per `/pma` *Task Tiers*: only trivial changes take
the fast path; everything else waits for explicit approval such as `proceed`.

### Project-specific facts

- The boards of Mica OS, one directory each (`x64/`, `virt-arm64/`, `cx3576/`, `s905x5m/`): `board.env` is the board definition (`BOARD_FEATURES`, `BOARD_FAMILY`, `IMAGE_KINDS` among its keys), `manifests/` the package manifests the assembly's resolver reads out of the bundle, `bsp/` the board's kernel and U-Boot inputs (configuration, device tree, patches, firmware, `hooks/`, and `bsp.env` naming them), `deb/` the producers, `evidence.json` the board evidence where the board keeps one, `tests/` the board's own tests
- `families/<family>/` holds what the boards of one SoC line share -- the kernel and U-Boot Dockerfiles, configure and build scripts, `family.env` with the source pins, `Makefile.inc` with the targets a board's `bsp/Makefile` includes -- and `families/common/` the scripts and checks the families share; `families/README.md` is the contract, including the hooks a board may supply. A family script never names a board
- Three source pins: `build-env/` (`mica-build-env`), `boot/` (`mica-boot`, the boot tooling and the shared inputs under `boot/common`) and `debian/` (`mica-debian`), fetched by `make deps`
- Products: every board package the boards declared plus `mica-kernel-<board>`, which packs the BSP outputs (`_out/<board>`), `board.env`, `evidence.json`, `manifests/`, the support image's firmware and the verity trust certificate the kernel embeds under `/usr/lib/mica/board/<board>/`; published by `release.yml` (CI only) into the one public package `ghcr.io/ybolab/mica-boards`, as `pool.<arch>.build-<commit12>` and each board's bundle as `board.<board>.build-<commit12>`; the assembly (`mica-build`) pins the packages through `deps/packages/` and the bundles through `deps/boards/`
- A kernel embeds the verity trust certificate of the trust domain the assembly signs with (`VERITY_TRUST_CERT`, default `meta/verity/signer.cert.pem`); a U-Boot embeds the FIT boot certificate (`FIT_TRUST_CERT`, `meta/boot/signer.cert.pem`); the assembly refuses a kernel archive built against another certificate, so the published archives must be built against the deployment's
- Quality gates: `make check` (lint, `board-contract-test`, `kernel-config-test` over every board, the cx3576 and s905x5m tests); `make pool` then `make package-gate` over the built archives
- Build resources: no fixed CPU, memory or job quotas; use the host and tool defaults

### Documentation entry points

- Tasks: `docs/task/index.md`
- Plans: `docs/plan/index.md`
- Changelog: `docs/changelog.md`
- Board documentation and design for the whole of Mica OS: `ybolab/mica` (`docs/boards/`)
