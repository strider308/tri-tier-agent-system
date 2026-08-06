$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot = Split-Path $PSScriptRoot -Parent
$StatePath = Join-Path $RepoRoot 'src\TriTier\State.psm1'
$TaskFlowPath = Join-Path $RepoRoot 'src\TriTier\TaskFlow.psm1'
$RepairCyclePath = Join-Path $RepoRoot 'src\TriTier\RepairCycle.psm1'

Import-Module $StatePath -Force
Import-Module $TaskFlowPath -Force
Import-Module $RepairCyclePath -Force

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

function New-FailedTaskReviewRun {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$RunId
    )

    $Run = New-TriTierRun `
        -ProjectPath $ProjectPath `
        -RunId $RunId `
        -Title "Repair cycle $RunId" `
        -CurrentTask "TASK-$RunId" `
        -NextAction "Luna must implement TASK-$RunId."

    Initialize-TriTierRunTaskFlow `
        -ProjectPath $ProjectPath `
        -RunId $Run.state.runId `
        -EventId "evt-$RunId-init" |
        Out-Null

    Complete-TriTierRunImplementation `
        -ProjectPath $ProjectPath `
        -RunId $Run.state.runId `
        -ImplementedBy 'luna-worker' `
        -Summary 'Implemented the bounded task.' `
        -EvidenceIds @("E-$RunId-IMPLEMENT") `
        -EventId "evt-$RunId-implementation" |
        Out-Null

    Submit-TriTierRunTaskReview `
        -ProjectPath $ProjectPath `
        -RunId $Run.state.runId `
        -Reviewer 'sol-adjudicator' `
        -Outcome 'FAIL' `
        -Summary 'Independent task review found a blocking defect.' `
        -EvidenceIds @("E-$RunId-TASK-REVIEW") `
        -EventId "evt-$RunId-task-review-fail" |
        Out-Null

    Get-TriTierRunRepairCycle `
        -ProjectPath $ProjectPath `
        -RunId $Run.state.runId
}

function Move-To-Adjudication {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$RunId,

        [Parameter(Mandatory)]
        [string]$Prefix
    )

    Start-TriTierRunRepairCycle `
        -ProjectPath $ProjectPath `
        -RunId $RunId `
        -Severity 'MEDIUM' `
        -Title 'Blocking task-review defect' `
        -Description 'Repair is required before final task approval.' `
        -AuthorizedBy 'terra-manager' `
        -EventId "evt-$Prefix-open" |
        Out-Null

    Complete-TriTierRunRepair `
        -ProjectPath $ProjectPath `
        -RunId $RunId `
        -RepairedBy 'luna-worker' `
        -RepairSummary 'Applied the first bounded repair.' `
        -EvidenceIds @("E-$Prefix-REPAIR") `
        -EventId "evt-$Prefix-repair" |
        Out-Null

    Submit-TriTierRunRepairReview `
        -ProjectPath $ProjectPath `
        -RunId $RunId `
        -Reviewer 'sol-adjudicator' `
        -Outcome 'FAIL' `
        -Summary 'Fresh review rejected the repair.' `
        -EvidenceIds @("E-$Prefix-FRESH-FAIL") `
        -EventId "evt-$Prefix-fresh-fail"
}

$TestRoot = Join-Path (
    [System.IO.Path]::GetTempPath()
) (
    'tri-tier-repair-cycle-' + [guid]::NewGuid().ToString('N')
)

try {
    New-Item -ItemType Directory -Path $TestRoot -Force | Out-Null

    $PassRun = New-FailedTaskReviewRun `
        -ProjectPath $TestRoot `
        -RunId 'repair-pass'

    Assert-Equal -Name 'Failed review remains REVIEW before authorization' -Expected 'REVIEW' -Actual $PassRun.flow.stage
    Assert-Equal -Name 'Failed review is not yet linked to a finding' -Expected '' -Actual $PassRun.flow.activeRepairFindingId

    Assert-Throws -Name 'Luna cannot authorize repair cycle' -Action {
        Start-TriTierRunRepairCycle `
            -ProjectPath $TestRoot `
            -RunId $PassRun.state.runId `
            -Severity 'MEDIUM' `
            -Title 'Unauthorized repair' `
            -Description 'Luna must not authorize its own repair.' `
            -AuthorizedBy 'luna-worker' `
            -EventId 'evt-pass-unauthorized-open' |
            Out-Null
    }

    $Opened = Start-TriTierRunRepairCycle `
        -ProjectPath $TestRoot `
        -RunId $PassRun.state.runId `
        -Severity 'MEDIUM' `
        -Title 'Blocking task-review defect' `
        -Description 'Repair is required before final task approval.' `
        -AuthorizedBy 'terra-manager' `
        -EventId 'evt-pass-open'

    Assert-Equal -Name 'Terra authorization enters REPAIR' -Expected 'REPAIR' -Actual $Opened.flow.stage
    Assert-Equal -Name 'REPAIR belongs to Luna' -Expected 'luna' -Actual $Opened.flow.responsibleParty
    Assert-Equal -Name 'Repair finding is OPEN' -Expected 'OPEN' -Actual $Opened.finding.status
    Assert-Equal -Name 'Medium repair blocks task' -Expected $true -Actual ([bool]$Opened.gate.taskBlocked)
    Assert-Equal -Name 'Repair authorization blocks advancement' -Expected $false -Actual ([bool]$Opened.flow.mayAdvance)

    $OpenHistoryCount = @($Opened.flow.transitionHistory).Count

    $OpenedReplay = Start-TriTierRunRepairCycle `
        -ProjectPath $TestRoot `
        -RunId $PassRun.state.runId `
        -Severity 'MEDIUM' `
        -Title 'Ignored replay' `
        -Description 'Ignored replay.' `
        -AuthorizedBy 'terra-manager' `
        -EventId 'evt-pass-open'

    Assert-Equal -Name 'Repair authorization replay is idempotent' -Expected $true -Actual ([bool]$OpenedReplay.replayed)
    Assert-Equal -Name 'Authorization replay preserves history' -Expected $OpenHistoryCount -Actual @($OpenedReplay.flow.transitionHistory).Count

    Assert-Throws -Name 'Second repair cycle cannot open while active' -Action {
        Start-TriTierRunRepairCycle `
            -ProjectPath $TestRoot `
            -RunId $PassRun.state.runId `
            -Severity 'MEDIUM' `
            -Title 'Duplicate cycle' `
            -Description 'Duplicate repair cycle.' `
            -AuthorizedBy 'terra-manager' `
            -EventId 'evt-pass-open-duplicate' |
            Out-Null
    }

    Assert-Throws -Name 'Task cannot continue while repair is active' -Action {
        Submit-TriTierRunTaskReview `
            -ProjectPath $TestRoot `
            -RunId $PassRun.state.runId `
            -Reviewer 'sol-adjudicator' `
            -Outcome 'PASS' `
            -Summary 'Invalid approval during repair.' `
            -EventId 'evt-pass-invalid-task-review' |
            Out-Null
    }

    Assert-Throws -Name 'Sol cannot perform Luna repair' -Action {
        Complete-TriTierRunRepair `
            -ProjectPath $TestRoot `
            -RunId $PassRun.state.runId `
            -RepairedBy 'sol-adjudicator' `
            -RepairSummary 'Invalid Sol repair.' `
            -EventId 'evt-pass-invalid-repair' |
            Out-Null
    }

    $Repaired = Complete-TriTierRunRepair `
        -ProjectPath $TestRoot `
        -RunId $PassRun.state.runId `
        -RepairedBy 'luna-worker' `
        -RepairSummary 'Applied the bounded repair.' `
        -EvidenceIds @('E-PASS-REPAIR') `
        -EventId 'evt-pass-repair'

    Assert-Equal -Name 'Repair completion enters FRESH_REVIEW' -Expected 'FRESH_REVIEW' -Actual $Repaired.flow.stage
    Assert-Equal -Name 'FRESH_REVIEW belongs to Sol' -Expected 'sol' -Actual $Repaired.flow.responsibleParty
    Assert-Equal -Name 'Repair finding awaits fresh review' -Expected 'REPAIRED_PENDING_REVIEW' -Actual $Repaired.finding.status

    $RepairHistoryCount = @($Repaired.flow.transitionHistory).Count

    $RepairReplay = Complete-TriTierRunRepair `
        -ProjectPath $TestRoot `
        -RunId $PassRun.state.runId `
        -RepairedBy 'luna-worker' `
        -RepairSummary 'Ignored replay.' `
        -EventId 'evt-pass-repair'

    Assert-Equal -Name 'Repair completion replay is idempotent' -Expected $true -Actual ([bool]$RepairReplay.replayed)
    Assert-Equal -Name 'Repair replay preserves history' -Expected $RepairHistoryCount -Actual @($RepairReplay.flow.transitionHistory).Count

    $RestartedFreshReview = Get-TriTierRunRepairCycle `
        -ProjectPath $TestRoot `
        -RunId $PassRun.state.runId

    Assert-Equal -Name 'Restart preserves FRESH_REVIEW stage' -Expected 'FRESH_REVIEW' -Actual $RestartedFreshReview.flow.stage

    Assert-Throws -Name 'Repair actor cannot fresh-review repair' -Action {
        Submit-TriTierRunRepairReview `
            -ProjectPath $TestRoot `
            -RunId $PassRun.state.runId `
            -Reviewer 'luna-worker' `
            -Outcome 'PASS' `
            -Summary 'Invalid self-review.' `
            -EventId 'evt-pass-invalid-fresh-review' |
            Out-Null
    }

    $FreshPassed = Submit-TriTierRunRepairReview `
        -ProjectPath $TestRoot `
        -RunId $PassRun.state.runId `
        -Reviewer 'sol-adjudicator' `
        -Outcome 'PASS' `
        -Summary 'Fresh independent repair review passed.' `
        -EvidenceIds @('E-PASS-FRESH') `
        -EventId 'evt-pass-fresh-pass'

    Assert-Equal -Name 'Fresh-review PASS returns to REVIEW' -Expected 'REVIEW' -Actual $FreshPassed.flow.stage
    Assert-Equal -Name 'Fresh-review PASS resolves finding' -Expected 'RESOLVED' -Actual $FreshPassed.finding.status
    Assert-Equal -Name 'Fresh-review PASS clears active link' -Expected '' -Actual $FreshPassed.flow.activeRepairFindingId
    Assert-Equal -Name 'Fresh-review PASS retains last finding' -Expected $FreshPassed.finding.findingId -Actual $FreshPassed.flow.lastRepairFindingId
    Assert-Equal -Name 'Fresh-review PASS still blocks advancement' -Expected $false -Actual ([bool]$FreshPassed.flow.mayAdvance)

    $FinalReview = Submit-TriTierRunTaskReview `
        -ProjectPath $TestRoot `
        -RunId $PassRun.state.runId `
        -Reviewer 'sol-adjudicator' `
        -Outcome 'PASS' `
        -Summary 'Final independent task review passed after repair.' `
        -EvidenceIds @('E-PASS-FINAL') `
        -EventId 'evt-pass-final-review'

    Assert-Equal -Name 'Final task review reaches CONTINUE' -Expected 'CONTINUE' -Actual $FinalReview.flow.stage
    Assert-Equal -Name 'Final task review permits advancement' -Expected $true -Actual ([bool]$FinalReview.flow.mayAdvance)

    $FailRun = New-FailedTaskReviewRun `
        -ProjectPath $TestRoot `
        -RunId 'repair-fail'

    $Adjudication = Move-To-Adjudication `
        -ProjectPath $TestRoot `
        -RunId $FailRun.state.runId `
        -Prefix 'fail'

    Assert-Equal -Name 'Failed fresh review enters ADJUDICATE' -Expected 'ADJUDICATE' -Actual $Adjudication.flow.stage
    Assert-Equal -Name 'Failed fresh review reopens finding' -Expected 'OPEN' -Actual $Adjudication.finding.status
    Assert-Equal -Name 'Failed fresh review increments cycle' -Expected 1 -Actual ([int]$Adjudication.finding.reviewCycle)
    Assert-Equal -Name 'ADJUDICATE belongs to Sol' -Expected 'sol' -Actual $Adjudication.flow.responsibleParty

    Assert-Throws -Name 'Repair cannot restart before adjudication' -Action {
        Complete-TriTierRunRepair `
            -ProjectPath $TestRoot `
            -RunId $FailRun.state.runId `
            -RepairedBy 'luna-worker' `
            -RepairSummary 'Invalid direct retry.' `
            -EventId 'evt-fail-invalid-direct-repair' |
            Out-Null
    }

    $RepairAgain = Submit-TriTierRunAdjudication `
        -ProjectPath $TestRoot `
        -RunId $FailRun.state.runId `
        -Adjudicator 'sol-adjudicator' `
        -Decision 'REPAIR_AGAIN' `
        -Summary 'A second bounded repair is justified.' `
        -EvidenceIds @('E-FAIL-ADJUDICATION') `
        -EventId 'evt-fail-adjudicate-repair'

    Assert-Equal -Name 'REPAIR_AGAIN returns to REPAIR' -Expected 'REPAIR' -Actual $RepairAgain.flow.stage
    Assert-Equal -Name 'REPAIR_AGAIN assigns Luna' -Expected 'luna' -Actual $RepairAgain.flow.responsibleParty

    $AdjudicationHistoryCount = @($RepairAgain.flow.transitionHistory).Count

    $RepairAgainReplay = Submit-TriTierRunAdjudication `
        -ProjectPath $TestRoot `
        -RunId $FailRun.state.runId `
        -Adjudicator 'sol-adjudicator' `
        -Decision 'REPAIR_AGAIN' `
        -Summary 'Ignored replay.' `
        -EventId 'evt-fail-adjudicate-repair'

    Assert-Equal -Name 'Adjudication replay is idempotent' -Expected $true -Actual ([bool]$RepairAgainReplay.replayed)
    Assert-Equal -Name 'Adjudication replay preserves history' -Expected $AdjudicationHistoryCount -Actual @($RepairAgainReplay.flow.transitionHistory).Count

    Complete-TriTierRunRepair `
        -ProjectPath $TestRoot `
        -RunId $FailRun.state.runId `
        -RepairedBy 'luna-worker' `
        -RepairSummary 'Applied the adjudicated second repair.' `
        -EvidenceIds @('E-FAIL-REPAIR-2') `
        -EventId 'evt-fail-repair-two' |
        Out-Null

    $SecondFreshPassed = Submit-TriTierRunRepairReview `
        -ProjectPath $TestRoot `
        -RunId $FailRun.state.runId `
        -Reviewer 'sol-adjudicator' `
        -Outcome 'PASS' `
        -Summary 'Second fresh repair review passed.' `
        -EvidenceIds @('E-FAIL-FRESH-2') `
        -EventId 'evt-fail-fresh-two-pass'

    Assert-Equal -Name 'Second fresh review returns to REVIEW' -Expected 'REVIEW' -Actual $SecondFreshPassed.flow.stage
    Assert-Equal -Name 'Second fresh review records cycle two' -Expected 2 -Actual ([int]$SecondFreshPassed.finding.reviewCycle)

    $OwnerRun = New-FailedTaskReviewRun `
        -ProjectPath $TestRoot `
        -RunId 'repair-owner'

    Move-To-Adjudication `
        -ProjectPath $TestRoot `
        -RunId $OwnerRun.state.runId `
        -Prefix 'owner' |
        Out-Null

    $OwnerGate = Submit-TriTierRunAdjudication `
        -ProjectPath $TestRoot `
        -RunId $OwnerRun.state.runId `
        -Adjudicator 'sol-adjudicator' `
        -Decision 'OWNER_DECISION' `
        -Summary 'Owner judgment is required.' `
        -EventId 'evt-owner-adjudicate'

    Assert-Equal -Name 'Owner adjudication blocks run' -Expected 'BLOCKED_OWNER_DECISION' -Actual $OwnerGate.state.status
    Assert-Equal -Name 'Owner adjudication assigns owner' -Expected 'owner' -Actual $OwnerGate.flow.responsibleParty

    Assert-Throws -Name 'Owner-blocked run rejects mutation' -Action {
        Submit-TriTierRunAdjudication `
            -ProjectPath $TestRoot `
            -RunId $OwnerRun.state.runId `
            -Adjudicator 'sol-adjudicator' `
            -Decision 'REPAIR_AGAIN' `
            -Summary 'Invalid mutation after owner gate.' `
            -EventId 'evt-owner-invalid-mutation' |
            Out-Null
    }

    $AbortRun = New-FailedTaskReviewRun `
        -ProjectPath $TestRoot `
        -RunId 'repair-abort'

    Move-To-Adjudication `
        -ProjectPath $TestRoot `
        -RunId $AbortRun.state.runId `
        -Prefix 'abort' |
        Out-Null

    $Aborted = Submit-TriTierRunAdjudication `
        -ProjectPath $TestRoot `
        -RunId $AbortRun.state.runId `
        -Adjudicator 'sol-adjudicator' `
        -Decision 'ABORT_FOR_SAFETY' `
        -Summary 'Continuing would violate safety constraints.' `
        -EventId 'evt-abort-adjudicate'

    Assert-Equal -Name 'Safety adjudication aborts run' -Expected 'ABORTED_FOR_SAFETY' -Actual $Aborted.state.status

    Assert-Throws -Name 'Aborted run rejects repair mutation' -Action {
        Complete-TriTierRunRepair `
            -ProjectPath $TestRoot `
            -RunId $AbortRun.state.runId `
            -RepairedBy 'luna-worker' `
            -RepairSummary 'Invalid repair after abort.' `
            -EventId 'evt-abort-invalid-repair' |
            Out-Null
    }

    $Resume = Get-TriTierRunResumeData `
        -ProjectPath $TestRoot `
        -RunId $PassRun.state.runId

    $NextActionPath = Join-Path `
        $Resume.runDirectory `
        'state\next-action.txt'

    $StoredNextAction = (Get-Content $NextActionPath -Raw).Trim()

    Assert-Equal -Name 'Repair cycle synchronizes exact next-action file' -Expected $Resume.state.nextAction -Actual $StoredNextAction

    $Validation = Test-TriTierRunState `
        -ProjectPath $TestRoot `
        -RunId $PassRun.state.runId

    Assert-Equal -Name 'Repair-cycle run state remains valid' -Expected $true -Actual ([bool]$Validation.valid)

    Write-Host 'Repair-cycle tests passed.' -ForegroundColor Green
}
finally {
    if (Test-Path $TestRoot) {
        Remove-Item -LiteralPath $TestRoot -Recurse -Force
    }
}
