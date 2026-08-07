# Contributor workflow

This repository treats durable state, routing authority, evidence, review independence, and recovery behavior as public contracts. Changes should preserve those contracts unless the change explicitly updates them with tests and documentation.

## Before editing

1. Start from a clean working tree.
2. Read [../AGENTS.md](../AGENTS.md).
3. Read [architecture.md](architecture.md), [risk-model.md](risk-model.md), [evidence-model.md](evidence-model.md), and the subsystem document relevant to the change.
4. Keep local caches, generated run state, secrets, and private audit material out of commits.
5. Do not modify a separate private agent installation as part of public repository work.

## Authority boundaries

- Terra coordinates, decomposes, persists durable state, and controls continuation.
- Luna performs bounded implementation and repair work.
- Sol performs independent review and adjudication.
- An implementer cannot satisfy its own independent review gate.
- Owner decisions remain explicit when the system cannot safely resolve a value judgment or irreversible risk.

See [agent-roles.md](agent-roles.md) and [handoff-contract.md](handoff-contract.md).

## PowerShell change discipline

- Prefer bounded functions with approved PowerShell verbs.
- Parse every generated or modified `.ps1` and `.psm1` file before execution.
- Do not rely on stale `$LASTEXITCODE`; capture it immediately after each child process.
- Avoid terminal-pasted here-strings and fragile trailing backticks.
- Treat exact text transformations as contracts: verify occurrence counts before replacement.
- Preserve caller-visible module exports when importing shared dependency modules.
- Fail closed when state, evidence, authority, installation ownership, or recovery identity is ambiguous.

## Required validation

From the repository root:

```powershell
pwsh -NoProfile -File .\scripts\verify-repository.ps1
pwsh -NoProfile -File .\src\tri-agent.ps1 doctor
git diff --check
```

For documentation-only changes, also run:

```powershell
pwsh -NoProfile -File .\tests\test-public-docs.ps1
```

If you changed a specific subsystem, run its targeted test before the full verifier.

## Public documentation rule

Every public CLI command must have exactly one command-reference section. New commands must update the command reference, examples when useful, and the repository verifier in the same change.

The command coverage test derives the CLI command cases from `src/tri-agent.ps1`; it does not trust a manually maintained docs-only list.

## Pull-request checklist

- Working tree contains only intended files.
- Generated/private runtime data is not staged.
- Modified PowerShell parses successfully.
- Targeted tests pass.
- Full repository verifier passes.
- CLI doctor passes.
- `git diff --check` passes.
- Documentation and examples match the implemented behavior.
- Review authority remains independent where required.
