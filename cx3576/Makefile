# mica-cx3576: the cx3576 board (Rockchip RK3576, signed FIT boot through U-Boot). The BSP build lives under bsp/,
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

.PHONY: help deps deps-check deps-bump build-env kernel kernel-config uboot-mos flash-mos flash-maskrom preflight pool package-gate publish kernel-config-test kernel-cmdline-test mac-stable-test gadget-configfs-test flash-verify-test lint check

help:
	@echo "  deps                fetch build-env/, boot/ and debian/ at their pins; deps-check reads without downloading"
	@echo "  deps-bump           DEP=mica-build-env|mica-boot [DEP_TAG=build-<commit12>] rewrites one pin"
	@echo "  build-env           the builder images, from the pins in build-env/images.env"
	@echo "  kernel              the board kernel into _out/bsp/kernel (VERITY_TRUST_CERT names the trust certificate it embeds; default meta/verity/signer.cert.pem)"
	@echo "  kernel-config       re-record bsp/kernel/config from the current fragments"
	@echo "  pool                every producer -- the board packages and mica-kernel-cx3576 -- indexed into _out/debs"
	@echo "  package-gate        the package gate over this repository's pool"
	@echo "  publish             the pool as the GitHub Release build-<commit12> of this commit"
	@echo "  kernel-config-test  the committed kernel config carries the shared floor (boot/common/kernel-config-test.sh)"
	@echo "  lint                shell hygiene of the tree"
	@echo "  check               lint, kernel-config-test, mac-stable-test, gadget-configfs-test, flash-verify-test"

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
uboot-mos:
	$(MAKE) -C bsp uboot-mos

# Flashing a built image over rkdeveloptool; MICA_IMAGE names the image the
# assembly produced (its _out/cx3576/image, or a copy).
flash-mos flash-maskrom:
	$(MAKE) -C bsp $@ MICA_IMAGE="$(MICA_IMAGE)"

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

# One architecture: this board builds for arm64 alone, and publish.sh takes
# both pools by default.
publish:
	bash build-env/deb/publish.sh --arch arm64

kernel-config-test:
	bash boot/common/kernel-config-test.sh cx3576 bsp/kernel/config/kernel-cx3576z.config bsp/kernel/configure.sh
mac-stable-test:
	bash tests/mac-stable-test.sh
gadget-configfs-test:
	bash tests/gadget-configfs-test.sh
flash-verify-test:
	bash tests/cx3576-flash-verify-test.sh
kernel-cmdline-test:
	bash tests/kernel-cmdline-test.sh

lint:
	bash gate/shell-lint.sh

check: lint kernel-config-test kernel-cmdline-test mac-stable-test gadget-configfs-test flash-verify-test
