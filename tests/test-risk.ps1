$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = Split-Path $PSScriptRoot -Parent
$ModulePath = Join-Path $RepoRoot "src\TriTier\Risk.psm1"

Import-Module $ModulePath -Force

$Cases = @(
    @{
        Name = "Documentation-only task"
        Prompt = "Update the README headings only. Do not modify code."
        ExpectedRisk = "R0"
        ExpectedTier = "luna"
    }
    @{
        Name = "Low-risk mechanical task"
        Prompt = "Rename this local variable."
        ExpectedRisk = "R1"
        ExpectedTier = "luna"
    }
    @{
        Name = "Normal product change"
        Prompt = "Implement the account settings workflow and tests."
        ExpectedRisk = "R2"
        ExpectedTier = "terra"
    }
    @{
        Name = "Authorization change"
        Prompt = "Change the tenant isolation and authorization logic."
        ExpectedRisk = "R3"
        ExpectedTier = "sol"
    }
    @{
        Name = "Production deployment"
        Prompt = "Deploy this release to production."
        ExpectedRisk = "R4"
        ExpectedTier = "sol"
    }
    @{
        Name = "Negated production action"
        Prompt = "Review only. Do not deploy this release to production."
        ExpectedRisk = "R1"
        ExpectedTier = "luna"
    }
)

$Failures = @()

foreach ($Case in $Cases) {
    $Result = Get-TriTierRiskClass -Prompt $Case.Prompt

    $Passed = (
        $Result.riskClass -eq $Case.ExpectedRisk -and
        $Result.recommendedTier -eq $Case.ExpectedTier
    )

    [PSCustomObject]@{
        Test = $Case.Name
        ExpectedRisk = $Case.ExpectedRisk
        ActualRisk = $Result.riskClass
        ExpectedTier = $Case.ExpectedTier
        ActualTier = $Result.recommendedTier
        Status = if ($Passed) { "PASS" } else { "FAIL" }
    } | Format-Table -AutoSize

    if (-not $Passed) {
        $Failures += $Case.Name
    }
}

if ($Failures.Count -gt 0) {
    throw "Risk tests failed: $($Failures -join ', ')"
}

Write-Host ""
Write-Host "Risk-model tests passed." -ForegroundColor Green
