# Durable Task Flow

Milestone 1 provides a deterministic, event-driven task transition core. It
does not yet connect finding repair cycles to task review failures.

## Stages

- `PLAN`: Terra selects the next bounded task.
- `IMPLEMENT`: Luna performs the bounded implementation.
- `REVIEW`: Sol performs an independent review.
- `CONTINUE`: Terra may advance only after review passes.

## Explicit events

- `Initialize-TriTierRunTaskFlow` creates or resumes the durable flow.
- `Start-TriTierRunTask` records Terra's task selection.
- `Complete-TriTierRunImplementation` records Luna's completion and moves to review.
- `Submit-TriTierRunTaskReview` records Sol's independent PASS or FAIL.
- `Start-TriTierRunPlanning` clears a passed task and returns to planning.

Every mutating event accepts an optional stable `EventId`. Reusing an applied
event ID returns the persisted result without duplicating transition history.

## Independence and failure safety

Task implementation must be completed by a Luna actor. Task review must be
submitted by a Sol actor and cannot be submitted by the implementation actor.

A passing review is the only route to `CONTINUE`. A failed review remains
durably blocked in `REVIEW`; it cannot be overwritten by a later pass or skip
directly to planning. Milestone 2 will connect that blocked state to persisted
findings, repair authorization, fresh review, and adjudication.

## Durable state

The complete flow, previous stage, actors, evidence IDs, outcome, revision, and
transition history are stored in `run-state.json`. The flow's exact next action
is also written to `state/next-action.txt`, so restart and compaction recovery
resume from the same stage.
