# Build the x64 kernel.
#
# There is no U-Boot and no rootfs target here, and that is the difference from
# boards/cx3576/bsp: a UEFI machine's firmware provides the boot chain, so the
# only thing this board compiles is its kernel. boards/x64/board.env used to
# say there was no BSP behind this board at all; that stopped being true with
# PLAN-074, and the layout file says so now.
.PHONY: all kernel kernel-config clean

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
BSP_OUT ?= ../../../_out/boards/x64


# EVERY BASE IMAGE COMES FROM build-env/images.env. The Dockerfile declares its
# FROM argument with NO default, so a recipe that forgot to pass one fails at
# `docker buildx build` with "base name should not be blank" rather than
# building against a floating tag.
#
# Called in the recipe and not assigned with $(shell ...), for the reason
# boards/cx3576/bsp/Makefile gives at length: a `:=` assignment runs the
# command while make PARSES the file, discards its exit status and its stderr,
# and leaves the variable empty on failure. Inside a recipe the `&&`
# short-circuits and make stops with from.sh's own message.
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

all: kernel

# The kernel, its modules, the config it was built from and its release string.
# --build-context mos-common is not optional: the Dockerfile COPYs the shared
# floor from it and fails loudly without it, which is what stops a kernel from
# being built against a fragment nobody merged.
kernel:
	bash $(GEN_KEYS) --if-absent --domain verity
	IMG="$$(bash $(FROM_SH) $(UBUNTU_ARG))" && \
	docker buildx build --build-context mos-common=../../common \
	  --build-context mos-trust=$(TRUST_DIR) \
	  -f kernel/Dockerfile --target artifact $$IMG \
	  $(if $(KERNEL_BUILDER),--builder $(KERNEL_BUILDER)) \
	  -o $(BSP_OUT)/kernel .
	@ls -la $(BSP_OUT)/kernel/

# Re-record config/x64.config from the fragments and the pinned source.
#
# It writes into the source tree on purpose. The recorded config IS a source
# file -- it is the reviewed build input, and the `kernel` target above refuses
# a build whose resolution differs from it -- so refreshing it is an edit that
# gets committed and read in a diff, which is the entire mechanism.
kernel-config:
	bash $(GEN_KEYS) --if-absent --domain verity
	IMG="$$(bash $(FROM_SH) $(UBUNTU_ARG))" && \
	docker buildx build --build-context mos-common=../../common \
	  --build-context mos-trust=$(TRUST_DIR) \
	  -f kernel/Dockerfile --target config $$IMG \
	  $(if $(KERNEL_BUILDER),--builder $(KERNEL_BUILDER)) \
	  -o kernel/config .
	@echo "recorded: kernel/config/x64.config ($$(grep -c . kernel/config/x64.config) lines)"

clean:
	rm -rf $(BSP_OUT)
