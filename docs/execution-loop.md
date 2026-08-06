# Durable automatic execution loop

Phase 4 connects the deterministic orchestration decision engine to a durable,
restartable execution loop.

The loop does not embed a specific agent runtime. It issues a versioned JSON
envelope to a configured PowerShell dispatcher. Phase 5 can bind that dispatcher
contract to the final Terra, Luna, and Sol profiles without changing the durable
loop.

## Control flow

For every step the loop:

1. reads the durable run state;
2. recomputes the orchestration decision;
3. stops before dispatch for owner, external, blocked, and terminal gates;
4. derives a stable action key from the durable state and decision;
5. persists an in-flight marker and a pre-dispatch checkpoint;
6. invokes the dispatcher in a child PowerShell process;
7. validates the dispatch result and re-reads durable state;
8. proves the claimed state-change outcome;
9. clears the in-flight marker and persists a post-dispatch checkpoint;
10. repeats until a gate, terminal state, or configured safety limit is reached.

## Durable files

Execution state is local to the project and ignored by the public repository:

```text
.tri-tier/
  runs/
    <run-id>/
      execution/
        execution-loop.json
        execution-loop.lock
        dispatches/
          step-0001-<action>-attempt-01-envelope.json
          step-0001-<action>-attempt-01-result.json
```

The loop does not alter the existing run-state schema. Its state is stored beside
the existing run state so restart recovery can evolve independently.

## Exclusive execution ownership

A non-dry-run invocation opens `execution-loop.lock` with exclusive file sharing
for the full execution call. A second `exec` or `exec-resume` process for the
same run fails closed before dispatch. The operating system releases the lock
handle if the owner process exits or crashes, so the durable in-flight marker can
then be recovered by a later resume.

The lock file may remain on disk after release; ownership is represented by the
open exclusive handle, not by file existence.

## Dispatcher contract

A dispatcher is a PowerShell file accepting:

```powershell
param(
    [string]$EnvelopePath,
    [string]$ResultPath
)
```

The envelope contains:

- `schemaVersion`
- `actionKey`
- `attempt`
- `step`
- `projectPath`
- `runId`
- `runStatePath`
- `nextActionPath`
- `resultPath`
- `runState`
- `decision`
- `issuedUtc`

The dispatcher performs exactly one durable orchestration action. It must write a
JSON result with:

```json
{
  "schemaVersion": 1,
  "actionKey": "<matching action key>",
  "outcome": "STATE_UPDATED",
  "summary": "What changed"
}
```

`outcome` is either:

- `STATE_UPDATED` when durable run state changed; or
- `NO_CHANGE` when it intentionally did not change.

The loop re-reads durable state and verifies the claim. A false `STATE_UPDATED`
or false `NO_CHANGE` result fails closed.

## Restart recovery

Before dispatch, the loop persists an `inFlight` record. If the process stops
after that write, `exec-resume` records an interrupted-action recovery event,
recomputes the current action, and retries only within the configured attempt
limit.

The dispatcher must therefore be idempotent for a stable `actionKey`.

## Safety limits

- `MaxSteps`: maximum dispatches in one invocation.
- `MaxSameDecision`: repeated unchanged decisions before pausing as stalled.
- `MaxAttemptsPerAction`: maximum dispatch attempts for one stable action key.
- `StepTimeoutSeconds`: child dispatcher timeout.

The loop never dispatches when the orchestration engine returns:

- `OWNER_DECISION`
- `WAIT_EXTERNAL`
- `STOP`
- `canContinue = false`

## Execution statuses

- `IDLE`
- `RUNNING`
- `RECOVERING`
- `WAITING_OWNER`
- `WAITING_EXTERNAL`
- `PAUSED_BLOCKED`
- `PAUSED_LIMIT`
- `PAUSED_STALLED`
- `COMPLETE`
- `FAILED`
- `ABORTED`

## Independence and authority

The loop follows the decision returned by `Orchestration.psm1`; it does not
override role authority:

- Terra coordinates and continues.
- Luna implements and repairs.
- Sol reviews and adjudicates.
- Owner gates remain non-automatic.

The dispatcher receives `responsibleParty` and the exact `nextAction`. It must
enforce the agent binding and evidence production appropriate to that decision.
