# The uefi family's targets, included by <board>/bsp/Makefile after it sets
# BOARD. One kernel Dockerfile serves every board of the family; what differs
# per board is its architecture (read from ../board.env) and its own
# kernel/config/ and kernel/versions.env, which are the build context.
#
#   make kernel          -> $(BSP_OUT)/kernel/{bzImage|Image,modules.tar,config,kernel.release}
#   make kernel-config   -> re-records kernel/config/$(BOARD).config from this build
#
# WHERE THE ARTEFACTS GO. `_out/<board>/`, not `out/` beside this file:
# `_out/` is the one directory every other build product in this repository
# lives in and the one a clean removes (RFCT-343 is what an output outside it
# cost). Overridable, because a build that wants to keep a tree aside should
# not have to edit this file.
ifeq ($(BOARD),)
$(error BOARD is not set; a board's bsp/Makefile sets it before including this file)
endif
FAMILY_DIR := ../../families/uefi
include $(FAMILY_DIR)/family.env
BSP_OUT ?= ../../_out/$(BOARD)

# EVERY BASE IMAGE COMES FROM build-env/images.env. The Dockerfile declares its
# FROM argument with NO default, so a recipe that forgot to pass one fails at
# `docker buildx build` with "base name should not be blank" rather than
# building against a floating tag. Called in the recipe and not assigned with
# $(shell ...): a `:=` assignment runs the command while make PARSES the file,
# discards its exit status and leaves the variable empty on failure.
FROM_SH := ../../build-env/from.sh
UBUNTU_ARG := MICA_IMAGE_UBUNTU_2404=IMAGE_UBUNTU_2404

# The same public certificate bundle to every builder. Kernel builds never
# mint keys; development material is generated explicitly before building.
VERITY_TRUST_CERT ?= ../../meta/verity/signer.cert.pem
VERITY_TOOL := ../../boot/verity-tool.sh

# The architecture table of the family: what a UEFI kernel of each
# architecture is called, where Kbuild leaves it, which defconfig it starts
# from and what the toolchain needs to cross to it. Keyed by the board's
# MICA_ARCH, read here from board.env because that file is the one statement
# of a board's architecture. A missing or unknown value is refused by name.
MICA_ARCH := $(shell sed -n 's/^MICA_ARCH=//p' ../board.env)
ifeq ($(MICA_ARCH),amd64)
KERNEL_ARGS := --build-arg KERNEL_DEFCONFIG=x86_64_defconfig \
  --build-arg KERNEL_IMAGE=bzImage --build-arg KERNEL_IMAGE_PATH=arch/x86/boot/bzImage \
  --build-arg KERNEL_MAKE_ENV= --build-arg KERNEL_CROSS_PACKAGES=
else ifeq ($(MICA_ARCH),arm64)
KERNEL_ARGS := --build-arg KERNEL_DEFCONFIG=defconfig \
  --build-arg KERNEL_IMAGE=Image --build-arg KERNEL_IMAGE_PATH=arch/arm64/boot/Image \
  --build-arg "KERNEL_MAKE_ENV=ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-" \
  --build-arg "KERNEL_CROSS_PACKAGES=gcc-aarch64-linux-gnu libc6-dev-arm64-cross"
else
$(error ../board.env declares MICA_ARCH='$(MICA_ARCH)'; the uefi family builds amd64 and arm64)
endif

KERNEL_BUILD = TRUST_DIR="$$(bash $(VERITY_TOOL) stage "$(VERITY_TRUST_CERT)" "$(BSP_OUT)/verity-trust")" && \
	IMG="$$(bash $(FROM_SH) $(UBUNTU_ARG))" && \
	docker buildx build --build-context mos-common=../../boot/common \
	  --build-context "mos-trust=$$TRUST_DIR" \
	  --build-arg BOARD=$(BOARD) --build-arg KERNEL_SOURCE=$(KERNEL_SOURCE) $(KERNEL_ARGS) \
	  -f $(FAMILY_DIR)/kernel/Dockerfile $$IMG \
	  $(if $(KERNEL_BUILDER),--builder $(KERNEL_BUILDER))

.PHONY: kernel kernel-config clean
kernel:
	$(KERNEL_BUILD) --target artifact -o $(BSP_OUT)/kernel kernel
	@ls -la $(BSP_OUT)/kernel/

# Re-record kernel/config/$(BOARD).config from the fragments and the pinned
# source. It writes into the source tree on purpose: the recorded config IS a
# source file -- the reviewed build input the `kernel` target refuses to
# differ from -- so refreshing it is an edit that gets committed and read in
# a diff, which is the entire mechanism.
kernel-config:
	$(KERNEL_BUILD) --target config -o kernel/config kernel
	@echo "recorded: kernel/config/$(BOARD).config ($$(grep -c . kernel/config/$(BOARD).config) lines)"

clean:
	rm -rf $(BSP_OUT)
