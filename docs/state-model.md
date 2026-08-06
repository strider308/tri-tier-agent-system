# Durable Run State

Each Tri-Tier execution run stores its state under:

```text
.tri-tier/runs/<run-id>/
├── plan/
├── state/
│   ├── run-state.json
│   └── next-action.txt
├── checkpoints/
├── tasks/
├── phases/
└── evidence/
```

## Exact next action

`next-action.txt` contains the precise next action required to continue
the run. Its value must match `run-state.json`.

## Checkpoints

A checkpoint records the current phase, current task, completed tasks,
unresolved findings, blockers, summary, and exact next action.

## Terminal states

- `COMPLETE`
- `COMPLETE_WITH_DEFERMENTS`
- `PAUSED_BY_OWNER`
- `BLOCKED_OWNER_DECISION`
- `BLOCKED_EXTERNAL_DEPENDENCY`
- `FAILED_VALIDATION`
- `ABORTED_FOR_SAFETY`

Runtime state is local and must not be committed by default.
## CLI commands

- `run-init` creates a durable run.
- `run-checkpoint` persists progress and the exact next action.
- `run-resume` validates and reloads the latest run state.
- `run-status` reads or updates the explicit run status.
