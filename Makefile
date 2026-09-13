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

# The boards, discovered: a directory with a board.env. Nothing here names one.
BOARDS := $(patsubst boards/%/board.env,%,$(wildcard boards/*/board.env))

.PHONY: help deps deps-check deps-bump build-env preflight pool package-gate publish board-contract-test kernel-config-test kernel-cmdline-test bench-collector-test mac-stable-test can-network-test gadget-configfs-test flash-verify-test wireless-test lint check

help:
	@echo "  deps                fetch build-env/ and boot/ at their pins; deps-check reads without downloading"
	@echo "  deps-bump           DEP=<repository> [DEP_TAG=build-<commit12>] rewrites one pin"
	@echo "  build-env           the builder images, from the pins in build-env/images.env"
	@echo "  <board>-<target>    delegate to <board>/bsp (kernel, kernel-config, firmware; a family's own: uboot-mos, uboot, uboot-package, userland)"
	@echo "  kernels, firmware   the same for every discovered board (what release.yml builds)"
	@echo "                      a kernel embeds the verity trust certificate: VERITY_TRUST_CERT (default meta/verity/signer.cert.pem)"
	@echo "  pool                every producer of every board, both architectures, indexed into _out/debs"
	@echo "  package-gate        the package gate over that pool"
	@echo "  publish             the pool and every board's bundle into the mica-boards package, as pool.<arch>.build-<commit12> and board.<board>.build-<commit12>"
	@echo "  board-contract-test every board declares BOARD_FEATURES, BOARD_FAMILY and IMAGE_KINDS, ships manifests/ and stages them into its bundle"
	@echo "  kernel-config-test  every board's committed kernel config carries the shared floor (boot/common/kernel-config-test.sh)"
	@echo "  lint                shell hygiene of the tree"
	@echo "  check               lint, board-contract-test, kernel-config-test and every board's own tests"

deps:
	bash tools/deps.sh fetch
deps-check:
	bash tools/deps.sh fetch --check
deps-bump:
	@test -n "$(DEP)" || { echo "error: DEP=<repository> is required, e.g. make deps-bump DEP=mica-boot" >&2; exit 1; }
	bash tools/deps.sh bump "$(DEP)" $(if $(DEP_TAG),--tag "$(DEP_TAG)")

build-env:
	bash build-env/build.sh

# The <board>-% delegation rules, one per discovered board (pattern rules,
# unlisted in .PHONY, which takes no patterns): the delegated names are
# open-ended, and a new board gets its rule the day its board.env lands.
define board_delegation
$(1)-%:
	$$(MAKE) -C boards/$(1) $$*
endef
$(foreach b,$(BOARDS),$(eval $(call board_delegation,$(b))))

# Every discovered board's kernel, and every board's firmware where its family
# has one: what a release builds, with no board typed into a workflow.
.PHONY: kernels firmware
kernels: $(BOARDS:%=%-kernel)
firmware: $(BOARDS:%=%-firmware)

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
	bash tools/publish-boards.sh

board-contract-test:
	bash tests/board-contract-test.sh

kernel-config-test:
	bash tools/kernel-config-test.sh

kernel-cmdline-test:
	bash boards/cx3576/tests/kernel-cmdline-test.sh
bench-collector-test:
	bash boards/cx3576/tests/bench/collector-test.sh
mac-stable-test:
	bash boards/cx3576/tests/mac-stable-test.sh
can-network-test:
	bash boards/cx3576/tests/can-network-test.sh
gadget-configfs-test:
	bash boards/cx3576/tests/gadget-configfs-test.sh
flash-verify-test:
	bash boards/cx3576/tests/cx3576-flash-verify-test.sh
wireless-test:
	bash boards/s905x5m/tests/s905x5m-wireless.sh

lint:
	bash tests/shell-lint.sh

check: lint board-contract-test kernel-config-test kernel-cmdline-test bench-collector-test mac-stable-test can-network-test gadget-configfs-test flash-verify-test wireless-test
