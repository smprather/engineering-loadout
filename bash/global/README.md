# bash/global

Canonical upstream bash config. Changes here should be upstreamed to the repo,
not made locally — use a layer override instead (`bash/user/`, `bash/corp/`, etc.).

## GRC (Generic Colorizer)

The `grc/` directory contains a patched GRC binary with hardcoded config paths
baked in so it works without system installation:

- `grc/bin/grc` — hardcoded: `conffilenames = [home + '/.config/bash/global/grc/etc/grc.conf']`
- `grc/bin/grcat` — hardcoded: `conffilepath += [home + '/.config/bash/global/grc/share/grc/']`

If you rebuild GRC from source, patch these paths accordingly.
Enabled via `LOADOUT_CFG_ENABLE_GRC=1` in `config.sh`.

## Bash Completions (`completions/`)

Bundled completions for offline environments. Sourced automatically by `global/bashrc`.
All `*.bash` files in any layer's `completions/` directory are sourced automatically.

To regenerate a completion from the tool's own generator:
```bash
rg --generate complete-bash > completions/rg.bash
bat --generate-shell-completion bash > completions/bat.bash
```

## github.scop.bash-completion

Vendored [scop/bash-completion](https://github.com/scop/bash-completion) library,
used as the base completion framework loaded before all other completions.
Required for most completion scripts to work correctly in offline environments
where the system bash-completion package may be absent or outdated.
