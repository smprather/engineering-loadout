# completions

Bundled shell completions for offline environments. Bash completions are
sourced automatically by `global/bashrc`.

| File | Tool | Shell |
|------|------|-------|
| `bat.bash` | [bat](https://github.com/sharkdp/bat) | bash |
| `rg.bash` | [ripgrep](https://github.com/BurntSushi/ripgrep) | bash |
| `zoxide.bash` | [zoxide](https://github.com/ajeetdsouza/zoxide) | bash |
| `hyperfine.bash` | [hyperfine](https://github.com/sharkdp/hyperfine) | bash |
| `watchexec.bash` | [watchexec](https://github.com/watchexec/watchexec) | bash |
| `_zoxide` | zoxide | zsh |
| `zoxide.fish` | zoxide | fish |
| `zoxide.elv` | zoxide | elvish |
| `zoxide.nu` | zoxide | nushell |
| `zoxide.ts` | zoxide | typescript (carapace) |
| `module.bash` | (internal) | bash |

To regenerate a completion, run the tool's built-in generator and drop the
output here. Example: `rg --generate complete-bash > rg.bash`
