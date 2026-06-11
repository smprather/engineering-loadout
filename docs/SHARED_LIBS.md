# Vendored Shared Libraries

Runtime dependencies vendored alongside binaries — no system library assumptions.

## Always installed (core deps for default tools)

| Library | Provides |
|---------|---------|
| `libbz2.so.1` | bzip2 compression (bat, tmux, and others) |
| `libevent_core-2.1.so.6` | Event loop (tmux) |
| `libexpat.so.1` | XML parsing |
| `libfontconfig.so.1` | Font discovery (xterm) |
| `libfreetype.so.6` | Font rendering (xterm) |
| `libICE.so.6` | Inter-Client Exchange (X11) |
| `libjq.so` | jq shared library |
| `libncurses.so.6` | Terminal UI (gnuplot, htop) |
| `libonig.so.5` | Oniguruma regex (jq) |
| `libpng16.so.16` | PNG image support (xterm) |
| `libreadline.so.7` | GNU readline (gnuplot, bash) |
| `libSM.so.6` | Session Management (X11) |
| `libtinfo.so.6` | Terminal info (ncurses) |
| `libuuid.so.1` | UUID generation |
| `libX11.so.6` | Core X11 client library |
| `libXau.so.6` | X11 authorization |
| `libXaw.so.7` | X11 Athena Widgets (xterm UI) |
| `libxcb.so.1` | X protocol C-language Binding |
| `libXext.so.6` | X11 extensions |
| `libXft.so.2` | X FreeType font rendering |
| `libXinerama.so.1` | Multi-monitor extension |
| `libXmu.so.6` | X11 miscellaneous utilities |
| `libXpm.so.4` | X PixMap (xterm icon) |
| `libXrender.so.1` | X Render extension |
| `libXt.so.6` | X Toolkit Intrinsics |
| `libxxhash.so.0` | Fast non-cryptographic hash |
| `libz.so.1` | zlib compression |

## `gui_libs` optional package (~80 libs)

Opt in with `./loadout install gui_libs`. Targets headless compute farm / LSF
nodes that have no GUI libraries but run GUI tools with `DISPLAY` forwarded
back to a workstation. All patchelf'd with `$ORIGIN` RPATH so they find each
other in `~/.local/lib64/`.

- **Qt5 5.15.3**: `libQt5Core`, `libQt5Gui`, `libQt5Widgets`, `libQt5DBus`,
  `libQt5Network`, `libQt5PrintSupport`, `libQt5XcbQpa`, `libQt5Xml`,
  `libQt5WaylandClient` + platform plugins `libqxcb.so`,
  `libqwayland-generic.so` (flat in `~/.local/lib64/`).
- **GTK3 3.22**: `libgtk-3`, `libgdk-3`, `libgdk_pixbuf-2.0`, `libatk-1.0`,
  `libatk-bridge-2.0`, `libatspi`.
- **ICU 60**: `libicudata`, `libicui18n`, `libicuuc` (~27 MB).
- **Cairo/Pango**: `libcairo`, `libpango-1.0`, `libharfbuzz`, `libfribidi`,
  `libgraphite2`.
- **xcb extensions**: `libxcb-icccm`, `libxcb-image`, `libxcb-keysyms`,
  `libxcb-randr`, `libxcb-render`, `libxcb-render-util`, `libxcb-shape`,
  `libxcb-shm`, `libxcb-sync`, `libxcb-util`, `libxcb-xfixes`,
  `libxcb-xinerama`, `libxcb-xinput`, `libxcb-xkb`.
- **Wayland**: `libwayland-client`, `libwayland-cursor`, `libwayland-egl`.
- **xkbcommon**: `libxkbcommon`, `libxkbcommon-x11`.
- **glib2 family**: `libglib-2.0`, `libgobject-2.0`, `libgio-2.0`,
  `libgmodule-2.0`, `libgthread-2.0`.
- **Fonts**: `libfontconfig`, `libfreetype`, `libpixman-1`, `libpng16`.

### WSLg cursor bug

Qt5's XCB backend corrupts XWayland's global cursor state (all X11 apps in
the session lose their cursor). Fix: add `export QT_QPA_PLATFORM=wayland`
to `~/.config/bash/user/bashrc`. The Wayland backend (included in
`gui_libs`) routes cursor management through the compositor directly,
bypassing XWayland.
