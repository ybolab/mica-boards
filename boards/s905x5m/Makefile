# s905x5m: a board of the amlogic family (Amlogic S7D on the BM201, signed FIT
# boot through U-Boot, SD boot). The kernel and U-Boot orchestration and the
# source pins live in families/amlogic/; this file names the board, includes
# the family's targets and keeps what is the board's own: the Bluetooth
# bridge userland, the FIT tools image and the Amlogic recovery package.
BOARD := s905x5m
include ../../families/amlogic/Makefile.inc

.PHONY: fit-tools uboot-package uboot-package-test userland

# The recovery package is this board's firmware too.
firmware: uboot-package

DEBIAN_ARG := MICA_IMAGE_DEBIAN_TRIXIE=IMAGE_DEBIAN_TRIXIE
UBOOT_ARTIFACTS := $(BSP_OUT)/uboot/u-boot.bin.signed \
	$(BSP_OUT)/uboot/u-boot.bin.sd.bin.signed \
	$(BSP_OUT)/uboot/DDR.USB
UBOOT_PACKAGE_DIR := $(BSP_OUT)/uboot-package

userland:
	IMG="$$(bash $(FROM_SH) $(DEBIAN_ARG))" && \
	docker buildx build --label ai-agent=true -t ai-agent/mos-s905x5m-userland --platform linux/arm64 --target artifact \
	  -f userland/Dockerfile $$IMG -o $(BSP_OUT)/userland userland

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
	bash loader/package/test-manifest.sh loader/package

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
		-f loader/package/Dockerfile $$IMG \
		-o "$$tmp_output" loader/package; \
	test -s "$$tmp_output/update.img"; \
	cmp -s uboot/package/config/aml_sdc_burn.ini "$$tmp_output/aml_sdc_burn.ini"; \
	(cd "$$tmp_output" && sha256sum update.img > update.img.sha256); \
	rm -rf "$(UBOOT_PACKAGE_DIR)"; \
	mv "$$tmp_output" "$(UBOOT_PACKAGE_DIR)"; \
	trap - 0 1 2 3 15; \
	ls -l "$(UBOOT_PACKAGE_DIR)/update.img"; \
	cat "$(UBOOT_PACKAGE_DIR)/update.img.sha256"
