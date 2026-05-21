# Bash Configuration

## File Layout

```
bash/
  bashrc          - Entry point (→ ~/.bashrc, ~/.bash_profile,
                    ~/.bash_login, ~/.profile). Loads functions.sh,
                    then sources config.sh and bashrc per layer.
  functions.sh    - Shared utilities loaded before any layer config
                    (path_*, is_truthy, fpcmp, array_slice, source_if_exists, etc.)
  global/         - Canonical upstream config. Don't edit locally — changes here
                    should be upstreamed to the repo.
    config.sh     - LOADOUT_CFG_* preference defaults
    bashrc        - PATH, colors, history, GRC, aliases, prompt, completions
    completions/  - Bundled bash completions (bat, rg, zoxide, hyperfine, watchexec)
    github.scop.bash-completion/  - Bundled bash-completion library (offline)
    grc/          - Generic Colorizer binaries and configs
  corp/           - Corp-level overrides (user-created, not committed here)
  site/           - Site-level overrides (user-created)
  project/        - Project-level overrides (user-created)
  user/           - Personal overrides (user-created)
```

## Loading Order

Files are sourced lowest-to-highest precedence: `global → corp → site → project → user`.
Each later layer overrides the previous.

```
bashrc
  └── functions.sh                     # shared utils (all layers can use these)
  └── global/config.sh                 # LOADOUT_CFG_* defaults
  └── corp/config.sh                   # (if exists) LOADOUT_CFG_* overrides
  └── site/config.sh                   # ...
  └── project/config.sh
  └── user/config.sh
  └── [exec into LOADOUT_CFG_PREFERRED_BASH]  # if set, executable, and not already running it
  └── global/bashrc                    # PATH, aliases, completions (exits if non-interactive)
  └── corp/bashrc                      # (if exists)
  └── site/bashrc
  └── project/bashrc
  └── user/bashrc
  └── unset_bashrc_local_vars          # clears all _* locals
  └── path_trim PATH                   # deduplicates PATH entries
```

## Adding Layer Overrides

Create files that will be picked up automatically — no edits to `global/` needed:

```bash
bash/user/config.sh      # override LOADOUT_CFG_* variables
bash/user/bashrc         # add aliases, functions, PATH entries
bash/corp/completions/mytool.bash  # add a completion (auto-sourced)
```

## Hook Injection Points

Each layer can inject code at specific points inside `global/bashrc` via numbered
files in `<layer>/global_hooks/`:

| File   | Injection point              |
|--------|------------------------------|
| `1.sh` | After functions loaded       |
| `2.sh` | After GLIBC detection        |
| `3.sh` | After PATH setup             |
| `4.sh` | After prompt configuration   |
| `5.sh` | Before bash completions      |
| `6.sh` | After bash completions loaded |
| `7.sh` | Late / deprecated            |

Example: `bash/corp/global_hooks/3.sh` — inject PATH entries after global PATH is set.
