# Atomic Task-Flow and Finding State

This integration substrate adds one durable write boundary for task flow,
findings, the finding gate, optional run status, and the exact next action.

It intentionally does not expose repair orchestration commands yet.

## Purpose

Task repair crosses two existing domains:

- task flow tracks PLAN, IMPLEMENT, REVIEW, and CONTINUE;
- finding lifecycle tracks OPEN, REPAIRED_PENDING_REVIEW, RESOLVED, and DEFERRED.

Writing those domains separately could leave a run partially updated after an
interruption. `Set-TriTierRunIntegratedState` validates both objects and writes
one combined `run-state.json` plus one matching `next-action.txt`.

## Repair stages

The integrated persistence boundary recognizes three reserved stages:

- `REPAIR`
- `FRESH_REVIEW`
- `ADJUDICATE`

These stages require `activeRepairFindingId` to reference exactly one active
finding. `FRESH_REVIEW` requires that finding to be
`REPAIRED_PENDING_REVIEW`; `REPAIR` and `ADJUDICATE` require it to be `OPEN`.

The ordinary task-flow setter continues to reject these stages. Only the
integrated persistence boundary may store them, preventing a repair stage from
being written without its linked finding and finding gate.

## Resume contract

After a successful fresh repair review, the active repair link is cleared, the
finding ID moves to `lastRepairFindingId`, and task flow resumes `REVIEW`.
A final independent task review is still required before `CONTINUE`.
