#!/bin/sh
# loadout gvim launcher -- VIM/VIMRUNTIME prefix derivation + env adaptation.
# Composed of: VIM header + build/gui-wrapper-env.sh + build/gtk3-launcher-env.sh.
# To regenerate: re-run this composition (header below) after fragment changes.

bin_dir=$(CDPATH= cd "$(dirname "$0")" && pwd -P) || exit 1
prefix=$(CDPATH= cd "$bin_dir/.." && pwd -P) || exit 1

VIM=${VIM:-"$prefix/share/vim"}
VIMRUNTIME=${VIMRUNTIME:-"$VIM/vim92"}
export VIM VIMRUNTIME

# build/gui-wrapper-env.sh -- shared env-adaptation block for GUI wrappers.
#
# Build scripts inline this file into their wrapper heredocs (cat it in; the
# installed wrapper must stay a self-contained script with no repo runtime
# dependency). Inlining keeps one source of truth for a block every GUI
# launcher needs.
#
# The problem it solves (derived from three shipped regressions, all masked on
# EL8 build boxes): loadout bundles GUI client libs (gui_libs) + Mesa vendor
# side (mesa3d_libs) for headless farm nodes that have NO GL/GUI stack. On
# hosts that DO have their own GL stack, unconditionally pointing the loader
# at the loadout lib64 area shadows host libs with EL8-era copies and breaks
# both the GUI and every child it spawns (flatpak: undefined symbol
# g_once_init_leave_pointer from EL8 glib 2.56; host grep vs old bundled
# libpcre2; pages of fontconfig parse errors from bundled 2.13 reading newer
# hosts' configs). Universal-host rule (see AGENTS.md): the HOST copy wins
# wherever the host can supply the soname; loadout libs step in only when the
# host cannot.
#
# Env-driven adaptation knobs (all optional; defaults are probes):
#   LOADOUT_GUI_HOST_GL=auto|1|0
#       auto (default): probe ldconfig for host libEGL.so.1; GL present means
#       the host stack owns GL -> NO lib64 export at all (children inherit a
#       clean environment). 1: assume host GL (same, skip the probe). 0: force
#       the loadout Mesa/GLVND fallback even if the host has GL (farm nodes,
#       or a broken host stack you want to bypass).
#   LOADOUT_GUI_HOST_FONTCONFIG=auto|0|<abs-path>
#       auto (default): if the host provides libfontconfig.so.1, LD_PRELOAD it
#       so the host lib+config pair stays version-consistent (the bundled EL8
#       2.13 cannot parse newer hosts' /etc/fonts and warns/errors on every
#       launch). LD_PRELOAD pins exactly this SONAME -- nothing else is
#       shadowed. 0: never preload (bundled copy via RUNPATH serves). An
#       absolute path: preload exactly that file.
#   LOADOUT_GUI_LIB64=<dir>
#       Overrides the loadout lib64 location probed from the wrapper's prefix
#       (rare; for split-prefix layouts where lib64 is not <prefix>/lib64).
#
# RPATH note: binaries carry RUNPATH (patchelf default), and LD_LIBRARY_PATH
# outranks RUNPATH in the loader -- so direct exec of the real binary still
# resolves everything via its baked RUNPATH, while this block can override
# resolution per-host without rebuilds. NEVER --force-rpath these payloads;
# that would invert the precedence and remove the escape hatch.
#
# Caller contract: the wrapper must have set $prefix (install root) before
# inlining this block. All exports are additive; caller-set values (including
# pre-set LD_LIBRARY_PATH/LD_PRELOAD/LIBGL_DRIVERS_PATH) are always preserved.

# ---- host GL probe + loadout Mesa/GLVND fallback (platform-conditioned) ----
if [ "${LOADOUT_GUI_HOST_GL:-auto}" = "auto" ]; then
  if command -v ldconfig >/dev/null 2>&1 \
     && ! ldconfig -p 2>/dev/null | grep -q 'libEGL\.so\.1'; then
    LOADOUT_GUI_HOST_GL=0
  else
    LOADOUT_GUI_HOST_GL=1
  fi
fi
if [ "${LOADOUT_GUI_HOST_GL:-1}" != "1" ]; then
  _gui_lib64="${LOADOUT_GUI_LIB64:-$prefix/lib64}"
  if [ -d "$_gui_lib64" ]; then
    export LD_LIBRARY_PATH="$_gui_lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    if [ -d "$_gui_lib64/dri" ]; then
      export LIBGL_DRIVERS_PATH="$_gui_lib64/dri${LIBGL_DRIVERS_PATH:+:$LIBGL_DRIVERS_PATH}"
    fi
  fi
  if [ -d "$prefix/share/glvnd/egl_vendor.d" ]; then
    export __EGL_VENDOR_LIBRARY_DIRS="$prefix/share/glvnd/egl_vendor.d${__EGL_VENDOR_LIBRARY_DIRS:+:$__EGL_VENDOR_LIBRARY_DIRS}"
  fi
fi
unset _gui_lib64

# ---- host fontconfig preference (platform-conditioned LD_PRELOAD) -----------
_fc_mode="${LOADOUT_GUI_HOST_FONTCONFIG:-auto}"
if [ "$_fc_mode" != "0" ]; then
  _host_fc=
  case "$_fc_mode" in
    auto)
      if command -v ldconfig >/dev/null 2>&1; then
        _host_fc=$(ldconfig -p 2>/dev/null | awk '/libfontconfig\.so\.1 /{print $NF; exit}')
      fi
      ;;
    /*) _host_fc="$_fc_mode" ;;
  esac
  if [ -n "$_host_fc" ] && [ -f "$_host_fc" ]; then
    LD_PRELOAD="$_host_fc${LD_PRELOAD:+:$LD_PRELOAD}"
    export LD_PRELOAD
  fi
fi
unset _host_fc _fc_mode# build/gtk3-launcher-env.sh -- GTK3-on-newer-hosts adaptation block for GUI
# launchers. Inlined by build scripts (cat it in; the installed wrapper must
# stay a self-contained script with no repo runtime dependency), AFTER
# build/gui-wrapper-env.sh, which owns the host-GL probe and the
# host-fontconfig LD_PRELOAD. This file owns only the two GTK3-specific
# adaptations; fontconfig parse spam is covered by that file.
#
# The problem it solves: the bundled EL8-era gdk-3 reads GNOME xsettings
# over GSettings on the Wayland display path (update_xft_settings), and
# newer GNOME removed the `antialiasing' key from the
# org.gnome.settings-daemon.plugins.xsettings schema. Any bundled-GTK3 app
# that opens a Wayland display therefore dies in GLib-GIO-ERROR before its
# first window -- even `gtkwave --version` aborts (exit 133). The X11 backend
# reads Xrm and is unaffected. A second, non-fatal wart rides along: host
# /usr gio modules are built against newer glib and fail to load against the
# bundled 2.56, printing undefined-symbol noise on every launch.
#
# Response, gated on a Wayland session with XWayland present (honours an
# explicitly set GDK_BACKEND/GIO_MODULE_DIR in all cases; EL8/X11 sessions
# take neither branch and behave exactly as before):
#   1. GDK_BACKEND=x11 -- take the X11 backend, which reads Xrm.
#   2. GIO_MODULE_DIR=<stable empty dir> -- stop loading the incompatible
#      host gio modules. Nothing bundled needs them (no bundled gio modules
#      ship); the apps read no dconf state.
#
# Knob (explicit wins over the probe):
#   LOADOUT_GTK_X11=auto|1|0
#       auto (default): enable when DISPLAY is set and the session looks like
#       Wayland (XDG_SESSION_TYPE=wayland or WAYLAND_DISPLAY set). 1: force
#       on. 0: never (pure passthrough, even on Wayland).

# ---- GTK3 Wayland-session abort guard (EL8 gdk vs newer GNOME) ----
if [ "${LOADOUT_GTK_X11:-auto}" = "auto" ]; then
  if [ -n "${DISPLAY:-}" ] \
     && { [ "${XDG_SESSION_TYPE:-}" = "wayland" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; }; then
    LOADOUT_GTK_X11=1
  else
    LOADOUT_GTK_X11=0
  fi
fi
if [ "${LOADOUT_GTK_X11:-0}" = "1" ]; then
  if [ -z "${GDK_BACKEND:-}" ]; then
    GDK_BACKEND=x11; export GDK_BACKEND
  fi
  if [ -z "${GIO_MODULE_DIR:-}" ]; then
    _gtk_gio_empty="${XDG_RUNTIME_DIR:-/tmp}/loadout-gio-empty"
    [ -d "$_gtk_gio_empty" ] || mkdir -p "$_gtk_gio_empty" 2>/dev/null
    if [ -d "$_gtk_gio_empty" ]; then
      GIO_MODULE_DIR="$_gtk_gio_empty"; export GIO_MODULE_DIR
    fi
    unset _gtk_gio_empty
  fi
fi

exec "$bin_dir/gvim.bin" -g "$@"
