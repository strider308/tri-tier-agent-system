$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot = Split-Path $PSScriptRoot -Parent
$StatePath = Join-Path $RepoRoot 'src\TriTier\State.psm1'
$LifecyclePath = Join-Path $RepoRoot 'src\TriTier\FindingLifecycle.psm1'

Import-Module $LifecyclePath -Force
Import-Module $StatePath -Force

if ($null -eq (Get-Command New-TriTierRun -ErrorAction SilentlyContinue)) {
    throw 'State command import failed: New-TriTierRun is unavailable.'
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

$TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    'tri-tier-finding-lifecycle-' + [guid]::NewGuid().ToString('N')
)

try {
    New-Item -ItemType Directory -Path $TestRoot -Force | Out-Null

    $RunArguments = @{
        ProjectPath = $TestRoot
        RunId = 'finding-lifecycle-test'
        Title = 'Persisted finding lifecycle test'
        CurrentTask = 'TASK-01'
        NextAction = 'Implement the bounded task.'
    }

    $Run = New-TriTierRun @RunArguments

    $CreateArguments = @{
        ProjectPath = $TestRoot
        RunId = $Run.state.runId
        Severity = 'MEDIUM'
        Title = 'Repair required'
        Description = 'The implementation requires a targeted repair.'
        Reviewer = 'sol-reviewer'
        TaskId = 'TASK-01'
        EvidenceIds = @('evidence-create')
    }

    $Created = Add-TriTierRunFinding @CreateArguments
    $FindingId = $Created.finding.findingId

    Assert-Equal -Name 'Create persists OPEN finding' -Expected 'OPEN' -Actual $Created.finding.status
    Assert-Equal -Name 'Create blocks task' -Expected $true -Actual ([bool]$Created.gate.taskBlocked)
    Assert-Equal -Name 'Create persists repair next action' -Expected $Created.gate.nextAction -Actual $Created.state.nextAction

    $RepairArguments = @{
        ProjectPath = $TestRoot
        RunId = $Run.state.runId
        FindingId = $FindingId
        RepairedBy = 'luna-worker'
        RepairSummary = 'Applied the targeted repair.'
        EvidenceIds = @('evidence-repair-1')
    }

    $Repaired = Repair-TriTierRunFinding @RepairArguments

    Assert-Equal -Name 'Repair enters pending review' -Expected 'REPAIRED_PENDING_REVIEW' -Actual $Repaired.finding.status
    Assert-Equal -Name 'Repair requests fresh review' -Expected $true -Actual ([bool]$Repaired.gate.requiresFreshReview)
    Assert-Equal -Name 'Repair persists review next action' -Expected $Repaired.gate.nextAction -Actual $Repaired.state.nextAction

    Assert-Throws -Name 'Repair actor cannot review persisted finding' -Action {
        $SameActorReview = @{
            ProjectPath = $TestRoot
            RunId = $Run.state.runId
            FindingId = $FindingId
            Reviewer = 'luna-worker'
            Outcome = 'PASS'
            Summary = 'Invalid same-actor review.'
        }

        Submit-TriTierRunFindingFreshReview @SameActorReview | Out-Null
    }

    $PendingAfterRejectedReview = Get-TriTierRunFinding -ProjectPath $TestRoot -RunId $Run.state.runId -FindingId $FindingId
    Assert-Equal -Name 'Rejected review leaves pending state' -Expected 'REPAIRED_PENDING_REVIEW' -Actual $PendingAfterRejectedReview.status

    $FailReviewArguments = @{
        ProjectPath = $TestRoot
        RunId = $Run.state.runId
        FindingId = $FindingId
        Reviewer = 'sol-reviewer'
        Outcome = 'FAIL'
        Summary = 'Repair did not satisfy the finding.'
        EvidenceIds = @('evidence-review-fail')
    }

    $FailedReview = Submit-TriTierRunFindingFreshReview @FailReviewArguments

    Assert-Equal -Name 'Failed review reopens persisted finding' -Expected 'OPEN' -Actual $FailedReview.finding.status
    Assert-Equal -Name 'Failed review increments cycle' -Expected 1 -Actual ([int]$FailedReview.finding.reviewCycle)
    Assert-Equal -Name 'Failed review restores repair next action' -Expected $FailedReview.gate.nextAction -Actual $FailedReview.state.nextAction

    $RepairArguments.RepairSummary = 'Applied the corrected repair.'
    $RepairArguments.EvidenceIds = @('evidence-repair-2')
    $SecondRepair = Repair-TriTierRunFinding @RepairArguments

    $PassReviewArguments = @{
        ProjectPath = $TestRoot
        RunId = $Run.state.runId
        FindingId = $FindingId
        Reviewer = 'terra-reviewer'
        Outcome = 'PASS'
        Summary = 'Independent review confirms the repair.'
        EvidenceIds = @('evidence-review-pass')
    }

    $PassedReview = Submit-TriTierRunFindingFreshReview @PassReviewArguments

    Assert-Equal -Name 'Passed review resolves persisted finding' -Expected 'RESOLVED' -Actual $PassedReview.finding.status
    Assert-Equal -Name 'Resolved finding clears unresolved IDs' -Expected 0 -Actual @($PassedReview.state.unresolvedFindings).Count
    Assert-Equal -Name 'Resolved finding clears task gate' -Expected $false -Actual ([bool]$PassedReview.gate.taskBlocked)
    Assert-Equal -Name 'Resolved finding advances next action' -Expected 'Proceed to the next task or phase gate.' -Actual $PassedReview.state.nextAction

    $LowFindingArguments = @{
        ProjectPath = $TestRoot
        RunId = $Run.state.runId
        Severity = 'LOW'
        Title = 'Owner-approved follow-up'
        Description = 'This low-severity item may be deferred.'
        Reviewer = 'sol-reviewer'
        TaskId = 'TASK-01'
    }

    $LowFinding = Add-TriTierRunFinding @LowFindingArguments

    $DeferralArguments = @{
        ProjectPath = $TestRoot
        RunId = $Run.state.runId
        FindingId = $LowFinding.finding.findingId
        Reason = 'Accepted for a later maintenance window.'
        OwnerApprovalRecord = 'owner-approval-test-001'
        OwnerApproved = $true
    }

    $Deferred = Set-TriTierRunFindingDeferral @DeferralArguments

    Assert-Equal -Name 'Owner deferral persists DEFERRED state' -Expected 'DEFERRED' -Actual $Deferred.finding.status
    Assert-Equal -Name 'Deferred finding clears unresolved IDs' -Expected 0 -Actual @($Deferred.state.unresolvedFindings).Count
    Assert-Equal -Name 'Lifecycle retains complete finding history' -Expected 2 -Actual @($Deferred.state.findings).Count

    $NextActionPath = Join-Path $Deferred.state.projectPath (
        '.tri-tier\runs\' + $Run.state.runId + '\state\next-action.txt'
    )

    $StoredNextAction = (Get-Content $NextActionPath -Raw).Trim()
    Assert-Equal -Name 'Lifecycle synchronizes exact next-action file' -Expected $Deferred.state.nextAction -Actual $StoredNextAction

    $Validation = Test-TriTierRunState -ProjectPath $TestRoot -RunId $Run.state.runId
    Assert-Equal -Name 'Lifecycle run state remains valid' -Expected $true -Actual ([bool]$Validation.valid)

    Write-Host 'Finding-lifecycle tests passed.' -ForegroundColor Green
}
finally {
    if (Test-Path $TestRoot) {
        Remove-Item -LiteralPath $TestRoot -Recurse -Force
    }
}
