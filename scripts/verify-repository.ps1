$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
# A successful verifier run must not inherit a stale native-command status.
$global:LASTEXITCODE = 0

$RepoRoot = Split-Path $PSScriptRoot -Parent

Write-Host "=== TRI-TIER REPOSITORY VERIFICATION ===" -ForegroundColor Cyan

$RequiredPaths = @(
    ".github\workflows\powershell.yml",
    ".gitignore",
    "LICENSE",
    "NOTICE",
    "README.md",
    "SECURITY.md",
    "CONTRIBUTING.md",
    "AGENTS.md",
    "CHANGELOG.md",
    "docs\architecture.md",
    "docs\risk-model.md",
    "docs\evidence-model.md",
    "docs\state-model.md",
    "docs\finding-model.md",
    "src\tri-agent.cmd",
    "src\tri-agent.ps1",
    "src\TriTier\Classification.psm1",
    "src\TriTier\Risk.psm1",
    "src\TriTier\Evidence.psm1",
    "src\TriTier\State.psm1",
    "src\TriTier\Findings.psm1",
    "agents\luna-router.toml",
    "agents\luna-worker.toml",
    "agents\sol-adjudicator.toml",
    "agents\sol-architect.toml",
    "agents\terra-manager.toml",
    "agents\terra-reviewer.toml",
    "tests\test-classification.ps1",
    "tests\test-risk.ps1",
    "tests\test-evidence.ps1",
    "tests\test-state.ps1",
    "tests\test-cli-state.ps1",
    "tests\test-findings.ps1"
)

$Failures = @()

foreach ($RelativePath in $RequiredPaths) {
    $FullPath = Join-Path $RepoRoot $RelativePath
    $Exists = Test-Path $FullPath

    [PSCustomObject]@{
        Path = $RelativePath
        Status = if ($Exists) { "PASS" } else { "FAIL" }
    } | Format-Table -AutoSize

    if (-not $Exists) {
        $Failures += $RelativePath
    }
}

$PublicFiles = Get-ChildItem $RepoRoot -Recurse -File |
    Where-Object {
        $_.FullName -notlike "*\.git\*" -and
        $_.FullName -notlike "*\_local-audit\*"
    }

$SensitivePatterns = @(
    "(?i)C:\\Users\\",
    "(?i)\bsk-[A-Za-z0-9_-]{20,}\b",
    "(?i)\bapi[_-]?key\s*=",
    "(?i)\baccess[_-]?token\s*=",
    "(?i)\bclient[_-]?secret\s*=",
    "(?i)\bpassword\s*=",
    "(?i)\bBearer\s+[A-Za-z0-9._~-]{15,}"
)

$SensitiveFindings = @()

foreach ($File in $PublicFiles) {
    try {
        $Content = Get-Content $File.FullName -Raw -ErrorAction Stop
    }
    catch {
        continue
    }

    foreach ($Pattern in $SensitivePatterns) {
        if ($Content -match $Pattern) {
            $SensitiveFindings += [PSCustomObject]@{
                File = $File.FullName.Substring($RepoRoot.Length + 1)
                Pattern = $Pattern
            }
        }
    }
}

if ($SensitiveFindings.Count -gt 0) {
    Write-Host ""
    Write-Host "Sensitive-reference scan failed:" -ForegroundColor Red
    $SensitiveFindings | Format-Table -AutoSize
    $Failures += "Sensitive-reference scan"
}
else {
    Write-Host ""
    Write-Host "Sensitive-reference scan: PASS" -ForegroundColor Green
}

$TestScripts = @(
    "tests\test-classification.ps1",
    "tests\test-risk.ps1",
    "tests\test-evidence.ps1",
    "tests\test-state.ps1",
    "tests\test-cli-state.ps1",
    "tests\test-findings.ps1"
)

foreach ($TestScript in $TestScripts) {
    Write-Host ""
    Write-Host "Running $TestScript" -ForegroundColor Cyan
    & (Join-Path $RepoRoot $TestScript)
}

Write-Host ""
Write-Host "Running CLI doctor" -ForegroundColor Cyan
& (Join-Path $RepoRoot "src\tri-agent.ps1") doctor

if ($Failures.Count -gt 0) {
    throw "Repository verification failed: $($Failures -join ', ')"
}

Write-Host ""
Write-Host "Repository verification passed." -ForegroundColor Green

# Native tools used by tests may leave a stale nonzero value even though
# every PowerShell test and repository gate succeeded.
$global:LASTEXITCODE = 0
