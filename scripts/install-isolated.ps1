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
    [string]::IsNullOrWhiteSpace($ConfirmTarget)
) {
    New-TriTierInstallPlan `
        -SourceRoot $RepositoryRoot `
        -TargetRoot $ResolvedTarget
}
else {
    $Arguments = @{
        SourceRoot = $RepositoryRoot
        TargetRoot = $ResolvedTarget
        ConfirmTarget = $ConfirmTarget
    }

    if (-not [string]::IsNullOrWhiteSpace($ConfirmInstallId)) {
        $Arguments.ConfirmInstallId = $ConfirmInstallId
    }

    Invoke-TriTierInstall @Arguments
}

if ($Json) {
    $Result | ConvertTo-Json -Depth 80
}
else {
    $Result | Format-List
}
