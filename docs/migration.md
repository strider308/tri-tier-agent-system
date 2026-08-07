# Installation migration

Migration upgrades an owned isolated installation to manifest schema 2 and the
current CLI version. It does not import or overwrite a private `.codex`
installation.

Inspect the migration first:

```powershell
.\src\tri-agent.ps1 migrate-plan `
    -InstallRoot "C:\path\to\isolated" `
    -Json
```

Apply only with both exact confirmations:

```powershell
.\src\tri-agent.ps1 migrate-apply `
    -InstallRoot "C:\path\to\isolated" `
    -ConfirmInstallRoot "C:\path\to\isolated" `
    -ConfirmInstallId "<install-id>" `
    -Json
```

The existing installation ID is preserved. The prior payload is moved to a
timestamped backup. Migration fails closed for unmanaged targets, unsupported
manifest schemas, invalid confirmations, modified payloads, or an unfinished
transaction.
