#!/bin/sh
# loadout uvx launcher -- uvx entry point for the loadout's uv.
#
# Upstream uvx is the same binary as uv invoked as `uv tool run`; the payload
# ships ONE binary (bin/uv.bin), so this wrapper supplies the uvx name.  It
# delegates through bin/uv (the launcher, not the raw binary) so the
# interpreter pin and any future launcher policy live in exactly one place.
#
# `uv tool run --version` is rejected by uv, so -V/--version is answered by uv
# itself (uvx is uv); everything else is `uv tool run ...`, which is exactly
# what upstream uvx does.
bin_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 1

case "${1:-}" in
-V | --version)
    exec "$bin_dir/uv" "$1"
    ;;
esac
exec "$bin_dir/uv" tool run "$@"
