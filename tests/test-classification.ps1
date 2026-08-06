$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = Split-Path $PSScriptRoot -Parent
$ModulePath = Join-Path `
    $RepoRoot `
    "src\TriTier\Classification.psm1"

Import-Module $ModulePath -Force

$Cases = @(
    @{
        Name         = "Security task routes to Sol"
        Prompt       = "Review tenant isolation and authorization boundaries."
        ExpectedTier = "sol"
        ExpectedRisk = "high"
    }
    @{
        Name         = "Formatting task routes to Luna"
        Prompt       = "Format and normalize these Markdown headings."
        ExpectedTier = "luna"
        ExpectedRisk = "low"
    }
    @{
        Name         = "Integrated implementation routes to Terra"
        Prompt       = "Implement the account settings workflow and tests."
        ExpectedTier = "terra"
        ExpectedRisk = "medium"
    }
    @{
        Name         = "Read-only review is not implementation"
        Prompt       = "Review only. Do not modify files."
        ExpectedTier = "terra"
        ExpectedRisk = "medium"
    }
)

$Failures = @()

foreach ($Case in $Cases) {
    $Result = Get-TriTierTaskClassification -Prompt $Case.Prompt

    $Passed = (
        $Result.recommendedTier -eq $Case.ExpectedTier -and
        $Result.riskLevel -eq $Case.ExpectedRisk
    )

    [PSCustomObject]@{
        Test         = $Case.Name
        ExpectedTier = $Case.ExpectedTier
        ActualTier   = $Result.recommendedTier
        ExpectedRisk = $Case.ExpectedRisk
        ActualRisk   = $Result.riskLevel
        Status       = if ($Passed) { "PASS" } else { "FAIL" }
    } | Format-Table -AutoSize

    if (-not $Passed) {
        $Failures += $Case.Name
    }
}

if ($Failures.Count -gt 0) {
    throw "Classification tests failed: $($Failures -join ', ')"
}

Write-Host ""
Write-Host "Classification tests passed." -ForegroundColor Green
