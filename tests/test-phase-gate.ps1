$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot = Split-Path $PSScriptRoot -Parent
$StatePath = Join-Path $RepoRoot 'src\TriTier\State.psm1'
$FindingsPath = Join-Path $RepoRoot 'src\TriTier\Findings.psm1'
$TaskFlowPath = Join-Path $RepoRoot 'src\TriTier\TaskFlow.psm1'
$PhaseGatePath = Join-Path $RepoRoot 'src\TriTier\PhaseGate.psm1'

Import-Module $StatePath -Force
Import-Module $FindingsPath -Force
Import-Module $TaskFlowPath -Force
Import-Module $PhaseGatePath -Force

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

function New-ReviewedRun {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$RunId,

        [Parameter(Mandatory)]
        [string]$Prefix
    )

    $Run = New-TriTierRun `
        -ProjectPath $ProjectPath `
        -RunId $RunId `
        -Title "Phase gate test $RunId" `
        -CurrentTask 'TASK-PHASE' `
        -NextAction 'Luna must implement TASK-PHASE.'

    Initialize-TriTierRunTaskFlow `
        -ProjectPath $ProjectPath `
        -RunId $Run.state.runId `
        -InitializedBy 'terra-manager' `
        -EventId "$Prefix-init" |
        Out-Null

    Complete-TriTierRunImplementation `
        -ProjectPath $ProjectPath `
        -RunId $Run.state.runId `
        -ImplementedBy 'luna-worker' `
        -Summary 'Phase implementation completed.' `
        -EvidenceIds @("$Prefix-implementation-evidence") `
        -EventId "$Prefix-implementation" |
        Out-Null

    Submit-TriTierRunTaskReview `
        -ProjectPath $ProjectPath `
        -RunId $Run.state.runId `
        -Reviewer 'sol-adjudicator' `
        -Outcome 'PASS' `
        -Summary 'Final task review passed.' `
        -EvidenceIds @("$Prefix-task-review-evidence") `
        -EventId "$Prefix-task-review" |
        Out-Null

    Get-TriTierRunState `
        -ProjectPath $ProjectPath `
        -RunId $Run.state.runId
}

$TestRoot = Join-Path (
    [System.IO.Path]::GetTempPath()
) (
    'tri-tier-phase-gate-' + [guid]::NewGuid().ToString('N')
)

try {
    New-Item -ItemType Directory -Path $TestRoot -Force | Out-Null

    $State = New-ReviewedRun `
        -ProjectPath $TestRoot `
        -RunId 'phase-r2' `
        -Prefix 'r2'

    $Started = Start-TriTierRunPhase `
        -ProjectPath $TestRoot `
        -RunId $State.runId `
        -PhaseId 'PHASE-R2' `
        -RiskClass 'R2' `
        -StartedBy 'terra-manager' `
        -EventId 'r2-phase-start'

    Assert-Equal -Name 'Phase start persists ACTIVE' -Expected 'ACTIVE' -Actual $Started.phase.status
    Assert-Equal -Name 'Phase start preserves R2 risk' -Expected 'R2' -Actual $Started.phase.riskClass
    Assert-Equal -Name 'Phase requirement is populated' -Expected $false -Actual ([string]::IsNullOrWhiteSpace([string]$Started.phase.requiredEvidenceLevel))

    $StartReplay = Start-TriTierRunPhase `
        -ProjectPath $TestRoot `
        -RunId $State.runId `
        -PhaseId 'PHASE-R2' `
        -RiskClass 'R2' `
        -StartedBy 'terra-manager' `
        -EventId 'r2-phase-start'

    Assert-Equal -Name 'Phase start replay is idempotent' -Expected $true -Actual ([bool]$StartReplay.replayed)

    $Insufficient = Submit-TriTierRunPhaseReady `
        -ProjectPath $TestRoot `
        -RunId $State.runId `
        -ObservedEvidenceLevel 'E2' `
        -EvidenceIds @('E-R2-LOW') `
        -SubmittedBy 'terra-manager' `
        -EventId 'r2-ready-low'

    Assert-Equal -Name 'Insufficient R2 evidence blocks phase' -Expected 'BLOCKED_BY_EVIDENCE' -Actual $Insufficient.phase.status
    Assert-Equal -Name 'Evidence block uses PHASE scope' -Expected 'PHASE' -Actual $Insufficient.decision.blockedScope
    Assert-Equal -Name 'Evidence block cannot continue' -Expected $false -Actual ([bool]$Insufficient.decision.canContinue)

    $Ready = Submit-TriTierRunPhaseReady `
        -ProjectPath $TestRoot `
        -RunId $State.runId `
        -ObservedEvidenceLevel 'E3' `
        -EvidenceIds @('E-R2-SUFFICIENT') `
        -SubmittedBy 'terra-manager' `
        -EventId 'r2-ready-pass'

    Assert-Equal -Name 'Sufficient R2 evidence reaches review' -Expected 'READY_FOR_REVIEW' -Actual $Ready.phase.status
    Assert-Equal -Name 'Ready phase routes to PHASE_REVIEW' -Expected 'PHASE_REVIEW' -Actual $Ready.decision.stage
    Assert-Equal -Name 'Ready phase assigns Sol' -Expected 'sol' -Actual $Ready.decision.responsibleParty

    $ReadyReplay = Submit-TriTierRunPhaseReady `
        -ProjectPath $TestRoot `
        -RunId $State.runId `
        -ObservedEvidenceLevel 'E3' `
        -EvidenceIds @('IGNORED') `
        -SubmittedBy 'terra-manager' `
        -EventId 'r2-ready-pass'

    Assert-Equal -Name 'Phase readiness replay is idempotent' -Expected $true -Actual ([bool]$ReadyReplay.replayed)

    Assert-Throws -Name 'Luna cannot review phase' -Action {
        Submit-TriTierRunPhaseReview `
            -ProjectPath $TestRoot `
            -RunId $State.runId `
            -Decision 'ACCEPT' `
            -Summary 'Invalid Luna review.' `
            -Reviewer 'luna-worker' `
            -EventId 'r2-invalid-review' |
            Out-Null
    }

    $Accepted = Submit-TriTierRunPhaseReview `
        -ProjectPath $TestRoot `
        -RunId $State.runId `
        -Decision 'ACCEPT' `
        -Summary 'R2 phase independently accepted.' `
        -EvidenceIds @('E-R2-REVIEW') `
        -Reviewer 'sol-adjudicator' `
        -EventId 'r2-accept'

    Assert-Equal -Name 'Phase review accepts phase' -Expected 'ACCEPTED' -Actual $Accepted.phase.status
    Assert-Equal -Name 'Accepted phase returns to CONTINUE' -Expected 'CONTINUE' -Actual $Accepted.decision.stage
    Assert-Equal -Name 'Accepted phase returns to Terra' -Expected 'terra' -Actual $Accepted.decision.responsibleParty

    $AcceptReplay = Submit-TriTierRunPhaseReview `
        -ProjectPath $TestRoot `
        -RunId $State.runId `
        -Decision 'ACCEPT' `
        -Summary 'Ignored duplicate review.' `
        -Reviewer 'sol-adjudicator' `
        -EventId 'r2-accept'

    Assert-Equal -Name 'Phase review replay is idempotent' -Expected $true -Actual ([bool]$AcceptReplay.replayed)

    $R3State = New-ReviewedRun `
        -ProjectPath $TestRoot `
        -RunId 'phase-r3' `
        -Prefix 'r3'

    Start-TriTierRunPhase `
        -ProjectPath $TestRoot `
        -RunId $R3State.runId `
        -PhaseId 'PHASE-R3' `
        -RiskClass 'R3' `
        -StartedBy 'terra-manager' `
        -EventId 'r3-phase-start' |
        Out-Null

    $R3NotIndependent = Submit-TriTierRunPhaseReady `
        -ProjectPath $TestRoot `
        -RunId $R3State.runId `
        -ObservedEvidenceLevel 'E4' `
        -EvidenceIds @('E-R3-NON-INDEPENDENT') `
        -SubmittedBy 'terra-manager' `
        -EventId 'r3-ready-non-independent'

    Assert-Equal -Name 'R3 non-independent evidence is blocked' -Expected 'BLOCKED_BY_EVIDENCE' -Actual $R3NotIndependent.phase.status

    $R3Ready = Submit-TriTierRunPhaseReady `
        -ProjectPath $TestRoot `
        -RunId $R3State.runId `
        -ObservedEvidenceLevel 'E4' `
        -EvidenceIds @('E-R3-INDEPENDENT') `
        -IndependentEvidence $true `
        -SubmittedBy 'terra-manager' `
        -EventId 'r3-ready-independent'

    Assert-Equal -Name 'R3 independent evidence is reviewable' -Expected 'READY_FOR_REVIEW' -Actual $R3Ready.phase.status

    $Rejected = Submit-TriTierRunPhaseReview `
        -ProjectPath $TestRoot `
        -RunId $R3State.runId `
        -Decision 'REJECT' `
        -Summary 'R3 phase requires bounded remediation.' `
        -Reviewer 'sol-adjudicator' `
        -EventId 'r3-reject'

    Assert-Equal -Name 'Rejected phase persists REJECTED' -Expected 'REJECTED' -Actual $Rejected.phase.status
    Assert-Equal -Name 'Rejected phase returns to PLAN' -Expected 'PLAN' -Actual $Rejected.decision.stage
    Assert-Equal -Name 'Rejected phase assigns Terra' -Expected 'terra' -Actual $Rejected.decision.responsibleParty

    $FindingState = New-ReviewedRun `
        -ProjectPath $TestRoot `
        -RunId 'phase-finding-block' `
        -Prefix 'finding'

    Start-TriTierRunPhase `
        -ProjectPath $TestRoot `
        -RunId $FindingState.runId `
        -PhaseId 'PHASE-FINDING' `
        -RiskClass 'R2' `
        -StartedBy 'terra-manager' `
        -EventId 'finding-phase-start' |
        Out-Null

    $HighFinding = New-TriTierFinding `
        -Severity 'HIGH' `
        -Title 'Phase-blocking finding' `
        -Description 'This finding blocks phase acceptance.' `
        -Reviewer 'sol-adjudicator' `
        -TaskId 'TASK-PHASE' `
        -PhaseId 'PHASE-FINDING'

    $HighGate = Test-TriTierFindingGate `
        -Findings @($HighFinding)

    Set-TriTierRunFindingState `
        -ProjectPath $TestRoot `
        -RunId $FindingState.runId `
        -Findings @($HighFinding) `
        -FindingGate $HighGate |
        Out-Null

    $FindingBlocked = Submit-TriTierRunPhaseReady `
        -ProjectPath $TestRoot `
        -RunId $FindingState.runId `
        -ObservedEvidenceLevel 'E3' `
        -EvidenceIds @('E-FINDING-PHASE') `
        -SubmittedBy 'terra-manager' `
        -EventId 'finding-ready'

    Assert-Equal -Name 'High finding blocks phase readiness' -Expected 'BLOCKED_BY_FINDINGS' -Actual $FindingBlocked.phase.status
    Assert-Equal -Name 'High finding uses PHASE scope' -Expected 'PHASE' -Actual $FindingBlocked.decision.blockedScope
    Assert-Equal -Name 'Finding-blocked phase cannot continue' -Expected $false -Actual ([bool]$FindingBlocked.decision.canContinue)

    $R4State = New-ReviewedRun `
        -ProjectPath $TestRoot `
        -RunId 'phase-r4' `
        -Prefix 'r4'

    Start-TriTierRunPhase `
        -ProjectPath $TestRoot `
        -RunId $R4State.runId `
        -PhaseId 'PHASE-R4' `
        -RiskClass 'R4' `
        -StartedBy 'terra-manager' `
        -EventId 'r4-phase-start' |
        Out-Null

    $R4OwnerGate = Submit-TriTierRunPhaseReady `
        -ProjectPath $TestRoot `
        -RunId $R4State.runId `
        -ObservedEvidenceLevel 'E5' `
        -EvidenceIds @('E-R4-INDEPENDENT') `
        -IndependentEvidence $true `
        -SubmittedBy 'terra-manager' `
        -EventId 'r4-ready-no-owner'

    Assert-Equal -Name 'R4 without owner approval is gated' -Expected 'OWNER_DECISION_REQUIRED' -Actual $R4OwnerGate.phase.status
    Assert-Equal -Name 'R4 owner gate blocks run status' -Expected 'BLOCKED_OWNER_DECISION' -Actual $R4OwnerGate.state.status
    Assert-Equal -Name 'R4 owner gate routes to owner' -Expected 'OWNER_DECISION' -Actual $R4OwnerGate.decision.stage

    $R4Ready = Submit-TriTierRunPhaseReady `
        -ProjectPath $TestRoot `
        -RunId $R4State.runId `
        -ObservedEvidenceLevel 'E5' `
        -EvidenceIds @('E-R4-INDEPENDENT') `
        -IndependentEvidence $true `
        -OwnerApprovalRecord 'owner-r4-approval-001' `
        -SubmittedBy 'terra-manager' `
        -EventId 'r4-ready-owner'

    Assert-Equal -Name 'R4 owner approval restores ACTIVE run' -Expected 'ACTIVE' -Actual $R4Ready.state.status
    Assert-Equal -Name 'R4 owner-approved phase is reviewable' -Expected 'READY_FOR_REVIEW' -Actual $R4Ready.phase.status

    $R4Accepted = Submit-TriTierRunPhaseReview `
        -ProjectPath $TestRoot `
        -RunId $R4State.runId `
        -Decision 'ACCEPT' `
        -Summary 'R4 phase accepted with independent evidence and owner approval.' `
        -EvidenceIds @('E-R4-REVIEW') `
        -Reviewer 'sol-adjudicator' `
        -EventId 'r4-accept'

    Assert-Equal -Name 'R4 phase can be accepted after all gates' -Expected 'ACCEPTED' -Actual $R4Accepted.phase.status

    $StoredState = Get-TriTierRunState `
        -ProjectPath $TestRoot `
        -RunId $R4State.runId

    $NextActionPath = Join-Path `
        $StoredState.projectPath `
        (
            '.tri-tier\runs\' +
            $StoredState.runId +
            '\state\next-action.txt'
        )

    $StoredNextAction = (Get-Content $NextActionPath -Raw).Trim()

    Assert-Equal -Name 'Phase gate synchronizes exact next-action file' -Expected $StoredState.nextAction -Actual $StoredNextAction

    $Validation = Test-TriTierRunState `
        -ProjectPath $TestRoot `
        -RunId $R4State.runId

    Assert-Equal -Name 'Phase-gate run state remains valid' -Expected $true -Actual ([bool]$Validation.valid)

    Write-Host 'Phase-gate tests passed.' -ForegroundColor Green
}
finally {
    if (Test-Path $TestRoot) {
        Remove-Item -LiteralPath $TestRoot -Recurse -Force
    }
}
