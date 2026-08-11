# Tri-Tier Agent System `v0.1.0-alpha`

This is the first public repository prerelease candidate for the Tri-Tier
Agent System. The repository release identifier is `v0.1.0-alpha`. The CLI
continues to report `0.10.0-alpha`; the two version numbers describe different
release tracks and should not be treated as interchangeable.

## What is included

- Terra coordinates plans, durable state, dependencies, and continuation.
- Luna performs bounded implementation and repair work.
- Sol performs independent review and adjudication.
- R0-R4 risk classes route work from low-risk tasks through owner-gated and
  production-sensitive decisions.
- E0-E5 evidence levels express the minimum evidence and independence needed
  for those risks.
- Durable state, findings, repair and fresh-review cycles, phase gates, and
  structured handoffs preserve an inspectable execution loop.
- The execution loop supports dry runs, bounded dispatch, restart recovery,
  owner gates, external waits, and fail-closed stops.
- Isolated installation, migration, uninstall, and recovery keep repository
  source separate from the private Codex installation and preserve reversible
  recovery paths.
- The command reference, quickstart, examples, contributor workflow, verifier,
  doctor, and offline publication-readiness test document and check the public
  surface.

## Known limitations

- This is alpha software and is not production-ready or a security boundary.
- Automated checks and worker reports are evidence, not certification or proof
  that a real-world outcome is safe.
- Production deployment, destructive changes, privacy decisions, and
  authorization boundaries still require explicit human review.
- Compatibility depends on the supported PowerShell and Git environment.
- The repository does not promise a stable public API or release support window
  for this prerelease.

Review [SECURITY.md](../SECURITY.md) for private vulnerability reporting and
[SUPPORT.md](../SUPPORT.md) for ordinary questions and safe bug reports.
