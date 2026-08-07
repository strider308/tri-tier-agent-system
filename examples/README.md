# Examples

These examples exercise public CLI entry points without changing the architecture or bypassing durable-state rules.

## Diagnostics

[diagnostics.ps1](diagnostics.ps1) runs `version` and `doctor`.

```powershell
pwsh -NoProfile -File .\examples\diagnostics.ps1
```

## Classify a task

[classify-task.ps1](classify-task.ps1) sends a task through the public classifier.

```powershell
pwsh -NoProfile -File .\examples\classify-task.ps1 `
    -Task "Document a low-risk feature"
```

## Plan an isolated installation

[plan-isolated-install.ps1](plan-isolated-install.ps1) runs only read-only compatibility and installation planning commands.

```powershell
pwsh -NoProfile -File .\examples\plan-isolated-install.ps1
```

## Inspect automatic execution without dispatch

[dry-run-execution.ps1](dry-run-execution.ps1) requires an existing durable run and calls `exec -DryRun -Json`.

```powershell
pwsh -NoProfile -File .\examples\dry-run-execution.ps1 `
    -ProjectPath <project-path> `
    -RunId <run-id>
```

For the complete public surface, see [../docs/command-reference.md](../docs/command-reference.md). For installation safety, see [../docs/installation.md](../docs/installation.md).
