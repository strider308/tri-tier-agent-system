$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot = Split-Path $PSScriptRoot -Parent
$StatePath = Join-Path $RepoRoot 'src\TriTier\State.psm1'
$FindingsPath = Join-Path $RepoRoot 'src\TriTier\Findings.psm1'
$TaskFlowPath = Join-Path $RepoRoot 'src\TriTier\TaskFlow.psm1'
$OrchestrationPath = Join-Path $RepoRoot 'src\TriTier\Orchestration.psm1'

Import-Module $StatePath -Force
Import-Module $FindingsPath -Force
Import-Module $TaskFlowPath -Force
Import-Module $OrchestrationPath -Force

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

function Copy-Object {
    param(
        [Parameter(Mandatory)]
        [object]$InputObject
    )

    $InputObject |
        ConvertTo-Json -Depth 100 |
        ConvertFrom-Json -Depth 100
}

$TestRoot = Join-Path (
    [System.IO.Path]::GetTempPath()
) (
    'tri-tier-orchestration-' + [guid]::NewGuid().ToString('N')
)

try {
    New-Item -ItemType Directory -Path $TestRoot -Force | Out-Null

    $Run = New-TriTierRun `
        -ProjectPath $TestRoot `
        -RunId 'orchestration-main' `
        -Title 'Orchestration decision test' `
        -CurrentTask 'TASK-ORCH' `
        -NextAction 'Luna must implement TASK-ORCH.'

    Initialize-TriTierRunTaskFlow `
        -ProjectPath $TestRoot `
        -RunId $Run.state.runId `
        -InitializedBy 'terra-manager' `
        -EventId 'orch-init' |
        Out-Null

    $ImplementDecision = Get-TriTierRunOrchestrationDecision `
        -ProjectPath $TestRoot `
        -RunId $Run.state.runId

    Assert-Equal -Name 'IMPLEMENT routes to Luna' -Expected 'IMPLEMENT' -Actual $ImplementDecision.stage
    Assert-Equal -Name 'IMPLEMENT responsible party is Luna' -Expected 'luna' -Actual $ImplementDecision.responsibleParty
    Assert-Equal -Name 'Active implementation can continue' -Expected $true -Actual ([bool]$ImplementDecision.canContinue)

    Complete-TriTierRunImplementation `
        -ProjectPath $TestRoot `
        -RunId $Run.state.runId `
        -ImplementedBy 'luna-worker' `
        -Summary 'Implementation completed.' `
        -EventId 'orch-implementation' |
        Out-Null

    $ReviewDecision = Get-TriTierRunOrchestrationDecision `
        -ProjectPath $TestRoot `
        -RunId $Run.state.runId

    Assert-Equal -Name 'REVIEW routes to Sol' -Expected 'REVIEW' -Actual $ReviewDecision.stage
    Assert-Equal -Name 'REVIEW responsible party is Sol' -Expected 'sol' -Actual $ReviewDecision.responsibleParty

    Submit-TriTierRunTaskReview `
        -ProjectPath $TestRoot `
        -RunId $Run.state.runId `
        -Reviewer 'sol-adjudicator' `
        -Outcome 'FAIL' `
        -Summary 'Task review failed.' `
        -EventId 'orch-review-fail' |
        Out-Null

    $FailedReviewDecision = Get-TriTierRunOrchestrationDecision `
        -ProjectPath $TestRoot `
        -RunId $Run.state.runId

    Assert-Equal -Name 'Failed REVIEW stays REVIEW' -Expected 'REVIEW' -Actual $FailedReviewDecision.stage
    Assert-Equal -Name 'Failed REVIEW routes to Terra' -Expected 'terra' -Actual $FailedReviewDecision.responsibleParty
    Assert-Equal -Name 'Failed REVIEW remains actionable' -Expected $true -Actual ([bool]$FailedReviewDecision.canContinue)

    $BlockedRun = New-TriTierRun `
        -ProjectPath $TestRoot `
        -RunId 'orchestration-blocked' `
        -Title 'Blocked orchestration test' `
        -CurrentTask 'TASK-BLOCKED' `
        -NextAction 'Luna must implement TASK-BLOCKED.'

    Initialize-TriTierRunTaskFlow `
        -ProjectPath $TestRoot `
        -RunId $BlockedRun.state.runId `
        -InitializedBy 'terra-manager' `
        -EventId 'blocked-init' |
        Out-Null

    $Finding = New-TriTierFinding `
        -Severity 'MEDIUM' `
        -Title 'Blocking task finding' `
        -Description 'This finding blocks task continuation.' `
        -Reviewer 'sol-adjudicator' `
        -TaskId 'TASK-BLOCKED'

    $Gate = Test-TriTierFindingGate -Findings @($Finding)

    Set-TriTierRunFindingState `
        -ProjectPath $TestRoot `
        -RunId $BlockedRun.state.runId `
        -Findings @($Finding) `
        -FindingGate $Gate |
        Out-Null

    $BlockedDecision = Get-TriTierRunOrchestrationDecision `
        -ProjectPath $TestRoot `
        -RunId $BlockedRun.state.runId

    Assert-Equal -Name 'Medium finding blocks TASK scope' -Expected 'TASK' -Actual $BlockedDecision.blockedScope
    Assert-Equal -Name 'Blocked task routes coordination to Terra' -Expected 'terra' -Actual $BlockedDecision.responsibleParty
    Assert-Equal -Name 'Blocked task cannot continue' -Expected $false -Actual ([bool]$BlockedDecision.canContinue)
    Assert-Equal -Name 'Blocked task exposes priority finding' -Expected $Finding.findingId -Actual $BlockedDecision.findingId

    $RepairState = Get-TriTierRunState `
        -ProjectPath $TestRoot `
        -RunId $BlockedRun.state.runId

    $ProjectedRepairState = Copy-Object -InputObject $RepairState
    $ProjectedRepairState.taskFlow.stage = 'REPAIR'
    $ProjectedRepairState.taskFlow.responsibleParty = 'luna'
    $ProjectedRepairState.taskFlow.activeRepairFindingId = $Finding.findingId
    $ProjectedRepairState.taskFlow.nextAction = [string]$Gate.nextAction
    $ProjectedRepairState.nextAction = [string]$Gate.nextAction

    $RepairDecision = Get-TriTierOrchestrationDecision `
        -RunState $ProjectedRepairState

    Assert-Equal -Name 'REPAIR remains actionable despite task block' -Expected 'REPAIR' -Actual $RepairDecision.stage
    Assert-Equal -Name 'REPAIR routes to Luna' -Expected 'luna' -Actual $RepairDecision.responsibleParty
    Assert-Equal -Name 'REPAIR can continue remediation' -Expected $true -Actual ([bool]$RepairDecision.canContinue)

    $OwnerState = Copy-Object -InputObject $RepairState
    $OwnerState.status = 'BLOCKED_OWNER_DECISION'
    $OwnerState.nextAction = 'Owner must approve continuation.'

    $OwnerDecision = Get-TriTierOrchestrationDecision `
        -RunState $OwnerState

    Assert-Equal -Name 'Owner gate routes to owner' -Expected 'OWNER_DECISION' -Actual $OwnerDecision.stage
    Assert-Equal -Name 'Owner gate requires owner' -Expected $true -Actual ([bool]$OwnerDecision.ownerRequired)
    Assert-Equal -Name 'Owner gate cannot continue' -Expected $false -Actual ([bool]$OwnerDecision.canContinue)

    $ExternalState = Copy-Object -InputObject $RepairState
    $ExternalState.status = 'BLOCKED_EXTERNAL_DEPENDENCY'
    $ExternalState.nextAction = 'Terra must wait for an external dependency.'

    $ExternalDecision = Get-TriTierOrchestrationDecision `
        -RunState $ExternalState

    Assert-Equal -Name 'External dependency selects WAIT_EXTERNAL' -Expected 'WAIT_EXTERNAL' -Actual $ExternalDecision.stage
    Assert-Equal -Name 'External dependency routes to Terra' -Expected 'terra' -Actual $ExternalDecision.responsibleParty
    Assert-Equal -Name 'External dependency cannot continue' -Expected $false -Actual ([bool]$ExternalDecision.canContinue)

    $TerminalState = Copy-Object -InputObject $RepairState
    $TerminalState.status = 'ABORTED_FOR_SAFETY'
    $TerminalState.nextAction = 'No further action.'

    $TerminalDecision = Get-TriTierOrchestrationDecision `
        -RunState $TerminalState

    Assert-Equal -Name 'Safety abort selects STOP' -Expected 'STOP' -Actual $TerminalDecision.stage
    Assert-Equal -Name 'Safety abort blocks run' -Expected 'RUN' -Actual $TerminalDecision.blockedScope
    Assert-Equal -Name 'Safety abort cannot continue' -Expected $false -Actual ([bool]$TerminalDecision.canContinue)

    $PhaseState = Copy-Object -InputObject $RepairState

    $PhaseState |
        Add-Member `
            -NotePropertyName phaseGate `
            -NotePropertyValue (
                [PSCustomObject][ordered]@{
                    phaseId = 'PHASE-READY'
                    status = 'READY_FOR_REVIEW'
                    nextAction = 'Sol must independently review PHASE-READY.'
                }
            ) `
            -Force

    $PhaseState.nextAction = 'Sol must independently review PHASE-READY.'

    $PhaseDecision = Get-TriTierOrchestrationDecision `
        -RunState $PhaseState

    Assert-Equal -Name 'Ready phase selects PHASE_REVIEW' -Expected 'PHASE_REVIEW' -Actual $PhaseDecision.stage
    Assert-Equal -Name 'Ready phase routes to Sol' -Expected 'sol' -Actual $PhaseDecision.responsibleParty
    Assert-Equal -Name 'Ready phase can continue to review' -Expected $true -Actual ([bool]$PhaseDecision.canContinue)

    Write-Host 'Orchestration decision tests passed.' -ForegroundColor Green
}
finally {
    if (Test-Path $TestRoot) {
        Remove-Item -LiteralPath $TestRoot -Recurse -Force
    }
}
