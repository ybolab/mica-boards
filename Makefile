# mica-boards: the boards of Mica OS -- x64, virt-arm64, cx3576, s905x5m --
# one directory each: the board definition, the BSP build under bsp/, the
# producers under deb/, the evidence and the board's tests. This file routes:
# `make <board>-<target>` delegates to the board's bsp/Makefile, `make pool`
# packs every producer of every board, `make publish` releases them together.

# THE SOURCE DEPENDENCIES, before anything else: build-env/ (mica-build-env)
# is the substrate every target reaches through, boot/ (mica-boot) the boot
# tooling and the shared inputs the BSP builds and the producers take, and
# debian/ (mica-debian) the snapshot the boot-tools image installs from.
# Fetched at their pins (deps/sources/*.json) by tools/deps.sh; `make deps`
# is the one target that may run without them.
ifeq ($(filter deps,$(MAKECMDGOALS)),)
ifeq ($(wildcard build-env/from.sh),)
$(error build-env/ is empty: the build substrate is fetched at its pin from ybolab/mica-build-env. Run: make deps)
endif
ifeq ($(wildcard boot/verity-tool.sh),)
$(error boot/ is empty: the boot tooling is fetched at its pin from ybolab/mica-boot. Run: make deps)
endif
endif

BOARDS := x64 virt-arm64 cx3576 s905x5m

.PHONY: help deps deps-check deps-bump build-env preflight pool package-gate publish kernel-config-test kernel-cmdline-test mac-stable-test gadget-configfs-test flash-verify-test wireless-test lint check

help:
	@echo "  deps                fetch build-env/, boot/ and debian/ at their pins; deps-check reads without downloading"
	@echo "  deps-bump           DEP=<repository> [DEP_TAG=build-<commit12>] rewrites one pin"
	@echo "  build-env           the builder images, from the pins in build-env/images.env"
	@echo "  <board>-<target>    delegate to <board>/bsp (kernel, kernel-config; cx3576: uboot-mos, flash-mos; s905x5m: uboot, userland, fit-tools, uboot-package)"
	@echo "                      a kernel embeds the verity trust certificate: VERITY_TRUST_CERT (default meta/verity/signer.cert.pem)"
	@echo "  pool                every producer of every board, both architectures, indexed into _out/debs"
	@echo "  package-gate        the package gate over that pool"
	@echo "  publish             the pool as the GitHub Release build-<commit12> of this commit"
	@echo "  kernel-config-test  every board's committed kernel config carries the shared floor (boot/common/kernel-config-test.sh)"
	@echo "  lint                shell hygiene of the tree"
	@echo "  check               lint, kernel-config-test and every board's own tests"

deps:
	bash tools/deps.sh fetch
deps-check:
	bash tools/deps.sh fetch --check
deps-bump:
	@test -n "$(DEP)" || { echo "error: DEP=<repository> is required, e.g. make deps-bump DEP=mica-boot" >&2; exit 1; }
	bash tools/deps.sh bump "$(DEP)" $(if $(DEP_TAG),--tag "$(DEP_TAG)")

build-env:
	bash build-env/build.sh

# The <board>-% delegation rules are pattern rules (unlisted in .PHONY, which
# takes no patterns): the delegated names are open-ended.
x64-%:
	$(MAKE) -C x64/bsp $*
virt-arm64-%:
	$(MAKE) -C virt-arm64/bsp $*
cx3576-%:
	$(MAKE) -C cx3576/bsp $*
s905x5m-%:
	$(MAKE) -C s905x5m/bsp $*

preflight:
	bash build-env/deb/preflight.sh

# Every producer this tree declares, for every architecture its producer.env
# names, read from build-env/deb/producers.sh rather than listed here.
pool: preflight
	@set -e; \
	bash build-env/deb/producers.sh | while read -r producer dir arches packages enablement; do \
	    for arch in $$(printf '%s' "$$arches" | tr ',' ' '); do \
	        echo "bash build-env/deb/build.sh --producer $$producer --arch $$arch"; \
	        bash build-env/deb/build.sh --producer "$$producer" --arch "$$arch"; \
	    done; \
	done
	bash build-env/deb/repo.sh --arch amd64
	bash build-env/deb/repo.sh --arch arm64

package-gate:
	bash build-env/deb/package-gate.sh

publish:
	bash build-env/deb/publish.sh

kernel-config-test:
	bash boot/common/kernel-config-test.sh x64 x64/bsp/kernel/config/x64.config x64/bsp/kernel/Dockerfile
	bash boot/common/kernel-config-test.sh virt-arm64 virt-arm64/bsp/kernel/config/virt-arm64.config virt-arm64/bsp/kernel/Dockerfile
	bash boot/common/kernel-config-test.sh cx3576 cx3576/bsp/kernel/config/kernel-cx3576z.config cx3576/bsp/kernel/configure.sh
	bash boot/common/kernel-config-test.sh s905x5m s905x5m/bsp/kernel/config/kernel-s905x5m.config s905x5m/bsp/kernel/Dockerfile

kernel-cmdline-test:
	bash cx3576/tests/kernel-cmdline-test.sh
mac-stable-test:
	bash cx3576/tests/mac-stable-test.sh
gadget-configfs-test:
	bash cx3576/tests/gadget-configfs-test.sh
flash-verify-test:
	bash cx3576/tests/cx3576-flash-verify-test.sh
wireless-test:
	bash s905x5m/tests/s905x5m-wireless.sh

lint:
	bash gate/shell-lint.sh

check: lint kernel-config-test kernel-cmdline-test mac-stable-test gadget-configfs-test flash-verify-test wireless-test
