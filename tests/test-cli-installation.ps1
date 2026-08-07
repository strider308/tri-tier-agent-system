Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$CliPath = Join-Path $RepositoryRoot 'src\tri-agent.ps1'
$PwshPath = (Get-Command pwsh -ErrorAction Stop).Source

function Test-Condition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory)]
        [bool]$Value
    )

    if (-not $Value) {
        throw "$Name failed."
    }

    [PSCustomObject]@{
        Test = $Name
        Status = 'PASS'
    } | Format-Table -AutoSize
}

function Test-EqualValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter()]
        [AllowNull()]
        [object]$Expected,

        [Parameter()]
        [AllowNull()]
        [object]$Actual
    )

    if ($Expected -ne $Actual) {
        throw "$Name failed. Expected: $Expected. Actual: $Actual."
    }

    [PSCustomObject]@{
        Test = $Name
        Status = 'PASS'
    } | Format-Table -AutoSize
}

function Invoke-TestCliJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $Output = @(
        & $PwshPath `
            -NoLogo `
            -NoProfile `
            -File $CliPath `
            @Arguments `
            -Json `
            2>&1 |
            ForEach-Object {
                [string]$_
            }
    )
    $ExitCode = $LASTEXITCODE
    $Text = $Output -join [Environment]::NewLine

    if ($ExitCode -ne 0) {
        throw (
            "CLI invocation failed with exit code ${ExitCode}:" +
            [Environment]::NewLine +
            $Text
        )
    }

    $Text | ConvertFrom-Json -Depth 80
}

$TestRoot = Join-Path $env:TEMP (
    'tri-tier-cli-installation-test-' + [guid]::NewGuid().ToString('N')
)
$InstallTarget = Join-Path $TestRoot 'isolated'

try {
    New-Item -ItemType Directory -Path $TestRoot -Force | Out-Null

    $Compatibility = Invoke-TestCliJson -Arguments @(
        'compatibility-check'
        '-InstallRoot'
        $InstallTarget
    )

    Test-EqualValue `
        -Name 'compatibility-check reports compatible' `
        -Expected $true `
        -Actual ([bool]$Compatibility.compatible)

    $InstallPlan = Invoke-TestCliJson -Arguments @(
        'install-plan'
        '-InstallRoot'
        $InstallTarget
    )

    Test-EqualValue `
        -Name 'install-plan can apply' `
        -Expected $true `
        -Actual ([bool]$InstallPlan.canApply)

    Test-EqualValue `
        -Name 'install-plan reports no private Codex mutation' `
        -Expected $false `
        -Actual ([bool]$InstallPlan.privateCodexMutation)

    $InstallResult = Invoke-TestCliJson -Arguments @(
        'install-apply'
        '-InstallRoot'
        $InstallTarget
        '-ConfirmInstallRoot'
        $InstallTarget
    )

    Test-EqualValue `
        -Name 'install-apply completes' `
        -Expected 'COMPLETE' `
        -Actual ([string]$InstallResult.status)

    $InstallStatus = Invoke-TestCliJson -Arguments @(
        'install-status'
        '-InstallRoot'
        $InstallTarget
    )

    Test-EqualValue `
        -Name 'install-status reports healthy' `
        -Expected $true `
        -Actual ([bool]$InstallStatus.healthy)

    $ManifestPath = Join-Path $InstallTarget 'install-manifest.json'
    $LegacyManifest = (
        [System.IO.File]::ReadAllText($ManifestPath) |
            ConvertFrom-Json -AsHashtable -Depth 80
    )
    $LegacyManifest.schemaVersion = 1
    $LegacyManifest.version = '0.9.0-alpha'
    [System.IO.File]::WriteAllText(
        $ManifestPath,
        (
            $LegacyManifest |
                ConvertTo-Json -Depth 80
        ) + [Environment]::NewLine,
        [System.Text.UTF8Encoding]::new($false)
    )

    $MigrationPlan = Invoke-TestCliJson -Arguments @(
        'migrate-plan'
        '-InstallRoot'
        $InstallTarget
    )

    Test-EqualValue `
        -Name 'migrate-plan recognizes legacy install' `
        -Expected $true `
        -Actual ([bool]$MigrationPlan.canApply)

    $MigrationResult = Invoke-TestCliJson -Arguments @(
        'migrate-apply'
        '-InstallRoot'
        $InstallTarget
        '-ConfirmInstallRoot'
        $InstallTarget
        '-ConfirmInstallId'
        ([string]$InstallStatus.installId)
    )

    Test-EqualValue `
        -Name 'migrate-apply completes' `
        -Expected 'COMPLETE' `
        -Actual ([string]$MigrationResult.status)

    $UninstallPlan = Invoke-TestCliJson -Arguments @(
        'uninstall-plan'
        '-InstallRoot'
        $InstallTarget
    )

    Test-EqualValue `
        -Name 'uninstall-plan is reversible' `
        -Expected $true `
        -Actual ([bool]$UninstallPlan.reversible)

    $UninstallResult = Invoke-TestCliJson -Arguments @(
        'uninstall-apply'
        '-InstallRoot'
        $InstallTarget
        '-ConfirmInstallRoot'
        $InstallTarget
        '-ConfirmInstallId'
        ([string]$InstallStatus.installId)
    )

    Test-EqualValue `
        -Name 'uninstall-apply completes' `
        -Expected 'COMPLETE' `
        -Actual ([string]$UninstallResult.status)

    Test-EqualValue `
        -Name 'uninstall-apply does not delete backup' `
        -Expected $false `
        -Actual ([bool]$UninstallResult.deleted)

    $VersionOutput = @(
        & $PwshPath `
            -NoLogo `
            -NoProfile `
            -File $CliPath `
            version `
            2>&1 |
            ForEach-Object {
                [string]$_
            }
    )
    $VersionExitCode = $LASTEXITCODE
    $VersionText = $VersionOutput -join [Environment]::NewLine

    if ($VersionExitCode -ne 0) {
        throw "CLI version command failed: $VersionText"
    }

    Test-Condition `
        -Name 'CLI version advanced' `
        -Value ($VersionText -match '0\.10\.0-alpha')

    Write-Host ''
    Write-Host 'Installation hardening CLI tests passed.' `
        -ForegroundColor Green
}
finally {
    if (Test-Path -LiteralPath $TestRoot) {
        Remove-Item -LiteralPath $TestRoot -Recurse -Force
    }
}
