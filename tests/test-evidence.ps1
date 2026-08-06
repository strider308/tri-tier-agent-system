$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = Split-Path $PSScriptRoot -Parent
$ModulePath = Join-Path $RepoRoot "src\TriTier\Evidence.psm1"

Import-Module $ModulePath -Force

$Cases = @(
    @{ Name = "R0 accepts E2"; Risk = "R0"; Evidence = "E2"; Independent = $false; Expected = $true }
    @{ Name = "R1 rejects E1"; Risk = "R1"; Evidence = "E1"; Independent = $false; Expected = $false }
    @{ Name = "R2 rejects E2"; Risk = "R2"; Evidence = "E2"; Independent = $false; Expected = $false }
    @{ Name = "R2 accepts E3"; Risk = "R2"; Evidence = "E3"; Independent = $false; Expected = $true }
    @{ Name = "R3 accepts E4"; Risk = "R3"; Evidence = "E4"; Independent = $false; Expected = $true }
    @{ Name = "R4 rejects non-independent E5"; Risk = "R4"; Evidence = "E5"; Independent = $false; Expected = $false }
    @{ Name = "R4 accepts independent E5"; Risk = "R4"; Evidence = "E5"; Independent = $true; Expected = $true }
)

$Failures = @()

foreach ($Case in $Cases) {
    $Arguments = @{
        RiskClass = $Case.Risk
        EvidenceLevel = $Case.Evidence
    }

    if ($Case.Independent) {
        $Arguments.IndependentlyReproduced = $true
    }

    $Result = Test-TriTierEvidenceSufficiency @Arguments
    $Passed = $Result.sufficient -eq $Case.Expected

    [PSCustomObject]@{
        Test = $Case.Name
        Risk = $Case.Risk
        Evidence = $Case.Evidence
        Expected = $Case.Expected
        Actual = $Result.sufficient
        Status = if ($Passed) { "PASS" } else { "FAIL" }
    } | Format-Table -AutoSize

    if (-not $Passed) {
        $Failures += $Case.Name
    }
}

$Record = New-TriTierEvidenceRecord `
    -EvidenceLevel "E3" `
    -Claim "Affected integration tests pass." `
    -Source "tests/integration" `
    -Command "pwsh ./tests/run.ps1" `
    -Result "PASS"

if ([string]::IsNullOrWhiteSpace($Record.evidenceId)) {
    $Failures += "Evidence record ID generation"
}

$RejectedInvalidE5 = $false

try {
    New-TriTierEvidenceRecord `
        -EvidenceLevel "E5" `
        -Claim "Independent review passed." `
        -Source "review-report.md" | Out-Null
}
catch {
    $RejectedInvalidE5 = $true
}

if (-not $RejectedInvalidE5) {
    $Failures += "Invalid E5 record was not rejected"
}

if ($Failures.Count -gt 0) {
    throw "Evidence tests failed: $($Failures -join ', ')"
}

Write-Host ""
Write-Host "Evidence-model tests passed." -ForegroundColor Green
