# mica-s905x5m: the s905x5m board (Amlogic S905X5M, signed FIT boot through U-Boot). The BSP build lives under bsp/,
# the producers under deb/; this file only routes.

# THE SOURCE DEPENDENCIES, before anything else: build-env/ (mica-build-env)
# is the substrate every target reaches through and boot/ (mica-boot) is the
# boot tooling the BSP build and the producers take. Both are fetched at
# their pins (deps/sources/*.json) by tools/deps.sh and are gitignored.
# `make deps` is the one target that may run without them.
ifeq ($(filter deps,$(MAKECMDGOALS)),)
ifeq ($(wildcard build-env/from.sh),)
$(error build-env/ is empty: the build substrate is fetched at its pin from ybolab/mica-build-env. Run: make deps)
endif
ifeq ($(wildcard boot/verity-tool.sh),)
$(error boot/ is empty: the boot tooling is fetched at its pin from ybolab/mica-boot. Run: make deps)
endif
endif

.PHONY: help deps deps-check deps-bump build-env kernel kernel-config uboot userland fit-tools uboot-package uboot-package-test preflight pool package-gate publish kernel-config-test wireless-test lint check

help:
	@echo "  deps                fetch build-env/ and boot/ at their pins; deps-check reads without downloading"
	@echo "  deps-bump           DEP=mica-build-env|mica-boot [DEP_TAG=build-<commit12>] rewrites one pin"
	@echo "  build-env           the builder images, from the pins in build-env/images.env"
	@echo "  kernel              the board kernel into _out/bsp/kernel (VERITY_TRUST_CERT names the trust certificate it embeds; default meta/verity/signer.cert.pem)"
	@echo "  kernel-config       re-record bsp/kernel/config from the current fragments"
	@echo "  pool                every producer -- the board packages and mica-kernel-s905x5m -- indexed into _out/debs"
	@echo "  package-gate        the package gate over this repository's pool"
	@echo "  publish             the pool as the GitHub Release build-<commit12> of this commit"
	@echo "  kernel-config-test  the committed kernel config carries the shared floor (boot/common/kernel-config-test.sh)"
	@echo "  lint                shell hygiene of the tree"
	@echo "  check               lint, kernel-config-test, wireless-test"

deps:
	bash tools/deps.sh fetch
deps-check:
	bash tools/deps.sh fetch --check
deps-bump:
	@test -n "$(DEP)" || { echo "error: DEP=<repository> is required, e.g. make deps-bump DEP=mica-boot" >&2; exit 1; }
	bash tools/deps.sh bump "$(DEP)" $(if $(DEP_TAG),--tag "$(DEP_TAG)")

build-env:
	bash build-env/build.sh

kernel:
	$(MAKE) -C bsp kernel
kernel-config:
	$(MAKE) -C bsp kernel-config
uboot userland fit-tools uboot-package uboot-package-test:
	$(MAKE) -C bsp $@

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
	bash build-env/deb/repo.sh --arch arm64

package-gate:
	bash build-env/deb/package-gate.sh

publish:
	bash build-env/deb/publish.sh

kernel-config-test:
	bash boot/common/kernel-config-test.sh s905x5m bsp/kernel/config/kernel-s905x5m.config bsp/kernel/Dockerfile
wireless-test:
	bash tests/s905x5m-wireless.sh

lint:
	bash gate/shell-lint.sh

check: lint kernel-config-test wireless-test
