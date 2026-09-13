# Build the virt-arm64 kernel.
#
# There is no U-Boot and no rootfs target here, which is the difference from
# boards/cx3576/bsp and the similarity to boards/x64/bsp: this board's firmware
# is AAVMF and it provides the boot chain, so the only thing compiled here is
# the kernel. And the kernel IS compiled, rather than taken from Debian,
# because the boot contract needs CONFIG_DM_INIT -- see kernel/versions.env.
.PHONY: all kernel kernel-config clean

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
BSP_OUT ?= ../../_out/virt-arm64


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
FROM_SH := ../../build-env/from.sh
UBUNTU_ARG := MICA_IMAGE_UBUNTU_2404=IMAGE_UBUNTU_2404

# Distribute the same public certificate bundle to every builder. Kernel builds
# never mint keys; development material is generated explicitly before building.
VERITY_TRUST_CERT ?= ../../meta/verity/signer.cert.pem
VERITY_TOOL := ../../boot/verity-tool.sh

all: kernel

# The kernel, its modules, the config it was built from and its release string.
# --build-context mos-common is not optional: the Dockerfile COPYs the shared
# floor from it and fails loudly without it, which is what stops a kernel from
# being built against a fragment nobody merged.
#
# No --platform and no builder requirement: the Dockerfile pins its build stage
# to $BUILDPLATFORM and cross-compiles with aarch64-linux-gnu-, so this runs
# natively on an amd64 host and needs neither binfmt_misc nor the mos-arm64
# docker-container builder.
kernel:
	TRUST_DIR="$$(bash $(VERITY_TOOL) stage "$(VERITY_TRUST_CERT)" "$(BSP_OUT)/verity-trust")" && \
	IMG="$$(bash $(FROM_SH) $(UBUNTU_ARG))" && \
	docker buildx build --build-context mos-common=../../boot/common \
	  --build-context "mos-trust=$$TRUST_DIR" \
	  -f kernel/Dockerfile --target artifact $$IMG \
	  $(if $(KERNEL_BUILDER),--builder $(KERNEL_BUILDER)) \
	  -o $(BSP_OUT)/kernel .
	@ls -la $(BSP_OUT)/kernel/

# Re-record config/virt-arm64.config from the fragments and the pinned source.
#
# It writes into the source tree on purpose. The recorded config IS a source
# file -- it is the reviewed build input, and the `kernel` target above refuses
# a build whose resolution differs from it -- so refreshing it is an edit that
# gets committed and read in a diff, which is the entire mechanism.
kernel-config:
	TRUST_DIR="$$(bash $(VERITY_TOOL) stage "$(VERITY_TRUST_CERT)" "$(BSP_OUT)/verity-trust")" && \
	IMG="$$(bash $(FROM_SH) $(UBUNTU_ARG))" && \
	docker buildx build --build-context mos-common=../../boot/common \
	  --build-context "mos-trust=$$TRUST_DIR" \
	  -f kernel/Dockerfile --target config $$IMG \
	  $(if $(KERNEL_BUILDER),--builder $(KERNEL_BUILDER)) \
	  -o kernel/config .
	@echo "recorded: kernel/config/virt-arm64.config ($$(grep -c . kernel/config/virt-arm64.config) lines)"

clean:
	rm -rf $(BSP_OUT)
