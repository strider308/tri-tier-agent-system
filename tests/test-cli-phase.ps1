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

    $Invocation.text.Trim() | ConvertFrom-Json -Depth 100
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

function New-CliReviewedRun {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$RunId,

        [Parameter(Mandatory)]
        [string]$Prefix
    )

    $Run = Invoke-CliJson -Arguments @(
        'run-init',
        '-ProjectPath', $ProjectPath,
        '-RunId', $RunId,
        '-Title', "CLI phase test $RunId",
        '-CurrentTask', 'TASK-PHASE-CLI',
        '-NextAction', 'Luna must implement TASK-PHASE-CLI.',
        '-Json'
    )

    Invoke-CliJson -Arguments @(
        'task-flow-init',
        '-ProjectPath', $ProjectPath,
        '-RunId', $Run.runId,
        '-Actor', 'terra-manager',
        '-EventId', "$Prefix-flow-init",
        '-Json'
    ) | Out-Null

    Invoke-CliJson -Arguments @(
        'implementation-complete',
        '-ProjectPath', $ProjectPath,
        '-RunId', $Run.runId,
        '-Actor', 'luna-worker',
        '-Summary', 'CLI phase implementation complete.',
        '-EvidenceIds', "$Prefix-implementation-evidence",
        '-EventId', "$Prefix-implementation",
        '-Json'
    ) | Out-Null

    Invoke-CliJson -Arguments @(
        'task-review',
        '-ProjectPath', $ProjectPath,
        '-RunId', $Run.runId,
        '-Actor', 'sol-adjudicator',
        '-Outcome', 'PASS',
        '-Summary', 'CLI final task review passed.',
        '-EvidenceIds', "$Prefix-task-review-evidence",
        '-EventId', "$Prefix-task-review",
        '-Json'
    ) | Out-Null

    $Run
}

$TestRoot = Join-Path (
    [System.IO.Path]::GetTempPath()
) (
    'tri-tier-cli-phase-' + [guid]::NewGuid().ToString('N')
)

try {
    New-Item -ItemType Directory -Path $TestRoot -Force | Out-Null

    $Run = New-CliReviewedRun `
        -ProjectPath $TestRoot `
        -RunId 'cli-phase-main' `
        -Prefix 'main'

    $Started = Invoke-CliJson -Arguments @(
        'phase-start',
        '-ProjectPath', $TestRoot,
        '-RunId', $Run.runId,
        '-PhaseId', 'PHASE-CLI-R2',
        '-PhaseRiskClass', 'R2',
        '-Actor', 'terra-manager',
        '-EventId', 'main-phase-start',
        '-Json'
    )

    Assert-Equal -Name 'phase-start returns ACTIVE' -Expected 'ACTIVE' -Actual $Started.phaseStatus
    Assert-Equal -Name 'phase-start returns R2' -Expected 'R2' -Actual $Started.riskClass

    $StartReplay = Invoke-CliJson -Arguments @(
        'phase-start',
        '-ProjectPath', $TestRoot,
        '-RunId', $Run.runId,
        '-PhaseId', 'PHASE-CLI-R2',
        '-PhaseRiskClass', 'R2',
        '-Actor', 'terra-manager',
        '-EventId', 'main-phase-start',
        '-Json'
    )

    Assert-Equal -Name 'phase-start replay is idempotent' -Expected $true -Actual ([bool]$StartReplay.replayed)

    $Insufficient = Invoke-CliJson -Arguments @(
        'phase-ready',
        '-ProjectPath', $TestRoot,
        '-RunId', $Run.runId,
        '-ObservedEvidenceLevel', 'E2',
        '-EvidenceIds', 'E-CLI-PHASE-LOW',
        '-Actor', 'terra-manager',
        '-EventId', 'main-phase-ready-low',
        '-Json'
    )

    Assert-Equal -Name 'phase-ready exposes evidence block' -Expected 'BLOCKED_BY_EVIDENCE' -Actual $Insufficient.phaseStatus
    Assert-Equal -Name 'evidence block uses PHASE scope' -Expected 'PHASE' -Actual $Insufficient.blockedScope
    Assert-Equal -Name 'evidence block cannot continue' -Expected $false -Actual ([bool]$Insufficient.canContinue)

    $Ready = Invoke-CliJson -Arguments @(
        'phase-ready',
        '-ProjectPath', $TestRoot,
        '-RunId', $Run.runId,
        '-ObservedEvidenceLevel', 'E3',
        '-EvidenceIds', 'E-CLI-PHASE-R2',
        '-Actor', 'terra-manager',
        '-EventId', 'main-phase-ready-pass',
        '-Json'
    )

    Assert-Equal -Name 'phase-ready reaches READY_FOR_REVIEW' -Expected 'READY_FOR_REVIEW' -Actual $Ready.phaseStatus
    Assert-Equal -Name 'phase-ready routes to PHASE_REVIEW' -Expected 'PHASE_REVIEW' -Actual $Ready.stage
    Assert-Equal -Name 'phase-ready assigns Sol' -Expected 'sol' -Actual $Ready.responsibleParty

    $PhaseStatus = Invoke-CliJson -Arguments @(
        'phase-status',
        '-ProjectPath', $TestRoot,
        '-RunId', $Run.runId,
        '-Json'
    )

    Assert-Equal -Name 'phase-status reads current phase' -Expected 'PHASE-CLI-R2' -Actual $PhaseStatus.phaseId
    Assert-Equal -Name 'phase-status reads ready state' -Expected 'READY_FOR_REVIEW' -Actual $PhaseStatus.phaseStatus

    $OrchestrationStatus = Invoke-CliJson -Arguments @(
        'orchestration-status',
        '-ProjectPath', $TestRoot,
        '-RunId', $Run.runId,
        '-Json'
    )

    Assert-Equal -Name 'orchestration-status reads PHASE_REVIEW' -Expected 'PHASE_REVIEW' -Actual $OrchestrationStatus.stage
    Assert-Equal -Name 'orchestration-status returns exact next action' -Expected $PhaseStatus.nextAction -Actual $OrchestrationStatus.nextAction

    Assert-CliFailure -Name 'Luna cannot accept phase' -Arguments @(
        'phase-accept',
        '-ProjectPath', $TestRoot,
        '-RunId', $Run.runId,
        '-Summary', 'Invalid Luna phase acceptance.',
        '-Actor', 'luna-worker',
        '-EventId', 'main-invalid-accept',
        '-Json'
    )

    $Accepted = Invoke-CliJson -Arguments @(
        'phase-accept',
        '-ProjectPath', $TestRoot,
        '-RunId', $Run.runId,
        '-Summary', 'CLI R2 phase accepted.',
        '-EvidenceIds', 'E-CLI-PHASE-REVIEW',
        '-Actor', 'sol-adjudicator',
        '-EventId', 'main-phase-accept',
        '-Json'
    )

    Assert-Equal -Name 'phase-accept returns ACCEPTED' -Expected 'ACCEPTED' -Actual $Accepted.phaseStatus
    Assert-Equal -Name 'phase-accept returns CONTINUE' -Expected 'CONTINUE' -Actual $Accepted.stage
    Assert-Equal -Name 'phase-accept returns Terra' -Expected 'terra' -Actual $Accepted.responsibleParty

    $AcceptReplay = Invoke-CliJson -Arguments @(
        'phase-review',
        '-ProjectPath', $TestRoot,
        '-RunId', $Run.runId,
        '-Decision', 'ACCEPT',
        '-Summary', 'Ignored duplicate acceptance.',
        '-Actor', 'sol-adjudicator',
        '-EventId', 'main-phase-accept',
        '-Json'
    )

    Assert-Equal -Name 'phase review replay is idempotent' -Expected $true -Actual ([bool]$AcceptReplay.replayed)

    $RejectRun = New-CliReviewedRun `
        -ProjectPath $TestRoot `
        -RunId 'cli-phase-reject' `
        -Prefix 'reject'

    Invoke-CliJson -Arguments @(
        'phase-start',
        '-ProjectPath', $TestRoot,
        '-RunId', $RejectRun.runId,
        '-PhaseId', 'PHASE-CLI-R3',
        '-PhaseRiskClass', 'R3',
        '-Actor', 'terra-manager',
        '-EventId', 'reject-phase-start',
        '-Json'
    ) | Out-Null

    $NonIndependent = Invoke-CliJson -Arguments @(
        'phase-ready',
        '-ProjectPath', $TestRoot,
        '-RunId', $RejectRun.runId,
        '-ObservedEvidenceLevel', 'E4',
        '-EvidenceIds', 'E-CLI-R3-NON-INDEPENDENT',
        '-Actor', 'terra-manager',
        '-EventId', 'reject-ready-non-independent',
        '-Json'
    )

    Assert-Equal -Name 'R3 CLI requires independent evidence' -Expected 'BLOCKED_BY_EVIDENCE' -Actual $NonIndependent.phaseStatus

    Invoke-CliJson -Arguments @(
        'phase-ready',
        '-ProjectPath', $TestRoot,
        '-RunId', $RejectRun.runId,
        '-ObservedEvidenceLevel', 'E4',
        '-EvidenceIds', 'E-CLI-R3-INDEPENDENT',
        '-EvidenceIndependent',
        '-Actor', 'terra-manager',
        '-EventId', 'reject-ready-independent',
        '-Json'
    ) | Out-Null

    $Rejected = Invoke-CliJson -Arguments @(
        'phase-reject',
        '-ProjectPath', $TestRoot,
        '-RunId', $RejectRun.runId,
        '-Summary', 'CLI R3 phase requires remediation.',
        '-Actor', 'sol-adjudicator',
        '-EventId', 'reject-phase-review',
        '-Json'
    )

    Assert-Equal -Name 'phase-reject returns REJECTED' -Expected 'REJECTED' -Actual $Rejected.phaseStatus
    Assert-Equal -Name 'phase-reject routes to PLAN' -Expected 'PLAN' -Actual $Rejected.stage
    Assert-Equal -Name 'phase-reject assigns Terra' -Expected 'terra' -Actual $Rejected.responsibleParty

    $VersionOutput = @(
        & $PwshPath -NoProfile -File $CliPath version 2>&1
    )

    if ($LASTEXITCODE -ne 0) {
        throw "CLI version command failed with exit code $LASTEXITCODE."
    }

    Assert-Equal `
        -Name 'CLI version advanced' `
        -Expected 'tri-tier-agent-system 0.7.0-alpha' `
        -Actual (($VersionOutput -join '').Trim())

    Write-Host 'Orchestration and phase-gate CLI tests passed.' -ForegroundColor Green
}
finally {
    if (Test-Path $TestRoot) {
        Remove-Item -LiteralPath $TestRoot -Recurse -Force
    }
}
