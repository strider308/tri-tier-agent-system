[CmdletBinding()]
param(
    [Parameter()]
    [string]$TargetRoot = '',

    [Parameter()]
    [string]$ConfirmTarget = '',

    [Parameter()]
    [string]$ConfirmInstallId = '',

    [Parameter()]
    [switch]$PlanOnly,

    [Parameter()]
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$ModulePath = Join-Path $RepositoryRoot 'src\TriTier\Installation.psm1'
Import-Module $ModulePath -Force

$ResolvedTarget = if ([string]::IsNullOrWhiteSpace($TargetRoot)) {
    Get-TriTierDefaultInstallRoot
}
else {
    $TargetRoot
}

$Result = if (
    $PlanOnly -or
    [string]::IsNullOrWhiteSpace($ConfirmTarget) -or
    [string]::IsNullOrWhiteSpace($ConfirmInstallId)
) {
    New-TriTierMigrationPlan `
        -SourceRoot $RepositoryRoot `
        -TargetRoot $ResolvedTarget
}
else {
    Invoke-TriTierMigration `
        -SourceRoot $RepositoryRoot `
        -TargetRoot $ResolvedTarget `
        -ConfirmTarget $ConfirmTarget `
        -ConfirmInstallId $ConfirmInstallId
}

if ($Json) {
    $Result | ConvertTo-Json -Depth 80
}
else {
    $Result | Format-List
}
