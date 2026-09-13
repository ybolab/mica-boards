# cx3576: a board of the rockchip family (Rockchip RK3576, signed FIT boot
# through U-Boot). The kernel and U-Boot orchestration and the source pins
# live in families/rockchip/; this file names the board, includes the
# family's targets and keeps what is the board's own: flashing the complete
# signed image over rkdeveloptool, the macOS flashing tool and the CJK
# source check.
BOARD := cx3576
include ../../families/rockchip/Makefile.inc

.PHONY: all rkdeveloptool-macos flash-maskrom flash-mos source-check

# The complete factory image is assembled from independently signed components.
MICA_OUT ?= ../../_out/image
MICA_IMAGE ?= $(lastword $(sort $(wildcard $(MICA_OUT)/mos-cx3576-*.img)))

TOOLS_DIR ?= flash/tools
THIRD_DIR ?= flash
RKDEVELOPTOOL_LOCAL := $(TOOLS_DIR)/rkdeveloptool
RKDEVELOPTOOL ?= $(if $(wildcard $(RKDEVELOPTOOL_LOCAL)),$(RKDEVELOPTOOL_LOCAL),rkdeveloptool)
VENDOR_MINILOADER := loader/MiniLoaderAll.bin
# Prefer coreutils sha256sum (Linux hosts and CI, no Perl needed); fall back
# to Perl/macOS shasum. Both accept the same `-c` checkfile format.
SHA256 := $(shell command -v sha256sum >/dev/null 2>&1 && echo sha256sum || echo "shasum -a 256")

all: kernel uboot-mos

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
	bash flash/scripts/verify-flash.sh --check "$(MICA_IMAGE)"
	$(RKDEVELOPTOOL) wl 0 "$(MICA_IMAGE)"
	RKDEVELOPTOOL='$(RKDEVELOPTOOL)' bash flash/scripts/verify-flash.sh "$(MICA_IMAGE)"
	$(RKDEVELOPTOOL) rd

flash-maskrom:
	@test -n "$(MICA_IMAGE)" || { echo 'error: no timestamped cx3576 image found; set MICA_IMAGE explicitly' >&2; exit 1; }
	bash flash/scripts/verify-flash.sh --check "$(MICA_IMAGE)"
	$(SHA256) -c loader/MiniLoaderAll.bin.sha256
	$(RKDEVELOPTOOL) db $(VENDOR_MINILOADER)
	$(MAKE) flash-mos MICA_IMAGE="$(MICA_IMAGE)" RKDEVELOPTOOL="$(RKDEVELOPTOOL)"
