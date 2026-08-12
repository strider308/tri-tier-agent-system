# Isolated installation

Tri-Tier's public installer copies the tested runtime into an isolated application directory. This is technical-alpha software: inspect the plan, keep a backup, and review the result before using it with real work.

## Requirements and default root

The currently validated platform is Windows with PowerShell 7 and Git. A compatible coding-agent harness is needed for actual agent dispatch; it is not bundled or assumed by the installer.

The default target is:

```text
%LOCALAPPDATA%\TriTierAgentSystem\isolated
```

The default is isolated from the source checkout. It does not modify `PATH`, `$HOME\.codex`, `CODEX_HOME`, or unrelated Codex settings.

## Check, plan, and apply

Use the CLI from the repository root. Both checks are read-only:

```powershell
$TriTierRoot = Join-Path $env:LOCALAPPDATA 'TriTierAgentSystem\isolated'

.\src\tri-agent.ps1 compatibility-check `
    -InstallRoot $TriTierRoot -Json

.\src\tri-agent.ps1 install-plan `
    -InstallRoot $TriTierRoot -Json
```

Apply only after reviewing the plan. The confirmation must exactly match the normalized target:

```powershell
.\src\tri-agent.ps1 install-apply `
    -InstallRoot $TriTierRoot `
    -ConfirmInstallRoot $TriTierRoot `
    -Json
```

An existing owned installation also requires its current `installId` for upgrade, migration, or uninstall operations. Read it with:

```powershell
.\src\tri-agent.ps1 install-status -InstallRoot $TriTierRoot -Json
```

## Installed launchers

The installed launchers are placed under `bin`:

```powershell
& "$TriTierRoot\bin\tri-agent.ps1" version
& "$TriTierRoot\bin\tri-agent.ps1" doctor
cmd.exe /d /c "`"$TriTierRoot\bin\tri-agent.cmd`" version"
```

These commands can be run from an unrelated working directory. The installed runtime should not need the repository to be the current directory.

## Custom roots and safety boundaries

Pass a custom root with `-InstallRoot`, and repeat the same value for `-ConfirmInstallRoot` when applying:

```powershell
$CustomRoot = 'D:\Tools\TriTierAgentSystem\isolated'
.\src\tri-agent.ps1 compatibility-check -InstallRoot $CustomRoot -Json
.\src\tri-agent.ps1 install-plan -InstallRoot $CustomRoot -Json
.\src\tri-agent.ps1 install-apply `
    -InstallRoot $CustomRoot `
    -ConfirmInstallRoot $CustomRoot `
    -Json
```

The installer rejects filesystem roots, source-overlapping targets, `$HOME\.codex`, `CODEX_HOME`, unsafe existing targets, symbolic links, and reparse-point ancestors. It does not change `PATH`.

## Upgrade and migration ownership

An owned target has an `installId` in its manifest. Upgrades and migrations require that ID so an unrelated or modified target cannot be silently taken over:

```powershell
.\src\tri-agent.ps1 migrate-plan -InstallRoot $TriTierRoot -Json
.\src\tri-agent.ps1 migrate-apply `
    -InstallRoot $TriTierRoot `
    -ConfirmInstallRoot $TriTierRoot `
    -ConfirmInstallId '<install-id-from-install-status>' `
    -Json
```

The prior payload is moved to a timestamped sibling backup. Migration fails closed for unmanaged targets, invalid confirmations, modified payloads, unsupported schemas, or unfinished transactions. See [migration](migration.md).

## Uninstall

Inspect first, then apply with the exact root and current install ID:

```powershell
.\src\tri-agent.ps1 uninstall-plan -InstallRoot $TriTierRoot -Json
.\src\tri-agent.ps1 uninstall-apply `
    -InstallRoot $TriTierRoot `
    -ConfirmInstallRoot $TriTierRoot `
    -ConfirmInstallId '<install-id-from-install-status>' `
    -Json
```

Uninstall is reversible: the owned installation is moved to a sibling `.tri-tier-backups` directory rather than deleted.

## Recovery and troubleshooting

Inspect an interrupted operation:

```powershell
.\src\tri-agent.ps1 install-status -InstallRoot $TriTierRoot -Json
.\src\tri-agent.ps1 install-recover -InstallRoot $TriTierRoot -Json
```

- If `pwsh` is unavailable, install PowerShell 7 and reopen the terminal; Windows PowerShell 5.1 is not the validated runtime.
- If `doctor` fails, confirm PowerShell 7, use the pinned tag, and rerun the command with `-Json` for diagnostic detail.
- If compatibility or plan refuses the root, choose a new ordinary directory outside the source checkout, `$HOME\.codex`, and `CODEX_HOME`; do not bypass the refusal.
- If the target is already owned or stale, use `install-status`, `migrate-plan`, or `install-recover`; do not delete the target manually.
- If the launcher cannot be found, verify `$TriTierRoot\bin\tri-agent.ps1` and inspect `install-status`.
- For ordinary usage questions and reproducible bugs, see [SUPPORT.md](../SUPPORT.md). For suspected vulnerabilities, use [SECURITY.md](../SECURITY.md), not a public issue.
