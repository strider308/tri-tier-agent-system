# Evidence-Backed Phase Gates

Phase gates sit above the task and repair flow. A phase cannot be accepted
until task work, findings, evidence, independence, owner approval, and Sol
review all satisfy the gate.

## Durable phase statuses

- `ACTIVE`
- `READY_FOR_REVIEW`
- `BLOCKED_BY_FINDINGS`
- `BLOCKED_BY_EVIDENCE`
- `OWNER_DECISION_REQUIRED`
- `ACCEPTED`
- `REJECTED`

The durable phase state stores risk class, required and observed evidence
levels, evidence IDs, independence, owner approval, Sol review, exact next
action, revision, and transition history.

## Risk and evidence

The phase gate calls the existing evidence module for the risk-class evidence
requirement and sufficiency decision.

Additional phase policy requires independent evidence for R3 and R4. R4 also
requires a non-empty owner approval record before independent phase review.

## Finding and task requirements

Phase readiness requires:

- task flow at `CONTINUE`;
- task advancement allowed by final task review;
- no unresolved task-, phase-, or run-blocking finding;
- sufficient evidence;
- independent evidence for R3 and R4;
- owner approval for R4.

A failed readiness evaluation is persisted rather than silently ignored. Terra
may submit a later event after the missing evidence, finding repair, task
review, or owner approval is available.

## Independent review

Only a Sol actor may accept or reject a ready phase.

Acceptance routes control to Terra to start the next phase or prepare run
completion. Rejection routes control to Terra planning for bounded
remediation. Phase acceptance does not itself mark the entire run complete.
