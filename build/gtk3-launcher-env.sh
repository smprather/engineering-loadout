# build/gtk3-launcher-env.sh -- GTK3-on-newer-hosts adaptation block for GUI
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
