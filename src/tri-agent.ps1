[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("classify", "evidence", "run-init", "run-checkpoint", "run-resume", "run-status", "doctor", "version")]
    [string]$Command = "doctor",

    [Parameter()]
    [AllowEmptyString()]
    [string]$Prompt = "",

    [Parameter()]
    [ValidateSet("R0", "R1", "R2", "R3", "R4")]
    [string]$RiskClass = "R2",

    [Parameter()]
    [ValidateSet("E0", "E1", "E2", "E3", "E4", "E5")]
    [string]$EvidenceLevel = "E0",

    [Parameter()]
    [switch]$IndependentlyReproduced,
    [Parameter()]
    [string]$ProjectPath = ".",

    [Parameter()]
    [string]$RunId = "",

    [Parameter()]
    [string]$Title = "",

    [Parameter()]
    [string]$PlanPath = "",

    [Parameter()]
    [string]$CurrentPhase = "PHASE-01",

    [Parameter()]
    [string]$CurrentTask = "",

    [Parameter()]
    [string]$NextAction = "",

    [Parameter()]
    [string]$Summary = "",

    [Parameter()]
    [string[]]$CompletedTasks,

    [Parameter()]
    [string[]]$UnresolvedFindings,

    [Parameter()]
    [string[]]$Blockers,

    [Parameter()]
    [string]$RunStatus = "",

    [Parameter()]
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ModulePaths = @{
    Classification = Join-Path $PSScriptRoot "TriTier\Classification.psm1"
    Risk = Join-Path $PSScriptRoot "TriTier\Risk.psm1"
    Evidence = Join-Path $PSScriptRoot "TriTier\Evidence.psm1"
    Findings = Join-Path $PSScriptRoot "TriTier\Findings.psm1"
    State = Join-Path $PSScriptRoot "TriTier\State.psm1"
}

foreach ($Entry in $ModulePaths.GetEnumerator()) {
    if (-not (Test-Path $Entry.Value)) {
        throw "Tri-Tier module not found: $($Entry.Value)"
    }

    Import-Module $Entry.Value -Force
}

switch ($Command) {
    "classify" {
        if ([string]::IsNullOrWhiteSpace($Prompt)) {
            throw "The classify command requires -Prompt."
        }

        $Route = Get-TriTierTaskClassification -Prompt $Prompt
        $Risk = Get-TriTierRiskClass -Prompt $Prompt

        $Result = [PSCustomObject]@{
            recommendedTier = $Route.recommendedTier
            riskClass = $Risk.riskClass
            riskName = $Risk.name
            minimumEvidence = $Risk.minimumEvidence
            ownerApprovalRequired = $Risk.ownerApprovalRequired
            freshReviewAfterRepair = $Risk.freshReviewAfterRepair
            minimumIndependentReviewers = $Risk.minimumIndependentReviewers
            reviewPolicy = $Risk.reviewPolicy
            reasons = @(@($Route.reasons) + @($Risk.reasons) | Select-Object -Unique)
        }

        if ($Json) {
            $Result | ConvertTo-Json -Depth 8
        }
        else {
            $Result | Format-List
        }

        break
    }

    "evidence" {
        $Arguments = @{
            RiskClass = $RiskClass
            EvidenceLevel = $EvidenceLevel
        }

        if ($IndependentlyReproduced) {
            $Arguments.IndependentlyReproduced = $true
        }

        $Result = Test-TriTierEvidenceSufficiency @Arguments

        if ($Json) {
            $Result | ConvertTo-Json -Depth 8
        }
        else {
            $Result | Format-List
        }

        if (-not $Result.sufficient) {
            $global:LASTEXITCODE = 1
        }
        else {
            $global:LASTEXITCODE = 0
        }

        break
    }

    "run-init" {
        if ([string]::IsNullOrWhiteSpace($Title)) {
            throw "The run-init command requires -Title."
        }

        $Arguments = @{
            ProjectPath = $ProjectPath
            Title = $Title
            CurrentPhase = $CurrentPhase
        }

        if (-not [string]::IsNullOrWhiteSpace($RunId)) {
            $Arguments.RunId = $RunId
        }

        if (-not [string]::IsNullOrWhiteSpace($PlanPath)) {
            $Arguments.PlanPath = $PlanPath
        }

        if (-not [string]::IsNullOrWhiteSpace($CurrentTask)) {
            $Arguments.CurrentTask = $CurrentTask
        }

        if (-not [string]::IsNullOrWhiteSpace($NextAction)) {
            $Arguments.NextAction = $NextAction
        }

        $Run = New-TriTierRun @Arguments

        $Result = [PSCustomObject]@{
            runId = $Run.state.runId
            title = $Run.state.title
            status = $Run.state.status
            runDirectory = $Run.runDirectory
            currentPhase = $Run.state.currentPhase
            currentTask = $Run.state.currentTask
            nextAction = $Run.state.nextAction
            baselineCommit = $Run.state.baselineCommit
            workingTreeStatus = $Run.state.workingTreeStatus
            planHash = $Run.state.planHash
        }

        if ($Json) {
            $Result | ConvertTo-Json -Depth 10
        }
        else {
            $Result | Format-List
        }

        break
    }

    "run-checkpoint" {
        if ([string]::IsNullOrWhiteSpace($RunId)) {
            throw "The run-checkpoint command requires -RunId."
        }

        if ([string]::IsNullOrWhiteSpace($Summary)) {
            throw "The run-checkpoint command requires -Summary."
        }

        if ([string]::IsNullOrWhiteSpace($NextAction)) {
            throw "The run-checkpoint command requires -NextAction."
        }

        $Arguments = @{
            ProjectPath = $ProjectPath
            RunId = $RunId
            Summary = $Summary
            NextAction = $NextAction
        }

        if (-not [string]::IsNullOrWhiteSpace($CurrentPhase)) {
            $Arguments.CurrentPhase = $CurrentPhase
        }

        if (-not [string]::IsNullOrWhiteSpace($CurrentTask)) {
            $Arguments.CurrentTask = $CurrentTask
        }

        if ($null -ne $CompletedTasks) {
            $Arguments.CompletedTasks = $CompletedTasks
        }

        if ($null -ne $UnresolvedFindings) {
            $Arguments.UnresolvedFindings = $UnresolvedFindings
        }

        if ($null -ne $Blockers) {
            $Arguments.Blockers = $Blockers
        }

        $Checkpoint = New-TriTierCheckpoint @Arguments

        $Result = [PSCustomObject]@{
            checkpointId = $Checkpoint.checkpointId
            runId = $Checkpoint.runId
            createdUtc = $Checkpoint.createdUtc
            summary = $Checkpoint.summary
            currentPhase = $Checkpoint.state.currentPhase
            currentTask = $Checkpoint.state.currentTask
            nextAction = $Checkpoint.state.nextAction
        }

        if ($Json) {
            $Result | ConvertTo-Json -Depth 10
        }
        else {
            $Result | Format-List
        }

        break
    }

    "run-resume" {
        if ([string]::IsNullOrWhiteSpace($RunId)) {
            throw "The run-resume command requires -RunId."
        }

        $Resume = Get-TriTierRunResumeData `
            -ProjectPath $ProjectPath `
            -RunId $RunId

        $Result = [PSCustomObject]@{
            runId = $Resume.state.runId
            title = $Resume.state.title
            status = $Resume.state.status
            currentPhase = $Resume.state.currentPhase
            currentTask = $Resume.state.currentTask
            completedTasks = @($Resume.state.completedTasks)
            unresolvedFindings = @($Resume.state.unresolvedFindings)
            blockers = @($Resume.state.blockers)
            nextAction = $Resume.nextAction
            lastCheckpointId = $Resume.state.lastCheckpointId
            latestCheckpointSummary = if ($null -ne $Resume.latestCheckpoint) {
                $Resume.latestCheckpoint.summary
            }
            else {
                ""
            }
            runDirectory = $Resume.runDirectory
        }

        if ($Json) {
            $Result | ConvertTo-Json -Depth 15
        }
        else {
            $Result | Format-List
        }

        break
    }

    "run-status" {
        if ([string]::IsNullOrWhiteSpace($RunId)) {
            throw "The run-status command requires -RunId."
        }

        if ([string]::IsNullOrWhiteSpace($RunStatus)) {
            $State = Get-TriTierRunState `
                -ProjectPath $ProjectPath `
                -RunId $RunId
        }
        else {
            $State = Set-TriTierRunStatus `
                -ProjectPath $ProjectPath `
                -RunId $RunId `
                -Status $RunStatus
        }

        $Result = [PSCustomObject]@{
            runId = $State.runId
            title = $State.title
            status = $State.status
            currentPhase = $State.currentPhase
            currentTask = $State.currentTask
            nextAction = $State.nextAction
            updatedUtc = $State.updatedUtc
        }

        if ($Json) {
            $Result | ConvertTo-Json -Depth 10
        }
        else {
            $Result | Format-List
        }

        break
    }
    "doctor" {
        $RequiredAgents = @(
            "luna-router.toml",
            "luna-worker.toml",
            "sol-adjudicator.toml",
            "sol-architect.toml",
            "terra-manager.toml",
            "terra-reviewer.toml"
        )

        $RepositoryRoot = Split-Path $PSScriptRoot -Parent
        $AgentRoot = Join-Path $RepositoryRoot "agents"
        $Checks = @()

        $Checks += [PSCustomObject]@{
            Check = "PowerShell"
            Status = "PASS"
            Detail = $PSVersionTable.PSVersion.ToString()
        }

        foreach ($Entry in $ModulePaths.GetEnumerator()) {
            $Checks += [PSCustomObject]@{
                Check = "$($Entry.Key) module"
                Status = if (Test-Path $Entry.Value) { "PASS" } else { "FAIL" }
                Detail = $Entry.Value
            }
        }

        foreach ($Agent in $RequiredAgents) {
            $Path = Join-Path $AgentRoot $Agent

            $Checks += [PSCustomObject]@{
                Check = "Agent: $Agent"
                Status = if (Test-Path $Path) { "PASS" } else { "FAIL" }
                Detail = $Path
            }
        }

        if ($Json) {
            $Checks | ConvertTo-Json -Depth 5
        }
        else {
            $Checks | Format-Table -AutoSize
        }

        if ($Checks.Status -contains "FAIL") {
            throw "Tri-Tier doctor found one or more failed checks."
        }

        break
    }

    "version" {
        "tri-tier-agent-system 0.4.0-alpha"
        break
    }
}
