# Finding Model

Tri-Tier review findings use five severities.

| Severity | Effect |
|---|---|
| INFO | Informational observation; does not block execution |
| LOW | Minor issue; does not automatically block the task |
| MEDIUM | Blocks task acceptance |
| HIGH | Blocks task and phase acceptance |
| CRITICAL | Blocks the task, phase, and entire run |

## Finding states

- OPEN
- REPAIRED_PENDING_REVIEW
- RESOLVED
- DEFERRED

## Repair and fresh review

Medium, high, and critical findings cannot move directly from OPEN to RESOLVED.

Required transition:

OPEN -> REPAIRED_PENDING_REVIEW -> independent fresh review -> RESOLVED or OPEN

The repair actor cannot perform the fresh review.

A failed fresh review reopens the finding and begins another repair cycle.

## Deferrals

Deferral requires an explicit owner approval record.

Critical findings cannot be deferred.
