# Orchestration and Phase-Gate CLI

The CLI exposes read-only orchestration decisions and durable phase-gate
transitions.

## Commands

- `orchestration-status`
- `phase-start`
- `phase-ready`
- `phase-review`
- `phase-accept`
- `phase-reject`
- `phase-status`

Mutating phase commands require an explicit actor and stable event ID.

## Phase parameters

- `-PhaseId`
- `-PhaseRiskClass`
- `-ObservedEvidenceLevel`
- `-EvidenceIndependent`
- `-OwnerApprovalRecord`
- `-EvidenceIds`
- `-Summary`
- `-Decision`
- `-Actor`
- `-EventId`

`phase-review` accepts `ACCEPT` or `REJECT`. `phase-accept` and
`phase-reject` are explicit convenience commands using the same underlying
module function.

## JSON output

Phase and orchestration commands return:

- run and phase status;
- risk and evidence levels;
- evidence independence and owner requirement;
- review actor and decision;
- orchestration stage and responsible party;
- blocked scope and continuation decision;
- priority finding ID;
- replay state;
- reason and exact next action.

The CLI version for this phase is `0.7.0-alpha`.
