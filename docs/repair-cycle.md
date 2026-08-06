# Persisted Repair Cycle

The repair-cycle module connects failed task reviews to persisted findings,
bounded Luna repair, independent Sol fresh review, and explicit adjudication.

## Flow

```text
REVIEW FAIL
→ Terra authorizes a blocking finding
→ REPAIR / Luna
→ FRESH_REVIEW / Sol
```

A passing fresh review resolves the linked finding and returns to final task
`REVIEW`. It never jumps directly to `CONTINUE`.

A failing fresh review reopens the finding, increments its review cycle, and
enters `ADJUDICATE`.

## Commands

- `Start-TriTierRunRepairCycle`
- `Complete-TriTierRunRepair`
- `Submit-TriTierRunRepairReview`
- `Submit-TriTierRunAdjudication`
- `Get-TriTierRunRepairCycle`

Every mutating command requires a stable `EventId`. Replaying an applied event
returns the persisted current state without duplicating transition or finding
history.

## Authority

- Terra alone authorizes a repair cycle after a failed independent task review.
- Luna alone performs the bounded repair.
- Sol alone performs fresh repair review and adjudication.
- The repair actor cannot perform the fresh review.

## Adjudication

Sol may choose exactly one of:

- `REPAIR_AGAIN`
- `OWNER_DECISION`
- `ABORT_FOR_SAFETY`
- `FAIL_VALIDATION`

`REPAIR_AGAIN` explicitly returns work to Luna. The other decisions block or
terminate the run through durable run status.

## Atomic persistence

Every repair transition uses `Set-TriTierRunIntegratedState`, so task flow,
findings, the finding gate, run status, and exact next action are written
through one validated persistence boundary.
