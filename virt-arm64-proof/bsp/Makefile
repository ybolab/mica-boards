# virt-arm64-proof: a board of the uefi family. The kernel build, its targets and its
# architecture table live in families/uefi/Makefile.inc; this file names the
# board and keeps only what is the board's own. There is no U-Boot and no
# rootfs target here: a UEFI machine's firmware provides the boot chain, so
# the only thing this board compiles is its kernel.
BOARD := virt-arm64-proof
include ../../families/uefi/Makefile.inc

.PHONY: all
all: kernel
