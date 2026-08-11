Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepositoryRoot = Split-Path $PSScriptRoot -Parent
$ModulePath = Join-Path $RepositoryRoot 'src\TriTier\Installation.psm1'
$CliPath = Join-Path $RepositoryRoot 'src\tri-agent.ps1'
$InstallationModule = Import-Module $ModulePath -PassThru
$TestRoot = Join-Path $env:TEMP ('tri-tier-phase9r-' + [guid]::NewGuid().ToString('N'))
$SourceRoot = $RepositoryRoot

function Assert-True {
    param([string]$Name, [bool]$Value)
    if (-not $Value) { throw "$Name failed." }
}

function Assert-False {
    param([string]$Name, [bool]$Value)
    Assert-True -Name $Name -Value (-not $Value)
}

function Assert-Equal {
    param([string]$Name, [object]$Expected, [object]$Actual)
    if ($Expected -ne $Actual) {
        throw "$Name failed. Expected '$Expected'. Actual '$Actual'."
    }
}

function Write-InstallJson {
    param([string]$Path, [object]$Value)
    [System.IO.File]::WriteAllText(
        $Path,
        (($Value | ConvertTo-Json -Depth 80) + [Environment]::NewLine),
        [System.Text.UTF8Encoding]::new($false)
    )
}

function Get-JournalPath {
    param([string]$TargetRoot)
    & $InstallationModule { param($Path) Get-TriTierInstallJournalPath -TargetRoot $Path } $TargetRoot
}

function New-HealthyInstall {
    param([string]$Name)
    $Target = Join-Path $TestRoot $Name
    $Result = Invoke-TriTierInstall -SourceRoot $SourceRoot -TargetRoot $Target -ConfirmTarget $Target
    Assert-Equal -Name "$Name install" -Expected 'COMPLETE' -Actual $Result.status
    $Target
}

try {
    New-Item -ItemType Directory -Path $TestRoot -Force | Out-Null

    $BoundaryRoot = Join-Path $TestRoot 'boundary'
    $BoundaryCases = @(
        @{ Path = 'child.txt'; Valid = $true }
        @{ Path = 'nested\file.txt'; Valid = $true }
        @{ Path = '.'; Valid = $true }
        @{ Path = '..\outside'; Valid = $false }
        @{ Path = '..\..\outside'; Valid = $false }
        @{ Path = (Join-Path $TestRoot 'other\file.txt'); Valid = $false }
        @{ Path = ($BoundaryRoot + '-escape\file.txt'); Valid = $false }
        @{ Path = 'nested/..\file.txt'; Valid = $true }
        @{ Path = 'NESTED\FILE.TXT'; Valid = $true }
        @{ Path = 'nested\'; Valid = $true }
        @{ Path = '\\server\share\escape'; Valid = $false }
        @{ Path = '\\?\C:\phase9r\escape'; Valid = $false }
        @{ Path = ''; Valid = $false }
    )

    foreach ($Case in $BoundaryCases) {
        $Result = & $InstallationModule {
            param($Path, $Root)
            Test-TriTierInstallPathBoundary -Path $Path -AuthorizedRoot $Root -BasePath $Root
        } $Case.Path $BoundaryRoot
        Assert-Equal -Name "boundary $($Case.Path)" -Expected $Case.Valid -Actual ([bool]$Result.valid)
    }

    $ReparseTarget = Join-Path $TestRoot 'reparse-target'
    $ReparseLink = Join-Path $TestRoot 'reparse-link'
    New-Item -ItemType Directory -Path $ReparseTarget -Force | Out-Null
    $ReparseCreated = $false
    try {
        New-Item -ItemType SymbolicLink -Path $ReparseLink -Target $ReparseTarget -ErrorAction Stop | Out-Null
        $ReparseCreated = $true
    }
    catch {
        Write-Host 'Reparse-point test skipped: symbolic-link creation unavailable.' -ForegroundColor Yellow
    }
    try {
        if ($ReparseCreated) {
        $ReparseResult = & $InstallationModule {
            param($Path, $Root)
            Test-TriTierInstallPathBoundary -Path $Path -AuthorizedRoot $Root -BasePath $Root
        } (Join-Path $ReparseLink 'escape.txt') $ReparseLink
        Assert-False -Name 'reparse-point escape rejected' -Value $ReparseResult.valid
        }
    }
    finally {
        if (Test-Path -LiteralPath $ReparseLink) {
            Remove-Item -LiteralPath $ReparseLink -Force
        }
    }

    $Target = Join-Path $TestRoot 'invalid-journal-target'
    $Outside = Join-Path $TestRoot 'outside'
    New-Item -ItemType Directory -Path $Target, $Outside -Force | Out-Null
    $TargetMarker = Join-Path $Target 'untouched.txt'
    $OutsideMarker = Join-Path $Outside 'untouched.txt'
    [System.IO.File]::WriteAllText($TargetMarker, 'target')
    [System.IO.File]::WriteAllText($OutsideMarker, 'outside')
    $InvalidJournal = [ordered]@{
        product = 'tri-tier-agent-system'
        journalSchemaVersion = 1
        operationId = [guid]::NewGuid().ToString('N')
        operation = 'INSTALL'
        state = 'STAGED'
        targetRoot = $Target
        stageRoot = $Outside
        backupPath = ''
        installId = 'synthetic'
    }
    $InvalidJournalPath = Get-JournalPath -TargetRoot $Target
    Write-InstallJson -Path $InvalidJournalPath -Value $InvalidJournal
    $Rejected = $false
    try { Repair-TriTierInstallation -TargetRoot $Target | Out-Null } catch { $Rejected = $true }
    Assert-True -Name 'unsafe journal path rejected' -Value $Rejected
    Assert-Equal -Name 'target survives unsafe journal rejection' -Expected 'target' -Actual ([System.IO.File]::ReadAllText($TargetMarker))
    Assert-Equal -Name 'outside survives unsafe journal rejection' -Expected 'outside' -Actual ([System.IO.File]::ReadAllText($OutsideMarker))

    $HealthTarget = New-HealthyInstall -Name 'health-target'
    $HealthStatus = Get-TriTierInstallStatus -TargetRoot $HealthTarget
    Assert-True -Name 'healthy install health' -Value $HealthStatus.healthy
    $RequiredFile = Join-Path $HealthTarget 'src\tri-agent.ps1'
    Add-Content -LiteralPath $RequiredFile -Value '# modified'
    $ModifiedStatus = Get-TriTierInstallStatus -TargetRoot $HealthTarget
    Assert-False -Name 'modified payload unhealthy' -Value $ModifiedStatus.healthy
    $ModifiedMigration = New-TriTierMigrationPlan -SourceRoot $SourceRoot -TargetRoot $HealthTarget
    Assert-False -Name 'migration rejects modified source' -Value $ModifiedMigration.canApply

    $MissingTarget = New-HealthyInstall -Name 'missing-target'
    Remove-Item -LiteralPath (Join-Path $MissingTarget 'src\tri-agent.ps1') -Force
    $MissingStatus = Get-TriTierInstallStatus -TargetRoot $MissingTarget
    Assert-False -Name 'missing required payload unhealthy' -Value $MissingStatus.healthy

    $CorruptTarget = New-HealthyInstall -Name 'corrupt-journal-target'
    $CorruptMarker = Join-Path $CorruptTarget 'src\tri-agent.ps1'
    $CorruptBefore = (Get-FileHash -LiteralPath $CorruptMarker -Algorithm SHA256).Hash
    $CorruptJournalPath = Get-JournalPath -TargetRoot $CorruptTarget
    [System.IO.File]::WriteAllText($CorruptJournalPath, '{')
    $CorruptRejected = $false
    try { Repair-TriTierInstallation -TargetRoot $CorruptTarget | Out-Null } catch { $CorruptRejected = $true }
    Assert-True -Name 'corrupt journal rejected' -Value $CorruptRejected
    Assert-Equal -Name 'corrupt journal preserves target' -Expected $CorruptBefore -Actual ((Get-FileHash -LiteralPath $CorruptMarker -Algorithm SHA256).Hash)

    $SchemaTarget = New-HealthyInstall -Name 'schema-target'
    $SchemaStatus = Get-TriTierInstallStatus -TargetRoot $SchemaTarget
    $SchemaOperationId = [guid]::NewGuid().ToString('N')
    $SchemaStage = Join-Path (Split-Path -Parent $SchemaTarget) ".tri-tier-stage-$SchemaOperationId"
    $SchemaJournal = [ordered]@{
        product = 'tri-tier-agent-system'
        journalSchemaVersion = 99
        operationId = $SchemaOperationId
        operation = 'INSTALL'
        state = 'STAGED'
        targetRoot = $SchemaTarget
        stageRoot = $SchemaStage
        backupPath = ''
        installId = [string]$SchemaStatus.installId
    }
    $SchemaJournalPath = Get-JournalPath -TargetRoot $SchemaTarget
    Write-InstallJson -Path $SchemaJournalPath -Value $SchemaJournal
    $SchemaRejected = $false
    try { Repair-TriTierInstallation -TargetRoot $SchemaTarget | Out-Null } catch { $SchemaRejected = $true }
    Assert-True -Name 'unsupported journal schema rejected' -Value $SchemaRejected
    Assert-True -Name 'unsupported schema leaves target' -Value (Test-Path -LiteralPath $SchemaTarget -PathType Container)

    $RecoveryTarget = New-HealthyInstall -Name 'restart-target'
    $RecoveryStatus = Get-TriTierInstallStatus -TargetRoot $RecoveryTarget
    $RecoveryOperationId = [guid]::NewGuid().ToString('N')
    $RecoveryBackupRoot = Join-Path (Split-Path -Parent $RecoveryTarget) '.tri-tier-backups'
    $RecoveryBackup = Join-Path $RecoveryBackupRoot ('restart-target-' + $RecoveryOperationId)
    New-Item -ItemType Directory -Path $RecoveryBackupRoot -Force | Out-Null
    Move-Item -LiteralPath $RecoveryTarget -Destination $RecoveryBackup
    $RecoveryStage = Join-Path (Split-Path -Parent $RecoveryTarget) ".tri-tier-stage-$RecoveryOperationId"
    $RecoveryJournal = [ordered]@{
        product = 'tri-tier-agent-system'
        journalSchemaVersion = 1
        operationId = $RecoveryOperationId
        operation = 'UPGRADE'
        state = 'BACKED_UP'
        targetRoot = $RecoveryTarget
        stageRoot = $RecoveryStage
        backupPath = $RecoveryBackup
        installId = [string]$RecoveryStatus.installId
    }
    Write-InstallJson -Path (Get-JournalPath -TargetRoot $RecoveryTarget) -Value $RecoveryJournal
    $RecoveryOutput = @(& pwsh -NoLogo -NoProfile -File $CliPath install-recover -InstallRoot $RecoveryTarget -Json 2>&1 | ForEach-Object { [string]$_ })
    Assert-Equal -Name 'restart recovery child process' -Expected 0 -Actual $LASTEXITCODE
    $RecoveryResult = ($RecoveryOutput -join [Environment]::NewLine) | ConvertFrom-Json -Depth 80
    Assert-Equal -Name 'restart recovery action' -Expected 'RESTORED_BACKUP' -Actual $RecoveryResult.action
    Assert-True -Name 'restart recovery healthy' -Value (Get-TriTierInstallStatus -TargetRoot $RecoveryTarget).healthy

    Write-Host 'Phase 9R adoption blocker tests passed.' -ForegroundColor Green
}
finally {
    if (Test-Path -LiteralPath $TestRoot) {
        Remove-Item -LiteralPath $TestRoot -Recurse -Force
    }
}
