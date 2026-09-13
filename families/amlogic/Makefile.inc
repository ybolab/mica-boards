# The amlogic family's targets, included by <board>/bsp/Makefile after it
# sets BOARD. The family owns the kernel and U-Boot orchestration
# (kernel/Dockerfile, kernel/configure.sh, kernel/build.sh, uboot/Dockerfile)
# and the source pins (family.env); the board owns its configuration and
# fragments, device tree, patches, out-of-tree modules and the hooks the
# family calls (kernel/hooks/), and names its files in bsp.env. The U-Boot
# policy (uboot/build-mos.sh, uboot/config, uboot/dts, uboot/patches,
# uboot/blobs) stays in the board's uboot/ directory, the build context.
#
#   make kernel   -> $(BSP_OUT)/kernel/{Image,modules.tar,<dtb>,config,kernel.release,System.map,regdb-certs.pem}
#   make uboot    -> $(BSP_OUT)/uboot/ (the signed U-Boot, DDR.USB, the FIT tools)
ifeq ($(BOARD),)
$(error BOARD is not set; a board's bsp/Makefile sets it before including this file)
endif
FAMILIES_DIR := ../../families
FAMILY_DIR := $(FAMILIES_DIR)/amlogic
include $(FAMILY_DIR)/family.env
include bsp.env
BSP_OUT ?= ../../_out/$(BOARD)

FROM_SH := ../../build-env/from.sh
UBUNTU_ARG := MICA_IMAGE_UBUNTU_2404=IMAGE_UBUNTU_2404

VERITY_TRUST_CERT ?= ../../meta/verity/signer.cert.pem
FIT_TRUST_CERT ?=
VERITY_TOOL := ../../boot/verity-tool.sh

.PHONY: kernel uboot firmware clean
kernel:
	TRUST_DIR="$$(bash $(VERITY_TOOL) stage "$(VERITY_TRUST_CERT)" "$(BSP_OUT)/verity-trust")" && \
	IMG="$$(bash $(FROM_SH) $(UBUNTU_ARG))" && \
	docker buildx build --label ai-agent=true -t ai-agent/mos-$(BOARD)-kernel \
	  --build-context families=$(FAMILIES_DIR) \
	  --build-context mos-common=../../boot/common --build-context "mos-trust=$$TRUST_DIR" \
	  --build-arg KERNEL_REPO=$(KERNEL_REPO) --build-arg KERNEL_COMMIT=$(KERNEL_COMMIT) \
	  --build-arg KERNEL_EXPECT=$(KERNEL_EXPECT) --build-arg KERNEL_CONFIG=$(KERNEL_CONFIG) \
	  --build-arg "KERNEL_FRAGMENTS=$(KERNEL_FRAGMENTS)" \
	  --build-arg KERNEL_DTB=$(KERNEL_DTB) --build-arg KERNEL_DTB_ARTIFACT=$(KERNEL_DTB_ARTIFACT) \
	  -f $(FAMILY_DIR)/kernel/Dockerfile --target artifact $$IMG \
	  -o $(BSP_OUT)/kernel .

# Only public FIT trust enters the firmware builder.
uboot:
	TRUST_DIR="$$(bash $(VERITY_TOOL) stage "$(FIT_TRUST_CERT)" "$(BSP_OUT)/fit-trust")" && \
	IMG="$$(bash $(FROM_SH) $(UBUNTU_ARG))" && \
	docker buildx build --label ai-agent=true -t ai-agent/mos-$(BOARD)-uboot \
	  --build-context mos-common=../../boot/common --build-context "mos-boot-trust=$$TRUST_DIR" \
	  --build-arg UBOOT_REPO=$(UBOOT_REPO) --build-arg UBOOT_COMMIT=$(UBOOT_COMMIT) \
	  -f $(FAMILY_DIR)/uboot/Dockerfile $$IMG \
	  -o $(BSP_OUT)/uboot uboot

# What the family builds; a board adds its own (s905x5m: uboot-package).
firmware: uboot
clean:
	rm -rf $(BSP_OUT)
