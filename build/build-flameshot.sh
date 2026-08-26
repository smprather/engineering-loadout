#!/bin/sh
# Build flameshot (screenshot tool) from source for el8.x86_64.glibc2p28.
#
# flameshot >=13.0 is Qt6-only upstream, but EL8 has only Qt5 5.15 (what gui_libs
# bundles) and NO prebuilt channel ships a glibc<=2.28 binary (fc/deb/AppImage are
# all glibc 2.34+). So we back-port the current release to Qt5 with a small, stable
# patch set (all stock Qt6->Qt5 idioms) and build natively on EL8 -> glibc 2.27.
#
# This is a MAINTAINED FORK-PATCH: each new flameshot release may need these
# re-applied. The patches are idempotent-ish (guarded) and fail loudly if a target
# string is missing, so a breaking upstream change is obvious at build time.
#
# Runtime: GUI tool. Links Qt5 (Core/Gui/Widgets/Network/DBus/Svg) + X11/xcb -- ALL
# provided by gui_libs. Install with: ./loadout install gui_libs flameshot
# RPATH $ORIGIN/../lib64 lets it find the bundled Qt5 in ~/.local/lib64.
#
# KDSingleApplication is DISABLED (its find_package is hardcoded -qt6 and it's only
# single-instance enforcement); USE_WAYLAND_CLIPBOARD is OFF (needs KF6, absent on EL8).
#
# Prerequisites on the build machine (EL8):
#   source /opt/rh/gcc-toolset-14/enable
#   sudo dnf install -y cmake qt5-qtbase-devel qt5-qtsvg-devel qt5-qttools-devel \
#       qt5-qtbase-private-devel libxcb-devel
#   # FetchContent pulls QtColorWidgets (gitlab) + QHotkey (github) at configure time
#   # -> needs network (not in the sandbox allowlist).
#
# Usage (run from any directory):
#   ./build/build-flameshot.sh --tag v13.3.0

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="$REPO/payload/el8.x86_64.glibc2p28/bin"
TAG=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --tag) shift; [ "$#" -gt 0 ] || { echo "missing value for --tag" >&2; exit 2; }; TAG="$1" ;;
        -h|--help) sed -n '2,/^$/p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

if [ -z "$TAG" ]; then
    echo "ERROR: --tag required, e.g.: $0 --tag v13.3.0" >&2
    echo "Stable releases: https://github.com/flameshot-org/flameshot/releases" >&2
    exit 1
fi
VERSION="${TAG#v}"

if [ -r /opt/rh/gcc-toolset-14/enable ]; then
    # shellcheck disable=SC1091
    . /opt/rh/gcc-toolset-14/enable
fi

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing required command: $1" >&2; exit 1; }; }
need gcc; need g++; need cmake; need git; need patchelf

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/build-flameshot-XXXXXX")
trap 'rm -rf "$WORK_DIR"' EXIT

echo "==> Downloading flameshot ${TAG} source ..."
curl -fL -o "$WORK_DIR/src.tar.gz" \
    "https://github.com/flameshot-org/flameshot/archive/refs/tags/${TAG}.tar.gz" \
    --retry 3 --retry-delay 2
tar xzf "$WORK_DIR/src.tar.gz" -C "$WORK_DIR"
SRC="$WORK_DIR/flameshot-${VERSION}"
cd "$SRC"

echo "==> Applying Qt5 back-port patches ..."
python3 - "$SRC" <<'PYEOF'
import sys, os
src = sys.argv[1]

def patch(rel, replacements, required=True):
    p = os.path.join(src, rel)
    with open(p) as f:
        s = f.read()
    for old, new in replacements:
        if old not in s:
            if required:
                sys.exit("PATCH TARGET MISSING in %s:\n  %r\nUpstream changed -- re-derive the Qt5 back-port." % (rel, old))
            continue
        s = s.replace(old, new)
    with open(p, "w") as f:
        f.write(s)
    print("  patched", rel)

# 1. CMake: qt6_* translation macros (command names can't be variable-expanded)
patch("src/CMakeLists.txt", [
    ("qt6_create_translation(", "qt5_create_translation("),
    ("qt6_add_translation(", "qt5_add_translation("),
])

# 2. generalconf.cpp: QStringDecoder/Encoder (Qt6) -> fromLocal8Bit/toLocal8Bit (both versions)
patch("src/config/generalconf.cpp", [
    ("#include <QStringDecoder>\n", ""),
    ("    QStringDecoder decoder(QStringDecoder::System);\n    QString text = decoder(file.readAll());\n",
     "    QString text = QString::fromLocal8Bit(file.readAll());\n"),
    ("    QStringEncoder encoder(QStringEncoder::System);\n    config.write(encoder(text));\n",
     "    config.write(text.toLocal8Bit());\n"),
])

# 3. enterEvent(QEnterEvent*) (Qt6) -> QEvent* on Qt5 (version-conditional)
def enter(decl):
    return ("#if QT_VERSION >= QT_VERSION_CHECK(6, 0, 0)\n" + decl.replace("QEVT", "QEnterEvent*") +
            "\n#else\n" + decl.replace("QEVT", "QEvent*") + "\n#endif")
patch("src/widgets/capture/notifierbox.h",
      [("    void enterEvent(QEnterEvent*) override;", enter("    void enterEvent(QEVT) override;"))])
patch("src/widgets/capture/notifierbox.cpp",
      [("void NotifierBox::enterEvent(QEnterEvent*)", enter("void NotifierBox::enterEvent(QEVT)"))])
patch("src/tools/pin/pinwidget.h",
      [("    void enterEvent(QEnterEvent*) override;", enter("    void enterEvent(QEVT) override;"))])
patch("src/tools/pin/pinwidget.cpp",
      [("void PinWidget::enterEvent(QEnterEvent*)", enter("void PinWidget::enterEvent(QEVT)"))])
# 14.0.0 grew a third enterEvent override, this one with a named parameter.
patch("src/utils/monitorpreview.h",
      [("    void enterEvent(QEnterEvent* event) override;",
        enter("    void enterEvent(QEVT event) override;"))])
patch("src/utils/monitorpreview.cpp",
      [("void MonitorPreview::enterEvent(QEnterEvent* event)",
        enter("void MonitorPreview::enterEvent(QEVT event)"))])

# 3b. QImageReader::setAllocationLimit (new in Qt 6.0) -- no Qt5 equivalent.
# Qt5 simply has no allocation cap, which is the behaviour every flameshot
# release before 14.0 shipped, so compiling the call out is not a regression.
patch("src/utils/screengrabber.cpp",
      [("    QImageReader::setAllocationLimit(1024);",
        "#if QT_VERSION >= QT_VERSION_CHECK(6, 0, 0)\n"
        "    QImageReader::setAllocationLimit(1024);\n"
        "#endif")])

# 3c. QMimeData::retrieveData's second parameter is QMetaType on Qt6 and
# QVariant::Type on Qt5. It is an override, so the signature has to match the
# base class exactly or it stops overriding anything (which is what the Qt5
# build reported). The body passes `type` straight through to
# QMimeData::retrieveData, so only the declaration needs to differ.
patch("src/utils/screenshotsaver.cpp",
      [("    QVariant retrieveData(const QString& mimeType,\n"
        "                          QMetaType type) const override",
        "#if QT_VERSION >= QT_VERSION_CHECK(6, 0, 0)\n"
        "    QVariant retrieveData(const QString& mimeType,\n"
        "                          QMetaType type) const override\n"
        "#else\n"
        "    QVariant retrieveData(const QString& mimeType,\n"
        "                          QVariant::Type type) const override\n"
        "#endif")])

# 4. QMouseEvent::globalPosition() (Qt6) -> globalPos() (present in both)
patch("src/widgets/draggablewidgetmaker.cpp",
      [("->globalPosition()", "->globalPos()")])

# 5. QList<QPair> << std::pair (Qt6 QPair==std::pair) -> qMakePair (both)
patch("src/widgets/capture/capturewidget.cpp",
      [("std::pair(", "qMakePair(")])

# 6. QFontDatabase static methods (Qt6) -> instance (Qt5)
patch("src/tools/text/textconfig.cpp",
      [("QFontDatabase::families()", "QFontDatabase().families()")])

# 7. main.cpp: QLibraryInfo::path (Qt6) -> location (Qt5); add QDebug include
patch("src/main.cpp", [
    ("#include <QApplication>", "#include <QApplication>\n#include <QDebug>"),
    ("QLibraryInfo::path(", "QLibraryInfo::location("),
])
print("All Qt5 back-port patches applied.")
PYEOF

echo "==> Configuring (Qt5) ..."
mkdir build && cd build
cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DQT_VERSION_MAJOR=5 \
    -DQT_DEFAULT_MAJOR_VERSION=5 \
    -DUSE_KDSINGLEAPPLICATION=OFF \
    -DUSE_WAYLAND_CLIPBOARD=OFF \
    -DCMAKE_INSTALL_PREFIX="$WORK_DIR/install"

echo "==> Building ..."
make -j"$(nproc 2>/dev/null || echo 2)"

FLAMESHOT_BIN="$SRC/build/src/flameshot"
[ -f "$FLAMESHOT_BIN" ] || { echo "ERROR: flameshot binary not built at $FLAMESHOT_BIN" >&2; exit 1; }

echo "==> Verifying ..."
QT_QPA_PLATFORM=offscreen "$FLAMESHOT_BIN" --version 2>&1 | head -2
echo "  Qt linkage:"
readelf -d "$FLAMESHOT_BIN" 2>/dev/null | grep -iE "NEEDED.*Qt5" | sed 's/.*\[/    /;s/\]//'
MAX_GLIBC="$(readelf -V "$FLAMESHOT_BIN" 2>/dev/null | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -1)"
echo "  Max glibc symbol: $MAX_GLIBC (target: GLIBC_2.28)"
case "$MAX_GLIBC" in
    GLIBC_2.2[0-8]|GLIBC_2.1[0-9]|GLIBC_2.[0-9]) echo "  OK -- EL8 compatible" ;;
    *) echo "  WARNING: $MAX_GLIBC > GLIBC_2.28" >&2 ;;
esac

echo "==> Packaging (strip -> patchelf -> bzip2) ..."
WORK_BIN="$WORK_DIR/flameshot"
cp "$FLAMESHOT_BIN" "$WORK_BIN"
strip "$WORK_BIN"
patchelf --set-rpath '$ORIGIN/../lib64' "$WORK_BIN"
bzip2 -kf "$WORK_BIN"
cp "${WORK_BIN}.bz2" "$BIN_DIR/flameshot.bz2"
chmod 644 "$BIN_DIR/flameshot.bz2"
echo "  -> $BIN_DIR/flameshot.bz2"

echo "==> Updating packages.json ..."
python3 -c "
import json, sys
path, ver = sys.argv[1], sys.argv[2]
with open(path) as f: data = json.load(f)
if 'flameshot' in data['packages']:
    data['packages']['flameshot']['version'] = ver
    print('packages.json: flameshot version -> ' + ver)
else:
    print('WARNING: flameshot not in packages.json')
with open(path, 'w') as f:
    json.dump(data, f, indent=2); f.write('\n')
" "$REPO/payload/packages.json" "$VERSION"

echo "==> Running strip-all-elf-binaries ..."
"$REPO/build/strip-all-elf-binaries"

echo ""
echo "Done. Produced: $BIN_DIR/flameshot.bz2 (flameshot ${VERSION}, Qt5, glibc ${MAX_GLIBC})"
echo "Install: ./loadout install gui_libs flameshot"
