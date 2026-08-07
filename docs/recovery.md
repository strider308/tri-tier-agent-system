# Installation recovery

Installation, upgrade, migration, and uninstall operations use a transaction
journal next to the target directory. A new operation refuses to start while a
journal exists.

Inspect the installation first:

```powershell
.\src\tri-agent.ps1 install-status `
    -InstallRoot "C:\path\to\isolated" `
    -Json
```

Recover an interrupted operation:

```powershell
.\src\tri-agent.ps1 install-recover `
    -InstallRoot "C:\path\to\isolated" `
    -Json
```

Recovery follows fail-closed rules:

1. Keep a healthy committed target.
2. Restore a valid backup when the target is absent or owned-but-invalid.
3. Remove an abandoned staging directory when no target exists.
4. Never delete or replace an unmanaged target.
5. Return `MANUAL_REVIEW_REQUIRED` when automatic recovery is unsafe.

Uninstall is reversible. It moves the owned installation into the sibling
`.tri-tier-backups` directory instead of deleting it.
