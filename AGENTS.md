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

- The x64 board (UEFI, systemd-boot, QEMU and generic PCs): `board.env` is the board definition (partition layout, boot backend, firmware files), `bsp/` the kernel build, `deb/` the producers, `evidence.json` the board evidence
- Two source pins: `build-env/` (`mica-build-env`, the substrate) and `boot/` (`mica-boot`, the boot tooling and the shared inputs under `boot/common`), fetched by `make deps`
- Products: the board packages this tree always declared plus `mica-kernel-x64`, which packs the BSP outputs (`_out/bsp`), `board.env`, `evidence.json`, the support image's firmware and the verity trust certificate the kernel embeds under `/usr/lib/mica/board/x64/`; published as the GitHub Release `build-<commit12>` of `ybolab/mica-x64`; the assembly (`mica-build`) imports them through `deps/packages/` and reads the kernel archive into `_out/boards/x64/`
- The kernel embeds the verity trust certificate of the trust domain the assembly signs with (`VERITY_TRUST_CERT`, default `meta/verity/signer.cert.pem`); a kernel built against another certificate is refused by the assembly, so the published archive must be built against the deployment's certificate
- Quality gates: `make check` (lint, `kernel-config-test`); `make pool` then `make package-gate` over the built archives
- Build resources: no fixed CPU, memory or job quotas; use the host and tool defaults

### Documentation entry points

- Tasks: `docs/task/index.md`
- Plans: `docs/plan/index.md`
- Changelog: `docs/changelog.md`
- Board documentation and design for the whole of Mica OS: `ybolab/mica` (`docs/boards/`)
