# Build the CX3576-Z BSP and flash the complete signed file-system image.
.PHONY: all uboot-mos kernel rkdeveloptool-macos flash-maskrom flash-mos \
	source-check clean

# WHERE THE ARTEFACTS GO. `_out/boards/<board>/`, not `out/` beside this file.
# `_out/` is the one directory every other build product in this repository
# lives in and the one a clean removes, and a BSP output sitting outside it is
# how `out/kernel/Image` stayed at its 2026-08-31 build for a week while
# boot/common/mos-required.fragment gained four symbols underneath it
# (RFCT-343). Overridable, because a build that wants to keep a tree aside
# should not have to edit this file.
#
# boards/<board>/deb/*/render.sh and stage.sh read the same default and accept
# the same override. It is a SEPARATE variable from BOARD_DIR on purpose:
# BOARD_DIR is the bsp SOURCE directory -- committed firmware, containers.env,
# this Makefile -- and conflating the two is what made "point BOARD_DIR at
# prebuilt artefacts" also repoint the firmware.
BSP_OUT ?= ../../_out/cx3576

# The complete factory image is assembled from independently signed components.
MICA_OUT ?= ../../_out/image
MICA_IMAGE ?= $(lastword $(sort $(wildcard $(MICA_OUT)/mos-cx3576-*.img)))

TOOLS_DIR ?= tools
THIRD_DIR ?= third
RKDEVELOPTOOL_LOCAL := $(TOOLS_DIR)/rkdeveloptool
RKDEVELOPTOOL ?= $(if $(wildcard $(RKDEVELOPTOOL_LOCAL)),$(RKDEVELOPTOOL_LOCAL),rkdeveloptool)
VENDOR_MINILOADER := uboot/MiniLoaderAll.bin
# Prefer coreutils sha256sum (Linux hosts and CI, no Perl needed); fall back
# to Perl/macOS shasum. Both accept the same `-c` checkfile format.
SHA256 := $(shell command -v sha256sum >/dev/null 2>&1 && echo sha256sum || echo "shasum -a 256")

# EVERY BASE IMAGE BELOW COMES FROM build-env/images.env. The
# four Dockerfiles this Makefile drives declare their FROM argument with NO
# default, so a recipe that forgot to pass one fails at `docker buildx build`
# with "base name should not be blank" rather than building against a tag.
#
# WHY IT IS CALLED IN THE RECIPE AND NOT ASSIGNED WITH $(shell ...). A `:=`
# assignment runs the command while make PARSES the file, discards its exit
# status and its stderr, and leaves the variable empty on failure -- so a broken
# pin would reach docker as a missing argument, and every target in this file
# would carry the failure whether or not it builds an image. Inside a recipe,
# `X="$$(...)" && docker ...` propagates: the substitution's non-zero status
# fails the assignment, the `&&` short-circuits, and make stops with the message
# from.sh printed. The one cost is that the value is computed per target, which
# is a file read.
FROM_SH := ../../build-env/from.sh
UBUNTU_ARG := MICA_IMAGE_UBUNTU_2404=IMAGE_UBUNTU_2404

# Distribute the same public certificate bundle to every builder. Kernel builds
# never mint keys; development material is generated explicitly before building.
VERITY_TRUST_CERT ?= ../../meta/verity/signer.cert.pem
FIT_TRUST_CERT ?=
VERITY_TOOL := ../../boot/verity-tool.sh
ALPINE_ARG := MICA_IMAGE_ALPINE_3_24_1=IMAGE_ALPINE_3_24_1

all: kernel uboot-mos

# `--build-context bsp-scripts=scripts --build-context mos-common=../../boot/common` is what lets the U-Boot target keep
# `uboot` as its build context while still reading bsp/scripts/.
# The kernel target's context is the board directory and reaches them with a
# plain COPY; widening this one to match would put the committed Wi-Fi firmware
# and the 9 MiB vendor MiniLoaderAll.bin into every U-Boot build's context.
# Fixed FIT policy with explicit public boot trust; no private signing input.
uboot-mos:
	TRUST_DIR="$$(bash $(VERITY_TOOL) stage "$(FIT_TRUST_CERT)" "$(BSP_OUT)/fit-trust")" && \
	IMG="$$(bash $(FROM_SH) $(UBUNTU_ARG))" && \
	docker buildx build --label ai-agent=true -t ai-agent/mos-cx-uboot \
	  --build-context bsp-scripts=scripts --build-context mos-common=../../boot/common --build-context "mos-boot-trust=$$TRUST_DIR" \
	  -f uboot/Dockerfile --target artifact-mos $$IMG \
	  $(if $(UBOOT_COMMIT),--build-arg UBOOT_COMMIT=$(UBOOT_COMMIT)) \
	  $(if $(RKBIN_COMMIT),--build-arg RKBIN_COMMIT=$(RKBIN_COMMIT)) \
	  -o $(BSP_OUT)/uboot-mos uboot

kernel:
	TRUST_DIR="$$(bash $(VERITY_TOOL) stage "$(VERITY_TRUST_CERT)" "$(BSP_OUT)/verity-trust")" && \
	IMG="$$(bash $(FROM_SH) $(UBUNTU_ARG))" && \
	docker buildx build --build-context mos-common=../../boot/common \
	  --build-context "mos-trust=$$TRUST_DIR" -f kernel/Dockerfile $$IMG \
	  $(if $(KERNEL_COMMIT),--build-arg KERNEL_COMMIT=$(KERNEL_COMMIT)) \
	  $(if $(KERNEL_EXPECT),--build-arg KERNEL_EXPECT=$(KERNEL_EXPECT)) \
	  -o $(BSP_OUT)/kernel .

# Build the native macOS flashing tool.
rkdeveloptool-macos:
	$(THIRD_DIR)/rkdeveloptool/build-macos.sh

# Reject CJK text in source and configuration files; Markdown is documentation.
source-check:
	@if git grep --untracked -I -n -P '(*UTF)[\x{3400}-\x{4dbf}\x{4e00}-\x{9fff}\x{f900}-\x{faff}]' \
		-- . ':(exclude)*.md'; then \
		echo 'error: CJK text is not allowed in source files' >&2; \
		exit 1; \
	else \
		rc=$$?; test "$$rc" -eq 1 || exit "$$rc"; \
	fi

# Full-system installation only. The board remains in Loader mode on any failure.
flash-mos:
	@test -n "$(MICA_IMAGE)" || { echo 'error: no timestamped cx3576 image found; set MICA_IMAGE explicitly' >&2; exit 1; }
	bash scripts/verify-flash.sh --check "$(MICA_IMAGE)"
	$(RKDEVELOPTOOL) wl 0 "$(MICA_IMAGE)"
	RKDEVELOPTOOL='$(RKDEVELOPTOOL)' bash scripts/verify-flash.sh "$(MICA_IMAGE)"
	$(RKDEVELOPTOOL) rd

flash-maskrom:
	@test -n "$(MICA_IMAGE)" || { echo 'error: no timestamped cx3576 image found; set MICA_IMAGE explicitly' >&2; exit 1; }
	bash scripts/verify-flash.sh --check "$(MICA_IMAGE)"
	$(SHA256) -c uboot/MiniLoaderAll.bin.sha256
	$(RKDEVELOPTOOL) db $(VENDOR_MINILOADER)
	$(MAKE) flash-mos MICA_IMAGE="$(MICA_IMAGE)" RKDEVELOPTOOL="$(RKDEVELOPTOOL)"

clean:
	rm -rf $(BSP_OUT)
