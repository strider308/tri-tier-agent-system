# Quickstart

This is the public technical-alpha path. It is currently validated primarily on Windows with PowerShell 7 and Git. Use a compatible coding-agent harness when you want actual agent dispatch; the CLI and durable workflow can be inspected without one.

## 1. Clone and pin the release

```powershell
git clone https://github.com/strider308/tri-tier-agent-system.git
Set-Location .\tri-tier-agent-system
git checkout v0.1.1-alpha
```

The detached-tag checkout is intentional: it pins the tested alpha runtime. The current repository release is `v0.1.1-alpha`; the CLI reports `0.10.0-alpha`.

## 2. Verify the checkout

```powershell
pwsh -NoProfile -File .\src\tri-agent.ps1 version
pwsh -NoProfile -File .\src\tri-agent.ps1 doctor
```

## 3. Plan an isolated installation

The default root is `%LOCALAPPDATA%\TriTierAgentSystem\isolated`. Planning is read-only.

```powershell
$TriTierRoot = Join-Path $env:LOCALAPPDATA 'TriTierAgentSystem\isolated'

pwsh -NoProfile -File .\src\tri-agent.ps1 compatibility-check `
    -InstallRoot $TriTierRoot -Json

pwsh -NoProfile -File .\src\tri-agent.ps1 install-plan `
    -InstallRoot $TriTierRoot -Json
```

Review the plan before applying it. The installer rejects unsafe, overlapping, unmanaged, or reparse-point targets.

## 4. Apply and inspect the installation

Applying requires the exact normalized target confirmation:

```powershell
pwsh -NoProfile -File .\src\tri-agent.ps1 install-apply `
    -InstallRoot $TriTierRoot `
    -ConfirmInstallRoot $TriTierRoot `
    -Json

pwsh -NoProfile -File .\src\tri-agent.ps1 install-status `
    -InstallRoot $TriTierRoot -Json
```

The installation is isolated from the source checkout, does not modify `PATH`, does not install into `$HOME\.codex`, and does not alter `CODEX_HOME`.

## 5. Launch the installed copy

The installed PowerShell launcher is:

```powershell
& "$TriTierRoot\bin\tri-agent.ps1" version
& "$TriTierRoot\bin\tri-agent.ps1" doctor
```

The CMD launcher is `$TriTierRoot\bin\tri-agent.cmd`:

```powershell
cmd.exe /d /c "`"$TriTierRoot\bin\tri-agent.cmd`" version"
```

Run these from an unrelated working directory to verify the installed copy is not relying on the repository checkout.

## 6. Safe first workflow

Classification is read-only and does not change a project:

```powershell
& "$TriTierRoot\bin\tri-agent.ps1" classify `
    -Prompt 'Document a low-risk feature' -Json
```

For a durable workflow, initialize a run, checkpoint it, and resume it from persisted state:

```powershell
& "$TriTierRoot\bin\tri-agent.ps1" run-init `
    -ProjectPath 'C:\path\to\project' `
    -RunId 'feature-audit' `
    -Title 'Feature audit' `
    -NextAction 'Prepare TASK-001.'

& "$TriTierRoot\bin\tri-agent.ps1" run-checkpoint `
    -ProjectPath 'C:\path\to\project' `
    -RunId 'feature-audit' `
    -Summary 'Checkpoint captured.' `
    -NextAction 'Resume the bounded workflow.'

& "$TriTierRoot\bin\tri-agent.ps1" run-resume `
    -ProjectPath 'C:\path\to\project' `
    -RunId 'feature-audit'
```

Use `exec -DryRun` to inspect an automatic dispatch without executing it. See the [command reference](command-reference.md), [state model](state-model.md), [repair cycle](repair-cycle.md), and [execution loop](execution-loop.md) for the next steps.

## 7. Uninstall or recover

Uninstall is planned first and requires the current `installId`; it moves the owned installation into a sibling backup instead of deleting it. Interrupted operations can be inspected and recovered with `install-status` and `install-recover`. See [installation](installation.md), [migration](migration.md), and [recovery](recovery.md).
