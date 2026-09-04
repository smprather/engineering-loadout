Bug: @envs install fails when its source config file is read-only (_rewrite_shared_prefix_line can't rewrite a mode-preserved copy)

Component: engineering-loadout — loadout_main.py
Seen in: v2026.08.28-1-gdb134db (install/copy mode, @envs)
Severity: breaks loadout install @envs for any deployment whose install source tree has read-only config files.

Symptom

WARNING: config files failed: [Errno 13] Permission denied: '/home/USER/.config/bash/global/config.sh'
...
  File "loadout_main.py", line 3962, in _rewrite_shared_prefix_line
    with open(cfg, "w") as f:
PermissionError: [Errno 13] Permission denied: '/home/USER/.config/bash/global/config.sh'

The config files install step is reported FAILED; global/config.sh is left without its LOADOUT_CFG_SHARED_PREFIX baked in.

Root cause

@envs installs the shell config by copying from the loadout export tree while preserving source file modes, then rewrites one line in place:

1. _install_env_bash → install_bash → _copy_tree_item / install_path use shutil.copy2(src, dest), which copies the source file's permission bits. If the source envs/bash/global/config.sh in the export tree is read-only (mode 0o444), the freshly installed ~/.config/bash/global/config.sh is 0o444 too
2. _install_env_bash then calls _mirror_shared_prefix → _rewrite_shared_prefix_line (line ~3946), which does:
   with open(cfg, "w") as f:      # line 3962 — no chmod first
       f.write(new_text)
   Opening a 0o444 file for writing raises PermissionError.

Minimal repro (isolated from the loadout):

import os, shutil
# read-only SOURCE (like a read-only export tree)
open("src","w").write("export LOADOUT_CFG_SHARED_PREFIX=\n"); os.chmod("src", 0o444)
shutil.copy2("src","dst")                       # dst inherits 0o444
open("dst","w")                                 # PermissionError: [Errno 13]

A pre-chmod on the destination home does not help: install_bash does remove_path(dest) + copy2, so it deletes and recreates the file with the source's 0o444 mode on every run.

Why this is a real-world config

A shared/near-native deployment can legitimately mark its published trees immutable (chmod -R a-w) to enforce "version leaves are read-only." The export tree is then both an artifact and an install source; @envs copying mode-preserving turns that into a per-user install failure. The installer should not assume its own freshly-installed target files are writable.

Suggested fix

Make _rewrite_shared_prefix_line not depend on the copied source mode. Two acceptable options:

Option A — chmod the target writable before rewriting (smallest change):

    if not n:
        eprint(f"  WARNING: LOADOUT_CFG_SHARED_PREFIX line not found in {cfg}; not baked")
        return False
    # The file may have been copied read-only from a read-only install source
    # (shutil.copy2 preserves source mode). Ensure we can rewrite our own file.
    try:
        os.chmod(cfg, os.stat(cfg).st_mode | stat.S_IWUSR)
    except OSError:
        pass
    with open(cfg, "w") as f:
        f.write(new_text)

Option B — atomic mkstemp + os.replace (preferred; matches the pattern already used at lines ~2948-2953 for relocation, and avoids a partial write):

    fd, tmp = tempfile.mkstemp(prefix=".loadout-cfg.", dir=os.path.dirname(cfg))
    try:
        with os.fdopen(fd, "w") as f:
            f.write(new_text)
        # normalize to a sane writable-by-owner mode; the source may be read-only
        os.chmod(tmp, 0o644)
        os.replace(tmp, cfg)
    except BaseException:
        with contextlib.suppress(FileNotFoundError):
            os.unlink(tmp)
        raise

Option B also fixes the more general class: any installed config file @envs later edits in place could hit the same wall if the source is read-only. Consider auditing other in-place open(..., "w") edits of installed config for the same assumption (e.g. install_tealdeer_config, the tcsh path in _mirror_shared_prefix).

Note on scope

This affects both the bash (.config/bash/global/config.sh, line ~3992) and tcsh (.config/tcsh/global/config.csh, line ~4003) branches of _mirror_shared_prefix, since both route through _rewrite_shared_prefix_line.
