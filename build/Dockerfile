# Build-machine image for build/build-*.sh and the payload-maintenance
# scripts (strip-all-elf-binaries, gen-content-manifest, gen-installed-sizes,
# gen-readme-table).
#
# WHY THIS EXISTS. build/ADDING_BINARIES.md documents AlmaLinux 8.10 (WSL2)
# as the one true build machine: every bundled binary's glibc floor, its
# libevent_core's stray libcrypto.so.1.1 dependency (see
# build/build-libevent-core.sh), and every SONAME choice in payload/ was
# decided against that platform's toolchain. Running the maintenance scripts
# on anything else is not a style choice -- it silently reintroduces exactly
# the bug this file exists to prevent. Confirmed the hard way: running
# strip-all-elf-binaries on a native Arch/CachyOS host (different tar/bzip2
# build) repacked 29 unrelated payload archives with different bytes and
# timestamps despite identical extracted content, because bzip2 1.0.8
# (CachyOS) and bzip2 1.0.6 (this image) don't round-trip identically for
# every input -- a diff with nothing to do with whatever binary you meant to
# touch. Do all payload-mutating work in this container; do everyday
# development (shell configs, testing the installer, day-to-day loadout use)
# natively -- that native/foreign-platform gap is the whole point of running
# loadout on a non-EL8 box in the first place.
#
# What's NOT baked in, deliberately:
#   - python3.14: loadout self-hosts it. `./loadout` (bind-mounted at /repo)
#     bootstraps its own interpreter from payload/<platform>/portable-python-*
#     .tar.bz2 on first run -- offline, no dnf package needed. `./loadout
#     install patchelf` gets you a payload-identical patchelf the same way if
#     you'd rather not rely on the dnf one below.
#   - cargo/rustc/uv: build-rust.sh and friends manage their own toolchains
#     (rustup, uv's self-installer); a distro rust package would be the wrong
#     version and give a false sense of coverage.
#   - gcc-toolset-14 is installed but NOT enabled by default in the image --
#     build/lib.sh's loadout_enable_gcc_toolset sources
#     /opt/rh/gcc-toolset-14/enable itself when a build script needs GCC 14
#     instead of the base gcc 8.5.0. This matches how the real build machine
#     behaves (enabled only in the interactive user bashrc, not system-wide).
#
# Usage: see build/build-shell (thin docker-run wrapper). Bind-mount the repo
# at /repo rather than COPYing it in, so the image stays reusable across repo
# changes and never goes stale:
#   docker build -t loadout-build -f build/Dockerfile build/
#   docker run --rm -it -v "$(pwd):/repo" -w /repo loadout-build

FROM almalinux:8.10

# *-source repos: needed for `dnf download --source <pkg>` (the
# rpmbuild-from-source-RPM pattern used by build-xephyr-openssl-free.sh and
# any future "shanghai'd binary has an unwanted dependency baked into its
# EL8 build, rebuild it properly" fix -- see that script's header for the
# worked example). Cheap to always have enabled; dnf only hits them on
# `download --source`.
RUN dnf install -y -q epel-release \
    && dnf config-manager --set-enabled powertools \
    && dnf config-manager --set-enabled appstream-source baseos-source \
        powertools-source ha-source resilientstorage-source \
    && dnf install -y -q \
        # Core toolchain (base gcc 8.5.0; scripts opt into gcc-toolset-14
        # themselves via loadout_enable_gcc_toolset when they need GCC 14).
        gcc gcc-c++ make \
        gcc-toolset-14 gcc-toolset-14-gcc-c++ \
        # Autotools + friends most build-*.sh scripts configure/autogen with.
        autoconf automake libtool pkgconf-pkg-config \
        bison flex gperf cmake \
        # Packaging: strip/readelf (binutils), patchelf (RPATH surgery),
        # bzip2/gzip/zstd/tar/cpio (archive formats used across payload/),
        # rpm2cpio (extracting vendor RPMs without installing them),
        # rpmbuild/dnf-plugins-core (dnf download --source + rpmbuild -bp,
        # for rebuilding a shanghai'd RPM from its own source + RH patches).
        binutils patchelf bzip2 gzip zstd tar cpio rpm-build dnf-plugins-core \
        # Misc scripts (loadout_require_cmds) call directly. coreutils is
        # already present as coreutils-single in the base image -- naming it
        # explicitly conflicts with that package.
        git curl file which patch systemtap-sdt-devel \
        # The "Notable devel packages already installed" list in
        # build/ADDING_BINARIES.md -- X11 stack, image/font/text libs, and
        # the general-purpose compression/parsing libs several build
        # scripts link against.
        libX11-devel libXext-devel libXrender-devel libXft-devel \
        libXrandr-devel libXi-devel libXcursor-devel libXfixes-devel \
        libXinerama-devel libXtst-devel libXcomposite-devel libXdamage-devel \
        cairo-devel pango-devel readline-devel ncurses-devel \
        libpng-devel freetype-devel fontconfig-devel bzip2-devel \
        expat-devel libuuid-devel zlib-devel libwebp-devel libtiff-devel \
        libjpeg-turbo-devel glib2-devel harfbuzz-devel fribidi-devel \
        pixman-devel pcre-devel pcre2-devel openssl-devel openssl3-devel \
        elfutils-libelf-devel libxml2-devel xxhash-devel lz4-devel \
        libevent-devel libffi-devel libselinux-devel libgcrypt-devel \
        libunwind-devel \
        # xorg-server (Xephyr) build closure: see
        # build-xephyr-openssl-free.sh's header for the full rationale.
        xorg-x11-util-macros xorg-x11-proto-devel xorg-x11-font-utils \
        xorg-x11-xtrans-devel libXfont2-devel libXau-devel libxkbfile-devel \
        libXres-devel libfontenc-devel libXdmcp-devel libdmx-devel \
        libXmu-devel libXpm-devel libXaw-devel libXv-devel \
        libpciaccess-devel mesa-libGL-devel mesa-libEGL-devel \
        mesa-libgbm-devel libdrm-devel kernel-headers pam-devel \
        audit-libs-devel libudev-devel \
        xcb-util-devel xcb-util-image-devel xcb-util-wm-devel \
        xcb-util-keysyms-devel xcb-util-renderutil-devel libxshmfence-devel \
        dbus-devel libepoxy-devel systemd-devel \
        # Qt5 (gui_libs) build closure: see build-qt5network-openssl3.sh.
        libxcb-devel libSM-devel libICE-devel cups-devel \
        libxkbcommon-devel libxkbcommon-x11-devel sqlite-devel \
        gtk3-devel krb5-devel cyrus-sasl-devel \
    && dnf clean all

WORKDIR /repo
