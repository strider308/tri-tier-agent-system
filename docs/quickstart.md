# Quickstart

Tri-Tier Agent System is designed to keep routing, durable state, evidence, review authority, and recovery explicit. Start with diagnostics, then use the subsystem-specific commands that match the work you are doing.

## 1. Verify the CLI

From the repository root:

```powershell
pwsh -NoProfile -File .\src\tri-agent.ps1 version
pwsh -NoProfile -File .\src\tri-agent.ps1 doctor
```

The current Phase 7 baseline remains `0.10.0-alpha`. Phase 7 is documentation-only and does not change runtime semantics or the CLI version.

## 2. Classify a task

Use the classifier before deciding which agent tier should own the work:

```powershell
pwsh -NoProfile -File .\src\tri-agent.ps1 classify `
    -Task "Update documentation for a low-risk feature" `
    -Json
```

The routing and risk model are explained in [risk-model.md](risk-model.md) and [evidence-model.md](evidence-model.md).

## 3. Plan an isolated installation

Planning is read-only:

```powershell
$InstallRoot = Join-Path $HOME '.tri-tier-agent-system'

pwsh -NoProfile -File .\src\tri-agent.ps1 compatibility-check `
    -InstallRoot $InstallRoot `
    -Json

pwsh -NoProfile -File .\src\tri-agent.ps1 install-plan `
    -InstallRoot $InstallRoot `
    -Json
```

Review the plan before using an apply command. Installation ownership, explicit confirmations, migration, quarantine uninstall, and recovery are documented in [installation.md](installation.md), [migration.md](migration.md), and [recovery.md](recovery.md).

## 4. Work with durable state

The durable-state lifecycle is documented in [state-model.md](state-model.md). Finding lifecycle, task flow, repair, phase gates, and automatic execution are documented separately so each transition remains reviewable:

- [finding-lifecycle.md](finding-lifecycle.md)
- [cli-flow.md](cli-flow.md)
- [repair-cycle.md](repair-cycle.md)
- [cli-phase.md](cli-phase.md)
- [cli-exec.md](cli-exec.md)

## 5. Use dry-run execution before dispatch

Once a run exists, inspect the next automatic dispatch without executing it:

```powershell
pwsh -NoProfile -File .\src\tri-agent.ps1 exec `
    -ProjectPath <project-path> `
    -RunId <run-id> `
    -DryRun `
    -Json
```

The result includes the selected durable stage, responsible party, profile, and structured handoff information when applicable.

## 6. Use the complete command reference

See [command-reference.md](command-reference.md) for the live public command surface and CLI parameter inventory.

Runnable examples are in [../examples/README.md](../examples/README.md).
