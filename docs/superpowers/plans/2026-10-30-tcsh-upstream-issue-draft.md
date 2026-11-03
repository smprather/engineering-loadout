# tcsh upstream issue -- POSTED 2026-10-31 as https://github.com/tcsh-org/tcsh/issues/128

Target: https://github.com/tcsh-org/tcsh/issues (new issue). Post only after
the user approves the text below. Loadout already works around it
(`envs/tcsh/global/helpers/prompt-markers`, commit `57a1844`); the issue is for
everyone else.

---

**Title:** Multi-line prompt (`\n` in `prompt`) is drawn as a soft wrap, so it
breaks when the terminal reflows on resize (tmux zoom, WezTerm, kitty, VTE)

**Description**

When `prompt` contains `\n`, tcsh does not emit a line feed for it. It moves to
the last column and pads the row (observed bytes: `ESC[80G` + two spaces + CR
on an 80-column terminal), so the terminal autowraps to the next row. To the
terminal that is a *soft* wrap: the two prompt lines are one logical line.

Terminals that reflow text on resize (tmux when a pane's width changes,
including `resize-pane -Z` zoom; WezTerm; kitty; VTE-based terminals; Windows
Terminal) re-wrap soft-wrapped lines at the new width. The prompt's lines then
merge onto one row, and changing the width back scrambles them. Lines printed by
programs (real LF) are unaffected, as is bash's multi-line `PS1`.

**Reproduce** (tcsh 6.24.16 on Arch Linux and 6.20.00 on AlmaLinux 8; tmux 3.x;
a private tmux server so no real session is touched):

```sh
printf 'set prompt = "AAA\\nBBB> "\n' > /tmp/rc && mkdir -p /tmp/h && cp /tmp/rc /tmp/h/.tcshrc
tmux -L repro -f /dev/null new-session -d -s m -x 60 -y 12 "env -i HOME=/tmp/h TERM=tmux-256color tcsh"
sleep 1; tmux -L repro send-keys -t m Enter; sleep 0.5
tmux -L repro capture-pane -J -p -t m     # -J joins soft-wrapped rows:  "AAA        ...        BBB>"
tmux -L repro resize-window -t m -x 120   # wider: AAA and BBB> now share one row on screen
tmux -L repro capture-pane -p -t m
tmux -L repro kill-server
```

**Expected:** each `\n` in the prompt produces a hard line break (CR LF), so the
prompt keeps its line structure across resizes, like `PS1` in bash.

**Workaround** (what we ship): print every prompt line except the last from
`precmd` as normal output, keep only the last line in `prompt`, and bind `^L`
with `bindkey -c` to a command that clears and reprints those lines, since tcsh
redraws only `prompt`.

**Possible fix:** in the prompt-drawing path (`ed.refresh.c`), emit a real
newline for a literal newline in the prompt instead of padding to a wrap,
keeping the virtual-cursor bookkeeping in step.
