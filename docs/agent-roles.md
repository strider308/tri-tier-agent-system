# Agent Roles and Durable Authority

Phase 5 binds the six public agent profiles to the deterministic orchestration and execution-loop stages.

## Runtime owners

| Stage | Responsible party | Profile | Write authority |
| --- | --- | --- | --- |
| PLAN | Terra | `terra_manager` | Yes |
| IMPLEMENT | Luna | `luna_worker` | Yes |
| REVIEW | Sol | `sol_architect` | No |
| Failed REVIEW coordination | Terra | `terra_manager` | Yes, coordination only |
| REPAIR | Luna | `luna_worker` | Yes |
| FRESH_REVIEW | Sol | `sol_architect` | No |
| ADJUDICATE | Sol | `sol_adjudicator` | No |
| CONTINUE | Terra | `terra_manager` | Yes |
| PHASE_REVIEW | Sol | `sol_adjudicator` | No |
| WAIT_EXTERNAL | Terra | `terra_manager` | Coordination only |
| OWNER_DECISION | Owner | No agent profile | No automatic continuation |
| STOP | Sol or none | `sol_adjudicator` when analysis is required | No |

## Advisory profiles

`luna_router` performs read-only bounded routing. It does not own a durable execution stage and cannot override persisted orchestration.

`terra_reviewer` performs read-only integration and evidence review. It may identify missing validation or escalation requirements, but it cannot satisfy a Sol-required independent review or phase gate.

## Independence

The profile that implements or repairs work cannot provide the required independent REVIEW, FRESH_REVIEW, or PHASE_REVIEW approval. Sol profiles remain read-only. Review failure creates evidence for a finding or adjudication; it does not authorize the reviewer to repair the code.

## Durable execution envelopes

The execution loop resolves the exact target profile before dispatch and includes both the resolved profile and a structured handoff in every envelope. `exec -DryRun -Json` surfaces the selected profile and handoff direction before work is dispatched. Owner decisions contain no agent profile and stop before automatic dispatch.
