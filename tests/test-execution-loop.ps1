$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot = Split-Path $PSScriptRoot -Parent
$StatePath = Join-Path $RepoRoot 'src\TriTier\State.psm1'
$TaskFlowPath = Join-Path $RepoRoot 'src\TriTier\TaskFlow.psm1'
$ExecutionLoopPath = Join-Path $RepoRoot 'src\TriTier\ExecutionLoop.psm1'

Import-Module $StatePath -Force
Import-Module $TaskFlowPath -Force
$ExecutionLoopModule = Import-Module $ExecutionLoopPath -Force -PassThru

function Assert-Equal {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter()]
        $Expected,

        [Parameter()]
        $Actual
    )

    $Passed = $Expected -eq $Actual

    [PSCustomObject]@{
        Test = $Name
        Status = if ($Passed) { 'PASS' } else { 'FAIL' }
    } | Format-Table -AutoSize

    if (-not $Passed) {
        throw "$Name failed. Expected: $Expected. Actual: $Actual."
    }
}

function Assert-True {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [bool]$Value
    )

    Assert-Equal -Name $Name -Expected $true -Actual $Value
}

function Assert-Throws {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [scriptblock]$Action
    )

    $Thrown = $false

    try {
        & $Action
    }
    catch {
        $Thrown = $true
    }

    Assert-True -Name $Name -Value $Thrown
}


Assert-True `
    -Name 'ExecutionLoop import preserves New-TriTierRun' `
    -Value (
        $null -ne (
            Get-Command `
                -Name 'New-TriTierRun' `
                -CommandType Function `
                -ErrorAction SilentlyContinue
        )
    )

Assert-True `
    -Name 'ExecutionLoop import preserves New-TriTierCheckpoint' `
    -Value (
        $null -ne (
            Get-Command `
                -Name 'New-TriTierCheckpoint' `
                -CommandType Function `
                -ErrorAction SilentlyContinue
        )
    )

Assert-True `
    -Name 'ExecutionLoop import preserves task-flow commands' `
    -Value (
        $null -ne (
            Get-Command `
                -Name 'Initialize-TriTierRunTaskFlow' `
                -CommandType Function `
                -ErrorAction SilentlyContinue
        )
    )

$StableActionDecision = [PSCustomObject][ordered]@{
    stage = 'IMPLEMENT'
    responsibleParty = 'luna'
    blockedScope = 'NONE'
    findingId = ''
    phaseId = ''
    nextAction = 'Implement the stable action-key task.'
}
$StableActionStateOne = [PSCustomObject][ordered]@{
    runId = 'action-key-stability'
    status = 'ACTIVE'
    currentTask = 'task-one'
    updatedUtc = '2026-08-06T00:00:00.0000000Z'
}
$StableActionStateTwo = [PSCustomObject][ordered]@{
    runId = 'action-key-stability'
    status = 'ACTIVE'
    currentTask = 'task-one'
    updatedUtc = '2026-08-06T00:00:01.0000000Z'
}
$ChangedTaskActionState = [PSCustomObject][ordered]@{
    runId = 'action-key-stability'
    status = 'ACTIVE'
    currentTask = 'task-two'
    updatedUtc = '2026-08-06T00:00:01.0000000Z'
}

$StableActionKeyOne = & $ExecutionLoopModule {
    param([object]$State, [object]$Decision)
    Get-TriTierExecutionActionKey -RunState $State -Decision $Decision
} $StableActionStateOne $StableActionDecision

$StableActionKeyTwo = & $ExecutionLoopModule {
    param([object]$State, [object]$Decision)
    Get-TriTierExecutionActionKey -RunState $State -Decision $Decision
} $StableActionStateTwo $StableActionDecision

$ChangedTaskActionKey = & $ExecutionLoopModule {
    param([object]$State, [object]$Decision)
    Get-TriTierExecutionActionKey -RunState $State -Decision $Decision
} $ChangedTaskActionState $StableActionDecision

Assert-Equal `
    -Name 'Bookkeeping timestamp does not change action key' `
    -Expected $StableActionKeyOne `
    -Actual $StableActionKeyTwo
Assert-True `
    -Name 'Current task changes action key' `
    -Value ($StableActionKeyOne -ne $ChangedTaskActionKey)

function Get-TestRunDirectory {
    param(
        [Parameter(Mandatory)]
        [string]$Root,

        [Parameter(Mandatory)]
        [string]$RunId
    )

    Join-Path $Root ".tri-tier\runs\$RunId"
}

function Set-TestRunStatus {
    param(
        [Parameter(Mandatory)]
        [string]$Root,

        [Parameter(Mandatory)]
        [string]$RunId,

        [Parameter(Mandatory)]
        [string]$Status,

        [Parameter(Mandatory)]
        [string]$NextAction
    )

    $RunDirectory = Get-TestRunDirectory -Root $Root -RunId $RunId
    $StatePath = Join-Path $RunDirectory 'state\run-state.json'
    $NextActionPath = Join-Path $RunDirectory 'state\next-action.txt'
    $State = Get-Content `
        -LiteralPath $StatePath `
        -Raw `
        -Encoding UTF8 |
        ConvertFrom-Json

    $State.status = $Status
    $State.nextAction = $NextAction
    $State.updatedUtc = [DateTime]::UtcNow.ToString('o')

    [System.IO.File]::WriteAllText(
        $StatePath,
        (
            $State |
                ConvertTo-Json -Depth 100
        ) + [Environment]::NewLine,
        [System.Text.UTF8Encoding]::new($false)
    )
    [System.IO.File]::WriteAllText(
        $NextActionPath,
        $NextAction + [Environment]::NewLine,
        [System.Text.UTF8Encoding]::new($false)
    )
}

function New-TestRun {
    param(
        [Parameter(Mandatory)]
        [string]$Root,

        [Parameter(Mandatory)]
        [string]$RunId
    )

    [void](
        New-TriTierRun `
            -ProjectPath $Root `
            -RunId $RunId `
            -Title "Execution-loop test $RunId" `
            -CurrentTask 'TASK-001' `
            -NextAction 'Luna must implement the bounded task.'
    )

    [void](
        Initialize-TriTierRunTaskFlow `
            -ProjectPath $Root `
            -RunId $RunId `
            -InitializedBy 'terra-manager' `
            -EventId "init-$RunId"
    )
}

$TestRoot = Join-Path (
    [System.IO.Path]::GetTempPath()
) (
    'tri-tier-execution-loop-' +
    [guid]::NewGuid().ToString('N')
)

New-Item -ItemType Directory -Path $TestRoot -Force | Out-Null

$CompletionDispatcher = Join-Path $TestRoot 'complete-dispatcher.ps1'
$NoChangeDispatcher = Join-Path $TestRoot 'no-change-dispatcher.ps1'
$CounterDispatcher = Join-Path $TestRoot 'counter-dispatcher.ps1'
$BadResultDispatcher = Join-Path $TestRoot 'bad-result-dispatcher.ps1'

$CompletionDispatcherContent = @'
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$EnvelopePath,

    [Parameter(Mandatory)]
    [string]$ResultPath
)

$ErrorActionPreference = 'Stop'
$Envelope = Get-Content -LiteralPath $EnvelopePath -Raw -Encoding UTF8 |
    ConvertFrom-Json
$State = Get-Content -LiteralPath $Envelope.runStatePath -Raw -Encoding UTF8 |
    ConvertFrom-Json
$State.status = 'COMPLETE'
$State.nextAction = 'Run completed by the deterministic test dispatcher.'
$State.updatedUtc = [DateTime]::UtcNow.ToString('o')
$Encoding = [System.Text.UTF8Encoding]::new($false)

[System.IO.File]::WriteAllText(
    $Envelope.runStatePath,
    ($State | ConvertTo-Json -Depth 100) + [Environment]::NewLine,
    $Encoding
)
[System.IO.File]::WriteAllText(
    $Envelope.nextActionPath,
    $State.nextAction + [Environment]::NewLine,
    $Encoding
)

$Result = [PSCustomObject][ordered]@{
    schemaVersion = 1
    actionKey = [string]$Envelope.actionKey
    outcome = 'STATE_UPDATED'
    summary = 'Completed the run through the test dispatcher.'
}

[System.IO.File]::WriteAllText(
    $ResultPath,
    ($Result | ConvertTo-Json -Depth 20) + [Environment]::NewLine,
    $Encoding
)
'@

$NoChangeDispatcherContent = @'
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$EnvelopePath,

    [Parameter(Mandatory)]
    [string]$ResultPath
)

$ErrorActionPreference = 'Stop'
$Envelope = Get-Content -LiteralPath $EnvelopePath -Raw -Encoding UTF8 |
    ConvertFrom-Json
$Result = [PSCustomObject][ordered]@{
    schemaVersion = 1
    actionKey = [string]$Envelope.actionKey
    outcome = 'NO_CHANGE'
    summary = 'Intentionally left durable run state unchanged.'
}

[System.IO.File]::WriteAllText(
    $ResultPath,
    ($Result | ConvertTo-Json -Depth 20) + [Environment]::NewLine,
    [System.Text.UTF8Encoding]::new($false)
)
'@

$CounterDispatcherContent = @'
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$EnvelopePath,

    [Parameter(Mandatory)]
    [string]$ResultPath
)

$MarkerPath = $ResultPath + '.invoked'
[System.IO.File]::WriteAllText(
    $MarkerPath,
    'invoked',
    [System.Text.UTF8Encoding]::new($false)
)
throw 'Counter dispatcher should not have been invoked.'
'@

$BadResultDispatcherContent = @'
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$EnvelopePath,

    [Parameter(Mandatory)]
    [string]$ResultPath
)

$Envelope = Get-Content -LiteralPath $EnvelopePath -Raw -Encoding UTF8 |
    ConvertFrom-Json
$Result = [PSCustomObject][ordered]@{
    schemaVersion = 1
    actionKey = 'wrong-action-key'
    outcome = 'STATE_UPDATED'
    summary = 'Wrote a deliberately invalid result.'
}

[System.IO.File]::WriteAllText(
    $ResultPath,
    ($Result | ConvertTo-Json -Depth 20) + [Environment]::NewLine,
    [System.Text.UTF8Encoding]::new($false)
)
'@

foreach ($Dispatcher in @(
    @{
        Path = $CompletionDispatcher
        Content = $CompletionDispatcherContent
    }
    @{
        Path = $NoChangeDispatcher
        Content = $NoChangeDispatcherContent
    }
    @{
        Path = $CounterDispatcher
        Content = $CounterDispatcherContent
    }
    @{
        Path = $BadResultDispatcher
        Content = $BadResultDispatcherContent
    }
)) {
    [System.IO.File]::WriteAllText(
        $Dispatcher.Path,
        $Dispatcher.Content,
        [System.Text.UTF8Encoding]::new($false)
    )
}

try {
    $DryRunId = 'execution-dry-run'
    New-TestRun -Root $TestRoot -RunId $DryRunId

    $DryRunResult = Invoke-TriTierRunExecutionLoop `
        -ProjectPath $TestRoot `
        -RunId $DryRunId `
        -DryRun

    Assert-True `
        -Name 'Dry run is reported without dispatch' `
        -Value ([bool]$DryRunResult.dryRun)
    Assert-Equal `
        -Name 'Dry run routes current task to IMPLEMENT' `
        -Expected 'IMPLEMENT' `
        -Actual $DryRunResult.decision.stage
    Assert-Equal `
        -Name 'Dry run routes implementation to Luna' `
        -Expected 'luna' `
        -Actual $DryRunResult.decision.responsibleParty
    Assert-Equal `
        -Name 'Dry run uses execution envelope schema two' `
        -Expected 2 `
        -Actual $DryRunResult.envelope.schemaVersion
    Assert-Equal `
        -Name 'Dry run resolves Luna worker profile' `
        -Expected 'luna_worker' `
        -Actual $DryRunResult.envelope.profileName
    Assert-Equal `
        -Name 'Dry run handoff targets Luna worker' `
        -Expected 'luna_worker' `
        -Actual $DryRunResult.envelope.handoff.toProfile
    Assert-Equal `
        -Name 'Dry run handoff retains IMPLEMENT stage' `
        -Expected 'IMPLEMENT' `
        -Actual $DryRunResult.envelope.handoff.stage
    Assert-True `
        -Name 'Dry run handoff includes acceptance criteria' `
        -Value (@($DryRunResult.envelope.handoff.acceptanceCriteria).Count -gt 0)

    $DryRunStatePath = Join-Path (
        Get-TestRunDirectory -Root $TestRoot -RunId $DryRunId
    ) 'execution\execution-loop.json'

    Assert-Equal `
        -Name 'Dry run writes no execution-loop state' `
        -Expected $false `
        -Actual (Test-Path -LiteralPath $DryRunStatePath)

    $IdentityRunId = 'execution-identity'
    New-TestRun -Root $TestRoot -RunId $IdentityRunId

    [void](
        Initialize-TriTierRunExecutionLoop `
            -ProjectPath $TestRoot `
            -RunId $IdentityRunId `
            -DispatcherPath $CompletionDispatcher `
            -MaxSteps 3 `
            -StepTimeoutSeconds 30
    )

    $IdentityStatePath = Join-Path (
        Get-TestRunDirectory -Root $TestRoot -RunId $IdentityRunId
    ) 'execution\execution-loop.json'
    $IdentityState = Get-Content `
        -LiteralPath $IdentityStatePath `
        -Raw `
        -Encoding UTF8 |
        ConvertFrom-Json
    $IdentityState.runId = 'different-run'

    [System.IO.File]::WriteAllText(
        $IdentityStatePath,
        (
            $IdentityState |
                ConvertTo-Json -Depth 100
        ) + [Environment]::NewLine,
        [System.Text.UTF8Encoding]::new($false)
    )

    Assert-Throws `
        -Name 'Execution-loop state rejects mismatched run identity' `
        -Action {
            Get-TriTierRunExecutionLoop `
                -ProjectPath $TestRoot `
                -RunId $IdentityRunId |
                Out-Null
        }

    $CompleteRunId = 'execution-complete'
    New-TestRun -Root $TestRoot -RunId $CompleteRunId

    $CompleteResult = Invoke-TriTierRunExecutionLoop `
        -ProjectPath $TestRoot `
        -RunId $CompleteRunId `
        -DispatcherPath $CompletionDispatcher `
        -MaxSteps 5 `
        -MaxSameDecision 2 `
        -MaxAttemptsPerAction 2 `
        -StepTimeoutSeconds 30

    Assert-Equal `
        -Name 'Dispatcher can drive run to COMPLETE' `
        -Expected 'COMPLETE' `
        -Actual $CompleteResult.loop.status
    Assert-True `
        -Name 'Completion path records a dispatch' `
        -Value ([bool]$CompleteResult.dispatched)
    Assert-Equal `
        -Name 'Completion updates durable run status' `
        -Expected 'COMPLETE' `
        -Actual $CompleteResult.state.status

    $PersistedComplete = Get-TriTierRunExecutionLoop `
        -ProjectPath $TestRoot `
        -RunId $CompleteRunId

    Assert-Equal `
        -Name 'Execution-loop completion is durable' `
        -Expected 'COMPLETE' `
        -Actual $PersistedComplete.status
    $CheckpointFiles = @(
        Get-ChildItem `
            -LiteralPath (
                Get-TestRunDirectory `
                    -Root $TestRoot `
                    -RunId $CompleteRunId
            ) `
            -Recurse `
            -File |
            Where-Object {
                $_.FullName -match '[\\/]checkpoints?[\\/]'
            }
    )

    Assert-True `
        -Name 'Execution-loop writes before and after checkpoints' `
        -Value ($CheckpointFiles.Count -ge 2)

    $OwnerRunId = 'execution-owner-gate'
    New-TestRun -Root $TestRoot -RunId $OwnerRunId
    Set-TestRunStatus `
        -Root $TestRoot `
        -RunId $OwnerRunId `
        -Status 'BLOCKED_OWNER_DECISION' `
        -NextAction 'Owner must approve the gated decision.'

    $OwnerResult = Invoke-TriTierRunExecutionLoop `
        -ProjectPath $TestRoot `
        -RunId $OwnerRunId `
        -DispatcherPath $CounterDispatcher `
        -MaxSteps 3 `
        -StepTimeoutSeconds 30

    Assert-Equal `
        -Name 'Owner gate stops automatic execution' `
        -Expected 'WAITING_OWNER' `
        -Actual $OwnerResult.loop.status
    Assert-Equal `
        -Name 'Owner gate does not dispatch work' `
        -Expected $false `
        -Actual ([bool]$OwnerResult.dispatched)

    $ExternalRunId = 'execution-external-gate'
    New-TestRun -Root $TestRoot -RunId $ExternalRunId
    Set-TestRunStatus `
        -Root $TestRoot `
        -RunId $ExternalRunId `
        -Status 'BLOCKED_EXTERNAL_DEPENDENCY' `
        -NextAction 'Wait for the external dependency.'

    $ExternalResult = Invoke-TriTierRunExecutionLoop `
        -ProjectPath $TestRoot `
        -RunId $ExternalRunId `
        -DispatcherPath $CounterDispatcher `
        -MaxSteps 3 `
        -StepTimeoutSeconds 30

    Assert-Equal `
        -Name 'External dependency stops automatic execution' `
        -Expected 'WAITING_EXTERNAL' `
        -Actual $ExternalResult.loop.status
    Assert-Equal `
        -Name 'External dependency does not dispatch work' `
        -Expected $false `
        -Actual ([bool]$ExternalResult.dispatched)

    $StalledRunId = 'execution-stalled'
    New-TestRun -Root $TestRoot -RunId $StalledRunId

    $StalledResult = Invoke-TriTierRunExecutionLoop `
        -ProjectPath $TestRoot `
        -RunId $StalledRunId `
        -DispatcherPath $NoChangeDispatcher `
        -MaxSteps 5 `
        -MaxSameDecision 1 `
        -MaxAttemptsPerAction 2 `
        -StepTimeoutSeconds 30

    Assert-Equal `
        -Name 'No-change dispatcher triggers stall protection' `
        -Expected 'PAUSED_STALLED' `
        -Actual $StalledResult.loop.status
    Assert-Equal `
        -Name 'Stall protection limits repeated dispatch' `
        -Expected 1 `
        -Actual ([int]$StalledResult.loop.currentStep)

    $RecoveryRunId = 'execution-recovery'
    New-TestRun -Root $TestRoot -RunId $RecoveryRunId

    $RecoveryState = Initialize-TriTierRunExecutionLoop `
        -ProjectPath $TestRoot `
        -RunId $RecoveryRunId `
        -DispatcherPath $CompletionDispatcher `
        -MaxSteps 5 `
        -MaxSameDecision 2 `
        -MaxAttemptsPerAction 2 `
        -StepTimeoutSeconds 30

    $RecoveryState.status = 'RUNNING'
    $RecoveryState.inFlight = [PSCustomObject][ordered]@{
        actionKey = 'interrupted-action'
        attempt = 1
        step = 1
        envelopePath = 'interrupted-envelope.json'
        resultPath = 'interrupted-result.json'
        startedUtc = [DateTime]::UtcNow.ToString('o')
    }

    $RecoveryStatePath = Join-Path (
        Get-TestRunDirectory -Root $TestRoot -RunId $RecoveryRunId
    ) 'execution\execution-loop.json'

    [System.IO.File]::WriteAllText(
        $RecoveryStatePath,
        (
            $RecoveryState |
                ConvertTo-Json -Depth 100
        ) + [Environment]::NewLine,
        [System.Text.UTF8Encoding]::new($false)
    )

    $RecoveredResult = Resume-TriTierRunExecutionLoop `
        -ProjectPath $TestRoot `
        -RunId $RecoveryRunId `
        -MaxSteps 5 `
        -MaxSameDecision 2 `
        -MaxAttemptsPerAction 2 `
        -StepTimeoutSeconds 30

    Assert-Equal `
        -Name 'Interrupted execution can resume to completion' `
        -Expected 'COMPLETE' `
        -Actual $RecoveredResult.loop.status
    Assert-True `
        -Name 'Interrupted execution recovery is recorded' `
        -Value (
            @(
                $RecoveredResult.loop.history |
                    Where-Object {
                        $_.eventType -eq 'INTERRUPTED_ACTION_RECOVERED'
                    }
            ).Count -eq 1
        )

    $RetryRunId = 'execution-retry-after-failure'
    New-TestRun -Root $TestRoot -RunId $RetryRunId

    Assert-Throws `
        -Name 'Invalid first attempt fails before retry' `
        -Action {
            Invoke-TriTierRunExecutionLoop `
                -ProjectPath $TestRoot `
                -RunId $RetryRunId `
                -DispatcherPath $BadResultDispatcher `
                -MaxSteps 3 `
                -MaxSameDecision 1 `
                -MaxAttemptsPerAction 2 `
                -StepTimeoutSeconds 30 |
                Out-Null
        }

    $RetryResult = Resume-TriTierRunExecutionLoop `
        -ProjectPath $TestRoot `
        -RunId $RetryRunId `
        -DispatcherPath $CompletionDispatcher `
        -MaxSteps 3 `
        -MaxSameDecision 1 `
        -MaxAttemptsPerAction 2 `
        -StepTimeoutSeconds 30

    Assert-Equal `
        -Name 'Failed attempt uses retry budget instead of stall budget' `
        -Expected 'COMPLETE' `
        -Actual $RetryResult.loop.status

    $LockRunId = 'execution-concurrent-lock'
    New-TestRun -Root $TestRoot -RunId $LockRunId

    $LockExecutionDirectory = Join-Path (
        Get-TestRunDirectory -Root $TestRoot -RunId $LockRunId
    ) 'execution'
    New-Item `
        -ItemType Directory `
        -Path $LockExecutionDirectory `
        -Force |
        Out-Null

    $HeldLockPath = Join-Path $LockExecutionDirectory 'execution-loop.lock'
    $HeldLock = [System.IO.FileStream]::new(
        $HeldLockPath,
        [System.IO.FileMode]::OpenOrCreate,
        [System.IO.FileAccess]::ReadWrite,
        [System.IO.FileShare]::None
    )

    try {
        Assert-Throws `
            -Name 'Concurrent execution invocation fails closed' `
            -Action {
                Invoke-TriTierRunExecutionLoop `
                    -ProjectPath $TestRoot `
                    -RunId $LockRunId `
                    -DispatcherPath $CompletionDispatcher `
                    -MaxSteps 3 `
                    -StepTimeoutSeconds 30 |
                    Out-Null
            }
    }
    finally {
        $HeldLock.Dispose()
    }

    $UnlockedResult = Invoke-TriTierRunExecutionLoop `
        -ProjectPath $TestRoot `
        -RunId $LockRunId `
        -DispatcherPath $CompletionDispatcher `
        -MaxSteps 3 `
        -StepTimeoutSeconds 30

    Assert-Equal `
        -Name 'Execution continues after exclusive lock release' `
        -Expected 'COMPLETE' `
        -Actual $UnlockedResult.loop.status

    $InvalidRunId = 'execution-invalid-result'
    New-TestRun -Root $TestRoot -RunId $InvalidRunId

    Assert-Throws `
        -Name 'Invalid dispatcher result fails closed' `
        -Action {
            Invoke-TriTierRunExecutionLoop `
                -ProjectPath $TestRoot `
                -RunId $InvalidRunId `
                -DispatcherPath $BadResultDispatcher `
                -MaxSteps 3 `
                -StepTimeoutSeconds 30 |
                Out-Null
        }

    $InvalidLoop = Get-TriTierRunExecutionLoop `
        -ProjectPath $TestRoot `
        -RunId $InvalidRunId

    Assert-Equal `
        -Name 'Dispatcher contract failure is durable' `
        -Expected 'FAILED' `
        -Actual $InvalidLoop.status
    Assert-Equal `
        -Name 'Failed dispatch clears in-flight marker' `
        -Expected $null `
        -Actual $InvalidLoop.inFlight

    Write-Host ''
    Write-Host 'Durable automatic execution-loop tests passed.' -ForegroundColor Green
}
finally {
    Remove-Item `
        -LiteralPath $TestRoot `
        -Recurse `
        -Force `
        -ErrorAction SilentlyContinue
}
