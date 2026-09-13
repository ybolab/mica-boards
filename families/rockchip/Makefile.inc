# The rockchip family's targets, included by boards/<board>/Makefile after it
# sets BOARD. The family owns the kernel and U-Boot orchestration
# (kernel/Dockerfile, kernel/configure.sh, kernel/build.sh, uboot/Dockerfile)
# and the source pins (family.env); the board owns its configuration, device
# tree, patches, firmware and the hooks the family calls (kernel/hooks/), and
# names its files in bsp.env. The U-Boot policy scripts (uboot/build.sh,
# uboot/build-mos.sh, uboot/tests/) stay in the board: they state that
# board's boot behaviour.
#
#   make kernel      -> $(BSP_OUT)/kernel/{Image,config,System.map,kernel.release,modules.tar,<dtb>,regdb-certs.pem}
#   make uboot-mos   -> $(BSP_OUT)/uboot-mos/ (u-boot-rockchip.bin, the FIT tools, mos.config)
#
# WHERE THE ARTEFACTS GO. `_out/<board>/`, the one directory every build
# product lives in and a clean removes (RFCT-343); overridable.
ifeq ($(BOARD),)
$(error BOARD is not set; a board's Makefile sets it before including this file)
endif
FAMILIES_DIR := ../../families
FAMILY_DIR := $(FAMILIES_DIR)/rockchip
include $(FAMILY_DIR)/family.env
include bsp.env
BSP_OUT ?= ../../_out/$(BOARD)

# EVERY BASE IMAGE COMES FROM build-env/images.env, resolved in the recipe
# and not with $(shell ...), so a broken pin stops make with from.sh's own
# message instead of reaching docker as an empty argument.
FROM_SH := ../../build-env/from.sh
UBUNTU_ARG := MICA_IMAGE_UBUNTU_2404=IMAGE_UBUNTU_2404

# The same public certificate bundles to every builder. Kernel and U-Boot
# builds never mint keys; development material is generated explicitly
# before building.
VERITY_TRUST_CERT ?= ../../meta/verity/signer.cert.pem
FIT_TRUST_CERT ?=
VERITY_TOOL := ../../boot/verity-tool.sh

.PHONY: kernel uboot-mos firmware clean
kernel:
	TRUST_DIR="$$(bash $(VERITY_TOOL) stage "$(VERITY_TRUST_CERT)" "$(BSP_OUT)/verity-trust")" && \
	IMG="$$(bash $(FROM_SH) $(UBUNTU_ARG))" && \
	docker buildx build --build-context families=$(FAMILIES_DIR) \
	  --build-context mos-common=../../boot/common --build-context "mos-trust=$$TRUST_DIR" \
	  --build-arg KERNEL_REPO=$(KERNEL_REPO) --build-arg KERNEL_COMMIT=$(KERNEL_COMMIT) \
	  --build-arg KERNEL_EXPECT=$(KERNEL_EXPECT) --build-arg KERNEL_CONFIG=$(KERNEL_CONFIG) \
	  --build-arg KERNEL_DTB=$(KERNEL_DTB) --build-arg KERNEL_DTB_ARTIFACT=$(KERNEL_DTB_ARTIFACT) \
	  -f $(FAMILY_DIR)/kernel/Dockerfile --target artifact $$IMG \
	  -o $(BSP_OUT)/kernel .

# Fixed FIT policy with explicit public boot trust; no private signing input.
# The context is the board's uboot/ directory (its policy scripts, patches,
# tests and the vendor loader); the shared fetch and patch scripts arrive
# through the `bsp-scripts` context so the context need not widen to the
# whole board directory with its committed firmware.
uboot-mos:
	TRUST_DIR="$$(bash $(VERITY_TOOL) stage "$(FIT_TRUST_CERT)" "$(BSP_OUT)/fit-trust")" && \
	IMG="$$(bash $(FROM_SH) $(UBUNTU_ARG))" && \
	docker buildx build --label ai-agent=true -t ai-agent/mos-$(BOARD)-uboot \
	  --build-context bsp-scripts=$(FAMILIES_DIR)/common/scripts \
	  --build-context mos-common=../../boot/common --build-context "mos-boot-trust=$$TRUST_DIR" \
	  --build-arg UBOOT_REPO=$(UBOOT_REPO) --build-arg UBOOT_COMMIT=$(UBOOT_COMMIT) \
	  --build-arg RKBIN_REPO=$(RKBIN_REPO) --build-arg RKBIN_COMMIT=$(RKBIN_COMMIT) \
	  --build-arg DDR_BLOB=$(DDR_BLOB) --build-arg BL31_BLOB=$(BL31_BLOB) \
	  --build-arg UBOOT_DEFCONFIG=$(UBOOT_DEFCONFIG) \
	  -f $(FAMILY_DIR)/uboot/Dockerfile --target artifact-mos $$IMG \
	  -o $(BSP_OUT)/uboot-mos loader

firmware: uboot-mos
clean:
	rm -rf $(BSP_OUT)
