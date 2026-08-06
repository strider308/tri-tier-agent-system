# Persisted Finding Lifecycle

The finding lifecycle connects the pure finding transition model to durable
run state.

## Transition sequence

```text
OPEN
  -> repair
REPAIRED_PENDING_REVIEW
  -> independent fresh review PASS
RESOLVED
```

A failed fresh review returns the finding to `OPEN` and increments its
`reviewCycle`. A permitted owner-approved deferral moves an unresolved
finding to `DEFERRED`.

## Persistent orchestration commands

- `Add-TriTierRunFinding`
- `Repair-TriTierRunFinding`
- `Submit-TriTierRunFindingFreshReview`
- `Set-TriTierRunFindingDeferral`
- `Get-TriTierRunFinding`

Every successful transition recalculates `Test-TriTierFindingGate`, stores
the complete finding collection, refreshes `unresolvedFindings`, persists
`findingGate`, and synchronizes the gate-derived exact next action with
`next-action.txt`.

Fresh review must be performed by someone other than the repair actor.
Deferral requires explicit owner approval, and CRITICAL findings cannot be
deferred.
