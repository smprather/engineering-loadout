# tcsh helper scripts

POSIX-sh helpers for the parts of the bash env that a csh **alias** cannot
express. They exist so that "csh has no functions" never becomes a reason to drop
a feature — see `envs/tcsh/README.md`.

Three shapes, and picking the wrong one is the usual bug:

| shape | when | how it is called |
|---|---|---|
| **prints a result** | the alias needs a value (a path, a count, a list) | `` alias x 'cmd "`helper`"' `` |
| **does the work** | pure side effects on the filesystem or other processes | `alias x 'helper \!*'` |
| **prints shell code** | it must change *this* shell's cwd, `$path`, or environment | ``alias x 'eval "`helper`"'`` |

The third shape is the important one. A helper is a separate process: it cannot
`cd` for you, and it cannot `setenv` for you. It has to emit the csh command and
let the caller `eval` it.

Two constraints every helper here obeys:

- **`#!/bin/sh`, and actually POSIX.** These run on RedHat 7 through 9 and Suse.
  No bashisms — no arrays, no `[[`, no `local` (it is not POSIX, though every
  shell we target happens to support it; we still avoid it).
- **Silent on the boring path.** Startup silence is a hard requirement for this
  environment, and several of these run from `precmd`. Errors that the user
  cannot act on go to `/dev/null`, not to stderr.

`git-branch.sh` predates this directory and stays where it is (the prompt in
`global/tcshrc` references it by path).
