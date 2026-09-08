# Build and flash the CX3576-Z Alpine image.
# Layout: U-Boot at LBA 64, boot at 16 MiB, and rootfs at 80 MiB.
.PHONY: all uboot uboot-mos kernel rootfs image rkdeveloptool-macos flash flash-maskrom flash-mos flash-rootfs-offline \
	source-check clean

# WHERE THE ARTEFACTS GO. `_out/boards/<board>/`, not `out/` beside this file.
# `_out/` is the one directory every other build product in this repository
# lives in and the one a clean removes, and a BSP output sitting outside it is
# how `out/kernel/Image` stayed at its 2026-08-31 build for a week while
# boards/common/mos-required.fragment gained four symbols underneath it
# (RFCT-343). Overridable, because a build that wants to keep a tree aside
# should not have to edit this file.
#
# boards/<board>/deb/*/render.sh and stage.sh read the same default and accept
# the same override. It is a SEPARATE variable from BOARD_DIR on purpose:
# BOARD_DIR is the bsp SOURCE directory -- committed firmware, containers.env,
# this Makefile -- and conflating the two is what made "point BOARD_DIR at
# prebuilt artefacts" also repoint the firmware.
BSP_OUT ?= ../../../_out/boards/cx3576

# WHERE THE PRODUCT IMAGE IS, for `flash-mos`. `_out/<board>/` is the top-level
# build's output directory -- `make os-image-cx3576` writes it -- and it is
# neither BSP_OUT nor BOARD_DIR. This Makefile is the only place in the tree
# that knows how to talk to the board, which is why the target for the mos
# image is here and not at the top level; the image it writes is not this
# directory's output, which is why the path is its own variable.
#
# The file name is READ from the layout, never copied into a second place:
# board.env owns IMAGE_LATEST_NAME and says so at its head. $(shell ...) here
# rather than in a recipe, unlike FROM_SH below, because the value is a name and
# not a command: it is expanded only when a flash target uses MOS_IMAGE, and an
# unreadable board.env stops make with the $(error) rather than silently
# handing rkdeveloptool a path ending in a slash.
MOS_OUT ?= ../../../_out/cx3576
MOS_IMAGE_NAME = $(or $(shell . ../board.env && printf '%s' "$$IMAGE_LATEST_NAME"),$(error cannot read IMAGE_LATEST_NAME from ../board.env))
MOS_IMAGE ?= $(MOS_OUT)/$(MOS_IMAGE_NAME)


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
FROM_SH := ../../../build-env/from.sh
UBUNTU_ARG := MOS_IMAGE_UBUNTU_2404=IMAGE_UBUNTU_2404

# THE VERITY CONTENT ANCHOR, minted if absent and passed as a named context.
# meta/ is gitignored, so a fresh checkout has no anchor and the kernel build
# would fail at its COPY -- the same shape `rootfs/build.sh` already handles for
# the RAUC keyring, and handled the same way: the generator writes a
# development-grade pair when there is none and says so loudly, and an operator
# who placed production material there keeps it. Only signer.cert.pem is read;
# the private half is never in a build context.
GEN_KEYS := ../../../pkgs/rauc/gen-dev-keys.sh
TRUST_DIR := ../../../meta/verity
ALPINE_ARG := MOS_IMAGE_ALPINE_3_24_1=IMAGE_ALPINE_3_24_1

all: image

# `--build-context bsp-scripts=scripts` is what lets the U-Boot target keep
# `uboot` as its build context while still reading boards/cx3576/bsp/scripts/.
# The kernel target's context is the board directory and reaches them with a
# plain COPY; widening this one to match would put the committed Wi-Fi firmware
# and the 9 MiB vendor MiniLoaderAll.bin into every U-Boot build's context.
uboot:
	IMG="$$(bash $(FROM_SH) $(UBUNTU_ARG))" && \
	docker buildx build --build-context bsp-scripts=scripts -f uboot/Dockerfile $$IMG \
	  $(if $(UBOOT_COMMIT),--build-arg UBOOT_COMMIT=$(UBOOT_COMMIT)) \
	  $(if $(RKBIN_COMMIT),--build-arg RKBIN_COMMIT=$(RKBIN_COMMIT)) \
	  -o $(BSP_OUT)/uboot uboot

# mos A/B variant (persistent redundant env + boot.scr contract); consumed by
# the mos image pipeline, while the debug variant above stays on alpine.
uboot-mos:
	IMG="$$(bash $(FROM_SH) $(UBUNTU_ARG))" && \
	docker buildx build --build-context bsp-scripts=scripts -f uboot/Dockerfile --target artifact-mos $$IMG \
	  $(if $(UBOOT_COMMIT),--build-arg UBOOT_COMMIT=$(UBOOT_COMMIT)) \
	  $(if $(RKBIN_COMMIT),--build-arg RKBIN_COMMIT=$(RKBIN_COMMIT)) \
	  -o $(BSP_OUT)/uboot-mos uboot

kernel:
	bash $(GEN_KEYS) --if-absent --domain verity
	IMG="$$(bash $(FROM_SH) $(UBUNTU_ARG))" && \
	docker buildx build --build-context mos-common=../../common \
	  --build-context mos-trust=$(TRUST_DIR) -f kernel/Dockerfile $$IMG \
	  $(if $(KERNEL_COMMIT),--build-arg KERNEL_COMMIT=$(KERNEL_COMMIT)) \
	  $(if $(KERNEL_EXPECT),--build-arg KERNEL_EXPECT=$(KERNEL_EXPECT)) \
	  -o $(BSP_OUT)/kernel .

rootfs: kernel
	IMG="$$(bash $(FROM_SH) $(ALPINE_ARG) $(UBUNTU_ARG))" && \
	docker buildx build -f rootfs/alpine/Dockerfile $$IMG \
	  --platform linux/arm64 \
	  --build-context kernel-out=$(BSP_OUT)/kernel \
	  --build-context firmware=rootfs/firmware \
	  -o $(BSP_OUT)/rootfs rootfs/alpine

image: uboot rootfs
	IMG="$$(bash $(FROM_SH) $(UBUNTU_ARG))" && \
	docker buildx build -f Dockerfile.alpine --target artifact $$IMG \
	  --build-context bsp-out=$(BSP_OUT) \
	  -o $(BSP_OUT) .
	@cd $(BSP_OUT) && $(SHA256) disk.img > disk.img.sha256
	@ls -la $(BSP_OUT)/disk.img
	@cat $(BSP_OUT)/disk.img.sha256

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

# Read the WHOLE written image back off the board and compare it with the file
# that was written. $(1) is that file.
#
# It used to read back the first 16 MiB, and everything that decides whether the
# machine runs is past it: board.env puts boot-a at 18 MiB and rootfs-a at 146
# MiB. A flash reported success and left a hole 22 MiB past the last verified
# byte; the board booted a kernel assembled from two builds and died in
# paging_init (docs/task/RFCT-351.md, closed by docs/task/RFCT-353.md). The
# reasoning that earned the boot area its read-back is intact and still runs
# first -- it is the first thing scripts/verify-flash.sh reads, and its comment
# moved there with it.
#
# The arithmetic lives in the script rather than in this macro because a
# recipe line is not testable and a script driven by a stub rkdeveloptool is:
# tests/cx3576-flash-verify-test.sh drives these targets with one, and checks
# the arguments, the sector arithmetic against board.env, and that a hole in the
# image turns the run red before `rd` reboots the board into it.
define verify-written-image
	RKDEVELOPTOOL='$(RKDEVELOPTOOL)' bash scripts/verify-flash.sh $(1)
endef

# Flash the complete image while the board is in Loader mode.
flash:
	@echo "WARNING: Keep board power and USB connected until rkdeveloptool rd completes."
	$(RKDEVELOPTOOL) wl 0 $(BSP_OUT)/disk.img
	$(call verify-written-image,$(BSP_OUT)/disk.img)
	$(RKDEVELOPTOOL) rd

# Recover from Maskrom with the pinned vendor Loader, then flash the full image.
flash-maskrom:
	@echo "WARNING: Keep board power and USB connected until rkdeveloptool rd completes."
	$(SHA256) -c uboot/MiniLoaderAll.bin.sha256
	$(RKDEVELOPTOOL) db $(VENDOR_MINILOADER)
	$(RKDEVELOPTOOL) wl 0 $(BSP_OUT)/disk.img
	$(call verify-written-image,$(BSP_OUT)/disk.img)
	$(RKDEVELOPTOOL) rd

# Flash the mos PRODUCT image -- the A/B image `make os-image-cx3576` builds,
# not the Alpine demo image the two targets above write.
#
# It existed only as a paragraph in docs/user/install.md telling a human to
# reach for rkdeveloptool by hand, which meant the image the fleet actually
# runs was the one image with no read-back at all -- and it is the path the
# board of docs/task/RFCT-351.md took. Same three steps and the same
# verification as `flash`; MOS_IMAGE selects a build other than the latest.
flash-mos:
	@echo "WARNING: Keep board power and USB connected until rkdeveloptool rd completes."
	$(RKDEVELOPTOOL) wl 0 $(MOS_IMAGE)
	$(call verify-written-image,$(MOS_IMAGE))
	$(RKDEVELOPTOOL) rd

# Flash only rootfs when the kernel and partition layout are unchanged.
flash-rootfs-offline:
	@echo "WARNING: Keep board power and USB connected until rkdeveloptool rd completes."
	$(RKDEVELOPTOOL) wl 163840 $(BSP_OUT)/rootfs/rootfs.img
	$(RKDEVELOPTOOL) rd

clean:
	rm -rf $(BSP_OUT)
