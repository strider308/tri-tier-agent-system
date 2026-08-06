# Changelog

All notable changes will be documented here.

## [Unreleased]

### Added

- Initial public repository structure
- Luna, Terra, and Sol agent definitions
- Task classification module
- `classify`, `doctor`, and `version` CLI commands
- Dependency-free classification tests
- Repository verification script

### Risk model

- Added formal R0-R4 task-risk classification
- Added owner-controlled R4 approval boundary
- Added minimum evidence and independent-review requirements
- Added risk-model tests and CLI output

### Evidence model

- Added E0-E5 evidence classifications
- Added minimum evidence requirements for R0-R4
- Added structured evidence records
- Added independent reproduction enforcement for E5
- Added evidence CLI and regression tests

### Durable run state

- Added local JSON run-state persistence
- Added atomic state and exact next-action writes
- Added resumable checkpoints
- Added run-state integrity validation
- Added explicit terminal run statuses

### Run-state CLI

- Added `run-init` for durable run creation
- Added `run-checkpoint` for progress persistence
- Added `run-resume` for exact next-action recovery
- Added `run-status` for explicit status inspection and updates
- Added end-to-end state CLI tests

### Fixed

- Reset successful repository verification to exit status zero instead of
  leaking a stale native-command exit status from an internal check.

### Finding model

- Added INFO, LOW, MEDIUM, HIGH, and CRITICAL finding severities.
- Added task, phase, and run blocking rules.
- Added repair and independent fresh-review transitions.
- Added owner-approved deferrals.
- Prohibited deferral of critical findings.
- Added deterministic next-action generation.

### Durable finding state

- Persisted complete finding records in durable run state.
- Persisted active finding IDs and the current finding gate.
- Synchronized gate-derived next actions with `next-action.txt`.
- Added resume coverage for finding-controlled next actions.
- Added repository verification for run/finding-state integration.

### Persisted finding lifecycle

- Added durable create, repair, fresh-review, and deferral transitions.
- Recalculated and persisted finding gates after every transition.
- Preserved review cycles and complete finding history across run resumes.
- Added integration coverage for fail, repair, pass, and deferral paths.

### Finding lifecycle CLI

- Added CLI commands to create, inspect, repair, review, and defer findings.
- Added explicit owner-approval enforcement for CLI deferrals.
- Added end-to-end JSON CLI coverage for persisted finding transitions.
- Advanced the CLI version to `0.5.0-alpha`.

### Durable task-flow transition core

- Added explicit PLAN, IMPLEMENT, REVIEW, and CONTINUE transitions.
- Added Terra task selection, Luna implementation completion, and independent Sol review enforcement.
- Added stable event IDs for idempotent transition replay.
- Persisted transition history, actors, evidence IDs, review outcome, previous stage, and exact next action.
- Kept failed reviews blocked until the finding-repair integration milestone authorizes continuation.

### Atomic task-flow and finding state

- Added one durable write boundary for task flow, findings, finding gate, optional run status, and exact next action.
- Reserved REPAIR, FRESH_REVIEW, and ADJUDICATE as integrated stages linked to one active finding.
- Prevented integrated repair stages from being persisted without the required finding status.
- Added repair linkage and resume metadata to durable task flow.
- Preserved final task REVIEW after a successful fresh repair review.

### Persisted repair cycle

- Added Terra-authorized repair-cycle creation after failed independent task review.
- Added bounded Luna repair and independent Sol fresh-review transitions.
- Added explicit REPAIR_AGAIN, OWNER_DECISION, ABORT_FOR_SAFETY, and FAIL_VALIDATION adjudication.
- Added stable event replay protection across every repair-cycle mutation.
- Returned accepted repairs to final task REVIEW instead of bypassing approval.
- Added complete pass, failed-review, retry, owner-gate, terminal, restart, and exact-next-action tests.

### Task-flow and repair-cycle CLI

- Added six task-flow CLI commands and five repair-cycle CLI commands.
- Added normalized JSON output with stage, role, gate, finding, replay, status, and exact next action.
- Required explicit actors and stable event IDs for every mutating flow command.
- Added child-process end-to-end coverage for pass, retry, owner-gate, role rejection, and idempotent replay paths.
- Added TaskFlow and RepairCycle modules to CLI doctor.
- Advanced the CLI version to `0.6.0-alpha`.

### Deterministic orchestration and phase gates

- Added a read-only orchestration decision engine for task, repair, owner, external, terminal, and phase-review routing.
- Added durable evidence-backed phase state with ACTIVE, blocked, reviewable, accepted, and rejected statuses.
- Connected phase readiness to existing finding gates and evidence sufficiency checks.
- Required independent evidence for R3 and R4 and owner approval for R4.
- Added Sol-only phase acceptance and rejection with stable event replay protection.
- Added orchestration and phase-gate CLI commands with normalized JSON output.
- Added module, CLI, owner-gate, finding-block, evidence-block, and exact-next-action tests.
- Advanced the CLI version to `0.7.0-alpha`.

### Durable automatic execution loop

- Added a durable dispatcher-driven execution loop that consumes deterministic orchestration decisions.
- Added stable action keys, exclusive run locks, in-flight markers, child-process timeouts, and restart recovery.
- Added pre-dispatch and post-dispatch checkpoints through the existing state contract.
- Added owner, external-dependency, blocked, terminal, step-limit, retry-limit, and stall stops.
- Added fail-closed dispatcher result validation and durable failure records.
- Added exec, exec-resume, and exec-status CLI commands plus dry-run envelope preview.
- Added execution-loop and CLI tests covering completion, owner gates, external waits, stalls, recovery, and invalid results.
- Advanced the CLI version to `0.8.0-alpha`.

### Agent role and handoff integration

- Bound all six agent profiles to explicit durable-stage authority and read/write limits.
- Added deterministic stage-to-profile routing for Terra, Luna, Sol, owner, waits, and stops.
- Added structured handoffs with bounded instructions, acceptance criteria, risk, evidence, findings, and independence metadata.
- Added fail-closed authority validation so implementation profiles cannot satisfy their own independent review.
- Added profile and handoff data to execution dispatcher envelopes using schema version 2.
- Added profile, handoff, and execution-envelope behavioural tests plus documentation.
- Advanced the CLI version to `0.9.0-alpha`.
