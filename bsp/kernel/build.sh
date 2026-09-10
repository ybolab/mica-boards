#!/usr/bin/env bash
# mos-build-side: container -- this cross-compiles the kernel inside the BSP
# builder image; docs/design/build.md section 0 is why there is no compiler here.
#
# Compile the CX3576-Z kernel, prove the compiled tree carries each patch, and
# package the results reproducibly.
#
#   build.sh <source-tree> <expected-kernel-release>
#
# Everything this writes outside the tree lands at the paths kernel/Dockerfile's
# artifact stage copies from: /modules.tar, /kernel.release and /rk3576-src.dtb.
set -euo pipefail

[ "$#" -eq 2 ] || {
    echo "usage: build.sh <source-tree> <expected-kernel-release>" >&2
    exit 1
}
SRC="$1"
KERNEL_EXPECT="$2"

[ -n "${KERNEL_EXPECT}" ] || {
    echo "error: build.sh was given no expected kernel release. The assertion below would then compare the built release against the empty string and could never hold, which is a different failure from the one it exists to report" >&2
    exit 1
}

cd "${SRC}"
# See kernel/configure.sh for why these are command-line assignments.
CROSS=(ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-)

make "${CROSS[@]}" -j"$(nproc)" Image modules

# The patch series proves it applied without rejects; these prove the tree that
# was just compiled carries each patch's effect -- one distinctive added line per
# patch, the same shape as uboot/build.sh's post-build greps.
#   0001  the yt8531_stock_init module parameter
#   0002  the AIC_WLAN_SUPPORT gate on the aic8800_sdio directory
#   0003  the Mali BUILD_DATE made deterministic
#   0004  the cx3576z dtb registered in the rockchip dts Makefile
#   0005  the RK3576 encoder fixed-rate OPP path
grep -qF 'module_param(yt8531_stock_init, bool, 0444);' drivers/net/phy/motorcomm.c
grep -qF 'obj-$(CONFIG_AIC_WLAN_SUPPORT) += aic8800_sdio/' drivers/net/wireless/Makefile
grep -qF 'BUILD_DATE=$(shell date -u -d' drivers/gpu/arm/mali400/mali/Kbuild
grep -qF 'dtb-$(CONFIG_ARCH_ROCKCHIP) += rk3576-cx3576z.dtb' \
    arch/arm64/boot/dts/rockchip/Makefile
grep -qF 'using fixed clock rates, devfreq is disabled' \
    drivers/video/rockchip/mpp/mpp_rkvenc2.c
grep -q '^CONFIG_LEDS_TRIGGER_HEARTBEAT=y' include/config/auto.conf

# The link-time symbol table and the object it came from, sized in the log
# because kernel/Dockerfile's artifact stage takes one and leaves the other and
# the reason is the ratio between these two numbers.
ls -l vmlinux System.map

release="$(cat include/config/kernel.release)"
echo "kernel release: ${release}"
[ "${release}" = "${KERNEL_EXPECT}" ] || {
    echo "error: the tree built ${release}; this board expects ${KERNEL_EXPECT}" >&2
    exit 1
}

make "${CROSS[@]}" INSTALL_MOD_PATH=/kmods INSTALL_MOD_STRIP=1 modules_install
# Kernel support ships runtime modules, without links into the build tree.
rm -f "/kmods/lib/modules/${release}/build" "/kmods/lib/modules/${release}/source"

# DETERMINISTIC ARCHIVE PARAMETERS, and this is a packaging fix rather than a
# compile one -- separable from the Image above and measured separately. RFCT-343
# compared two modules.tar from two --no-cache builds: every member was
# byte-identical, the member ORDER was identical, and every header carried the
# wall clock of its build. So the archive, not its contents, was the whole
# difference. --mtime pins that clock to the one instant this repository stamps
# everywhere; --owner/--group/--numeric-owner keep the ids from describing the
# builder; --sort=name makes the order a function of the names rather than of
# readdir, which agreed across the two runs measured and is promised by nothing.
tar --sort=name --mtime=@1577836800 --owner=0 --group=0 --numeric-owner \
    -C /kmods -cf /modules.tar lib
printf '%s\n' "${release}" >/kernel.release
ls /kmods/lib/modules/

# THE BOARD DTB, built from the maintained source. The Makefile entry that makes
# this target exist is kernel/patches/0004, applied with the rest of the series
# -- it was an `echo ... >>` in the Dockerfile until RFCT-343, which is an edit to
# the kernel source performed by a shell redirection in the middle of a build,
# invisible to the series and to review. The .dts itself is copied in beside the
# patches, so the tree is coherent from the moment 0004 names the file rather
# than only by the time this step runs.
make "${CROSS[@]}" rockchip/rk3576-cx3576z.dtb
cp arch/arm64/boot/dts/rockchip/rk3576-cx3576z.dtb /rk3576-src.dtb

# The status LEDs, read back out of the compiled blob: the red one is on at boot
# and the blue one off, and their GPIO polarity is what says which is which.
[ "$(fdtget /rk3576-src.dtb /leds/status-red label)" = "status-red" ]
[ "$(fdtget /rk3576-src.dtb /leds/status-red default-state)" = "on" ]
[ "$(fdtget -t x /rk3576-src.dtb /leds/status-red gpios | awk '{print $3}')" = "1" ]
[ "$(fdtget /rk3576-src.dtb /leds/status-blue label)" = "status-blue" ]
[ "$(fdtget /rk3576-src.dtb /leds/status-blue default-state)" = "off" ]
[ "$(fdtget -t x /rk3576-src.dtb /leds/status-blue gpios | awk '{print $3}')" = "0" ]
