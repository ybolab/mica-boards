.PHONY: kernel uboot uboot-package uboot-package-test emmc-package emmc-package-test \
	emmc-installer emmc-installer-test userland

BSP_OUT ?= ../../../_out/boards/s905x5m
FROM_SH := ../../../build-env/from.sh
UBUNTU_ARG := MOS_IMAGE_UBUNTU_2404=IMAGE_UBUNTU_2404
DEBIAN_ARG := MOS_IMAGE_DEBIAN_TRIXIE=IMAGE_DEBIAN_TRIXIE
UBOOT_ARTIFACTS := $(BSP_OUT)/uboot/u-boot.bin.signed \
	$(BSP_OUT)/uboot/u-boot.bin.sd.bin.signed \
	$(BSP_OUT)/uboot/DDR.USB
UBOOT_PACKAGE_DIR := $(BSP_OUT)/uboot-package
EMMC_PACKAGE_DIR := $(BSP_OUT)/emmc-package
EMMC_INSTALLER_DIR := $(BSP_OUT)/emmc-installer
EMMC_INSTALLER_PACKAGE ?=
# This is the only image producer the complete package consumes. Its p1 is an
# SD-only bridge, so emmc-package extracts only the typed mos-owned ranges and
# never reuses that byte range as an eMMC payload.
EMMC_SD_IMAGE ?= ../../../_out/s905x5m/s905x5m-mos-sd-latest.img

kernel:
	IMG="$$(bash $(FROM_SH) $(UBUNTU_ARG))" && \
	docker buildx build --build-context mos-common=../../common -f kernel/Dockerfile $$IMG \
	  $(if $(KERNEL_REPO),--build-arg KERNEL_REPO=$(KERNEL_REPO)) \
	  $(if $(KERNEL_COMMIT),--build-arg KERNEL_COMMIT=$(KERNEL_COMMIT)) \
	  $(if $(KERNEL_EXPECT),--build-arg KERNEL_EXPECT=$(KERNEL_EXPECT)) \
	  -o $(BSP_OUT)/kernel .

userland:
	IMG="$$(bash $(FROM_SH) $(DEBIAN_ARG))" && \
	docker buildx build --platform linux/arm64 --target artifact \
	  -f userland/Dockerfile $$IMG -o $(BSP_OUT)/userland userland

# The default U-Boot artifact stage includes the section 5 contract gate. It
# exports only when board-owned requirements pass; the separately tracked FIT
# signing debt remains a loud warning rather than a silent acceptance claim.
uboot:
	IMG="$$(bash $(FROM_SH) $(UBUNTU_ARG))" && \
	docker buildx build -f uboot/Dockerfile $$IMG \
	  $(if $(UBOOT_REPO),--build-arg UBOOT_REPO=$(UBOOT_REPO)) \
	  $(if $(UBOOT_COMMIT),--build-arg UBOOT_COMMIT=$(UBOOT_COMMIT)) \
	  -o $(BSP_OUT)/uboot uboot

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
	docker buildx build --platform linux/386 --target artifact \
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

# Complete recovery package: consume the existing SD assembler's bytes, then
# package them with the RFCT-928 Amlogic consumer. It deliberately has no card
# burn sidecar; its intended write path is host USB burning after owner gate.
emmc-package-test:
	bash uboot/package/test-manifest.sh uboot/package emmc

emmc-package: emmc-package-test
	@set -eu; \
	for artifact in $(UBOOT_ARTIFACTS); do \
		[ -s "$$artifact" ] || { \
			printf 'error: missing U-Boot artifact: %s\\n' "$$artifact" >&2; \
			printf '%s\\n' '       run make uboot before make emmc-package' >&2; \
			exit 1; \
		}; \
	done; \
	image="$(EMMC_SD_IMAGE)"; \
	[ -f "$$image" ] || { \
		printf 'error: missing assembled SD image: %s\\n' "$$image" >&2; \
		printf '%s\\n' '       run make os-image-s905x5m-sd, or pass EMMC_SD_IMAGE=path/to/s905x5m-...-sd-.img' >&2; \
		exit 1; \
	}; \
	image_dir="$$(cd "$$(dirname "$$image")" && pwd -P)"; \
	image="$$image_dir/$$(basename "$$image")"; \
	mkdir -p "$(BSP_OUT)"; \
	tmp_stage="$$(mktemp -d "$(abspath $(BSP_OUT))/.emmc-package.XXXXXX")"; \
	trap 'rm -rf "$$tmp_stage"' 0 1 2 3 15; \
	payload_dir="$$tmp_stage/payloads"; \
	tmp_output="$$tmp_stage/output"; \
	bash ../../../build/run.sh --extract-s905x5m-emmc-payloads \
		--image "$$image" --out-dir "$$payload_dir"; \
	IMG="$$(bash $(FROM_SH) $(DEBIAN_ARG))"; \
	docker buildx build --platform linux/386 --target emmc-artifact \
		--build-context uboot-artifacts=$(BSP_OUT)/uboot \
		--build-context emmc-payloads="$$payload_dir" \
		-f uboot/package/Dockerfile $$IMG \
		-o "$$tmp_output" uboot/package; \
	test -s "$$tmp_output/update.img"; \
	(cd "$$tmp_output" && sha256sum update.img > update.img.sha256); \
	rm -rf "$(EMMC_PACKAGE_DIR)"; \
	mv "$$tmp_output" "$(EMMC_PACKAGE_DIR)"; \
	trap - 0 1 2 3 15; \
	rm -rf "$$tmp_stage"; \
	ls -l "$(EMMC_PACKAGE_DIR)/update.img"; \
	cat "$(EMMC_PACKAGE_DIR)/update.img.sha256"

# A reusable installer is a file-only consumer of one explicitly named complete
# package. It never receives a block-device path and cannot write the board or
# an SD card as part of its build.
emmc-installer-test:
	bash uboot/installer/test-config.sh \
		uboot/config/bm201_emmc_installer.h \
		uboot/installer/config/bm201upd.ini \
		uboot/installer/complete-package-files.txt \
		uboot/package/config/emmc.cfg

emmc-installer: emmc-installer-test
	@set -eu; \
	package="$(EMMC_INSTALLER_PACKAGE)"; \
	[ -n "$$package" ] || { \
		printf '%s\\n' 'error: pass EMMC_INSTALLER_PACKAGE=/absolute/or/relative/path/update.img' >&2; \
		exit 2; \
	}; \
	[ -f "$$package" ] || { \
		printf 'error: missing installer package: %s\\n' "$$package" >&2; \
		exit 1; \
	}; \
	package_dir="$$(cd "$$(dirname "$$package")" && pwd -P)"; \
	package="$$package_dir/$$(basename "$$package")"; \
	[ "$$(basename "$$package")" = update.img ] || { \
		printf 'error: installer package must be named update.img, not %s\\n' "$$package" >&2; \
		exit 1; \
	}; \
	artifact=$(BSP_OUT)/uboot/u-boot.bin.sd.bin.signed; \
	[ -s "$$artifact" ] || { \
		printf 'error: missing U-Boot artifact: %s\\n' "$$artifact" >&2; \
		printf '%s\\n' '       run make uboot before make emmc-installer' >&2; \
		exit 1; \
	}; \
	mkdir -p "$(BSP_OUT)"; \
	tmp_output="$$(mktemp -d $(BSP_OUT)/.emmc-installer.XXXXXX)"; \
	trap 'rm -rf "$$tmp_output"' 0 1 2 3 15; \
	IMG="$$(bash $(FROM_SH) $(DEBIAN_ARG))"; \
	docker buildx build --platform linux/386 --target artifact \
		--build-context uboot-artifacts=$(BSP_OUT)/uboot \
		--build-context emmc-package="$$package_dir" \
		-f uboot/installer/Dockerfile $$IMG \
		-o "$$tmp_output" uboot; \
	test -s "$$tmp_output/disk.img"; \
	(cd "$$tmp_output" && sha256sum disk.img > disk.img.sha256); \
	rm -rf "$(EMMC_INSTALLER_DIR)"; \
	mv "$$tmp_output" "$(EMMC_INSTALLER_DIR)"; \
	trap - 0 1 2 3 15; \
	ls -l "$(EMMC_INSTALLER_DIR)/disk.img"; \
	cat "$(EMMC_INSTALLER_DIR)/disk.img.sha256"
