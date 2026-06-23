# PowerShell Windows Bundle

Bundled artifact:

- `PowerShell-7.6.3-win-x64.zip`
- Source: `https://github.com/PowerShell/PowerShell/releases/download/v7.6.3/PowerShell-7.6.3-win-x64.zip`
- SHA256: `07DDB0D00B660459560EF82A9841DA7705B27CD5DCCA5A0D7B025A98ECA29ECA`

The ZIP is stored as `.part-NNN` chunks to keep each Git object below the
repository's normal 45 MiB chunk size. `loadout-pwsh-bootstrap.ps1` and
`loadout.ps1` rejoin the parts at install time.
