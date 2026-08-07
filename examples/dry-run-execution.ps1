[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ProjectPath,

    [Parameter(Mandatory)]
    [string]$RunId,

    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$CliPath = Join-Path $RepoRoot 'src\tri-agent.ps1'

$Output = @(
    & $CliPath exec `
        -ProjectPath $ProjectPath `
        -RunId $RunId `
        -DryRun `
        -Json `
        2>&1 |
        ForEach-Object { [string]$_ }
)
$ExitCode = $LASTEXITCODE

if ($ExitCode -ne 0) {
    throw (
        'Execution dry-run failed with exit code ' +
        $ExitCode +
        '.' +
        [Environment]::NewLine +
        ($Output -join [Environment]::NewLine)
    )
}

$Output
