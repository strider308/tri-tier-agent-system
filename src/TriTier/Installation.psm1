Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:TriTierInstallProduct = 'tri-tier-agent-system'
$script:TriTierInstallVersion = '0.10.0-alpha'
$script:TriTierInstallSchemaVersion = 2
$script:TriTierMinimumPowerShellVersion = [version]'7.4.0'

function Get-TriTierInstallProperty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter()]
        [object]$DefaultValue = $null
    )

    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) {
            return $InputObject[$Name]
        }

        return $DefaultValue
    }

    $Property = $InputObject.PSObject.Properties[$Name]

    if ($null -eq $Property) {
        return $DefaultValue
    }

    $Property.Value
}

function ConvertTo-TriTierInstallHashtable {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [System.Collections.IDictionary]) {
        $Converted = [ordered]@{}

        foreach ($Key in $Value.Keys) {
            $Converted[[string]$Key] = ConvertTo-TriTierInstallHashtable `
                -Value $Value[$Key]
        }

        return ,$Converted
    }

    if (
        $Value -is [System.Collections.IEnumerable] -and
        -not ($Value -is [string])
    ) {
        $ConvertedItems = @(
            foreach ($Item in $Value) {
                ConvertTo-TriTierInstallHashtable -Value $Item
            }
        )

        return ,$ConvertedItems
    }

    if (
        $Value -is [pscustomobject] -or
        (
            -not ($Value -is [System.ValueType]) -and
            -not ($Value -is [string]) -and
            @($Value.PSObject.Properties).Count -gt 0
        )
    ) {
        $Converted = [ordered]@{}

        foreach ($Property in $Value.PSObject.Properties) {
            $Converted[$Property.Name] = ConvertTo-TriTierInstallHashtable `
                -Value $Property.Value
        }

        return ,$Converted
    }

    return $Value
}

function Get-TriTierInstallFullPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    [System.IO.Path]::GetFullPath(
        [Environment]::ExpandEnvironmentVariables($Path)
    ).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
}

function Test-TriTierInstallPathWithin {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ChildPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ParentPath
    )

    $ResolvedChild = Get-TriTierInstallFullPath -Path $ChildPath
    $ResolvedParent = Get-TriTierInstallFullPath -Path $ParentPath
    $Comparison = [System.StringComparison]::OrdinalIgnoreCase

    if ([string]::Equals($ResolvedChild, $ResolvedParent, $Comparison)) {
        return $true
    }

    $Prefix = $ResolvedParent + [System.IO.Path]::DirectorySeparatorChar
    $ResolvedChild.StartsWith($Prefix, $Comparison)
}

function Get-TriTierDefaultInstallRoot {
    [CmdletBinding()]
    param()

    $BasePath = [string]$env:LOCALAPPDATA

    if ([string]::IsNullOrWhiteSpace($BasePath)) {
        $BasePath = Join-Path $HOME 'AppData\Local'
    }

    Get-TriTierInstallFullPath -Path (
        Join-Path $BasePath 'TriTierAgentSystem\isolated'
    )
}

function Get-TriTierProtectedInstallRoots {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$SourceRoot = ''
    )

    $Roots = [System.Collections.Generic.List[string]]::new()

    foreach ($Candidate in @(
        (Join-Path $HOME '.codex')
        [string]$env:CODEX_HOME
        $SourceRoot
    )) {
        if ([string]::IsNullOrWhiteSpace($Candidate)) {
            continue
        }

        try {
            $ResolvedCandidate = Get-TriTierInstallFullPath -Path $Candidate
        }
        catch {
            continue
        }

        if (-not $Roots.Contains($ResolvedCandidate)) {
            $Roots.Add($ResolvedCandidate)
        }
    }

    @($Roots)
}

function Test-TriTierInstallTarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$TargetRoot,

        [Parameter()]
        [string]$SourceRoot = ''
    )

    $Reasons = [System.Collections.Generic.List[string]]::new()
    $ResolvedTarget = ''

    try {
        $ResolvedTarget = Get-TriTierInstallFullPath -Path $TargetRoot
    }
    catch {
        $Reasons.Add('Target path cannot be normalized.')
    }

    if (-not [string]::IsNullOrWhiteSpace($ResolvedTarget)) {
        $TargetPathRoot = [System.IO.Path]::GetPathRoot($ResolvedTarget)

        if (
            [string]::Equals(
                $ResolvedTarget,
                $TargetPathRoot.TrimEnd('\', '/'),
                [System.StringComparison]::OrdinalIgnoreCase
            )
        ) {
            $Reasons.Add('Installation target cannot be a filesystem root.')
        }

        if ($ResolvedTarget.Length -gt 180) {
            $Reasons.Add(
                'Installation target is too long for reliable Windows tooling.'
            )
        }

        foreach (
            $ProtectedRoot in @(
                Get-TriTierProtectedInstallRoots -SourceRoot $SourceRoot
            )
        ) {
            if (
                (Test-TriTierInstallPathWithin `
                    -ChildPath $ResolvedTarget `
                    -ParentPath $ProtectedRoot) -or
                (Test-TriTierInstallPathWithin `
                    -ChildPath $ProtectedRoot `
                    -ParentPath $ResolvedTarget)
            ) {
                $Reasons.Add(
                    "Installation target overlaps protected root: $ProtectedRoot"
                )
            }
        }

        if (Test-Path -LiteralPath $ResolvedTarget) {
            $TargetItem = Get-Item -LiteralPath $ResolvedTarget -Force

            if (
                ($TargetItem.Attributes -band
                    [System.IO.FileAttributes]::ReparsePoint) -ne 0
            ) {
                $Reasons.Add(
                    'Installation target cannot be a symbolic link or reparse point.'
                )
            }
        }

        $Ancestor = Split-Path -Parent $ResolvedTarget

        while (
            -not [string]::IsNullOrWhiteSpace($Ancestor) -and
            (Test-Path -LiteralPath $Ancestor)
        ) {
            $AncestorItem = Get-Item -LiteralPath $Ancestor -Force

            if (
                ($AncestorItem.Attributes -band
                    [System.IO.FileAttributes]::ReparsePoint) -ne 0
            ) {
                $Reasons.Add(
                    "Installation ancestor is a reparse point: $Ancestor"
                )
                break
            }

            $NextAncestor = Split-Path -Parent $Ancestor

            if ($NextAncestor -eq $Ancestor) {
                break
            }

            $Ancestor = $NextAncestor
        }
    }

    [PSCustomObject][ordered]@{
        valid = ($Reasons.Count -eq 0)
        targetRoot = $ResolvedTarget
        protectedRoots = @(
            Get-TriTierProtectedInstallRoots -SourceRoot $SourceRoot
        )
        reasons = @($Reasons)
    }
}

function Get-TriTierInstallManifestPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$TargetRoot
    )

    Join-Path (
        Get-TriTierInstallFullPath -Path $TargetRoot
    ) 'install-manifest.json'
}

function Get-TriTierInstallJournalPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$TargetRoot
    )

    $ResolvedTarget = Get-TriTierInstallFullPath -Path $TargetRoot
    $Parent = Split-Path -Parent $ResolvedTarget
    $Leaf = Split-Path -Leaf $ResolvedTarget
    $SafeLeaf = $Leaf -replace '[^A-Za-z0-9._-]', '_'

    Join-Path $Parent ".tri-tier-$SafeLeaf-install-transaction.json"
}


function Get-TriTierInstallLockPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$TargetRoot
    )

    (Get-TriTierInstallJournalPath -TargetRoot $TargetRoot) + '.lock'
}

function New-TriTierInstallLockHandle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$TargetRoot
    )

    $LockPath = Get-TriTierInstallLockPath -TargetRoot $TargetRoot
    $LockDirectory = Split-Path -Parent $LockPath
    New-Item -ItemType Directory -Path $LockDirectory -Force | Out-Null

    try {
        [System.IO.File]::Open(
            $LockPath,
            [System.IO.FileMode]::OpenOrCreate,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::None
        )
    }
    catch {
        throw (
            'Another installation operation owns the isolated target lock: ' +
            $LockPath
        )
    }
}

function Get-TriTierInstallJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    $Raw = [System.IO.File]::ReadAllText($Path)

    if ([string]::IsNullOrWhiteSpace($Raw)) {
        return $null
    }

    ConvertTo-TriTierInstallHashtable -Value (
        $Raw | ConvertFrom-Json -Depth 80
    )
}

function Set-TriTierInstallJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Value
    )

    $Directory = Split-Path -Parent $Path

    if (-not [string]::IsNullOrWhiteSpace($Directory)) {
        New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    }

    $TemporaryPath = "$Path.tmp-$([guid]::NewGuid().ToString('N'))"
    $Json = $Value | ConvertTo-Json -Depth 80

    try {
        [System.IO.File]::WriteAllText(
            $TemporaryPath,
            $Json + [Environment]::NewLine,
            [System.Text.UTF8Encoding]::new($false)
        )

        Move-Item `
            -LiteralPath $TemporaryPath `
            -Destination $Path `
            -Force
    }
    finally {
        if (Test-Path -LiteralPath $TemporaryPath) {
            Remove-Item -LiteralPath $TemporaryPath -Force
        }
    }
}

function Get-TriTierInstallManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$TargetRoot
    )

    Get-TriTierInstallJson -Path (
        Get-TriTierInstallManifestPath -TargetRoot $TargetRoot
    )
}

function Test-TriTierInstallManifest {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$Manifest
    )

    $Reasons = [System.Collections.Generic.List[string]]::new()

    if ($null -eq $Manifest) {
        $Reasons.Add('Installation manifest is missing.')
    }
    else {
        $Product = [string](
            Get-TriTierInstallProperty `
                -InputObject $Manifest `
                -Name 'product' `
                -DefaultValue ''
        )
        $InstallId = [string](
            Get-TriTierInstallProperty `
                -InputObject $Manifest `
                -Name 'installId' `
                -DefaultValue ''
        )
        $Version = [string](
            Get-TriTierInstallProperty `
                -InputObject $Manifest `
                -Name 'version' `
                -DefaultValue ''
        )
        $SchemaVersion = [int](
            Get-TriTierInstallProperty `
                -InputObject $Manifest `
                -Name 'schemaVersion' `
                -DefaultValue 1
        )

        if ($Product -ne $script:TriTierInstallProduct) {
            $Reasons.Add('Installation manifest product is not owned by Tri-Tier.')
        }

        if ([string]::IsNullOrWhiteSpace($InstallId)) {
            $Reasons.Add('Installation manifest installId is missing.')
        }

        if ([string]::IsNullOrWhiteSpace($Version)) {
            $Reasons.Add('Installation manifest version is missing.')
        }

        if ($SchemaVersion -notin @(1, 2)) {
            $Reasons.Add(
                "Unsupported installation manifest schema: $SchemaVersion"
            )
        }
    }

    [PSCustomObject][ordered]@{
        valid = ($Reasons.Count -eq 0)
        reasons = @($Reasons)
    }
}

function Get-TriTierInstallSourceFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SourceRoot
    )

    $ResolvedSource = Get-TriTierInstallFullPath -Path $SourceRoot

    foreach ($RequiredRelativePath in @(
        'src\tri-agent.ps1'
        'src\tri-agent.cmd'
        'src\TriTier\AgentProfiles.psm1'
        'src\TriTier\ExecutionLoop.psm1'
        'agents\luna-worker.toml'
        'agents\terra-manager.toml'
        'agents\sol-architect.toml'
    )) {
        $RequiredPath = Join-Path $ResolvedSource $RequiredRelativePath

        if (-not (Test-Path -LiteralPath $RequiredPath -PathType Leaf)) {
            throw "Required installation source file is missing: $RequiredPath"
        }
    }

    $Files = [System.Collections.Generic.List[object]]::new()

    foreach ($RelativeDirectory in @('src', 'agents', 'docs')) {
        $Directory = Join-Path $ResolvedSource $RelativeDirectory

        if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
            continue
        }

        foreach (
            $File in @(
                Get-ChildItem `
                    -LiteralPath $Directory `
                    -File `
                    -Recurse |
                    Sort-Object FullName
            )
        ) {
            $RelativePath = [System.IO.Path]::GetRelativePath(
                $ResolvedSource,
                $File.FullName
            )

            $Files.Add(
                [PSCustomObject][ordered]@{
                    relativePath = $RelativePath
                    sourcePath = $File.FullName
                    sha256 = (
                        Get-FileHash `
                            -LiteralPath $File.FullName `
                            -Algorithm SHA256
                    ).Hash.ToLowerInvariant()
                    length = [long]$File.Length
                }
            )
        }
    }

    foreach ($RelativeFile in @(
        'README.md'
        'LICENSE'
        'NOTICE'
        'SECURITY.md'
    )) {
        $FilePath = Join-Path $ResolvedSource $RelativeFile

        if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
            continue
        }

        $FileItem = Get-Item -LiteralPath $FilePath
        $Files.Add(
            [PSCustomObject][ordered]@{
                relativePath = $RelativeFile
                sourcePath = $FilePath
                sha256 = (
                    Get-FileHash `
                        -LiteralPath $FilePath `
                        -Algorithm SHA256
                ).Hash.ToLowerInvariant()
                length = [long]$FileItem.Length
            }
        )
    }

    @($Files)
}

function Test-TriTierInstallPowerShellFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    $Tokens = $null
    $ParseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $Path,
        [ref]$Tokens,
        [ref]$ParseErrors
    )

    [PSCustomObject][ordered]@{
        valid = (@($ParseErrors).Count -eq 0)
        errors = @(
            $ParseErrors |
                ForEach-Object {
                    [PSCustomObject][ordered]@{
                        line = $_.Extent.StartLineNumber
                        column = $_.Extent.StartColumnNumber
                        message = $_.Message
                    }
                }
        )
    }
}

function Get-TriTierCompatibilityReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SourceRoot,

        [Parameter()]
        [string]$TargetRoot = ''
    )

    $ResolvedSource = Get-TriTierInstallFullPath -Path $SourceRoot
    $ResolvedTarget = if ([string]::IsNullOrWhiteSpace($TargetRoot)) {
        Get-TriTierDefaultInstallRoot
    }
    else {
        Get-TriTierInstallFullPath -Path $TargetRoot
    }

    $Checks = [System.Collections.Generic.List[object]]::new()
    $IsWindowsPlatform = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [System.Runtime.InteropServices.OSPlatform]::Windows
    )

    $Checks.Add(
        [PSCustomObject][ordered]@{
            name = 'Windows platform'
            status = if ($IsWindowsPlatform) { 'PASS' } else { 'FAIL' }
            detail = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
            required = $true
        }
    )

    $PowerShellCompatible = $PSVersionTable.PSVersion -ge
        $script:TriTierMinimumPowerShellVersion

    $Checks.Add(
        [PSCustomObject][ordered]@{
            name = 'PowerShell version'
            status = if ($PowerShellCompatible) { 'PASS' } else { 'FAIL' }
            detail = [string]$PSVersionTable.PSVersion
            required = $true
        }
    )

    $TargetCheck = Test-TriTierInstallTarget `
        -TargetRoot $ResolvedTarget `
        -SourceRoot $ResolvedSource

    $Checks.Add(
        [PSCustomObject][ordered]@{
            name = 'Isolated target'
            status = if ($TargetCheck.valid) { 'PASS' } else { 'FAIL' }
            detail = if ($TargetCheck.valid) {
                $ResolvedTarget
            }
            else {
                $TargetCheck.reasons -join '; '
            }
            required = $true
        }
    )

    $SourceFilesValid = $true
    $SourceDetail = ''

    try {
        $SourceFiles = @(
            Get-TriTierInstallSourceFiles -SourceRoot $ResolvedSource
        )
        $SourceDetail = "$($SourceFiles.Count) source files"
    }
    catch {
        $SourceFilesValid = $false
        $SourceDetail = $_.Exception.Message
        $SourceFiles = @()
    }

    $Checks.Add(
        [PSCustomObject][ordered]@{
            name = 'Source payload'
            status = if ($SourceFilesValid) { 'PASS' } else { 'FAIL' }
            detail = $SourceDetail
            required = $true
        }
    )

    $PowerShellPayloadValid = $true
    $PowerShellErrors = [System.Collections.Generic.List[string]]::new()

    foreach (
        $SourceFile in @(
            $SourceFiles |
                Where-Object {
                    [System.IO.Path]::GetExtension(
                        [string]$_.sourcePath
                    ) -in @('.ps1', '.psm1')
                }
        )
    ) {
        $ParseResult = Test-TriTierInstallPowerShellFile `
            -Path $SourceFile.sourcePath

        if (-not $ParseResult.valid) {
            $PowerShellPayloadValid = $false

            foreach ($ParseError in $ParseResult.errors) {
                $PowerShellErrors.Add(
                    "$($SourceFile.relativePath):$($ParseError.line): " +
                    $ParseError.message
                )
            }
        }
    }

    $Checks.Add(
        [PSCustomObject][ordered]@{
            name = 'PowerShell payload parsing'
            status = if ($PowerShellPayloadValid) { 'PASS' } else { 'FAIL' }
            detail = if ($PowerShellPayloadValid) {
                'All source PowerShell files parse.'
            }
            else {
                $PowerShellErrors -join '; '
            }
            required = $true
        }
    )

    $CodexCommand = Get-Command codex -ErrorAction SilentlyContinue
    $Checks.Add(
        [PSCustomObject][ordered]@{
            name = 'Codex CLI'
            status = if ($null -eq $CodexCommand) { 'INFO' } else { 'PASS' }
            detail = if ($null -eq $CodexCommand) {
                'Codex is optional for isolated installation.'
            }
            else {
                [string]$CodexCommand.Source
            }
            required = $false
        }
    )

    $GitCommand = Get-Command git -ErrorAction SilentlyContinue
    $Checks.Add(
        [PSCustomObject][ordered]@{
            name = 'Git CLI'
            status = if ($null -eq $GitCommand) { 'INFO' } else { 'PASS' }
            detail = if ($null -eq $GitCommand) {
                'Git metadata will be omitted.'
            }
            else {
                [string]$GitCommand.Source
            }
            required = $false
        }
    )

    $RequiredFailures = @(
        $Checks |
            Where-Object {
                $_.required -and $_.status -ne 'PASS'
            }
    )

    [PSCustomObject][ordered]@{
        compatible = ($RequiredFailures.Count -eq 0)
        sourceRoot = $ResolvedSource
        targetRoot = $ResolvedTarget
        minimumPowerShellVersion = [string]$script:TriTierMinimumPowerShellVersion
        checks = @($Checks)
    }
}

function New-TriTierInstallPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SourceRoot,

        [Parameter()]
        [string]$TargetRoot = ''
    )

    $ResolvedSource = Get-TriTierInstallFullPath -Path $SourceRoot
    $ResolvedTarget = if ([string]::IsNullOrWhiteSpace($TargetRoot)) {
        Get-TriTierDefaultInstallRoot
    }
    else {
        Get-TriTierInstallFullPath -Path $TargetRoot
    }

    $Compatibility = Get-TriTierCompatibilityReport `
        -SourceRoot $ResolvedSource `
        -TargetRoot $ResolvedTarget
    $ExistingManifest = Get-TriTierInstallManifest -TargetRoot $ResolvedTarget
    $ManifestCheck = Test-TriTierInstallManifest -Manifest $ExistingManifest
    $ExistingState = if (-not (Test-Path -LiteralPath $ResolvedTarget)) {
        'MISSING'
    }
    elseif ($ManifestCheck.valid) {
        'OWNED'
    }
    else {
        'UNMANAGED'
    }
    $SourceFiles = @(
        Get-TriTierInstallSourceFiles -SourceRoot $ResolvedSource
    )

    [PSCustomObject][ordered]@{
        operation = if ($ExistingState -eq 'OWNED') {
            'UPGRADE'
        }
        else {
            'INSTALL'
        }
        canApply = (
            $Compatibility.compatible -and
            $ExistingState -ne 'UNMANAGED'
        )
        sourceRoot = $ResolvedSource
        targetRoot = $ResolvedTarget
        version = $script:TriTierInstallVersion
        schemaVersion = $script:TriTierInstallSchemaVersion
        existingState = $ExistingState
        existingInstallId = if ($ManifestCheck.valid) {
            [string]$ExistingManifest.installId
        }
        else {
            ''
        }
        requiresInstallIdConfirmation = ($ExistingState -eq 'OWNED')
        fileCount = $SourceFiles.Count + 2
        privateCodexMutation = $false
        pathMutation = $false
        compatibility = $Compatibility
    }
}

function Get-TriTierInstallStatus {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$TargetRoot = ''
    )

    $ResolvedTarget = if ([string]::IsNullOrWhiteSpace($TargetRoot)) {
        Get-TriTierDefaultInstallRoot
    }
    else {
        Get-TriTierInstallFullPath -Path $TargetRoot
    }

    if (-not (Test-Path -LiteralPath $ResolvedTarget -PathType Container)) {
        return [PSCustomObject][ordered]@{
            status = 'NOT_INSTALLED'
            targetRoot = $ResolvedTarget
            owned = $false
            healthy = $false
            version = ''
            schemaVersion = 0
            installId = ''
            modifiedFiles = @()
            missingFiles = @()
        }
    }

    $Manifest = Get-TriTierInstallManifest -TargetRoot $ResolvedTarget
    $ManifestCheck = Test-TriTierInstallManifest -Manifest $Manifest

    if (-not $ManifestCheck.valid) {
        return [PSCustomObject][ordered]@{
            status = 'UNMANAGED'
            targetRoot = $ResolvedTarget
            owned = $false
            healthy = $false
            version = ''
            schemaVersion = 0
            installId = ''
            modifiedFiles = @()
            missingFiles = @()
            reasons = $ManifestCheck.reasons
        }
    }

    $ModifiedFiles = [System.Collections.Generic.List[string]]::new()
    $MissingFiles = [System.Collections.Generic.List[string]]::new()
    $ManifestFiles = @(
        Get-TriTierInstallProperty `
            -InputObject $Manifest `
            -Name 'files' `
            -DefaultValue @()
    )

    foreach ($ManifestFile in $ManifestFiles) {
        $RelativePath = [string](
            Get-TriTierInstallProperty `
                -InputObject $ManifestFile `
                -Name 'relativePath' `
                -DefaultValue ''
        )
        $ExpectedHash = [string](
            Get-TriTierInstallProperty `
                -InputObject $ManifestFile `
                -Name 'sha256' `
                -DefaultValue ''
        )

        if ([string]::IsNullOrWhiteSpace($RelativePath)) {
            continue
        }

        $InstalledPath = Join-Path $ResolvedTarget $RelativePath

        if (-not (Test-Path -LiteralPath $InstalledPath -PathType Leaf)) {
            $MissingFiles.Add($RelativePath)
            continue
        }

        $ActualHash = (
            Get-FileHash `
                -LiteralPath $InstalledPath `
                -Algorithm SHA256
        ).Hash.ToLowerInvariant()

        if ($ActualHash -ne $ExpectedHash.ToLowerInvariant()) {
            $ModifiedFiles.Add($RelativePath)
        }
    }

    $Healthy = (
        $ModifiedFiles.Count -eq 0 -and
        $MissingFiles.Count -eq 0
    )

    [PSCustomObject][ordered]@{
        status = if ($Healthy) { 'INSTALLED' } else { 'DRIFTED' }
        targetRoot = $ResolvedTarget
        owned = $true
        healthy = $Healthy
        version = [string]$Manifest.version
        schemaVersion = [int](
            Get-TriTierInstallProperty `
                -InputObject $Manifest `
                -Name 'schemaVersion' `
                -DefaultValue 1
        )
        installId = [string]$Manifest.installId
        modifiedFiles = @($ModifiedFiles)
        missingFiles = @($MissingFiles)
    }
}

function Invoke-TriTierInstall {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SourceRoot,

        [Parameter()]
        [string]$TargetRoot = '',

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ConfirmTarget,

        [Parameter()]
        [string]$ConfirmInstallId = ''
    )

    $Plan = New-TriTierInstallPlan `
        -SourceRoot $SourceRoot `
        -TargetRoot $TargetRoot

    if (-not $Plan.canApply) {
        throw 'Installation plan is blocked.'
    }

    $ResolvedTarget = [string]$Plan.targetRoot
    $ResolvedConfirmation = Get-TriTierInstallFullPath -Path $ConfirmTarget

    if (
        -not [string]::Equals(
            $ResolvedTarget,
            $ResolvedConfirmation,
            [System.StringComparison]::OrdinalIgnoreCase
        )
    ) {
        throw 'ConfirmTarget must exactly match the normalized target root.'
    }

    $ExistingManifest = Get-TriTierInstallManifest -TargetRoot $ResolvedTarget
    $ExistingManifestCheck = Test-TriTierInstallManifest `
        -Manifest $ExistingManifest
    $ExistingOwned = $ExistingManifestCheck.valid

    if ($ExistingOwned) {
        $ExistingInstallId = [string]$ExistingManifest.installId

        if (
            [string]::IsNullOrWhiteSpace($ConfirmInstallId) -or
            $ConfirmInstallId -ne $ExistingInstallId
        ) {
            throw (
                'Existing installation requires its exact installId through ' +
                'ConfirmInstallId.'
            )
        }
    }

    $Parent = Split-Path -Parent $ResolvedTarget
    $Leaf = Split-Path -Leaf $ResolvedTarget
    $OperationId = [guid]::NewGuid().ToString('N')
    $StageRoot = Join-Path $Parent ".tri-tier-stage-$OperationId"
    $BackupRoot = Join-Path $Parent '.tri-tier-backups'
    $BackupPath = Join-Path $BackupRoot (
        "$Leaf-$((Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ'))-" +
        $OperationId
    )
    $JournalPath = Get-TriTierInstallJournalPath -TargetRoot $ResolvedTarget
    $InstalledTargetCreated = $false
    $ExistingTargetMoved = $false
    $ResolvedInstallId = if ($ExistingOwned) {
        [string]$ExistingManifest.installId
    }
    else {
        [guid]::NewGuid().ToString()
    }

    New-Item -ItemType Directory -Path $Parent -Force | Out-Null
    $InstallLockHandle = New-TriTierInstallLockHandle `
        -TargetRoot $ResolvedTarget

    try {
        if (Test-Path -LiteralPath $JournalPath) {
        throw (
            'An unfinished installation transaction exists. Run recovery first: ' +
            $JournalPath
        )
    }

    $Journal = [ordered]@{
        product = $script:TriTierInstallProduct
        operationId = $OperationId
        operation = if ($ExistingOwned) { 'UPGRADE' } else { 'INSTALL' }
        state = 'PREPARED'
        targetRoot = $ResolvedTarget
        stageRoot = $StageRoot
        backupPath = if ($ExistingOwned) { $BackupPath } else { '' }
        installId = $ResolvedInstallId
        startedUtc = (Get-Date).ToUniversalTime().ToString('o')
    }

    Set-TriTierInstallJson -Path $JournalPath -Value $Journal

    try {
        New-Item -ItemType Directory -Path $StageRoot -Force | Out-Null
        $SourceFiles = @(
            Get-TriTierInstallSourceFiles -SourceRoot $Plan.sourceRoot
        )

        foreach ($SourceFile in $SourceFiles) {
            $DestinationPath = Join-Path `
                $StageRoot `
                ([string]$SourceFile.relativePath)
            $DestinationDirectory = Split-Path -Parent $DestinationPath

            New-Item `
                -ItemType Directory `
                -Path $DestinationDirectory `
                -Force |
                Out-Null

            Copy-Item `
                -LiteralPath $SourceFile.sourcePath `
                -Destination $DestinationPath `
                -Force
        }

        $BinRoot = Join-Path $StageRoot 'bin'
        New-Item -ItemType Directory -Path $BinRoot -Force | Out-Null

        $PowerShellLauncher = @'
$Root = Split-Path -Parent $PSScriptRoot
$CliPath = Join-Path $Root 'src\tri-agent.ps1'
& $CliPath @args
exit $LASTEXITCODE
'@

        $CmdLauncher = @'
@echo off
pwsh -NoLogo -NoProfile -File "%~dp0tri-agent.ps1" %*
exit /b %ERRORLEVEL%
'@

        [System.IO.File]::WriteAllText(
            (Join-Path $BinRoot 'tri-agent.ps1'),
            $PowerShellLauncher.TrimStart() + [Environment]::NewLine,
            [System.Text.UTF8Encoding]::new($false)
        )
        [System.IO.File]::WriteAllText(
            (Join-Path $BinRoot 'tri-agent.cmd'),
            $CmdLauncher.TrimStart().Replace("`n", "`r`n"),
            [System.Text.ASCIIEncoding]::new()
        )

        foreach (
            $PowerShellFile in @(
                Get-ChildItem `
                    -LiteralPath $StageRoot `
                    -File `
                    -Recurse |
                    Where-Object {
                        $_.Extension -in @('.ps1', '.psm1')
                    }
            )
        ) {
            $ParseResult = Test-TriTierInstallPowerShellFile `
                -Path $PowerShellFile.FullName

            if (-not $ParseResult.valid) {
                throw (
                    'Staged PowerShell file does not parse: ' +
                    $PowerShellFile.FullName
                )
            }
        }

        $ManifestFiles = @(
            foreach (
                $InstalledFile in @(
                    Get-ChildItem `
                        -LiteralPath $StageRoot `
                        -File `
                        -Recurse |
                        Sort-Object FullName
                )
            ) {
                [PSCustomObject][ordered]@{
                    relativePath = [System.IO.Path]::GetRelativePath(
                        $StageRoot,
                        $InstalledFile.FullName
                    )
                    sha256 = (
                        Get-FileHash `
                            -LiteralPath $InstalledFile.FullName `
                            -Algorithm SHA256
                    ).Hash.ToLowerInvariant()
                    length = [long]$InstalledFile.Length
                }
            }
        )

        $SourceCommit = ''
        $GitCommand = Get-Command git -ErrorAction SilentlyContinue

        if ($null -ne $GitCommand) {
            $SourceCommitOutput = @(
                & $GitCommand.Source `
                    -C $Plan.sourceRoot `
                    rev-parse HEAD `
                    2>$null
            )

            if ($LASTEXITCODE -eq 0 -and $SourceCommitOutput.Count -gt 0) {
                $SourceCommit = ([string]$SourceCommitOutput[0]).Trim()
            }
        }

        $Manifest = [ordered]@{
            product = $script:TriTierInstallProduct
            schemaVersion = $script:TriTierInstallSchemaVersion
            version = $script:TriTierInstallVersion
            installId = $ResolvedInstallId
            installedUtc = (Get-Date).ToUniversalTime().ToString('o')
            sourceRoot = [string]$Plan.sourceRoot
            sourceCommit = $SourceCommit
            privateCodexMutation = $false
            pathMutation = $false
            files = $ManifestFiles
        }

        Set-TriTierInstallJson `
            -Path (Join-Path $StageRoot 'install-manifest.json') `
            -Value $Manifest

        $Journal.state = 'STAGED'
        Set-TriTierInstallJson -Path $JournalPath -Value $Journal

        if ($ExistingOwned) {
            New-Item `
                -ItemType Directory `
                -Path $BackupRoot `
                -Force |
                Out-Null

            Move-Item `
                -LiteralPath $ResolvedTarget `
                -Destination $BackupPath
            $ExistingTargetMoved = $true
            $Journal.state = 'BACKED_UP'
            Set-TriTierInstallJson -Path $JournalPath -Value $Journal
        }

        Move-Item `
            -LiteralPath $StageRoot `
            -Destination $ResolvedTarget
        $InstalledTargetCreated = $true
        $Journal.state = 'COMMITTED'
        Set-TriTierInstallJson -Path $JournalPath -Value $Journal

        $HistoryRoot = Join-Path $ResolvedTarget 'install-history'
        New-Item -ItemType Directory -Path $HistoryRoot -Force | Out-Null
        Copy-Item `
            -LiteralPath $JournalPath `
            -Destination (
                Join-Path $HistoryRoot "$OperationId.json"
            ) `
            -Force
        Remove-Item -LiteralPath $JournalPath -Force

        $Status = Get-TriTierInstallStatus -TargetRoot $ResolvedTarget

        if (-not $Status.healthy) {
            throw 'Installed payload failed post-install hash validation.'
        }

        [PSCustomObject][ordered]@{
            operation = [string]$Journal.operation
            status = 'COMPLETE'
            targetRoot = $ResolvedTarget
            installId = $ResolvedInstallId
            version = $script:TriTierInstallVersion
            backupPath = if ($ExistingTargetMoved) {
                $BackupPath
            }
            else {
                ''
            }
            privateCodexMutation = $false
            pathMutation = $false
        }
    }
    catch {
        $OriginalError = $_

        if ($InstalledTargetCreated -and (Test-Path -LiteralPath $ResolvedTarget)) {
            Remove-Item `
                -LiteralPath $ResolvedTarget `
                -Recurse `
                -Force
        }

        if (
            $ExistingTargetMoved -and
            (Test-Path -LiteralPath $BackupPath)
        ) {
            Move-Item `
                -LiteralPath $BackupPath `
                -Destination $ResolvedTarget
        }

        if (Test-Path -LiteralPath $StageRoot) {
            Remove-Item -LiteralPath $StageRoot -Recurse -Force
        }

        if (Test-Path -LiteralPath $JournalPath) {
            Remove-Item -LiteralPath $JournalPath -Force
        }

        throw $OriginalError
    }
    }
    finally {
        $InstallLockHandle.Dispose()
    }
}

function New-TriTierUninstallPlan {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$TargetRoot = ''
    )

    $ResolvedTarget = if ([string]::IsNullOrWhiteSpace($TargetRoot)) {
        Get-TriTierDefaultInstallRoot
    }
    else {
        Get-TriTierInstallFullPath -Path $TargetRoot
    }
    $Status = Get-TriTierInstallStatus -TargetRoot $ResolvedTarget

    [PSCustomObject][ordered]@{
        operation = 'UNINSTALL'
        canApply = ($Status.owned -and $Status.healthy)
        targetRoot = $ResolvedTarget
        installId = [string]$Status.installId
        version = [string]$Status.version
        reversible = $true
        deletion = $false
        privateCodexMutation = $false
        status = $Status
    }
}

function Invoke-TriTierUninstall {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$TargetRoot = '',

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ConfirmTarget,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ConfirmInstallId
    )

    $Plan = New-TriTierUninstallPlan -TargetRoot $TargetRoot

    if (-not $Plan.canApply) {
        throw 'Uninstall plan is blocked because the installation is not healthy.'
    }

    $ResolvedConfirmation = Get-TriTierInstallFullPath -Path $ConfirmTarget

    if (
        -not [string]::Equals(
            [string]$Plan.targetRoot,
            $ResolvedConfirmation,
            [System.StringComparison]::OrdinalIgnoreCase
        )
    ) {
        throw 'ConfirmTarget must exactly match the normalized target root.'
    }

    if ($ConfirmInstallId -ne [string]$Plan.installId) {
        throw 'ConfirmInstallId does not match the owned installation.'
    }

    $ResolvedTarget = [string]$Plan.targetRoot
    $Parent = Split-Path -Parent $ResolvedTarget
    $Leaf = Split-Path -Leaf $ResolvedTarget
    $OperationId = [guid]::NewGuid().ToString('N')
    $BackupRoot = Join-Path $Parent '.tri-tier-backups'
    $QuarantinePath = Join-Path $BackupRoot (
        "$Leaf-uninstalled-" +
        "$((Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ'))-" +
        $OperationId
    )
    $JournalPath = Get-TriTierInstallJournalPath -TargetRoot $ResolvedTarget
    $UninstallLockHandle = New-TriTierInstallLockHandle `
        -TargetRoot $ResolvedTarget

    try {
        if (Test-Path -LiteralPath $JournalPath) {
        throw 'An unfinished installation transaction requires recovery first.'
    }

    $Journal = [ordered]@{
        product = $script:TriTierInstallProduct
        operationId = $OperationId
        operation = 'UNINSTALL'
        state = 'PREPARED'
        targetRoot = $ResolvedTarget
        stageRoot = ''
        backupPath = $QuarantinePath
        installId = [string]$Plan.installId
        startedUtc = (Get-Date).ToUniversalTime().ToString('o')
    }

    Set-TriTierInstallJson -Path $JournalPath -Value $Journal

    try {
        New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
        Move-Item `
            -LiteralPath $ResolvedTarget `
            -Destination $QuarantinePath
        $Journal.state = 'QUARANTINED'
        Set-TriTierInstallJson -Path $JournalPath -Value $Journal
        Remove-Item -LiteralPath $JournalPath -Force

        [PSCustomObject][ordered]@{
            operation = 'UNINSTALL'
            status = 'COMPLETE'
            targetRoot = $ResolvedTarget
            installId = [string]$Plan.installId
            quarantinePath = $QuarantinePath
            reversible = $true
            deleted = $false
            privateCodexMutation = $false
        }
    }
    catch {
        $OriginalError = $_

        if (
            -not (Test-Path -LiteralPath $ResolvedTarget) -and
            (Test-Path -LiteralPath $QuarantinePath)
        ) {
            Move-Item `
                -LiteralPath $QuarantinePath `
                -Destination $ResolvedTarget
        }

        if (Test-Path -LiteralPath $JournalPath) {
            Remove-Item -LiteralPath $JournalPath -Force
        }

        throw $OriginalError
    }
    }
    finally {
        $UninstallLockHandle.Dispose()
    }
}

function New-TriTierMigrationPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SourceRoot,

        [Parameter()]
        [string]$TargetRoot = ''
    )

    $ResolvedTarget = if ([string]::IsNullOrWhiteSpace($TargetRoot)) {
        Get-TriTierDefaultInstallRoot
    }
    else {
        Get-TriTierInstallFullPath -Path $TargetRoot
    }
    $Status = Get-TriTierInstallStatus -TargetRoot $ResolvedTarget
    $Manifest = Get-TriTierInstallManifest -TargetRoot $ResolvedTarget
    $SchemaVersion = if ($null -eq $Manifest) {
        0
    }
    else {
        [int](
            Get-TriTierInstallProperty `
                -InputObject $Manifest `
                -Name 'schemaVersion' `
                -DefaultValue 1
        )
    }
    $NeedsMigration = (
        $Status.owned -and
        (
            $Status.version -ne $script:TriTierInstallVersion -or
            $SchemaVersion -ne $script:TriTierInstallSchemaVersion
        )
    )
    $InstallPlan = New-TriTierInstallPlan `
        -SourceRoot $SourceRoot `
        -TargetRoot $ResolvedTarget

    [PSCustomObject][ordered]@{
        operation = 'MIGRATE'
        canApply = ($NeedsMigration -and $InstallPlan.canApply)
        targetRoot = $ResolvedTarget
        installId = [string]$Status.installId
        fromVersion = [string]$Status.version
        toVersion = $script:TriTierInstallVersion
        fromSchemaVersion = $SchemaVersion
        toSchemaVersion = $script:TriTierInstallSchemaVersion
        backupRequired = $true
        privateCodexMutation = $false
        installPlan = $InstallPlan
    }
}

function Invoke-TriTierMigration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SourceRoot,

        [Parameter()]
        [string]$TargetRoot = '',

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ConfirmTarget,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ConfirmInstallId
    )

    $Plan = New-TriTierMigrationPlan `
        -SourceRoot $SourceRoot `
        -TargetRoot $TargetRoot

    if (-not $Plan.canApply) {
        throw 'Migration plan is not applicable.'
    }

    $Result = Invoke-TriTierInstall `
        -SourceRoot $SourceRoot `
        -TargetRoot $Plan.targetRoot `
        -ConfirmTarget $ConfirmTarget `
        -ConfirmInstallId $ConfirmInstallId

    [PSCustomObject][ordered]@{
        operation = 'MIGRATE'
        status = [string]$Result.status
        targetRoot = [string]$Result.targetRoot
        installId = [string]$Result.installId
        fromVersion = [string]$Plan.fromVersion
        toVersion = [string]$Result.version
        backupPath = [string]$Result.backupPath
        privateCodexMutation = $false
    }
}

function Repair-TriTierInstallation {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$TargetRoot = ''
    )

    $ResolvedTarget = if ([string]::IsNullOrWhiteSpace($TargetRoot)) {
        Get-TriTierDefaultInstallRoot
    }
    else {
        Get-TriTierInstallFullPath -Path $TargetRoot
    }
    $RecoveryLockHandle = New-TriTierInstallLockHandle `
        -TargetRoot $ResolvedTarget

    try {
        $JournalPath = Get-TriTierInstallJournalPath -TargetRoot $ResolvedTarget
        $Journal = Get-TriTierInstallJson -Path $JournalPath

    if ($null -eq $Journal) {
        return [PSCustomObject][ordered]@{
            action = 'NO_ACTION'
            targetRoot = $ResolvedTarget
            journalPath = $JournalPath
            recovered = $true
        }
    }

    if (
        [string](
            Get-TriTierInstallProperty `
                -InputObject $Journal `
                -Name 'product' `
                -DefaultValue ''
        ) -ne $script:TriTierInstallProduct
    ) {
        throw 'Recovery journal is not owned by Tri-Tier.'
    }

    $JournalTarget = Get-TriTierInstallFullPath -Path (
        [string]$Journal.targetRoot
    )

    if (
        -not [string]::Equals(
            $ResolvedTarget,
            $JournalTarget,
            [System.StringComparison]::OrdinalIgnoreCase
        )
    ) {
        throw 'Recovery journal target does not match the requested target.'
    }

    $StageRoot = [string](
        Get-TriTierInstallProperty `
            -InputObject $Journal `
            -Name 'stageRoot' `
            -DefaultValue ''
    )
    $BackupPath = [string](
        Get-TriTierInstallProperty `
            -InputObject $Journal `
            -Name 'backupPath' `
            -DefaultValue ''
    )
    $TargetStatus = Get-TriTierInstallStatus -TargetRoot $ResolvedTarget

    if ($TargetStatus.owned -and $TargetStatus.healthy) {
        if (
            -not [string]::IsNullOrWhiteSpace($StageRoot) -and
            (Test-Path -LiteralPath $StageRoot)
        ) {
            Remove-Item -LiteralPath $StageRoot -Recurse -Force
        }

        Remove-Item -LiteralPath $JournalPath -Force

        return [PSCustomObject][ordered]@{
            action = 'KEPT_HEALTHY_TARGET'
            targetRoot = $ResolvedTarget
            journalPath = $JournalPath
            recovered = $true
        }
    }

    if (
        -not [string]::IsNullOrWhiteSpace($BackupPath) -and
        (Test-Path -LiteralPath $BackupPath -PathType Container)
    ) {
        if (Test-Path -LiteralPath $ResolvedTarget) {
            $UnsafeStatus = Get-TriTierInstallStatus -TargetRoot $ResolvedTarget

            if ($UnsafeStatus.status -eq 'UNMANAGED') {
                throw (
                    'Recovery will not remove an unmanaged target. ' +
                    'Manual review is required.'
                )
            }

            Remove-Item `
                -LiteralPath $ResolvedTarget `
                -Recurse `
                -Force
        }

        Move-Item `
            -LiteralPath $BackupPath `
            -Destination $ResolvedTarget

        if (
            -not [string]::IsNullOrWhiteSpace($StageRoot) -and
            (Test-Path -LiteralPath $StageRoot)
        ) {
            Remove-Item -LiteralPath $StageRoot -Recurse -Force
        }

        Remove-Item -LiteralPath $JournalPath -Force
        $RestoredStatus = Get-TriTierInstallStatus -TargetRoot $ResolvedTarget

        if (-not $RestoredStatus.owned) {
            throw 'Recovered backup is not a valid Tri-Tier installation.'
        }

        return [PSCustomObject][ordered]@{
            action = 'RESTORED_BACKUP'
            targetRoot = $ResolvedTarget
            journalPath = $JournalPath
            recovered = $true
        }
    }

    if (
        -not [string]::IsNullOrWhiteSpace($StageRoot) -and
        (Test-Path -LiteralPath $StageRoot)
    ) {
        Remove-Item -LiteralPath $StageRoot -Recurse -Force
    }

    if (-not (Test-Path -LiteralPath $ResolvedTarget)) {
        Remove-Item -LiteralPath $JournalPath -Force

        return [PSCustomObject][ordered]@{
            action = 'REMOVED_PARTIAL_STAGE'
            targetRoot = $ResolvedTarget
            journalPath = $JournalPath
            recovered = $true
        }
    }

    [PSCustomObject][ordered]@{
        action = 'MANUAL_REVIEW_REQUIRED'
        targetRoot = $ResolvedTarget
        journalPath = $JournalPath
        recovered = $false
    }
    }
    finally {
        $RecoveryLockHandle.Dispose()
    }
}

Export-ModuleMember -Function @(
    'Get-TriTierCompatibilityReport'
    'Get-TriTierDefaultInstallRoot'
    'Get-TriTierInstallJournalPath'
    'Get-TriTierInstallLockPath'
    'Get-TriTierInstallManifest'
    'Get-TriTierInstallStatus'
    'Invoke-TriTierInstall'
    'Invoke-TriTierMigration'
    'Invoke-TriTierUninstall'
    'New-TriTierInstallPlan'
    'New-TriTierMigrationPlan'
    'New-TriTierUninstallPlan'
    'Repair-TriTierInstallation'
    'Test-TriTierInstallManifest'
    'Test-TriTierInstallTarget'
)
