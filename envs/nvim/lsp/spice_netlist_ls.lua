---@brief
---
--- https://github.com/smprather/spice-netlist-ls
---
--- `spice-netlist-ls` -- a formatter + linter + language server for SPICE
--- netlists (HSPICE golden, with dialects for ngspice, LTspice, and
--- Spectre-SPICE). Ships as two static-pie musl binaries bundled by this repo
--- (see build/build-prebuilt-bin.sh --tool spice-netlist-ls); `spicefmt` is
--- the CLI formatter/linter and `spice-netlist-ls` is this LSP server.
---
--- What it gives an offline farm node: diagnostics (undefined subckt, arity,
--- floating nodes, duplicate instances, unterminated subckt, .ends mismatch,
--- orphan continuation), `textDocument/formatting` (idempotent, the same
--- engine `spicefmt` uses), and `textDocument/definition` (X instantiation
--- -> `.subckt`, following `.include`/`.inc`/`.lib` transitively). A `.scs`
--- file with `simulator lang=spice`/`lang=spectre` directives gets
--- per-section dialect routing -- each section is parsed under the dialect
--- its directive selects, with diagnostics reported on global line numbers.
---
--- `cmd` resolves `spice-netlist-ls` from <prefix>/bin (on PATH under a
--- normal loadout install). No `--version`: the LSP binary is a server, so
--- the smoke in tests/prebuilt-binaries drives the sibling `spicefmt` CLI
--- (format + lint + idempotency) rather than trusting a banner.

-- nvim's builtin filetype.lua maps .sp / .scs / .cir -> `spice` already, but
-- `.subckt` is not in its table. Register it here (runs at lsp config time,
-- before any buffer loads) so the server attaches to .subckt decks too.
-- Format-on-save is handled centrally by conform.nvim's BufWritePre autocmd
-- in envs/nvim/lua/global/init.lua, which falls back to this server's
-- textDocument/formatting when no conform formatter is registered for the
-- filetype -- so no per-ft autocmd is needed.
vim.filetype.add({
  extension = {
    subckt = "spice",
  },
})

---@type vim.lsp.Config
return {
  cmd = { "spice-netlist-ls" },
  filetypes = { "spice", "cir", "scs", "subckt" },
  root_markers = { "spicefmt.toml", ".git" },
  -- Netlists are frequently standalone cards opened outside any project;
  -- without this the server never attaches to a single .sp picked from a
  -- shared tree.
  single_file_support = true,
}
