[CmdletBinding()]
param(
    [Parameter()]
    [string]$TargetRoot = '',

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

$Result = Repair-TriTierInstallation -TargetRoot $ResolvedTarget

if ($Json) {
    $Result | ConvertTo-Json -Depth 80
}
else {
    $Result | Format-List
}
