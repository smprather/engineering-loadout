#!/bin/sh
# Print the current git branch, or nothing at all. Used by the tcsh prompt.
#
# Why a script instead of inlining this in the precmd alias: csh cannot redirect
# stderr separately from stdout (there is no `2>/dev/null`), so an inline version
# has to use `|&`, which merges git's error text INTO the captured value -- and a
# repo with no commits yet, or a detached HEAD, then renders git's multi-line
# "Use '--' to separate paths from revisions" hint straight into the user's prompt.
#
# symbolic-ref (not rev-parse) is deliberate: it resolves correctly on an unborn
# HEAD (a fresh `git init` with no commits), where rev-parse --abbrev-ref fails.
# A detached HEAD has no symbolic ref, so we fall back to a short sha.
#
# Silence on failure is the contract: outside a repo this prints nothing and exits 0.

branch=$(git symbolic-ref --short HEAD 2>/dev/null) || branch=""

if [ -z "$branch" ]; then
    # Detached HEAD (or not a repo at all -- then this fails too and stays empty).
    branch=$(git rev-parse --short HEAD 2>/dev/null) || branch=""
fi

[ -n "$branch" ] && printf '%s' "$branch"
exit 0
