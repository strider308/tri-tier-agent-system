# Tri-Tier Agent System v0.1.1-alpha

`v0.1.1-alpha` is the current recommended public technical-alpha release. The CLI reports `0.10.0-alpha`; these are separate repository-release and CLI version identifiers.

## What is included

- Terra/Luna/Sol agent roles and explicit handoff boundaries.
- R0–R4 risk classification and E0–E5 evidence levels.
- Durable run state, checkpoints, restart/resume, and recovery.
- Finding lifecycle, repair, fresh independent review, and phase gates.
- Isolated installation, migration, uninstall, and recovery paths.
- A 43-command public CLI surface and PowerShell/CMD entry points.

## Validation notes

The release has public validation for deterministic evidence resolution, isolated installation, recovery and migration health, durable state, restart/resume, finding/repair/fresh-review, and owner gating. These are test results, not guarantees of correct code or safe production operation.

## Alpha expectations

This is not production-ready, enterprise-ready, certified, fully autonomous, or a replacement for human ownership. APIs and workflows may change. Pin this tag for repeatable use, work in isolated branches or worktrees, review generated changes, and report reproducible problems through [support](../SUPPORT.md). Suspected vulnerabilities belong in the private process described by [SECURITY.md](../SECURITY.md).

## Previous release

The historical `v0.1.0-alpha` notes remain available in [release-v0.1.0-alpha.md](release-v0.1.0-alpha.md).
