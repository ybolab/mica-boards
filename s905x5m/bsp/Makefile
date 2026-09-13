.PHONY: kernel uboot fit-tools uboot-package uboot-package-test userland

BSP_OUT ?= ../../_out/s905x5m
FROM_SH := ../../build-env/from.sh
UBUNTU_ARG := MICA_IMAGE_UBUNTU_2404=IMAGE_UBUNTU_2404
DEBIAN_ARG := MICA_IMAGE_DEBIAN_TRIXIE=IMAGE_DEBIAN_TRIXIE
UBOOT_ARTIFACTS := $(BSP_OUT)/uboot/u-boot.bin.signed \
	$(BSP_OUT)/uboot/u-boot.bin.sd.bin.signed \
	$(BSP_OUT)/uboot/DDR.USB
UBOOT_PACKAGE_DIR := $(BSP_OUT)/uboot-package

VERITY_TRUST_CERT ?= ../../meta/verity/signer.cert.pem
FIT_TRUST_CERT ?=
VERITY_TOOL := ../../boot/verity-tool.sh

kernel:
	TRUST_DIR="$$(bash $(VERITY_TOOL) stage "$(VERITY_TRUST_CERT)" "$(BSP_OUT)/verity-trust")" && \
	IMG="$$(bash $(FROM_SH) $(UBUNTU_ARG))" && \
	docker buildx build --label ai-agent=true -t ai-agent/mos-s905x5m-kernel \
	  --build-context mos-common=../../boot/common --build-context "mos-trust=$$TRUST_DIR" -f kernel/Dockerfile $$IMG \
	  $(if $(KERNEL_REPO),--build-arg KERNEL_REPO=$(KERNEL_REPO)) \
	  $(if $(KERNEL_COMMIT),--build-arg KERNEL_COMMIT=$(KERNEL_COMMIT)) \
	  $(if $(KERNEL_EXPECT),--build-arg KERNEL_EXPECT=$(KERNEL_EXPECT)) \
	  -o $(BSP_OUT)/kernel .

userland:
	IMG="$$(bash $(FROM_SH) $(DEBIAN_ARG))" && \
	docker buildx build --label ai-agent=true -t ai-agent/mos-s905x5m-userland --platform linux/arm64 --target artifact \
	  -f userland/Dockerfile $$IMG -o $(BSP_OUT)/userland userland

# Only public FIT trust enters the firmware builder.
uboot:
	TRUST_DIR="$$(bash $(VERITY_TOOL) stage "$(FIT_TRUST_CERT)" "$(BSP_OUT)/fit-trust")" && \
	IMG="$$(bash $(FROM_SH) $(UBUNTU_ARG))" && \
	docker buildx build --label ai-agent=true -t ai-agent/mos-s905x5m-uboot \
	  --build-context mos-common=../../boot/common --build-context "mos-boot-trust=$$TRUST_DIR" \
	  -f uboot/Dockerfile $$IMG \
	  $(if $(UBOOT_REPO),--build-arg UBOOT_REPO=$(UBOOT_REPO)) \
	  $(if $(UBOOT_COMMIT),--build-arg UBOOT_COMMIT=$(UBOOT_COMMIT)) \
	  -o $(BSP_OUT)/uboot uboot

fit-tools:
	@test -x "$(BSP_OUT)/uboot/tools/fit_check_sign"
	bash ../../boot/build-tools.sh
	docker build --label ai-agent=true -t ai-agent/mos-fit-tools-amd64 \
	  --build-arg MICA_BOOT_TOOLS=ai-agent/mos-boot-tools-amd64 \
	  --build-context fit-tools=$(BSP_OUT)/uboot/tools \
	  -f ../../boot/Dockerfile.fit ../../boot

# Packaging is a separate consumer of the section-3 U-Boot artifact interface.
# It deliberately does not rebuild U-Boot: first produce the three artifacts
# with `make uboot`, then package exactly those bytes.
uboot-package-test:
	bash uboot/package/test-manifest.sh uboot/package

uboot-package: uboot-package-test
	@set -eu; \
	for artifact in $(UBOOT_ARTIFACTS); do \
		[ -s "$$artifact" ] || { \
			printf 'error: missing U-Boot artifact: %s\\n' "$$artifact" >&2; \
			printf '%s\\n' '       run make uboot before make uboot-package' >&2; \
			exit 1; \
		}; \
	done; \
	mkdir -p "$(BSP_OUT)"; \
	tmp_output="$$(mktemp -d $(BSP_OUT)/.uboot-package.XXXXXX)"; \
	trap 'rm -rf "$$tmp_output"' 0 1 2 3 15; \
	IMG="$$(bash $(FROM_SH) $(DEBIAN_ARG))"; \
	docker buildx build --label ai-agent=true -t ai-agent/mos-s905x5m-recovery --platform linux/386 --target bootloader-artifact \
		--build-context uboot-artifacts=$(BSP_OUT)/uboot \
		-f uboot/package/Dockerfile $$IMG \
		-o "$$tmp_output" uboot/package; \
	test -s "$$tmp_output/update.img"; \
	cmp -s uboot/package/config/aml_sdc_burn.ini "$$tmp_output/aml_sdc_burn.ini"; \
	(cd "$$tmp_output" && sha256sum update.img > update.img.sha256); \
	rm -rf "$(UBOOT_PACKAGE_DIR)"; \
	mv "$$tmp_output" "$(UBOOT_PACKAGE_DIR)"; \
	trap - 0 1 2 3 15; \
	ls -l "$(UBOOT_PACKAGE_DIR)/update.img"; \
	cat "$(UBOOT_PACKAGE_DIR)/update.img.sha256"
