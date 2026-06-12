# Bash Configuration

## Layer system

```
bash/global/    ← upstream, managed here — do not modify locally
bash/corp/      ← corporation-level overrides  (user-created)
bash/site/      ← site-level overrides         (user-created)
bash/team/      ← team-level overrides          (user-created)
bash/project/   ← project-level overrides      (user-created)
bash/user/      ← personal overrides            (user-created)
```

Layer order (lowest → highest precedence):
`global → corp → site → team → project → user`.

Each layer sources `config.sh` (preferences) then `bashrc` (aliases/prompt).
Override any `LOADOUT_CFG_*` variable in your layer's `config.sh`:

```bash
# bash/user/config.sh
export LOADOUT_CFG_PREFERRED_VI=nvim
export LOADOUT_CFG_ENABLE_STARSHIP=1
export LOADOUT_CFG_ENABLE_FZF=1
export LOADOUT_CFG_PREFERRED_BASH=/home/user/.local/bin/bash
```

## Hook injection points

Insert code at precise points in the shell startup sequence:

| Hook | Fires after |
|------|-------------|
| `global_hooks/1.sh` | Functions loaded |
| `global_hooks/2.sh` | glibc detection |
| `global_hooks/3.sh` | PATH setup |
| `global_hooks/4.sh` | Prompt configured |
| `global_hooks/5.sh` | Before completions |
| `global_hooks/6.sh` | Completions loaded |
| `global_hooks/7.sh` | Late / final |

Example — inject a site-specific EDA tool path at hook 3:

```bash
# bash/site/global_hooks/3.sh
path_prepend_if_dir /tools/cadence/bin
path_prepend_if_dir /tools/synopsys/bin
```

## Notable aliases

```bash
b / bb / bbb …        # cd .. up 1–10 levels
cdd / cddd …          # cd to Nth most-recently-modified directory
p / cdp               # bookmark cwd / return to it
g                     # ripgrep (falls back to grep -r -i)
f                     # fd (falls back to find .)
vi / vim              # LOADOUT_CFG_PREFERRED_VI
v                     # nvim -n -R - (read stdin, read-only)
fvi                   # fzf file picker → open in editor
t                     # exec bash (reload shell)
w                     # type -a (where is this defined?)
we                    # watchexec --clear --poll 500
ga / gs / gc / gp     # git add / status / commit / push
gsp                   # git stash, pull, pop
lh / la / lah         # ls --human / --all / both
rs                    # rsync with progress, excludes .snapshot/
du / dum              # disk usage sorted by size (GB / MB)
extract_rpm           # rpm2cpio | cpio -idmv
```
