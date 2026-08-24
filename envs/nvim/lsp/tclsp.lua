---@brief
---
--- https://github.com/nmoroze/tclint
---
--- `tclsp` -- the Tcl language server shipped by tclint. Provides
--- diagnostics, formatting, and go-to-definition for Tcl and the Tcl-dialect
--- constraint files common in EDA flows (.tcl, .sdc, .xdc, .upf).
---
--- tclint is a pure-Python package (py3-none-any wheel) installed via the
--- loadout's `uv tool` mechanism; see build/ADDING_BINARIES.md. The `tclsp`
--- launcher at <prefix>/bin/tclsp is an isolated venv shim that resolves the
--- bundled Python 3.14 interpreter by absolute path, so it starts under
--- headless nvim and from GUI-launched editors alike.
---
--- `tclsp` has no `--version` flag (it is an LSP server, not a CLI); the
--- lint smoke in tests/prebuilt-binaries drives the real `tclint` binary
--- against a file with a known violation rather than trusting a banner.

---@type vim.lsp.Config
return {
  cmd = { "tclsp" },
  filetypes = { "tcl", "sdc" },
  root_markers = { "tclint.toml", ".tclint", ".git" },
  -- Tcl constraint files are frequently standalone (a single .sdc opened
  -- outside any project); without this the server never attaches.
  single_file_support = true,
}