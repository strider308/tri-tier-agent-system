$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot = Split-Path $PSScriptRoot -Parent
$CliPath = Join-Path $RepoRoot 'src\tri-agent.ps1'
$PwshPath = (Get-Command pwsh -ErrorAction Stop).Source

function Invoke-CliRaw {
    param(
        [Parameter(Mandatory)]
        [object[]]$Arguments
    )

    $Output = @(
        & $PwshPath -NoProfile -File $CliPath @Arguments 2>&1
    )

    [PSCustomObject]@{
        exitCode = $LASTEXITCODE
        text = @(
            $Output | ForEach-Object {
                [string]$_
            }
        ) -join [Environment]::NewLine
    }
}

function Invoke-CliJson {
    param(
        [Parameter(Mandatory)]
        [object[]]$Arguments
    )

    $Invocation = Invoke-CliRaw -Arguments $Arguments

    if ($Invocation.exitCode -ne 0) {
        throw (
            "CLI command failed with exit code $($Invocation.exitCode): " +
            ($Arguments -join ' ') +
            [Environment]::NewLine +
            $Invocation.text
        )
    }

    if ([string]::IsNullOrWhiteSpace($Invocation.text)) {
        throw "CLI command returned no JSON: $($Arguments -join ' ')"
    }

    $Invocation.text.Trim() | ConvertFrom-Json -Depth 50
}

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

function Assert-CliFailure {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [object[]]$Arguments
    )

    $Invocation = Invoke-CliRaw -Arguments $Arguments

    Assert-Equal `
        -Name $Name `
        -Expected $true `
        -Actual ($Invocation.exitCode -ne 0)
}

function New-CliRun {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$RunId
    )

    Invoke-CliJson -Arguments @(
        'run-init',
        '-ProjectPath', $ProjectPath,
        '-RunId', $RunId,
        '-Title', "CLI flow test $RunId",
        '-CurrentTask', 'TASK-01',
        '-NextAction', 'Luna must implement TASK-01.',
        '-Json'
    )
}

function Move-CliRunToAdjudication {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$RunId,

        [Parameter(Mandatory)]
        [string]$Prefix
    )

    Invoke-CliJson -Arguments @(
        'task-flow-init',
        '-ProjectPath', $ProjectPath,
        '-RunId', $RunId,
        '-Actor', 'terra-manager',
        '-EventId', "$Prefix-init",
        '-Json'
    ) | Out-Null

    Invoke-CliJson -Arguments @(
        'implementation-complete',
        '-ProjectPath', $ProjectPath,
        '-RunId', $RunId,
        '-Actor', 'luna-worker',
        '-Summary', 'Implementation completed.',
        '-EventId', "$Prefix-implementation",
        '-Json'
    ) | Out-Null

    Invoke-CliJson -Arguments @(
        'task-review',
        '-ProjectPath', $ProjectPath,
        '-RunId', $RunId,
        '-Actor', 'sol-adjudicator',
        '-Outcome', 'FAIL',
        '-Summary', 'Task review found a blocking defect.',
        '-EventId', "$Prefix-task-review-fail",
        '-Json'
    ) | Out-Null

    Invoke-CliJson -Arguments @(
        'repair-open',
        '-ProjectPath', $ProjectPath,
        '-RunId', $RunId,
        '-Actor', 'terra-manager',
        '-Severity', 'MEDIUM',
        '-Title', 'CLI repair required',
        '-Description', 'The failed task review requires repair.',
        '-EventId', "$Prefix-repair-open",
        '-Json'
    ) | Out-Null

    Invoke-CliJson -Arguments @(
        'repair-complete',
        '-ProjectPath', $ProjectPath,
        '-RunId', $RunId,
        '-Actor', 'luna-worker',
        '-Summary', 'Applied the first repair.',
        '-EventId', "$Prefix-repair-complete",
        '-Json'
    ) | Out-Null

    Invoke-CliJson -Arguments @(
        'repair-review',
        '-ProjectPath', $ProjectPath,
        '-RunId', $RunId,
        '-Actor', 'sol-architect',
        '-Outcome', 'FAIL',
        '-Summary', 'The first repair failed independent review.',
        '-EventId', "$Prefix-repair-review-fail",
        '-Json'
    )
}

$TestRoot = Join-Path (
    [System.IO.Path]::GetTempPath()
) (
    'tri-tier-cli-flow-' + [guid]::NewGuid().ToString('N')
)

try {
    New-Item -ItemType Directory -Path $TestRoot -Force | Out-Null

    $Run = New-CliRun `
        -ProjectPath $TestRoot `
        -RunId 'cli-flow-main'

    Assert-Equal -Name 'run-init returns ACTIVE' -Expected 'ACTIVE' -Actual $Run.status

    $Initialized = Invoke-CliJson -Arguments @(
        'task-flow-init',
        '-ProjectPath', $TestRoot,
        '-RunId', $Run.runId,
        '-Actor', 'terra-manager',
        '-EventId', 'main-init',
        '-Json'
    )

    Assert-Equal -Name 'task-flow-init returns IMPLEMENT' -Expected 'IMPLEMENT' -Actual $Initialized.stage
    Assert-Equal -Name 'task-flow-init assigns Luna' -Expected 'luna' -Actual $Initialized.responsibleParty

    Assert-CliFailure -Name 'Terra cannot complete implementation' -Arguments @(
        'implementation-complete',
        '-ProjectPath', $TestRoot,
        '-RunId', $Run.runId,
        '-Actor', 'terra-manager',
        '-Summary', 'Invalid implementation actor.',
        '-EventId', 'main-invalid-implementation',
        '-Json'
    )

    $Implementation = Invoke-CliJson -Arguments @(
        'implementation-complete',
        '-ProjectPath', $TestRoot,
        '-RunId', $Run.runId,
        '-Actor', 'luna-worker',
        '-Summary', 'Implemented the bounded CLI task.',
        '-EvidenceIds', 'E-CLI-IMPLEMENT',
        '-EventId', 'main-implementation',
        '-Json'
    )

    Assert-Equal -Name 'implementation-complete enters REVIEW' -Expected 'REVIEW' -Actual $Implementation.stage
    Assert-Equal -Name 'implementation-complete assigns Sol' -Expected 'sol' -Actual $Implementation.responsibleParty

    $ImplementationReplay = Invoke-CliJson -Arguments @(
        'implementation-complete',
        '-ProjectPath', $TestRoot,
        '-RunId', $Run.runId,
        '-Actor', 'luna-worker',
        '-Summary', 'Ignored duplicate implementation.',
        '-EventId', 'main-implementation',
        '-Json'
    )

    Assert-Equal -Name 'implementation event replay is idempotent' -Expected $true -Actual ([bool]$ImplementationReplay.replayed)

    Assert-CliFailure -Name 'Luna cannot perform task review' -Arguments @(
        'task-review',
        '-ProjectPath', $TestRoot,
        '-RunId', $Run.runId,
        '-Actor', 'luna-worker',
        '-Outcome', 'PASS',
        '-Summary', 'Invalid self-review.',
        '-EventId', 'main-invalid-task-review',
        '-Json'
    )

    $FailedTaskReview = Invoke-CliJson -Arguments @(
        'task-review',
        '-ProjectPath', $TestRoot,
        '-RunId', $Run.runId,
        '-Actor', 'sol-adjudicator',
        '-Outcome', 'FAIL',
        '-Summary', 'Independent task review found a defect.',
        '-EventId', 'main-task-review-fail',
        '-Json'
    )

    Assert-Equal -Name 'failed task review remains REVIEW' -Expected 'REVIEW' -Actual $FailedTaskReview.stage
    Assert-Equal -Name 'failed task review hands control to Terra' -Expected 'terra' -Actual $FailedTaskReview.responsibleParty

    Assert-CliFailure -Name 'repair-open requires Terra actor' -Arguments @(
        'repair-open',
        '-ProjectPath', $TestRoot,
        '-RunId', $Run.runId,
        '-Actor', 'luna-worker',
        '-Severity', 'MEDIUM',
        '-Title', 'Invalid authorization',
        '-Description', 'Luna cannot authorize repair.',
        '-EventId', 'main-invalid-repair-open',
        '-Json'
    )

    $Opened = Invoke-CliJson -Arguments @(
        'repair-open',
        '-ProjectPath', $TestRoot,
        '-RunId', $Run.runId,
        '-Actor', 'terra-manager',
        '-Severity', 'MEDIUM',
        '-Title', 'CLI repair required',
        '-Description', 'Repair the failed task review finding.',
        '-EvidenceIds', 'E-CLI-REVIEW',
        '-EventId', 'main-repair-open',
        '-Json'
    )

    Assert-Equal -Name 'repair-open enters REPAIR' -Expected 'REPAIR' -Actual $Opened.stage
    Assert-Equal -Name 'repair-open assigns Luna' -Expected 'luna' -Actual $Opened.responsibleParty
    Assert-Equal -Name 'repair-open blocks task' -Expected 'TASK' -Actual $Opened.blockedScope

    $OpenReplay = Invoke-CliJson -Arguments @(
        'repair-open',
        '-ProjectPath', $TestRoot,
        '-RunId', $Run.runId,
        '-Actor', 'terra-manager',
        '-Severity', 'MEDIUM',
        '-Title', 'Ignored duplicate',
        '-Description', 'Ignored duplicate event.',
        '-EventId', 'main-repair-open',
        '-Json'
    )

    Assert-Equal -Name 'repair-open replay is idempotent' -Expected $true -Actual ([bool]$OpenReplay.replayed)

    $RepairStatus = Invoke-CliJson -Arguments @(
        'repair-status',
        '-ProjectPath', $TestRoot,
        '-RunId', $Run.runId,
        '-Json'
    )

    Assert-Equal -Name 'repair-status reads REPAIR' -Expected 'REPAIR' -Actual $RepairStatus.stage
    Assert-Equal -Name 'repair-status returns finding ID' -Expected $Opened.findingId -Actual $RepairStatus.findingId

    $Repaired = Invoke-CliJson -Arguments @(
        'repair-complete',
        '-ProjectPath', $TestRoot,
        '-RunId', $Run.runId,
        '-Actor', 'luna-worker',
        '-Summary', 'Applied the first CLI repair.',
        '-EvidenceIds', 'E-CLI-REPAIR-1',
        '-EventId', 'main-repair-complete-1',
        '-Json'
    )

    Assert-Equal -Name 'repair-complete enters FRESH_REVIEW' -Expected 'FRESH_REVIEW' -Actual $Repaired.stage
    Assert-Equal -Name 'repair-complete assigns Sol' -Expected 'sol' -Actual $Repaired.responsibleParty

    $FailedRepairReview = Invoke-CliJson -Arguments @(
        'repair-review',
        '-ProjectPath', $TestRoot,
        '-RunId', $Run.runId,
        '-Actor', 'sol-architect',
        '-Outcome', 'FAIL',
        '-Summary', 'First repair failed fresh review.',
        '-EvidenceIds', 'E-CLI-FRESH-FAIL',
        '-EventId', 'main-repair-review-fail',
        '-Json'
    )

    Assert-Equal -Name 'failed repair review enters ADJUDICATE' -Expected 'ADJUDICATE' -Actual $FailedRepairReview.stage
    Assert-Equal -Name 'failed repair review increments cycle' -Expected 1 -Actual ([int]$FailedRepairReview.reviewCycle)

    $Retry = Invoke-CliJson -Arguments @(
        'repair-adjudicate',
        '-ProjectPath', $TestRoot,
        '-RunId', $Run.runId,
        '-Actor', 'sol-adjudicator',
        '-Decision', 'REPAIR_AGAIN',
        '-Summary', 'Authorize one corrected repair.',
        '-EventId', 'main-adjudicate-retry',
        '-Json'
    )

    Assert-Equal -Name 'REPAIR_AGAIN returns to REPAIR' -Expected 'REPAIR' -Actual $Retry.stage
    Assert-Equal -Name 'REPAIR_AGAIN assigns Luna' -Expected 'luna' -Actual $Retry.responsibleParty

    Invoke-CliJson -Arguments @(
        'repair-complete',
        '-ProjectPath', $TestRoot,
        '-RunId', $Run.runId,
        '-Actor', 'luna-worker',
        '-Summary', 'Applied the corrected CLI repair.',
        '-EvidenceIds', 'E-CLI-REPAIR-2',
        '-EventId', 'main-repair-complete-2',
        '-Json'
    ) | Out-Null

    $PassedRepairReview = Invoke-CliJson -Arguments @(
        'repair-review',
        '-ProjectPath', $TestRoot,
        '-RunId', $Run.runId,
        '-Actor', 'sol-architect',
        '-Outcome', 'PASS',
        '-Summary', 'Corrected repair passed fresh review.',
        '-EvidenceIds', 'E-CLI-FRESH-PASS',
        '-EventId', 'main-repair-review-pass',
        '-Json'
    )

    Assert-Equal -Name 'passed repair review returns to REVIEW' -Expected 'REVIEW' -Actual $PassedRepairReview.stage
    Assert-Equal -Name 'passed repair review resolves finding' -Expected 'RESOLVED' -Actual $PassedRepairReview.findingStatus

    $PassedTaskReview = Invoke-CliJson -Arguments @(
        'task-review',
        '-ProjectPath', $TestRoot,
        '-RunId', $Run.runId,
        '-Actor', 'sol-adjudicator',
        '-Outcome', 'PASS',
        '-Summary', 'Final independent task review passed.',
        '-EventId', 'main-task-review-pass',
        '-Json'
    )

    Assert-Equal -Name 'final task review enters CONTINUE' -Expected 'CONTINUE' -Actual $PassedTaskReview.stage
    Assert-Equal -Name 'final task review permits advancement' -Expected $true -Actual ([bool]$PassedTaskReview.mayAdvance)

    $Planning = Invoke-CliJson -Arguments @(
        'task-planning-start',
        '-ProjectPath', $TestRoot,
        '-RunId', $Run.runId,
        '-Actor', 'terra-manager',
        '-EventId', 'main-planning',
        '-Json'
    )

    Assert-Equal -Name 'task-planning-start returns PLAN' -Expected 'PLAN' -Actual $Planning.stage

    $SecondTask = Invoke-CliJson -Arguments @(
        'task-start',
        '-ProjectPath', $TestRoot,
        '-RunId', $Run.runId,
        '-TaskId', 'TASK-02',
        '-Actor', 'terra-manager',
        '-Instruction', 'Luna must implement TASK-02.',
        '-EventId', 'main-task-two',
        '-Json'
    )

    Assert-Equal -Name 'task-start enters IMPLEMENT' -Expected 'IMPLEMENT' -Actual $SecondTask.stage
    Assert-Equal -Name 'task-start persists new task' -Expected 'TASK-02' -Actual $SecondTask.currentTask

    $TaskStatus = Invoke-CliJson -Arguments @(
        'task-flow-status',
        '-ProjectPath', $TestRoot,
        '-RunId', $Run.runId,
        '-Json'
    )

    Assert-Equal -Name 'task-flow-status reads current stage' -Expected 'IMPLEMENT' -Actual $TaskStatus.stage
    Assert-Equal -Name 'task-flow-status returns exact next action' -Expected 'Luna must implement TASK-02.' -Actual $TaskStatus.nextAction

    $OwnerRun = New-CliRun `
        -ProjectPath $TestRoot `
        -RunId 'cli-flow-owner'

    $OwnerAdjudication = Move-CliRunToAdjudication `
        -ProjectPath $TestRoot `
        -RunId $OwnerRun.runId `
        -Prefix 'owner'

    Assert-Equal -Name 'owner path reaches ADJUDICATE' -Expected 'ADJUDICATE' -Actual $OwnerAdjudication.stage

    $OwnerDecision = Invoke-CliJson -Arguments @(
        'repair-adjudicate',
        '-ProjectPath', $TestRoot,
        '-RunId', $OwnerRun.runId,
        '-Actor', 'sol-adjudicator',
        '-Decision', 'OWNER_DECISION',
        '-Summary', 'Owner judgment is required.',
        '-EventId', 'owner-adjudication',
        '-Json'
    )

    Assert-Equal -Name 'OWNER_DECISION blocks run status' -Expected 'BLOCKED_OWNER_DECISION' -Actual $OwnerDecision.status
    Assert-Equal -Name 'OWNER_DECISION assigns owner' -Expected 'owner' -Actual $OwnerDecision.responsibleParty

    Assert-CliFailure -Name 'owner-gated run rejects further repair mutation' -Arguments @(
        'repair-complete',
        '-ProjectPath', $TestRoot,
        '-RunId', $OwnerRun.runId,
        '-Actor', 'luna-worker',
        '-Summary', 'Invalid mutation while owner-gated.',
        '-EventId', 'owner-invalid-mutation',
        '-Json'
    )

    $VersionOutput = @(
        & $PwshPath -NoProfile -File $CliPath version 2>&1
    )

    if ($LASTEXITCODE -ne 0) {
        throw "CLI version command failed with exit code $LASTEXITCODE."
    }

    Assert-Equal `
        -Name 'CLI version advanced' `
        -Expected 'tri-tier-agent-system 0.10.0-alpha' `
        -Actual (($VersionOutput -join '').Trim())

    Write-Host 'Task-flow and repair-cycle CLI tests passed.' -ForegroundColor Green
}
finally {
    if (Test-Path $TestRoot) {
        Remove-Item -LiteralPath $TestRoot -Recurse -Force
    }
}
