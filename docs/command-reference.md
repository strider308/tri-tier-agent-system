# Command reference

This reference is generated from the public CLI surface at Phase 7 baseline `0.10.0-alpha`.
Phase 7 does not change runtime semantics or the CLI version.

## Invocation

```powershell
pwsh -NoProfile -File .\src\tri-agent.ps1 <command> [parameters]
```

## Public parameter inventory

The CLI exposes one shared script parameter surface. Individual commands validate the combinations they require.

| Parameter | Type |
| --- | --- |
| `-Actor` | `String` |
| `-Blockers` | `String[]` |
| `-Command` | `String` |
| `-CompletedTasks` | `String[]` |
| `-ConfirmInstallId` | `String` |
| `-ConfirmInstallRoot` | `String` |
| `-CurrentPhase` | `String` |
| `-CurrentTask` | `String` |
| `-Decision` | `String` |
| `-Description` | `String` |
| `-DispatcherPath` | `String` |
| `-DryRun` | `SwitchParameter` |
| `-EventId` | `String` |
| `-EvidenceIds` | `String[]` |
| `-EvidenceIndependent` | `SwitchParameter` |
| `-EvidenceLevel` | `String` |
| `-FindingId` | `String` |
| `-IndependentlyReproduced` | `SwitchParameter` |
| `-InstallRoot` | `String` |
| `-Instruction` | `String` |
| `-Json` | `SwitchParameter` |
| `-MaxAttemptsPerAction` | `Int32` |
| `-MaxSameDecision` | `Int32` |
| `-MaxSteps` | `Int32` |
| `-NextAction` | `String` |
| `-ObservedEvidenceLevel` | `String` |
| `-Outcome` | `String` |
| `-OwnerApprovalRecord` | `String` |
| `-OwnerApproved` | `SwitchParameter` |
| `-PhaseId` | `String` |
| `-PhaseRiskClass` | `String` |
| `-PlanPath` | `String` |
| `-ProjectPath` | `String` |
| `-Prompt` | `String` |
| `-Reason` | `String` |
| `-RepairedBy` | `String` |
| `-RepairSummary` | `String` |
| `-Reviewer` | `String` |
| `-ReviewSummary` | `String` |
| `-RiskClass` | `String` |
| `-RunId` | `String` |
| `-RunStatus` | `String` |
| `-Severity` | `String` |
| `-StepTimeoutSeconds` | `Int32` |
| `-Summary` | `String` |
| `-TaskId` | `String` |
| `-Title` | `String` |
| `-UnresolvedFindings` | `String[]` |

## Commands

### `classify`

**Category:** Routing and risk

Classify a task into the Tri-Tier routing model and return the matching risk/tier decision.

```powershell
pwsh -NoProfile -File .\src\tri-agent.ps1 classify [parameters]
```

See [risk-model.md](risk-model.md) for the subsystem contract and state semantics.

### `compatibility-check`

**Category:** Isolated installation

Inspect source and target compatibility without mutating the installation.

```powershell
pwsh -NoProfile -File .\src\tri-agent.ps1 compatibility-check [parameters]
```

See [installation.md](installation.md) for the subsystem contract and state semantics.

### `doctor`

**Category:** Diagnostics

Run repository and module health checks exposed by the CLI.

```powershell
pwsh -NoProfile -File .\src\tri-agent.ps1 doctor [parameters]
```

See [README.md](../README.md) for the subsystem contract and state semantics.

### `evidence`

**Category:** Routing and risk

Evaluate evidence expectations against the Tri-Tier risk/evidence model.

```powershell
pwsh -NoProfile -File .\src\tri-agent.ps1 evidence [parameters]
```

See [evidence-model.md](evidence-model.md) for the subsystem contract and state semantics.

### `exec`

**Category:** Automatic execution

Run the durable automatic execution loop, or inspect the next dispatch using dry-run mode.

```powershell
pwsh -NoProfile -File .\src\tri-agent.ps1 exec [parameters]
```

See [cli-exec.md](cli-exec.md) for the subsystem contract and state semantics.

### `exec-resume`

**Category:** Automatic execution

Resume an interrupted durable automatic execution loop.

```powershell
pwsh -NoProfile -File .\src\tri-agent.ps1 exec-resume [parameters]
```

See [cli-exec.md](cli-exec.md) for the subsystem contract and state semantics.

### `exec-status`

**Category:** Automatic execution

Read persisted execution-loop status without dispatching work.

```powershell
pwsh -NoProfile -File .\src\tri-agent.ps1 exec-status [parameters]
```

See [cli-exec.md](cli-exec.md) for the subsystem contract and state semantics.

### `finding-add`

**Category:** Findings

Create and persist an evidence-backed finding against a run.

```powershell
pwsh -NoProfile -File .\src\tri-agent.ps1 finding-add [parameters]
```

See [finding-lifecycle.md](finding-lifecycle.md) for the subsystem contract and state semantics.

### `finding-defer`

**Category:** Findings

Defer an eligible finding when the required owner approval is present.

```powershell
pwsh -NoProfile -File .\src\tri-agent.ps1 finding-defer [parameters]
```

See [finding-lifecycle.md](finding-lifecycle.md) for the subsystem contract and state semantics.

### `finding-get`

**Category:** Findings

Read a persisted finding.

```powershell
pwsh -NoProfile -File .\src\tri-agent.ps1 finding-get [parameters]
```

See [finding-lifecycle.md](finding-lifecycle.md) for the subsystem contract and state semantics.

### `finding-repair`

**Category:** Findings

Record bounded repair completion and move a finding toward fresh review.

```powershell
pwsh -NoProfile -File .\src\tri-agent.ps1 finding-repair [parameters]
```

See [finding-lifecycle.md](finding-lifecycle.md) for the subsystem contract and state semantics.

### `finding-review`

**Category:** Findings

Submit an independent finding review result.

```powershell
pwsh -NoProfile -File .\src\tri-agent.ps1 finding-review [parameters]
```

See [finding-lifecycle.md](finding-lifecycle.md) for the subsystem contract and state semantics.

### `implementation-complete`

**Category:** Task and repair flow

Record implementation completion and hand the task to independent review.

```powershell
pwsh -NoProfile -File .\src\tri-agent.ps1 implementation-complete [parameters]
```

See [cli-flow.md](cli-flow.md) for the subsystem contract and state semantics.

### `install-apply`

**Category:** Isolated installation

Apply an explicitly confirmed isolated installation transaction.

```powershell
pwsh -NoProfile -File .\src\tri-agent.ps1 install-apply [parameters]
```

See [installation.md](installation.md) for the subsystem contract and state semantics.

### `install-plan`

**Category:** Isolated installation

Build a read-only isolated-installation plan.

```powershell
pwsh -NoProfile -File .\src\tri-agent.ps1 install-plan [parameters]
```

See [installation.md](installation.md) for the subsystem contract and state semantics.

### `install-recover`

**Category:** Isolated installation

Recover an interrupted installation transaction from its durable journal.

```powershell
pwsh -NoProfile -File .\src\tri-agent.ps1 install-recover [parameters]
```

See [recovery.md](recovery.md) for the subsystem contract and state semantics.

### `install-status`

**Category:** Isolated installation

Read isolated installation ownership and status.

```powershell
pwsh -NoProfile -File .\src\tri-agent.ps1 install-status [parameters]
```

See [installation.md](installation.md) for the subsystem contract and state semantics.

### `migrate-apply`

**Category:** Isolated installation

Apply an explicitly confirmed schema-aware installation migration.

```powershell
pwsh -NoProfile -File .\src\tri-agent.ps1 migrate-apply [parameters]
```

See [migration.md](migration.md) for the subsystem contract and state semantics.

### `migrate-plan`

**Category:** Isolated installation

Build a read-only migration plan for an owned installation.

```powershell
pwsh -NoProfile -File .\src\tri-agent.ps1 migrate-plan [parameters]
```

See [migration.md](migration.md) for the subsystem contract and state semantics.

### `orchestration-status`

**Category:** Orchestration and phase gates

Read the deterministic orchestration decision for the current durable state.

```powershell
pwsh -NoProfile -File .\src\tri-agent.ps1 orchestration-status [parameters]
```

See [orchestration.md](orchestration.md) for the subsystem contract and state semantics.

### `phase-accept`

**Category:** Orchestration and phase gates

Accept a reviewable phase and return control to continuation.

```powershell
pwsh -NoProfile -File .\src\tri-agent.ps1 phase-accept [parameters]
```

See [cli-phase.md](cli-phase.md) for the subsystem contract and state semantics.

### `phase-ready`

**Category:** Orchestration and phase gates

Submit phase readiness evidence and evaluate phase gates.

```powershell
pwsh -NoProfile -File .\src\tri-agent.ps1 phase-ready [parameters]
```

See [cli-phase.md](cli-phase.md) for the subsystem contract and state semantics.

### `phase-reject`

**Category:** Orchestration and phase gates

Reject a phase and return control to planning.

```powershell
pwsh -NoProfile -File .\src\tri-agent.ps1 phase-reject [parameters]
```

See [cli-phase.md](cli-phase.md) for the subsystem contract and state semantics.

### `phase-review`

**Category:** Orchestration and phase gates

Submit the independent Sol phase-review decision.

```powershell
pwsh -NoProfile -File .\src\tri-agent.ps1 phase-review [parameters]
```

See [cli-phase.md](cli-phase.md) for the subsystem contract and state semantics.

### `phase-start`

**Category:** Orchestration and phase gates

Start durable phase tracking with its risk and evidence requirement.

```powershell
pwsh -NoProfile -File .\src\tri-agent.ps1 phase-start [parameters]
```

See [cli-phase.md](cli-phase.md) for the subsystem contract and state semantics.

### `phase-status`

**Category:** Orchestration and phase gates

Read the persisted phase state and gate result.

```powershell
pwsh -NoProfile -File .\src\tri-agent.ps1 phase-status [parameters]
```

See [cli-phase.md](cli-phase.md) for the subsystem contract and state semantics.

### `repair-adjudicate`

**Category:** Task and repair flow

Record Sol adjudication after a failed fresh review.

```powershell
pwsh -NoProfile -File .\src\tri-agent.ps1 repair-adjudicate [parameters]
```

See [repair-cycle.md](repair-cycle.md) for the subsystem contract and state semantics.

### `repair-complete`

**Category:** Task and repair flow

Record Luna repair completion and move to fresh review.

```powershell
pwsh -NoProfile -File .\src\tri-agent.ps1 repair-complete [parameters]
```

See [repair-cycle.md](repair-cycle.md) for the subsystem contract and state semantics.

### `repair-open`

**Category:** Task and repair flow

Authorize and open the bounded repair cycle for a failed review.

```powershell
pwsh -NoProfile -File .\src\tri-agent.ps1 repair-open [parameters]
```

See [repair-cycle.md](repair-cycle.md) for the subsystem contract and state semantics.

### `repair-review`

**Category:** Task and repair flow

Submit the fresh independent review for a repair.

```powershell
pwsh -NoProfile -File .\src\tri-agent.ps1 repair-review [parameters]
```

See [repair-cycle.md](repair-cycle.md) for the subsystem contract and state semantics.

### `repair-status`

**Category:** Task and repair flow

Read the current durable repair-cycle status.

```powershell
pwsh -NoProfile -File .\src\tri-agent.ps1 repair-status [parameters]
```

See [repair-cycle.md](repair-cycle.md) for the subsystem contract and state semantics.

### `run-checkpoint`

**Category:** Durable run state

Write a durable checkpoint for an existing run.

```powershell
pwsh -NoProfile -File .\src\tri-agent.ps1 run-checkpoint [parameters]
```

See [state-model.md](state-model.md) for the subsystem contract and state semantics.

### `run-init`

**Category:** Durable run state

Create a durable run record and persist its initial next action.

```powershell
pwsh -NoProfile -File .\src\tri-agent.ps1 run-init [parameters]
```

See [state-model.md](state-model.md) for the subsystem contract and state semantics.

### `run-resume`

**Category:** Durable run state

Recover an existing run from its persisted state and latest checkpoint.

```powershell
pwsh -NoProfile -File .\src\tri-agent.ps1 run-resume [parameters]
```

See [state-model.md](state-model.md) for the subsystem contract and state semantics.

### `run-status`

**Category:** Durable run state

Read or update durable run status through the public CLI surface.

```powershell
pwsh -NoProfile -File .\src\tri-agent.ps1 run-status [parameters]
```

See [state-model.md](state-model.md) for the subsystem contract and state semantics.

### `task-flow-init`

**Category:** Task and repair flow

Initialize durable task-flow state for the current task.

```powershell
pwsh -NoProfile -File .\src\tri-agent.ps1 task-flow-init [parameters]
```

See [cli-flow.md](cli-flow.md) for the subsystem contract and state semantics.

### `task-flow-status`

**Category:** Task and repair flow

Read the persisted task-flow stage and exact next action.

```powershell
pwsh -NoProfile -File .\src\tri-agent.ps1 task-flow-status [parameters]
```

See [cli-flow.md](cli-flow.md) for the subsystem contract and state semantics.

### `task-planning-start`

**Category:** Task and repair flow

Return an advancing task flow to planning.

```powershell
pwsh -NoProfile -File .\src\tri-agent.ps1 task-planning-start [parameters]
```

See [cli-flow.md](cli-flow.md) for the subsystem contract and state semantics.

### `task-review`

**Category:** Task and repair flow

Submit the independent task review result.

```powershell
pwsh -NoProfile -File .\src\tri-agent.ps1 task-review [parameters]
```

See [cli-flow.md](cli-flow.md) for the subsystem contract and state semantics.

### `task-start`

**Category:** Task and repair flow

Start a selected task and enter implementation.

```powershell
pwsh -NoProfile -File .\src\tri-agent.ps1 task-start [parameters]
```

See [cli-flow.md](cli-flow.md) for the subsystem contract and state semantics.

### `uninstall-apply`

**Category:** Isolated installation

Move an explicitly confirmed owned installation to quarantine.

```powershell
pwsh -NoProfile -File .\src\tri-agent.ps1 uninstall-apply [parameters]
```

See [installation.md](installation.md) for the subsystem contract and state semantics.

### `uninstall-plan`

**Category:** Isolated installation

Build a read-only uninstall plan for an owned installation.

```powershell
pwsh -NoProfile -File .\src\tri-agent.ps1 uninstall-plan [parameters]
```

See [installation.md](installation.md) for the subsystem contract and state semantics.

### `version`

**Category:** Diagnostics

Print the current Tri-Tier Agent System CLI version.

```powershell
pwsh -NoProfile -File .\src\tri-agent.ps1 version [parameters]
```

See [README.md](../README.md) for the subsystem contract and state semantics.
