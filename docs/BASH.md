# Bash Configuration

## Layer system

```
bash/global/    <- upstream, managed here -- do not modify locally
bash/corp/      <- corporation-level overrides  (user-created)
bash/site/      <- site-level overrides         (user-created)
bash/team/      <- team-level overrides          (user-created)
bash/project/   <- project-level overrides      (user-created)
bash/user/      <- personal overrides            (user-created)
```

Layer order (lowest -> highest precedence):
`global -> corp -> site -> team -> project -> user`.

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

Example -- inject a site-specific EDA tool path at hook 3:

```bash
# bash/site/global_hooks/3.sh
path_prepend_if_dir /tools/cadence/bin
path_prepend_if_dir /tools/synopsys/bin
```

## Prompt & shell integration

The prompt is configured in `bash/global/bashrc` and serves the whole terminal
matrix (raw wezterm, tmux-in-wezterm, tmux-in-st, st/xterm, `dumb`/`linux`) with
login and `exec bash` behaving identically.

| Variable | Default | Purpose |
|----------|---------|---------|
| `LOADOUT_CFG_ENABLE_STARSHIP` | `1` | Starship prompt (falls back to the built-in prompt) |
| `LOADOUT_CFG_ENABLE_WEZTERM_SHELL_INTEGRATION` | `1` | Source the loadout-owned `wezterm.sh` (OSC 133 semantic zones, OSC 7 cwd, user vars). Safe everywhere; self-skips `dumb`/`linux` and non-interactive shells |
| `LOADOUT_CFG_WEZTERM_SHELL_INTEGRATION` | `""` | Explicit path to `wezterm.sh`; empty auto-resolves (vendored copy -> wezterm-binary-relative -> shared prefix). Set from a `--dest-dir` installer to pin it. Never `/etc` |

WezTerm shell integration is **vendored** at `bash/global/wezterm/wezterm.sh`
(the bundled wezterm runtime ships only `wezterm shell-completion`, not the
integration script) and is loaded from user-writable space only -- never
`/etc/profile.d/wezterm.sh`. tmux-in-wezterm needs `set -g allow-passthrough on`
for the OSC sequences to reach wezterm.

> **Editing the prompt block?** It is clobber-sensitive: the loadout does not own
> `PROMPT_COMMAND` and Starship does not always hook through it. The wrong
> "simplification" makes the Starship prompt vanish on login shells while still
> working after `exec bash`. Read **`bash/global/README.md` -> "Prompt & shell
> integration"** for the full rationale, the required ordering, and how to verify
> with a real PTY (not `bash -lic`, which hides the bug).

## Notable aliases

```bash
b / bb / bbb ...        # cd .. up 1-10 levels
cdd / cddd ...          # cd to Nth most-recently-modified directory
p / cdp               # bookmark cwd / return to it
g                     # ripgrep (falls back to grep -r -i)
f                     # fd (falls back to find .)
vi / vim              # LOADOUT_CFG_PREFERRED_VI
v                     # nvim -n -R - (read stdin, read-only)
fvi                   # fzf file picker -> open in editor
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
