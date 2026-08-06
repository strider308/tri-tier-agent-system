$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = Split-Path $PSScriptRoot -Parent
$ModulePath = Join-Path $RepoRoot "src\TriTier\Findings.psm1"

Import-Module $ModulePath -Force

$Failures = @()

function Assert-FindingTest {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [bool]$Condition
    )

    [PSCustomObject]@{
        Test   = $Name
        Status = if ($Condition) { "PASS" } else { "FAIL" }
    } | Format-Table -AutoSize

    if (-not $Condition) {
        $script:Failures += $Name
    }
}

$MediumFinding = New-TriTierFinding `
    -Severity MEDIUM `
    -Title "Missing authorization test" `
    -Description "The modified authorization path lacks coverage." `
    -Reviewer "sol" `
    -TaskId "TASK-001"

$MediumGate = Test-TriTierFindingGate `
    -Findings @($MediumFinding)

Assert-FindingTest `
    -Name "Medium finding blocks task" `
    -Condition $MediumGate.taskBlocked

Assert-FindingTest `
    -Name "Medium finding does not block phase" `
    -Condition (-not $MediumGate.phaseBlocked)

Assert-FindingTest `
    -Name "Open medium finding requires repair" `
    -Condition $MediumGate.requiresRepair

$HighFinding = New-TriTierFinding `
    -Severity HIGH `
    -Title "Cross-tenant access possible" `
    -Description "Tenant isolation can be bypassed." `
    -Reviewer "sol" `
    -TaskId "TASK-002"

$HighGate = Test-TriTierFindingGate `
    -Findings @($HighFinding)

Assert-FindingTest `
    -Name "High finding blocks phase" `
    -Condition $HighGate.phaseBlocked

$CriticalFinding = New-TriTierFinding `
    -Severity CRITICAL `
    -Title "Destructive production path" `
    -Description "The operation can irreversibly destroy production data." `
    -Reviewer "sol" `
    -TaskId "TASK-003"

$CriticalGate = Test-TriTierFindingGate `
    -Findings @($CriticalFinding)

Assert-FindingTest `
    -Name "Critical finding blocks run" `
    -Condition $CriticalGate.runBlocked

$CriticalDeferralRejected = $false

try {
    Set-TriTierFindingDeferral `
        -Finding $CriticalFinding `
        -Reason "Accept temporarily" `
        -OwnerApprovalRecord "OWNER-001" `
        -OwnerApproved |
        Out-Null
}
catch {
    $CriticalDeferralRejected = $true
}

Assert-FindingTest `
    -Name "Critical finding cannot be deferred" `
    -Condition $CriticalDeferralRejected

$LowFinding = New-TriTierFinding `
    -Severity LOW `
    -Title "Minor naming inconsistency" `
    -Description "A local name differs from the established convention." `
    -Reviewer "terra"

$DeferredLow = Set-TriTierFindingDeferral `
    -Finding $LowFinding `
    -Reason "Defer until naming cleanup phase." `
    -OwnerApprovalRecord "OWNER-002" `
    -OwnerApproved

Assert-FindingTest `
    -Name "Owner can defer low finding" `
    -Condition ($DeferredLow.status -eq "DEFERRED")

$RepairedMedium = Repair-TriTierFinding `
    -Finding $MediumFinding `
    -RepairedBy "luna" `
    -RepairSummary "Added authorization regression coverage." `
    -EvidenceIds @("EVIDENCE-001")

Assert-FindingTest `
    -Name "Medium repair requires fresh review" `
    -Condition (
        $RepairedMedium.status -eq
        "REPAIRED_PENDING_REVIEW"
    )

$PendingGate = Test-TriTierFindingGate `
    -Findings @($RepairedMedium)

Assert-FindingTest `
    -Name "Pending fresh review blocks task" `
    -Condition $PendingGate.taskBlocked

Assert-FindingTest `
    -Name "Pending review produces exact next action" `
    -Condition (
        $PendingGate.nextAction -like
        "Assign a fresh independent review*"
    )

$SameActorRejected = $false

try {
    Submit-TriTierFindingFreshReview `
        -Finding $RepairedMedium `
        -Reviewer "luna" `
        -Outcome PASS `
        -Summary "Self-review passed." |
        Out-Null
}
catch {
    $SameActorRejected = $true
}

Assert-FindingTest `
    -Name "Repair actor cannot perform fresh review" `
    -Condition $SameActorRejected

$ResolvedMedium = Submit-TriTierFindingFreshReview `
    -Finding $RepairedMedium `
    -Reviewer "sol" `
    -Outcome PASS `
    -Summary "Authorization regression independently reproduced." `
    -EvidenceIds @("EVIDENCE-002")

Assert-FindingTest `
    -Name "Independent fresh review resolves finding" `
    -Condition ($ResolvedMedium.status -eq "RESOLVED")

$ResolvedGate = Test-TriTierFindingGate `
    -Findings @($ResolvedMedium)

Assert-FindingTest `
    -Name "Resolved finding clears task gate" `
    -Condition $ResolvedGate.passed

$FailedReviewFinding = New-TriTierFinding `
    -Severity MEDIUM `
    -Title "Incomplete validation" `
    -Description "The validation does not cover the failing path." `
    -Reviewer "terra"

$FailedReviewFinding = Repair-TriTierFinding `
    -Finding $FailedReviewFinding `
    -RepairedBy "luna" `
    -RepairSummary "Expanded validation."

$FailedReviewFinding = Submit-TriTierFindingFreshReview `
    -Finding $FailedReviewFinding `
    -Reviewer "sol" `
    -Outcome FAIL `
    -Summary "The original failure remains reproducible."

Assert-FindingTest `
    -Name "Failed fresh review reopens finding" `
    -Condition ($FailedReviewFinding.status -eq "OPEN")

Assert-FindingTest `
    -Name "Failed review increments cycle" `
    -Condition ($FailedReviewFinding.reviewCycle -eq 1)

if ($Failures.Count -gt 0) {
    throw "Finding tests failed: $($Failures -join ', ')"
}

Write-Host ""
Write-Host "Finding-model tests passed." -ForegroundColor Green
