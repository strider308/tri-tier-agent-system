# Tri-Tier Agent System

An evidence-driven orchestration system for coding agents.

Tri-Tier separates software work across three responsibilities:

- **Terra** coordinates plans, tasks, dependencies, and run state.
- **Luna** investigates, implements, tests, and repairs.
- **Sol** reviews architecture, risk, security, and acceptance evidence.

## Status

`0.3.0-alpha`

The current release contains canonical agent definitions, task routing,
R0-R4 risk classification, and E0-E5 evidence enforcement. Persistent run
state, review/repair cycles, and phase gates are under active development.

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
