#!/usr/bin/env python3
"""Prove markdown-oxide actually serves LSP over a real Obsidian vault.

`markdown-oxide --version` exits 0 from a binary that cannot resolve a single
wikilink, and this repo has shipped that class of false green before (gtkwave's
converters exited 255 printing an error and scored OK; ngspice with a dead
datadir is silent). So the smoke drives the actual protocol:

    initialize -> initialized -> didOpen -> textDocument/definition

on a two-note vault, and requires the definition of `[[note-b]]` to resolve to
note-b.md. That exercises the whole point of the package -- PKM link
resolution against a `.obsidian` vault root -- not merely that the ELF loads.

Usage:  lsp-smoke.py /path/to/markdown-oxide
Exits non-zero with a diagnostic on any failure.
"""

import json
import os
import subprocess
import sys
import tempfile


def frame(payload: dict) -> bytes:
    body = json.dumps(payload).encode()
    return b"Content-Length: %d\r\n\r\n%s" % (len(body), body)


def read_message(stream) -> dict | None:
    """Read one Content-Length-framed LSP message."""
    length = None
    while True:
        line = stream.readline()
        if not line:
            return None
        line = line.strip()
        if not line:
            break
        if line.lower().startswith(b"content-length:"):
            length = int(line.split(b":", 1)[1])
    if length is None:
        return None
    return json.loads(stream.read(length))


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    # Must be absolute: the server is spawned with cwd=<temp vault>, so a
    # relative path would resolve against the vault and vanish.
    server = os.path.abspath(sys.argv[1])
    if not os.path.isfile(server) or not os.access(server, os.X_OK):
        print(f"FAIL: not an executable file: {server}", file=sys.stderr)
        return 2

    with tempfile.TemporaryDirectory(prefix="moxide-smoke-") as vault:
        # `.obsidian/` is what makes this a vault root for markdown-oxide
        # (see root_markers in envs/nvim/lsp/markdown_oxide.lua).
        os.mkdir(os.path.join(vault, ".obsidian"))
        note_a = os.path.join(vault, "note-a.md")
        note_b = os.path.join(vault, "note-b.md")
        with open(note_a, "w") as fh:
            fh.write("# Note A\n\nLink to [[note-b]] here.\n")
        with open(note_b, "w") as fh:
            fh.write("# Note B\n\nTarget of the wikilink.\n")

        proc = subprocess.Popen(
            [server],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            cwd=vault,
        )
        assert proc.stdin and proc.stdout

        root_uri = "file://" + vault
        uri_a = "file://" + note_a

        def send(msg):
            proc.stdin.write(frame(msg))
            proc.stdin.flush()

        send(
            {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "processId": os.getpid(),
                    "rootUri": root_uri,
                    "workspaceFolders": [{"uri": root_uri, "name": "smoke"}],
                    "capabilities": {},
                },
            }
        )

        # The server emits window/logMessage notifications before the
        # initialize result, so match on the request id rather than taking
        # whatever arrives first.
        init = None
        for _ in range(200):
            msg = read_message(proc.stdout)
            if msg is None:
                break
            if msg.get("id") == 1:
                init = msg
                break
        if not init or "result" not in init:
            proc.kill()
            print(f"FAIL: no initialize result (got {init!r})", file=sys.stderr)
            print(proc.stderr.read().decode(errors="replace"), file=sys.stderr)
            return 1
        caps = init["result"].get("capabilities", {})
        if not caps.get("definitionProvider"):
            proc.kill()
            print(f"FAIL: server does not advertise definitionProvider; capabilities={sorted(caps)}", file=sys.stderr)
            return 1

        send({"jsonrpc": "2.0", "method": "initialized", "params": {}})
        send(
            {
                "jsonrpc": "2.0",
                "method": "textDocument/didOpen",
                "params": {
                    "textDocument": {
                        "uri": uri_a,
                        "languageId": "markdown",
                        "version": 1,
                        "text": open(note_a).read(),
                    }
                },
            }
        )

        # Line 2 is "Link to [[note-b]] here."; character 12 sits inside the
        # wikilink target.
        send(
            {
                "jsonrpc": "2.0",
                "id": 2,
                "method": "textDocument/definition",
                "params": {
                    "textDocument": {"uri": uri_a},
                    "position": {"line": 2, "character": 12},
                },
            }
        )

        # Skip logs/diagnostics/progress until the id=2 response arrives.
        resolved = None
        for _ in range(200):
            msg = read_message(proc.stdout)
            if msg is None:
                break
            if msg.get("id") == 2:
                resolved = msg
                break

        proc.kill()
        proc.wait(timeout=10)

        if resolved is None:
            print("FAIL: no response to textDocument/definition", file=sys.stderr)
            print(proc.stderr.read().decode(errors="replace"), file=sys.stderr)
            return 1

        result = resolved.get("result")
        if not result:
            print(
                f"FAIL: wikilink [[note-b]] did not resolve (result={result!r}). "
                "The server started but PKM link resolution is dead.",
                file=sys.stderr,
            )
            return 1

        locations = result if isinstance(result, list) else [result]
        targets = [loc.get("uri") or loc.get("targetUri") or "" for loc in locations]
        if not any(t.endswith("note-b.md") for t in targets):
            print(f"FAIL: definition resolved to {targets!r}, expected note-b.md", file=sys.stderr)
            return 1

    print("  LSP smoke OK: [[note-b]] resolved to note-b.md")
    return 0


if __name__ == "__main__":
    sys.exit(main())
