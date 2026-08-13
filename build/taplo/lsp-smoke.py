#!/usr/bin/env python3
"""Prove taplo actually serves LSP -- formatting AND diagnostics -- offline.

`taplo --version` exits 0 from a binary that cannot serve a single request, and
this repo has shipped that class of false green before (gtkwave's converters
exited 255 printing an error and scored OK; ngspice with a dead datadir is
silent). So the smoke drives the real protocol:

    initialize -> initialized -> didOpen -> textDocument/formatting
                                         -> publishDiagnostics

and requires (a) a formatting edit that normalises `a=1` to `a = 1`, and (b) at
least one diagnostic on a genuinely broken document.

The diagnostics half is the part that matters for an offline farm node. taplo
has two independent validation layers:

  * the TOML grammar itself, which is compiled in and always available; and
  * JSON Schema validation, which resolves schemas from a catalog. Upstream's
    default catalogs are remote (schemastore.org / taplo.tamasfe.dev) and
    therefore dead on an air-gapped node -- where taplo does not fail, it
    silently drops to grammar-only checking.

With a catalog path passed as the second argument, this smoke also proves the
OFFLINE SCHEMA path over LSP. That is a genuinely different channel from the
CLI's `--schema-catalog` flag: `taplo lsp stdio` takes no such flag, so the
editors hand catalogs over as LSP client settings instead (see
envs/nvim/lsp/taplo.lua and envs/helix/languages.toml). Testing only the CLI
would leave the editor path -- the one users actually touch -- unverified.

Usage:  lsp-smoke.py /path/to/taplo [/path/to/catalog.json]
Exits non-zero with a diagnostic on any failure.
"""

import json
import os
import pathlib
import signal
import subprocess
import sys
import tempfile

# The server is a child process we drive over pipes; if it wedges (which is the
# exact failure an offline schema fetch would produce) the test must fail
# rather than hang a release gate forever.
TIMEOUT_S = 30


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
    if len(sys.argv) not in (2, 3):
        print(__doc__, file=sys.stderr)
        return 2
    # Must be absolute: the server is spawned with cwd=<temp workspace>, so a
    # relative path would resolve against the workspace and vanish.
    server = os.path.abspath(sys.argv[1])
    if not os.path.isfile(server) or not os.access(server, os.X_OK):
        print(f"FAIL: not an executable file: {server}", file=sys.stderr)
        return 2

    catalog = None
    if len(sys.argv) == 3:
        catalog = os.path.abspath(sys.argv[2])
        if not os.path.isfile(catalog):
            print(f"FAIL: no such catalog: {catalog}", file=sys.stderr)
            return 2

    with tempfile.TemporaryDirectory(prefix="taplo-smoke-") as ws:
        root = pathlib.Path(ws)
        # Unformatted but VALID -- drives textDocument/formatting.
        ugly = root / "ugly.toml"
        ugly.write_text('[package]\nname="demo"\nversion   =    "1.0"\n')
        # Grammar-level breakage -- drives publishDiagnostics without needing a
        # schema. An unterminated string cannot parse under any schema setting.
        broken = root / "broken.toml"
        broken.write_text('[package\nname = "demo\n')
        # Grammatically PERFECT, schema-invalid. Only the catalog catches this,
        # so it is the one document that proves offline schemas reached the LSP.
        bogus = root / "Cargo.toml"
        bogus.write_text('[package]\nname = "demo"\nversion = "0.1.0"\nnot_a_real_cargo_key = 3\n')

        proc = subprocess.Popen(
            [server, "lsp", "stdio"],
            cwd=ws,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )

        # The read loop blocks on the server's stdout. A server that never
        # answers -- the shape an accidental network fetch takes when the
        # network is namespaced away -- would otherwise wedge a build or a
        # release gate forever, so cap the whole exchange.
        def _timeout(_sig, _frm):
            raise TimeoutError(f"no answer from the language server within {TIMEOUT_S}s")

        signal.signal(signal.SIGALRM, _timeout)
        signal.alarm(TIMEOUT_S)
        try:
            rc = drive(proc, root, ugly, broken, bogus, catalog)
        except TimeoutError as exc:
            print(f"FAIL: {exc}", file=sys.stderr)
            rc = 1
        finally:
            signal.alarm(0)
            proc.kill()
            proc.wait(timeout=TIMEOUT_S)
        return rc


def drive(
    proc,
    root: pathlib.Path,
    ugly: pathlib.Path,
    broken: pathlib.Path,
    bogus: pathlib.Path,
    catalog: str | None,
) -> int:
    root_uri = root.as_uri()

    def send(payload: dict) -> None:
        proc.stdin.write(frame(payload))
        proc.stdin.flush()

    send(
        {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "processId": os.getpid(),
                "rootUri": root_uri,
                "capabilities": {
                    "textDocument": {
                        "publishDiagnostics": {},
                        "formatting": {"dynamicRegistration": False},
                    }
                },
                # Mirror what envs/nvim/lsp/taplo.lua ships.
                "initializationOptions": {
                    "configurationSection": "evenBetterToml",
                    "cachePath": str(root / "cache"),
                },
            },
        }
    )
    init = read_message(proc.stdout)
    if init is None or "result" not in init:
        print(f"FAIL: no initialize result (got {init!r})", file=sys.stderr)
        return 1
    caps = init["result"].get("capabilities", {})
    if not caps.get("documentFormattingProvider"):
        print("FAIL: server does not advertise documentFormattingProvider", file=sys.stderr)
        return 1

    send({"jsonrpc": "2.0", "method": "initialized", "params": {}})
    # taplo pulls its settings via workspace/configuration. `catalogs` is
    # ALWAYS the bundled path or empty -- never upstream's remote default --
    # so a run that reaches the network fails instead of passing by luck.
    if catalog:
        settings = {
            "schema": {
                "enabled": True,
                "catalogs": [pathlib.Path(catalog).as_uri()],
                "repositoryEnabled": False,
            }
        }
    else:
        settings = {"schema": {"enabled": False, "catalogs": [], "repositoryEnabled": False}}
    send(
        {
            "jsonrpc": "2.0",
            "method": "workspace/didChangeConfiguration",
            "params": {"settings": {"evenBetterToml": settings}},
        }
    )

    docs = [ugly, broken] + ([bogus] if catalog else [])
    for path in docs:
        send(
            {
                "jsonrpc": "2.0",
                "method": "textDocument/didOpen",
                "params": {
                    "textDocument": {
                        "uri": path.as_uri(),
                        "languageId": "toml",
                        "version": 1,
                        "text": path.read_text(),
                    }
                },
            }
        )

    send(
        {
            "jsonrpc": "2.0",
            "id": 2,
            "method": "textDocument/formatting",
            "params": {
                "textDocument": {"uri": ugly.as_uri()},
                "options": {"tabSize": 2, "insertSpaces": True},
            },
        }
    )

    formatted = None
    diagnosed = False
    # Schema diagnostics are only expected when a catalog was supplied; with no
    # catalog this stays satisfied so the loop still terminates.
    schema_flagged = catalog is None
    # One read loop for every answer: the formatting response and the
    # diagnostics arrive interleaved with taplo's own requests
    # (workspace/configuration, client/registerCapability), which must be
    # answered or the server stalls waiting on them.
    while formatted is None or not diagnosed or not schema_flagged:
        msg = read_message(proc.stdout)
        if msg is None:
            print("FAIL: server closed the stream early", file=sys.stderr)
            return 1

        if msg.get("id") is not None and "method" in msg:
            # Server -> client request: must be answered.
            result = [settings] if msg["method"] == "workspace/configuration" else None
            send({"jsonrpc": "2.0", "id": msg["id"], "result": result})
            continue

        if msg.get("id") == 2:
            if "error" in msg:
                print(f"FAIL: formatting error: {msg['error']}", file=sys.stderr)
                return 1
            formatted = msg.get("result") or []
            continue

        if msg.get("method") == "textDocument/publishDiagnostics":
            params = msg.get("params", {})
            diags = params.get("diagnostics") or []
            if params.get("uri") == broken.as_uri() and diags:
                diagnosed = True
            if params.get("uri") == bogus.as_uri():
                # taplo publishes an empty set first, then re-publishes once the
                # schema resolves -- so only a NON-empty set counts here.
                if any("not_a_real_cargo_key" in d.get("message", "") for d in diags):
                    schema_flagged = True

    if not formatted:
        print("FAIL: formatting returned no edits for an unformatted document", file=sys.stderr)
        return 1
    new_text = "".join(edit.get("newText", "") for edit in formatted)
    if 'name = "demo"' not in new_text:
        print(f'FAIL: formatter did not normalise `name="demo"`; got: {new_text!r}', file=sys.stderr)
        return 1

    extra = "; offline catalog flagged an unknown Cargo.toml key" if catalog else ""
    print(f"  LSP OK: formatting normalised spacing; broken document produced diagnostics{extra}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
