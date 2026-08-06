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
