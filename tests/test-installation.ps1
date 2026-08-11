Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$ModulePath = Join-Path $RepositoryRoot 'src\TriTier\Installation.psm1'
$InstallationModule = Import-Module $ModulePath -Force -PassThru

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

$TestRoot = Join-Path $env:TEMP (
    'tri-tier-installation-test-' + [guid]::NewGuid().ToString('N')
)
$InstallTarget = Join-Path $TestRoot 'isolated'
$UnmanagedTarget = Join-Path $TestRoot 'unmanaged'

try {
    New-Item -ItemType Directory -Path $TestRoot -Force | Out-Null

    $ScalarConversion = & $InstallationModule {
        ConvertTo-TriTierInstallHashtable -Value 42
    }

    Test-EqualValue `
        -Name 'Scalar JSON value conversion is stable' `
        -Expected 42 `
        -Actual $ScalarConversion

    $NestedConversion = & $InstallationModule {
        ConvertTo-TriTierInstallHashtable `
            -Value (
                [PSCustomObject][ordered]@{
                    schemaVersion = 2
                    product = 'tri-tier-agent-system'
                    enabled = $true
                    files = @(
                        [PSCustomObject][ordered]@{
                            path = 'src/tri-agent.ps1'
                            size = 1
                        }
                    )
                    multipleFiles = @(
                        [PSCustomObject][ordered]@{
                            path = 'src/tri-agent.ps1'
                            size = 1
                        }
                        [PSCustomObject][ordered]@{
                            path = 'src/tri-agent.cmd'
                            size = 2
                        }
                    )
                }
            )
    }

    Test-EqualValue `
        -Name 'Nested JSON integer remains intact' `
        -Expected 2 `
        -Actual $NestedConversion.schemaVersion

    Test-EqualValue `
        -Name 'Nested JSON string remains intact' `
        -Expected 'tri-tier-agent-system' `
        -Actual $NestedConversion.product

    Test-EqualValue `
        -Name 'Nested JSON boolean remains intact' `
        -Expected $true `
        -Actual $NestedConversion.enabled

    Test-EqualValue `
        -Name 'Single-item JSON array remains an array' `
        -Expected 1 `
        -Actual @($NestedConversion.files).Count

    Test-EqualValue `
        -Name 'Single-item JSON array retains object' `
        -Expected 'src/tri-agent.ps1' `
        -Actual $NestedConversion.files[0].path

    Test-EqualValue `
        -Name 'Multi-item JSON array remains intact' `
        -Expected 2 `
        -Actual @($NestedConversion.multipleFiles).Count

    Test-EqualValue `
        -Name 'Multi-item JSON array retains first object' `
        -Expected 'src/tri-agent.ps1' `
        -Actual $NestedConversion.multipleFiles[0].path

    Test-EqualValue `
        -Name 'Multi-item JSON array retains second object' `
        -Expected 'src/tri-agent.cmd' `
        -Actual $NestedConversion.multipleFiles[1].path

    $DefaultRoot = Get-TriTierDefaultInstallRoot
    $CodexRoot = Join-Path $HOME '.codex'

    Test-Condition `
        -Name 'Default install root avoids private Codex root' `
        -Value (
            -not $DefaultRoot.StartsWith(
                [System.IO.Path]::GetFullPath($CodexRoot),
                [System.StringComparison]::OrdinalIgnoreCase
            )
        )

    $UnsafeTarget = Join-Path $CodexRoot 'tri-tier-phase6-test'
    $UnsafeCheck = Test-TriTierInstallTarget `
        -TargetRoot $UnsafeTarget `
        -SourceRoot $RepositoryRoot

    Test-EqualValue `
        -Name 'Private Codex target is rejected' `
        -Expected $false `
        -Actual ([bool]$UnsafeCheck.valid)

    $Compatibility = Get-TriTierCompatibilityReport `
        -SourceRoot $RepositoryRoot `
        -TargetRoot $InstallTarget

    Test-EqualValue `
        -Name 'Isolated compatibility report passes' `
        -Expected $true `
        -Actual ([bool]$Compatibility.compatible)

    $Plan = New-TriTierInstallPlan `
        -SourceRoot $RepositoryRoot `
        -TargetRoot $InstallTarget

    $InstallLockPath = Get-TriTierInstallLockPath `
        -TargetRoot $InstallTarget
    New-Item `
        -ItemType Directory `
        -Path (Split-Path -Parent $InstallLockPath) `
        -Force |
        Out-Null
    $HeldInstallLock = [System.IO.File]::Open(
        $InstallLockPath,
        [System.IO.FileMode]::OpenOrCreate,
        [System.IO.FileAccess]::ReadWrite,
        [System.IO.FileShare]::None
    )
    $ConcurrentInstallRejected = $false

    try {
        try {
            Invoke-TriTierInstall `
                -SourceRoot $RepositoryRoot `
                -TargetRoot $InstallTarget `
                -ConfirmTarget $InstallTarget |
                Out-Null
        }
        catch {
            if (
                $_.Exception.Message -match
                'owns the isolated target lock'
            ) {
                $ConcurrentInstallRejected = $true
            }
            else {
                throw
            }
        }
    }
    finally {
        $HeldInstallLock.Dispose()
    }

    Test-EqualValue `
        -Name 'Concurrent install invocation fails closed' `
        -Expected $true `
        -Actual $ConcurrentInstallRejected

    Test-EqualValue `
        -Name 'Fresh install plan can apply' `
        -Expected $true `
        -Actual ([bool]$Plan.canApply)

    Test-EqualValue `
        -Name 'Fresh install plan mutates no private Codex files' `
        -Expected $false `
        -Actual ([bool]$Plan.privateCodexMutation)

    $InstallResult = Invoke-TriTierInstall `
        -SourceRoot $RepositoryRoot `
        -TargetRoot $InstallTarget `
        -ConfirmTarget $InstallTarget

    Test-EqualValue `
        -Name 'Fresh isolated install completes' `
        -Expected 'COMPLETE' `
        -Actual ([string]$InstallResult.status)

    Test-EqualValue `
        -Name 'Fresh isolated install reports no PATH mutation' `
        -Expected $false `
        -Actual ([bool]$InstallResult.pathMutation)

    $InstalledStatus = Get-TriTierInstallStatus `
        -TargetRoot $InstallTarget

    Test-EqualValue `
        -Name 'Installed payload is healthy' `
        -Expected $true `
        -Actual ([bool]$InstalledStatus.healthy)

    Test-EqualValue `
        -Name 'Installed version is current' `
        -Expected '0.10.0-alpha' `
        -Actual ([string]$InstalledStatus.version)

    Test-Condition `
        -Name 'Installed launcher exists' `
        -Value (
            Test-Path `
                -LiteralPath (
                    Join-Path $InstallTarget 'bin\tri-agent.ps1'
                ) `
                -PathType Leaf
        )

    New-Item `
        -ItemType Directory `
        -Path $UnmanagedTarget `
        -Force |
        Out-Null
    [System.IO.File]::WriteAllText(
        (Join-Path $UnmanagedTarget 'foreign.txt'),
        'not owned by tri-tier'
    )

    $UnmanagedPlan = New-TriTierInstallPlan `
        -SourceRoot $RepositoryRoot `
        -TargetRoot $UnmanagedTarget

    Test-EqualValue `
        -Name 'Unmanaged target fails closed' `
        -Expected $false `
        -Actual ([bool]$UnmanagedPlan.canApply)

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

    $MigrationPlan = New-TriTierMigrationPlan `
        -SourceRoot $RepositoryRoot `
        -TargetRoot $InstallTarget

    Test-EqualValue `
        -Name 'Legacy isolated install requires migration' `
        -Expected $true `
        -Actual ([bool]$MigrationPlan.canApply)

    Test-EqualValue `
        -Name 'Migration preserves installation identity' `
        -Expected ([string]$InstalledStatus.installId) `
        -Actual ([string]$MigrationPlan.installId)

    $MigrationResult = Invoke-TriTierMigration `
        -SourceRoot $RepositoryRoot `
        -TargetRoot $InstallTarget `
        -ConfirmTarget $InstallTarget `
        -ConfirmInstallId $InstalledStatus.installId

    Test-EqualValue `
        -Name 'Migration completes' `
        -Expected 'COMPLETE' `
        -Actual ([string]$MigrationResult.status)

    Test-Condition `
        -Name 'Migration creates rollback backup' `
        -Value (
            Test-Path `
                -LiteralPath $MigrationResult.backupPath `
                -PathType Container
        )

    $MigratedStatus = Get-TriTierInstallStatus `
        -TargetRoot $InstallTarget

    Test-EqualValue `
        -Name 'Migrated version is current' `
        -Expected '0.10.0-alpha' `
        -Actual ([string]$MigratedStatus.version)

    Test-EqualValue `
        -Name 'Migrated schema is current' `
        -Expected 2 `
        -Actual ([int]$MigratedStatus.schemaVersion)

    $RecoveryOperationId = [guid]::NewGuid().ToString('N')
    $RecoveryBackupRoot = Join-Path $TestRoot '.tri-tier-backups'
    $RecoveryBackup = Join-Path $RecoveryBackupRoot (
        'isolated-recovery-' + $RecoveryOperationId
    )
    New-Item -ItemType Directory -Path $RecoveryBackupRoot -Force | Out-Null
    Move-Item `
        -LiteralPath $InstallTarget `
        -Destination $RecoveryBackup

    $RecoveryJournalPath = Get-TriTierInstallJournalPath `
        -TargetRoot $InstallTarget
    $RecoveryJournal = [ordered]@{
        product = 'tri-tier-agent-system'
        journalSchemaVersion = 1
        operationId = $RecoveryOperationId
        operation = 'UPGRADE'
        state = 'BACKED_UP'
        targetRoot = $InstallTarget
        stageRoot = (Join-Path $TestRoot ".tri-tier-stage-$RecoveryOperationId")
        backupPath = $RecoveryBackup
        installId = [string]$MigratedStatus.installId
        startedUtc = (Get-Date).ToUniversalTime().ToString('o')
    }
    [System.IO.File]::WriteAllText(
        $RecoveryJournalPath,
        (
            $RecoveryJournal |
                ConvertTo-Json -Depth 40
        ) + [Environment]::NewLine,
        [System.Text.UTF8Encoding]::new($false)
    )

    $RecoveryResult = Repair-TriTierInstallation `
        -TargetRoot $InstallTarget

    Test-EqualValue `
        -Name 'Interrupted replacement restores backup' `
        -Expected 'RESTORED_BACKUP' `
        -Actual ([string]$RecoveryResult.action)

    $RecoveredStatus = Get-TriTierInstallStatus `
        -TargetRoot $InstallTarget

    Test-EqualValue `
        -Name 'Recovered installation is healthy' `
        -Expected $true `
        -Actual ([bool]$RecoveredStatus.healthy)

    Test-Condition `
        -Name 'Recovery journal is removed' `
        -Value (
            -not (
                Test-Path `
                    -LiteralPath $RecoveryJournalPath `
                    -PathType Leaf
            )
        )

    $UninstallPlan = New-TriTierUninstallPlan `
        -TargetRoot $InstallTarget

    Test-EqualValue `
        -Name 'Healthy install can be reversibly uninstalled' `
        -Expected $true `
        -Actual ([bool]$UninstallPlan.canApply)

    $UninstallResult = Invoke-TriTierUninstall `
        -TargetRoot $InstallTarget `
        -ConfirmTarget $InstallTarget `
        -ConfirmInstallId $RecoveredStatus.installId

    Test-EqualValue `
        -Name 'Reversible uninstall completes' `
        -Expected 'COMPLETE' `
        -Actual ([string]$UninstallResult.status)

    Test-EqualValue `
        -Name 'Uninstall deletes no owned payload' `
        -Expected $false `
        -Actual ([bool]$UninstallResult.deleted)

    Test-Condition `
        -Name 'Uninstall quarantines prior installation' `
        -Value (
            Test-Path `
                -LiteralPath $UninstallResult.quarantinePath `
                -PathType Container
        )

    Test-EqualValue `
        -Name 'Target is absent after uninstall' `
        -Expected 'NOT_INSTALLED' `
        -Actual (
            [string](
                Get-TriTierInstallStatus `
                    -TargetRoot $InstallTarget
            ).status
        )

    Write-Host ''
    Write-Host 'Installation, migration, recovery, and uninstall tests passed.' `
        -ForegroundColor Green
}
finally {
    if (Test-Path -LiteralPath $TestRoot) {
        Remove-Item -LiteralPath $TestRoot -Recurse -Force
    }
}
