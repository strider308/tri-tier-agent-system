# Deterministic Orchestration Decisions

The orchestration module converts durable run state into one deterministic
decision. It does not execute agents and does not duplicate task-flow or
repair-cycle transitions.

## Decision fields

Every decision contains:

- run ID and run status;
- stage and responsible party;
- blocked scope;
- whether automatic continuation is allowed;
- whether owner action is required;
- priority finding ID;
- current task and phase status;
- reason and exact next action.

## Routing

- `PLAN` routes to Terra.
- `IMPLEMENT` routes to Luna.
- `REVIEW` routes to Sol, except a failed review routes to Terra for repair authorization.
- `REPAIR` routes to Luna.
- `FRESH_REVIEW` routes to Sol.
- `ADJUDICATE` routes to Sol.
- `CONTINUE` routes to Terra.
- `PHASE_REVIEW` routes to Sol.
- owner-gated runs route to the owner.
- external dependency waits route to Terra.
- complete, failed, or safety-aborted runs stop.

## Blocking scopes

The decision uses the persisted finding gate:

- MEDIUM findings block the task.
- HIGH findings block the phase.
- CRITICAL findings block the run.

A blocking finding prevents ordinary work from continuing. An active
`REPAIR`, `FRESH_REVIEW`, or `ADJUDICATE` stage remains actionable because
those stages are the authorized remediation path.

## Read-only behavior

`Get-TriTierOrchestrationDecision` evaluates a supplied run-state object.
`Get-TriTierRunOrchestrationDecision` reads durable state and returns the same
decision. Neither function mutates the run.
