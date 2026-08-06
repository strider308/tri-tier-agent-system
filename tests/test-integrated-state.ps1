$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot = Split-Path $PSScriptRoot -Parent
$StatePath = Join-Path $RepoRoot 'src\TriTier\State.psm1'
$TaskFlowPath = Join-Path $RepoRoot 'src\TriTier\TaskFlow.psm1'
$FindingsPath = Join-Path $RepoRoot 'src\TriTier\Findings.psm1'

Import-Module $FindingsPath -Force
Import-Module $TaskFlowPath -Force
Import-Module $StatePath -Force

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

    Assert-Equal -Name $Name -Expected $true -Actual $Thrown
}

function Copy-Object {
    param(
        [Parameter(Mandatory)]
        [object]$InputObject
    )

    $InputObject |
        ConvertTo-Json -Depth 50 |
        ConvertFrom-Json -Depth 50
}

$TestRoot = Join-Path (
    [System.IO.Path]::GetTempPath()
) (
    'tri-tier-integrated-state-' + [guid]::NewGuid().ToString('N')
)

try {
    New-Item -ItemType Directory -Path $TestRoot -Force | Out-Null

    $Run = New-TriTierRun `
        -ProjectPath $TestRoot `
        -RunId 'integrated-state-test' `
        -Title 'Integrated state test' `
        -CurrentTask 'TASK-INTEGRATED' `
        -NextAction 'Luna must implement TASK-INTEGRATED.'

    $Initialized = Initialize-TriTierRunTaskFlow `
        -ProjectPath $TestRoot `
        -RunId $Run.state.runId `
        -EventId 'evt-integrated-init'

    $Finding = New-TriTierFinding `
        -Severity 'MEDIUM' `
        -Title 'Task review defect' `
        -Description 'The failed task review requires repair.' `
        -Reviewer 'sol-adjudicator' `
        -TaskId 'TASK-INTEGRATED'

    $Findings = @($Finding)
    $Gate = Test-TriTierFindingGate -Findings $Findings
    $RepairFlow = Copy-Object -InputObject $Initialized.flow

    $RepairFlow.stage = 'REPAIR'
    $RepairFlow.previousStage = 'REVIEW'
    $RepairFlow.responsibleParty = 'luna'
    $RepairFlow.mayAdvance = $false
    $RepairFlow.reviewOutcome = 'FAIL'
    $RepairFlow.activeRepairFindingId = $Finding.findingId
    $RepairFlow.lastRepairFindingId = ''
    $RepairFlow.repairResumeStage = 'REVIEW'
    $RepairFlow.repairActor = ''
    $RepairFlow.repairReviewActor = ''
    $RepairFlow.repairReviewOutcome = 'NOT_STARTED'
    $RepairFlow.adjudicationDecision = ''
    $RepairFlow.nextAction = $Gate.nextAction

    $RepairState = Set-TriTierRunIntegratedState `
        -ProjectPath $TestRoot `
        -RunId $Run.state.runId `
        -Findings $Findings `
        -FindingGate $Gate `
        -TaskFlowState $RepairFlow

    Assert-Equal -Name 'Integrated state persists REPAIR stage' -Expected 'REPAIR' -Actual $RepairState.taskFlow.stage
    Assert-Equal -Name 'Integrated state persists linked finding' -Expected $Finding.findingId -Actual $RepairState.taskFlow.activeRepairFindingId
    Assert-Equal -Name 'Integrated state persists unresolved finding' -Expected $Finding.findingId -Actual @($RepairState.unresolvedFindings)[0]
    Assert-Equal -Name 'Integrated state uses task-flow next action' -Expected $RepairFlow.nextAction -Actual $RepairState.nextAction

    Assert-Throws -Name 'Base task-flow setter rejects REPAIR stage' -Action {
        Set-TriTierRunTaskFlowState `
            -ProjectPath $TestRoot `
            -RunId $Run.state.runId `
            -TaskFlowState $RepairFlow |
            Out-Null
    }

    $MissingLinkFlow = Copy-Object -InputObject $RepairFlow
    $MissingLinkFlow.activeRepairFindingId = 'missing-finding'

    Assert-Throws -Name 'REPAIR requires linked active finding' -Action {
        Set-TriTierRunIntegratedState `
            -ProjectPath $TestRoot `
            -RunId $Run.state.runId `
            -Findings $Findings `
            -FindingGate $Gate `
            -TaskFlowState $MissingLinkFlow |
            Out-Null
    }

    Assert-Throws -Name 'Integrated state rejects duplicate finding IDs' -Action {
        Set-TriTierRunIntegratedState `
            -ProjectPath $TestRoot `
            -RunId $Run.state.runId `
            -Findings @($Finding, $Finding) `
            -FindingGate $Gate `
            -TaskFlowState $RepairFlow |
            Out-Null
    }

    $RepairedFinding = Repair-TriTierFinding `
        -Finding $Finding `
        -RepairedBy 'luna-worker' `
        -RepairSummary 'Applied bounded repair.' `
        -EvidenceIds @('E-REPAIR-01')

    $FreshFindings = @($RepairedFinding)
    $FreshGate = Test-TriTierFindingGate -Findings $FreshFindings
    $FreshFlow = Copy-Object -InputObject $RepairFlow

    $FreshFlow.stage = 'FRESH_REVIEW'
    $FreshFlow.previousStage = 'REPAIR'
    $FreshFlow.responsibleParty = 'sol'
    $FreshFlow.repairActor = 'luna-worker'
    $FreshFlow.repairReviewOutcome = 'PENDING'
    $FreshFlow.nextAction = $FreshGate.nextAction

    $FreshState = Set-TriTierRunIntegratedState `
        -ProjectPath $TestRoot `
        -RunId $Run.state.runId `
        -Findings $FreshFindings `
        -FindingGate $FreshGate `
        -TaskFlowState $FreshFlow

    Assert-Equal -Name 'Integrated state persists FRESH_REVIEW stage' -Expected 'FRESH_REVIEW' -Actual $FreshState.taskFlow.stage
    Assert-Equal -Name 'FRESH_REVIEW persists pending finding' -Expected 'REPAIRED_PENDING_REVIEW' -Actual $FreshState.findings[0].status

    $ResolvedFinding = Submit-TriTierFindingFreshReview `
        -Finding $RepairedFinding `
        -Reviewer 'sol-adjudicator' `
        -Outcome 'PASS' `
        -Summary 'Fresh repair review passed.' `
        -EvidenceIds @('E-FRESH-01')

    $ResolvedFindings = @($ResolvedFinding)
    $ResolvedGate = Test-TriTierFindingGate -Findings $ResolvedFindings
    $ReviewFlow = Copy-Object -InputObject $FreshFlow

    $ReviewFlow.stage = 'REVIEW'
    $ReviewFlow.previousStage = 'FRESH_REVIEW'
    $ReviewFlow.responsibleParty = 'sol'
    $ReviewFlow.reviewOutcome = 'PENDING'
    $ReviewFlow.activeRepairFindingId = ''
    $ReviewFlow.lastRepairFindingId = $ResolvedFinding.findingId
    $ReviewFlow.repairReviewActor = 'sol-adjudicator'
    $ReviewFlow.repairReviewOutcome = 'PASSED'
    $ReviewFlow.nextAction = (
        'Sol must perform the final independent task review after repair.'
    )

    $ReviewState = Set-TriTierRunIntegratedState `
        -ProjectPath $TestRoot `
        -RunId $Run.state.runId `
        -Findings $ResolvedFindings `
        -FindingGate $ResolvedGate `
        -TaskFlowState $ReviewFlow

    Assert-Equal -Name 'Resolved repair resumes REVIEW stage' -Expected 'REVIEW' -Actual $ReviewState.taskFlow.stage
    Assert-Equal -Name 'Resolved repair clears active link' -Expected '' -Actual $ReviewState.taskFlow.activeRepairFindingId
    Assert-Equal -Name 'Resolved repair preserves last finding' -Expected $ResolvedFinding.findingId -Actual $ReviewState.taskFlow.lastRepairFindingId
    Assert-Equal -Name 'Resolved repair clears unresolved IDs' -Expected 0 -Actual @($ReviewState.unresolvedFindings).Count

    $NextActionPath = Join-Path `
        $ReviewState.projectPath `
        (
            '.tri-tier\runs\' +
            $ReviewState.runId +
            '\state\next-action.txt'
        )

    $StoredNextAction = (Get-Content $NextActionPath -Raw).Trim()

    Assert-Equal -Name 'Integrated state synchronizes exact next-action file' -Expected $ReviewState.nextAction -Actual $StoredNextAction

    $Validation = Test-TriTierRunState `
        -ProjectPath $TestRoot `
        -RunId $Run.state.runId

    Assert-Equal -Name 'Integrated run state remains valid' -Expected $true -Actual ([bool]$Validation.valid)

    Write-Host 'Integrated-state tests passed.' -ForegroundColor Green
}
finally {
    if (Test-Path $TestRoot) {
        Remove-Item -LiteralPath $TestRoot -Recurse -Force
    }
}
