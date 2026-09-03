# syntax=docker/dockerfile:1@sha256:ecfaec9ed6d810b56388c508f4121597bfbba70d41a6dfeee4d8cad5f295fc32
# check=skip=InvalidDefaultArgInFrom
# The board-x64 producer: the `mos-board-x64` package.
#
#   bash build-env/deb/build.sh --producer board-x64 --arch amd64
#
# Everything the image carries because it is the x64 board: the configuration
# rendered from boards/x64/board.env, and grub-editenv.
#
# NOTHING IS COMPILED HERE, and the kernel is not in this package either. It is
# boards/x64/bsp's output, packaged separately as mos-kernel-x64, which this
# package depends on -- so a kernel bump moves versions.env and the recorded
# config, while a layout change moves board.env, and the two are visible apart
# in /usr/share/mos/manifest.tsv.
#
# THERE IS NO INITRAMFS ON THIS BOARD, since PLAN-074. This producer used to
# ship /etc/initramfs-tools/hooks/mos-verity and a local-top script, because
# Debian's generic kernel has no CONFIG_DM_INIT and ignored the dm-mod.create=
# verity table the boot contract puts on the kernel command line -- so an initrd
# had to re-parse that line and call veritysetup itself. mos-kernel-x64 carries
# the device mapper, dm-verity and squashfs built in and reads the cmdline
# directly, exactly as cx3576's kernel does, so the hook, the script, the
# initrd and the update-initramfs run that built it are all gone.
#
# No default for the bases, for the reason build-env/deb/Dockerfile gives: a
# driver that failed to pass the argument would otherwise build from a floating
# tag.
ARG MOS_BUILD_DEB
ARG MOS_IMAGE_DEBIAN_TRIXIE

# grub-editenv, taken out of grub-common exactly as
# rootfs/scripts/grub-editenv-install.sh takes it, and from the same trixie
# the device root is assembled from.
#
# THE FILE, NOT THE PACKAGE. grub-common is a 20 MB installed increment that
# drags in libfreetype6, libpng16, libfuse3, libefivar and gettext-base, none
# of which a device that only rewrites a grubenv has any use for; the binary is
# 403 KB. Extracting one path skips dependency resolution, so the libraries it
# needs are asserted here instead -- RAUC's grub backend execs this binary, and
# a missing library surfaces at runtime only as "Failed to start grub-editenv".
FROM ${MOS_IMAGE_DEBIAN_TRIXIE} AS grub
RUN set -eu; \
    apt-get update; \
    apt-get install -y --no-install-recommends libdevmapper1.02.1; \
    cd /tmp; \
    apt-get download grub-common; \
    dpkg-deb --fsys-tarfile grub-common_*.deb \
        | tar -xO ./usr/bin/grub-editenv > /usr/bin/grub-editenv; \
    chmod 0755 /usr/bin/grub-editenv; \
    mkdir -p /harvest; \
    dpkg-deb --fsys-tarfile grub-common_*.deb \
        | tar -xO ./usr/share/doc/grub-common/copyright > /harvest/grub-common.copyright; \
    rm -f /tmp/grub-common_*.deb; \
    [ -s /usr/bin/grub-editenv ] || \
        { echo "error: extracting grub-editenv produced an empty file; RAUC's grub backend would fail at runtime with 'No such file or directory'" >&2; exit 1; }; \
    missing="$(ldd /usr/bin/grub-editenv | awk '/not found/{print $1}' | tr '\n' ' ')"; \
    [ -z "${missing}" ] || \
        { echo "error: grub-editenv was taken out of its package but this root does not carry:${missing}. Extracting one file skips dependency resolution, so a missing library shows up as a dynamic-link failure at runtime, inside a child process RAUC reports only as 'Failed to start grub-editenv'" >&2; exit 1; }; \
    grub-editenv --help >/dev/null 2>&1 || \
        { echo "error: grub-editenv is installed and will not run" >&2; exit 1; }; \
    ldd /usr/bin/grub-editenv; \
    echo "grub: grub-editenv extracted ($(stat -c%s /usr/bin/grub-editenv) bytes), which RAUC's grub backend execs to read and write grubenv"; \
    [ -s /harvest/grub-common.copyright ] || \
        { echo "error: grub-common ships no /usr/share/doc/grub-common/copyright to harvest, so the GPL-3 record for the binary above would have to be written by hand -- which is a claim about the file rather than the file's own licence" >&2; exit 1; }; \
    grep -c '^License: GPL-3' /harvest/grub-common.copyright >/dev/null || \
        { echo "error: the harvested grub-common copyright declares no GPL-3 licence; boards/x64/deb/board-x64/copyright records grub-editenv as GPL-3-or-later and that record must match what Debian ships" >&2; exit 1; }

FROM ${MOS_BUILD_DEB} AS pack

# pack.sh comes over as a named context rather than out of the image. It is the
# packaging CONTRACT, shared by every producer, and build-env/deb/README.md
# requires this shape: an edit to the packer then takes effect without
# rebuilding the whole builder family.
COPY --from=packer pack.sh /usr/local/bin/pack.sh

COPY --from=board deb/board-x64/copyright deb/board-x64/render.sh /in/
COPY --from=board deb/board-x64/control/ /in/control/
COPY --from=grub /usr/bin/grub-editenv /in/grub-editenv
COPY --from=grub /harvest/grub-common.copyright /in/grub-common.copyright

# The rendering inputs, placed at their REPOSITORY paths rather than beside
# each other: pkgs/rauc/render-config.sh derives the repository root from
# its own location and reads the board layout and the shared fstab template
# through it. It is invoked and never reimplemented, so the RAUC template, the
# statusfile placement and the boot-attempts refusal keep one owner.
COPY --from=board board.env /src/boards/x64/board.env
COPY --from=board overlay/etc/systemd/system/boot.mount.in /src/boards/x64/overlay/etc/systemd/system/boot.mount.in
COPY --from=rauc render-config.sh system.conf.in /src/pkgs/rauc/
COPY --from=overlay etc/fstab.in /src/rootfs/overlay/etc/fstab.in

# libdevmapper1.02.1 in the PACKING container, and it changes no byte of the
# payload. dpkg-shlibdeps resolves an ELF's dependencies against the libraries
# installed next to it and asks dpkg which package provides each one; without
# this, grub-editenv's NEEDED libdevmapper.so.1.02.1 resolves to nothing and
# build-env/deb/pack.sh's ${shlibs:Depends} expansion fails by name. The
# control template also names the package outright -- see it for why.
RUN set -eu; \
    apt-get update; \
    apt-get install -y --no-install-recommends libdevmapper1.02.1; \
    rm -rf /var/lib/apt/lists/*

ARG MOS_DEB_VERSION
ARG MOS_DEB_ARCH
ARG SOURCE_DATE_EPOCH

# The paths, the modes and the enablement link are the ones
# rootfs/scripts/overlay-install.sh and grub-editenv-install.sh write today,
# so a root composed from this package is the tree the stage chain installs.
#
# ENABLEMENT IS OWNED BY THE PACKAGE. local-fs.target.wants/boot.mount is a
# symlink IN THE PAYLOAD, not something a maintainer script creates: there is
# no postinst here and nothing calls `systemctl enable`. overlay-install.sh
# creates exactly this link, and only when boot.mount exists -- which is on
# this board and not on cx3576, because RAUC's grub backend edits a file on the
# ESP while the U-Boot backend writes a raw partition, so /boot is a mountpoint
# on exactly one of the two.
#
# NOT a conffile, deliberately. /etc here is on an immutable dm-verity
# squashfs; a conffiles entry would promise a merge that cannot happen.
#
# NO /etc/fw_env.config. There is no U-Boot on this board and that file names
# two partitions boards/x64/board.env does not create -- a configuration
# file describing storage that does not exist is readable, plausible and wrong.
# render.sh does not render it and rootfs/build.sh deletes it on amd64.
#
# NO GRUB CONFIGURATION IN THE PAYLOAD. This package once staged
# boards/x64/grub.cfg at /usr/lib/mos/board/x64/grub.cfg, placeholders
# intact, on the reasoning that image-assembly input travels with the board.
# Nothing ever read it: build/src/mkimage-x64.ts renders the ESP copy from
# the TREE path, boards/x64/grub.cfg, which is where the assembler runs and
# where the file is version-controlled. The packaged copy was therefore an
# unrendered template with @BOOT_A_PARTNUM@ and @ROOTFS_A_PARTUUID@ still in it,
# sitting in a signed read-only dm-verity root -- a configuration file that
# describes a boot no machine performs, indistinguishable at a glance from one
# that does. It is a build-host input, so the build host is where it lives.
# cx3576's /usr/lib/mos/board/<board>/ is not the same case and is not being
# argued against here: the finalizer exports that board's kernel, DTB, U-Boot
# image and boot.cmd OUT OF THE INSTALLED PACKAGE, so those bytes have a
# reader. Here there was none.
#
# The copyright is this board's own and is COMPLETED here: the harvested
# /usr/share/doc/grub-common/copyright is appended as the body of the file's
# GPL-3.0-or-later stanza, indented one space with blank lines written as `.`,
# which is how the machine-readable format carries verbatim text. Harvested
# from the very archive grub-editenv came out of rather than hand-written,
# because a GPL-3 binary shipped inside our archive is exactly the obligation
# a loose binary copy obscures.
RUN set -eu; \
    bash /in/render.sh /src /render; \
    install -D -m 0644 /render/fstab       /stage/etc/fstab; \
    install -D -m 0644 /render/boot.mount  /stage/etc/systemd/system/boot.mount; \
    install -D -m 0644 /render/system.conf /stage/etc/rauc/system.conf; \
    install -d -m 0755 /stage/etc/systemd/system/local-fs.target.wants; \
    ln -s /etc/systemd/system/boot.mount \
          /stage/etc/systemd/system/local-fs.target.wants/boot.mount; \
    install -d -m 0755 /stage/boot; \
    install -D -m 0755 /in/grub-editenv /stage/usr/bin/grub-editenv; \
    doc=/stage/usr/share/doc/mos-board-x64/copyright; \
    install -D -m 0644 /in/copyright "${doc}"; \
    sed -e 's/^[[:space:]]*$/./' -e 's/^/ /' /in/grub-common.copyright >>"${doc}"; \
    grep -c '^ Upstream-Name: GNU GRUB$' "${doc}" >/dev/null || \
        { echo "error: the harvested grub-common copyright is not in ${doc}; the package would ship a GPL-3 binary under a licence stanza with no text in it" >&2; exit 1; }; \
    pack.sh --root /stage --control /in/control/mos-board-x64.control \
        --version "${MOS_DEB_VERSION}" --arch "${MOS_DEB_ARCH}" --out /out

# The export stage, the shape pkgs/mosd/deb/mosd/Dockerfile ends in:
# `-o type=local` writes this stage's filesystem into _out/debs/<arch>/pool/
# and nothing here installs into a root.
FROM scratch AS out
COPY --from=pack /out/ /
