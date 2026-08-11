# Tri-Tier Agent System

An evidence-driven orchestration system for coding agents.

Tri-Tier separates software work across three responsibilities:

- **Terra** coordinates plans, tasks, dependencies, and run state.
- **Luna** investigates, implements, tests, and repairs.
- **Sol** reviews architecture, risk, security, and acceptance evidence.

## Status

The first public repository prerelease is targeted as `v0.1.0-alpha`.
The CLI currently reports `0.10.0-alpha`; these are separate repository and
CLI version identifiers.

The current baseline contains canonical agent definitions, task routing,
R0-R4 risk classification, E0-E5 evidence enforcement, persistent run state,
review/repair cycles, phase gates, and isolated installation/recovery.

## Execution direction

```text
Terra prepares a bounded task
        ↓
Luna implements
        ↓
Sol independently reviews
        ↓
Luna repairs findings
        ↓
A fresh Sol review verifies the repair
        ↓
Terra records acceptance and continues
```

## Requirements

- PowerShell 7 recommended
- Git
- A compatible coding-agent harness

## Try it

```powershell
pwsh .\src\tri-agent.ps1 doctor

pwsh .\src\tri-agent.ps1 classify `
    -Prompt "Review tenant isolation and authorization boundaries."
```

## Verify the repository

```powershell
pwsh .\scripts\verify-repository.ps1
```

## Project status

This project is not yet production-ready. Use it in isolated branches and
review all generated changes before merging or deployment.

## License

Licensed under the Apache License, Version 2.0. See LICENSE and NOTICE.
## Durable runs

Initialize a run:

    pwsh .\src\tri-agent.ps1 run-init `
        -ProjectPath C:\path\to\project `
        -RunId feature-audit `
        -Title "Feature audit" `
        -NextAction "Prepare TASK-001."

Create a checkpoint:

    pwsh .\src\tri-agent.ps1 run-checkpoint `
        -ProjectPath C:\path\to\project `
        -RunId feature-audit `
        -Summary "TASK-001 implemented." `
        -NextAction "Assign independent Sol review." `
        -CurrentTask TASK-001

Resume from persisted state:

    pwsh .\src\tri-agent.ps1 run-resume `
        -ProjectPath C:\path\to\project `
        -RunId feature-audit

Read or update run status:

    pwsh .\src\tri-agent.ps1 run-status `
        -ProjectPath C:\path\to\project `
        -RunId feature-audit

    pwsh .\src\tri-agent.ps1 run-status `
        -ProjectPath C:\path\to\project `
        -RunId feature-audit `
        -RunStatus COMPLETE

<!-- BEGIN TRI-TIER PUBLIC DOCS -->
## Public documentation

- [Quickstart](docs/quickstart.md)
- [Command reference](docs/command-reference.md)
- [Runnable examples](examples/README.md)
- [Contributor workflow](docs/contributor-workflow.md)
- [Security policy](SECURITY.md)
- [Support](SUPPORT.md)
- [v0.1.0-alpha release notes](docs/release-v0.1.0-alpha.md)

The public command reference is mechanically checked against the live CLI command cases.
<!-- END TRI-TIER PUBLIC DOCS -->
