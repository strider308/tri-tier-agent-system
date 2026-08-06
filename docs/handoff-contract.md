# Structured Agent Handoff Contract

The `AgentProfiles` module creates and validates deterministic handoffs between orchestration stages and agent profiles.

## Required fields

- `schemaVersion`
- `runId`
- `phaseId`
- `taskId`
- `fromProfile`
- `toProfile`
- `targetType`
- `stage`
- `responsibleParty`
- `riskClass`
- `blockedScope`
- `ownerRequired`
- `instruction`
- `acceptanceCriteria`
- `evidenceIds`
- `unresolvedFindingIds`
- `independentReviewRequired`
- `implementationProfile`
- `createdUtc`

## Validation rules

1. The orchestration stage and responsible party must resolve to exactly one authorized runtime profile, except owner and no-agent stops.
2. IMPLEMENT and REPAIR require a write-capable profile and resolve only to `luna_worker`.
3. Sol-owned REVIEW and FRESH_REVIEW resolve to `sol_architect`.
4. ADJUDICATE, PHASE_REVIEW, and Sol-owned STOP resolve to `sol_adjudicator`.
5. A failed REVIEW assigned to Terra resolves to `terra_manager` for repair authorization, not implementation or approval.
6. OWNER_DECISION names no agent profile and cannot be dispatched automatically.
7. `targetType` is derived from orchestration and cannot be changed to bypass an agent or owner gate.
8. REVIEW and FRESH_REVIEW record `luna_worker` as the implementation profile; PHASE_REVIEW records `terra_manager`.
9. A profile cannot independently review work when it is also recorded as the implementation profile.
10. Every handoff includes non-empty instructions and stage-specific acceptance criteria.

## Dispatcher use

Dispatchers should treat the handoff as an authority boundary, not a suggestion. They must invoke only the named profile, preserve the bounded instruction, return evidence through the durable run state, and refuse incompatible stage/profile combinations.
