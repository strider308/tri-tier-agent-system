# Task-Flow and Repair-Cycle CLI

The CLI exposes the verified task-flow and repair-cycle modules without
reimplementing their transition rules.

## Task-flow commands

- `task-flow-init`
- `task-start`
- `implementation-complete`
- `task-review`
- `task-flow-status`
- `task-planning-start`

## Repair-cycle commands

- `repair-open`
- `repair-complete`
- `repair-review`
- `repair-adjudicate`
- `repair-status`

All mutating commands require an explicit `-Actor` and stable `-EventId`.
Read-only status commands require only `-ProjectPath` and `-RunId`.

## Shared output

With `-Json`, every task-flow and repair-cycle command returns a normalized
object containing:

- run ID and run status;
- current stage and responsible party;
- whether advancement is allowed;
- current task;
- blocked scope and task, phase, and run gate flags;
- linked finding ID, status, and review cycle when present;
- event replay status;
- exact next action and update timestamp.

## Role boundaries

Terra initializes flow, selects tasks, starts planning, and authorizes repair.
Luna completes implementation and repair. Sol reviews tasks, performs fresh
repair review, and adjudicates failed repair review. The underlying modules
remain the authority and reject role or stage bypass attempts.

## Adjudication decisions

`repair-adjudicate` accepts only:

- `REPAIR_AGAIN`
- `OWNER_DECISION`
- `ABORT_FOR_SAFETY`
- `FAIL_VALIDATION`

Owner-gated and terminal runs reject further repair-cycle mutation.
