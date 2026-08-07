[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$CliPath = Join-Path $RepoRoot 'src\tri-agent.ps1'

$VersionOutput = @(
    & $CliPath version 2>&1 |
        ForEach-Object { [string]$_ }
)
$VersionExitCode = $LASTEXITCODE

if ($VersionExitCode -ne 0) {
    throw (
        'Version command failed with exit code ' +
        $VersionExitCode +
        '.'
    )
}

$VersionOutput

$DoctorOutput = @(
    & $CliPath doctor 2>&1 |
        ForEach-Object { [string]$_ }
)
$DoctorExitCode = $LASTEXITCODE

if ($DoctorExitCode -ne 0) {
    throw (
        'Doctor command failed with exit code ' +
        $DoctorExitCode +
        '.' +
        [Environment]::NewLine +
        ($DoctorOutput -join [Environment]::NewLine)
    )
}

$DoctorOutput
