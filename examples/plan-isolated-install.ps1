[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),

    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'TriTierAgentSystem\isolated')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$CliPath = Join-Path $RepoRoot 'src\tri-agent.ps1'

$CompatibilityOutput = @(
    & $CliPath compatibility-check `
        -InstallRoot $InstallRoot `
        -Json `
        2>&1 |
        ForEach-Object { [string]$_ }
)
$CompatibilityExitCode = $LASTEXITCODE

if ($CompatibilityExitCode -ne 0) {
    throw (
        'Compatibility check failed with exit code ' +
        $CompatibilityExitCode +
        '.'
    )
}

$CompatibilityOutput

$PlanOutput = @(
    & $CliPath install-plan `
        -InstallRoot $InstallRoot `
        -Json `
        2>&1 |
        ForEach-Object { [string]$_ }
)
$PlanExitCode = $LASTEXITCODE

if ($PlanExitCode -ne 0) {
    throw (
        'Install plan failed with exit code ' +
        $PlanExitCode +
        '.'
    )
}

$PlanOutput
