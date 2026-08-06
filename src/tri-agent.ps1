[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("classify", "evidence", "doctor", "version")]
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
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ModulePaths = @{
    Classification = Join-Path $PSScriptRoot "TriTier\Classification.psm1"
    Risk = Join-Path $PSScriptRoot "TriTier\Risk.psm1"
    Evidence = Join-Path $PSScriptRoot "TriTier\Evidence.psm1"
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
        "tri-tier-agent-system 0.3.0-alpha"
        break
    }
}
