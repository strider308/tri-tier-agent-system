# Automatic execution CLI

Phase 4 adds three commands to `tri-agent`.

## Preview the next dispatch

```powershell
tri-agent exec `
    -ProjectPath C:\dev\sample `
    -RunId run-001 `
    -DryRun `
    -Json
```

Dry-run mode reads the durable state and returns the next orchestration envelope.
It does not create execution-loop state and does not invoke a dispatcher.

## Run automatically

```powershell
tri-agent exec `
    -ProjectPath C:\dev\sample `
    -RunId run-001 `
    -DispatcherPath C:\tools\tri-tier-dispatcher.ps1 `
    -MaxSteps 25 `
    -MaxSameDecision 2 `
    -MaxAttemptsPerAction 2 `
    -StepTimeoutSeconds 1800 `
    -Json
```

Outside dry-run mode, `DispatcherPath` is required. Only one non-dry-run
execution invocation may own a run at a time. A concurrent `exec` or
`exec-resume` fails closed before dispatch.

## Resume after interruption

```powershell
tri-agent exec-resume `
    -ProjectPath C:\dev\sample `
    -RunId run-001 `
    -Json
```

Resume uses the dispatcher path stored in durable execution-loop state unless a
replacement `DispatcherPath` is supplied.

## Inspect execution state

```powershell
tri-agent exec-status `
    -ProjectPath C:\dev\sample `
    -RunId run-001 `
    -Json
```

The normalized result includes:

- run and loop status;
- current step;
- orchestration stage;
- responsible party;
- blocking scope;
- owner requirement;
- finding and phase identifiers;
- whether a dispatch occurred;
- dry-run state;
- stable action key;
- dispatcher path;
- stop reason;
- exact next action.

## Stop behavior

The command returns without dispatch when the durable decision requires:

- owner action;
- an external dependency;
- a blocked scope;
- a terminal stop.

These states are persisted in the execution-loop record so an operator can
inspect the reason and later use `exec-resume`.
