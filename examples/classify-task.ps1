[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Task,

    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$CliPath = Join-Path $RepoRoot 'src\tri-agent.ps1'

$Output = @(
    & $CliPath classify `
        -Task $Task `
        -Json `
        2>&1 |
        ForEach-Object { [string]$_ }
)
$ExitCode = $LASTEXITCODE

if ($ExitCode -ne 0) {
    throw (
        'Classification failed with exit code ' +
        $ExitCode +
        '.' +
        [Environment]::NewLine +
        ($Output -join [Environment]::NewLine)
    )
}

$Output
