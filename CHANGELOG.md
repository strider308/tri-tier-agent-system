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
