[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Test-EqualValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Expected,

        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Actual
    )

    if ($Expected -ne $Actual) {
        throw "$Name failed. Expected: $Expected. Actual: $Actual."
    }

    [PSCustomObject][ordered]@{
        Test = $Name
        Status = 'PASS'
    }
}

function Test-TrueValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [bool]$Value
    )

    if (-not $Value) {
        throw "$Name failed."
    }

    [PSCustomObject][ordered]@{
        Test = $Name
        Status = 'PASS'
    }
}

function Get-PublicCliCommands {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CliPath
    )

    @(
        [regex]::Matches(
            [System.IO.File]::ReadAllText($CliPath),
            "(?m)^\s*['""]([^'""]+)['""]\s*\{"
        ) |
            ForEach-Object {
                $_.Groups[1].Value
            } |
            Sort-Object -Unique
    )
}

function Test-MarkdownLinks {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $Text = [System.IO.File]::ReadAllText($Path)
    $MatchesFound = [regex]::Matches(
        $Text,
        '\[[^\]]+\]\(([^)]+)\)'
    )

    foreach ($LinkMatch in $MatchesFound) {
        $Target = [string]$LinkMatch.Groups[1].Value

        if (
            [string]::IsNullOrWhiteSpace($Target) -or
            $Target.StartsWith('#') -or
            $Target -match '^[a-zA-Z][a-zA-Z0-9+.-]*:'
        ) {
            continue
        }

        $TargetPath = ($Target -split '#', 2)[0]

        if ([string]::IsNullOrWhiteSpace($TargetPath)) {
            continue
        }

        $ResolvedTarget = [System.IO.Path]::GetFullPath(
            (Join-Path (Split-Path -Parent $Path) $TargetPath)
        )

        if (-not (Test-Path -LiteralPath $ResolvedTarget)) {
            throw (
                'Broken relative Markdown link in ' +
                $Path +
                ': ' +
                $Target
            )
        }
    }

    [PSCustomObject][ordered]@{
        Test = 'Markdown links resolve: ' + (Split-Path -Leaf $Path)
        Status = 'PASS'
    }
}

$CliPath = Join-Path $RepoRoot 'src\tri-agent.ps1'
$CommandReferencePath = Join-Path $RepoRoot 'docs\command-reference.md'
$QuickstartPath = Join-Path $RepoRoot 'docs\quickstart.md'
$ContributorWorkflowPath = Join-Path $RepoRoot 'docs\contributor-workflow.md'
$ExamplesReadmePath = Join-Path $RepoRoot 'examples\README.md'
$ReadmePath = Join-Path $RepoRoot 'README.md'
$ContributingPath = Join-Path $RepoRoot 'CONTRIBUTING.md'

$ExpectedCommands = @(
    'classify'
    'evidence'
    'run-init'
    'run-checkpoint'
    'run-resume'
    'run-status'
    'finding-add'
    'finding-get'
    'finding-repair'
    'finding-review'
    'finding-defer'
    'task-flow-init'
    'task-start'
    'implementation-complete'
    'task-review'
    'task-flow-status'
    'task-planning-start'
    'repair-open'
    'repair-complete'
    'repair-review'
    'repair-adjudicate'
    'repair-status'
    'orchestration-status'
    'phase-start'
    'phase-ready'
    'phase-review'
    'phase-accept'
    'phase-reject'
    'phase-status'
    'exec'
    'exec-resume'
    'exec-status'
    'compatibility-check'
    'install-plan'
    'install-apply'
    'install-status'
    'uninstall-plan'
    'uninstall-apply'
    'migrate-plan'
    'migrate-apply'
    'install-recover'
    'doctor'
    'version'
) | Sort-Object

$CliCommands = Get-PublicCliCommands -CliPath $CliPath

Test-EqualValue `
    -Name 'Public CLI command count' `
    -Expected 43 `
    -Actual @($CliCommands).Count

Test-EqualValue `
    -Name 'Public CLI command set' `
    -Expected ($ExpectedCommands -join "`n") `
    -Actual ($CliCommands -join "`n")

$CommandReferenceText = [System.IO.File]::ReadAllText(
    $CommandReferencePath
)
$DocumentedCommands = @(
    [regex]::Matches(
        $CommandReferenceText,
        '(?m)^### `([^`]+)`\s*$'
    ) |
        ForEach-Object {
            $_.Groups[1].Value
        } |
        Sort-Object
)

Test-EqualValue `
    -Name 'Command reference section count' `
    -Expected 43 `
    -Actual @($DocumentedCommands).Count

Test-EqualValue `
    -Name 'Command reference covers exact CLI surface' `
    -Expected ($CliCommands -join "`n") `
    -Actual ($DocumentedCommands -join "`n")

$CliMetadata = Get-Command $CliPath
$CommonParameters = @(
    'Verbose'
    'Debug'
    'ErrorAction'
    'WarningAction'
    'InformationAction'
    'ProgressAction'
    'ErrorVariable'
    'WarningVariable'
    'InformationVariable'
    'OutVariable'
    'OutBuffer'
    'PipelineVariable'
)

$ScriptParameters = @(
    $CliMetadata.Parameters.Values |
        Where-Object {
            $_.Name -notin $CommonParameters
        } |
        Sort-Object Name
)

foreach ($ScriptParameter in $ScriptParameters) {
    $ParameterMarker = '| `-' + $ScriptParameter.Name + '` |'

    Test-TrueValue `
        -Name ('Parameter documented: ' + $ScriptParameter.Name) `
        -Value $CommandReferenceText.Contains($ParameterMarker)
}

Test-TrueValue `
    -Name 'Command reference records current CLI version' `
    -Value $CommandReferenceText.Contains('0.10.0-alpha')

$ReadmeText = [System.IO.File]::ReadAllText($ReadmePath)
$ContributingText = [System.IO.File]::ReadAllText($ContributingPath)

foreach ($ReadmeMarker in @(
    '<!-- BEGIN TRI-TIER PUBLIC DOCS -->'
    'docs/quickstart.md'
    'docs/command-reference.md'
    'examples/README.md'
    'docs/contributor-workflow.md'
    '<!-- END TRI-TIER PUBLIC DOCS -->'
)) {
    Test-TrueValue `
        -Name ('README public docs marker: ' + $ReadmeMarker) `
        -Value $ReadmeText.Contains($ReadmeMarker)
}

foreach ($ContributingMarker in @(
    '<!-- BEGIN TRI-TIER CONTRIBUTOR WORKFLOW -->'
    'docs/contributor-workflow.md'
    'tests/test-public-docs.ps1'
    '<!-- END TRI-TIER CONTRIBUTOR WORKFLOW -->'
)) {
    Test-TrueValue `
        -Name ('CONTRIBUTING workflow marker: ' + $ContributingMarker) `
        -Value $ContributingText.Contains($ContributingMarker)
}

foreach ($MarkdownPath in @(
    $CommandReferencePath
    $QuickstartPath
    $ContributorWorkflowPath
    $ExamplesReadmePath
)) {
    Test-MarkdownLinks -Path $MarkdownPath
}

$ExamplePaths = @(
    Get-ChildItem `
        -LiteralPath (Join-Path $RepoRoot 'examples') `
        -Filter '*.ps1' `
        -File |
        Sort-Object FullName
)

Test-EqualValue `
    -Name 'Runnable public example count' `
    -Expected 4 `
    -Actual @($ExamplePaths).Count

foreach ($ExamplePath in $ExamplePaths) {
    $Tokens = $null
    $ParseErrors = $null

    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $ExamplePath.FullName,
        [ref]$Tokens,
        [ref]$ParseErrors
    )

    if (@($ParseErrors).Count -gt 0) {
        $ErrorText = @(
            $ParseErrors |
                ForEach-Object {
                    "$($_.Extent.StartLineNumber):" +
                    "$($_.Extent.StartColumnNumber) " +
                    $_.Message
                }
        ) -join [Environment]::NewLine

        throw (
            'Example parser validation failed: ' +
            $ExamplePath.FullName +
            [Environment]::NewLine +
            $ErrorText
        )
    }

    $ExampleText = [System.IO.File]::ReadAllText(
        $ExamplePath.FullName
    )
    $InvokedCommands = @(
        [regex]::Matches(
            $ExampleText,
            '(?m)&\s+\$CliPath\s+([a-z][a-z0-9-]+)'
        ) |
            ForEach-Object {
                $_.Groups[1].Value
            } |
            Sort-Object -Unique
    )

    foreach ($InvokedCommand in $InvokedCommands) {
        Test-TrueValue `
            -Name (
                'Example uses public command: ' +
                $ExamplePath.Name +
                ' -> ' +
                $InvokedCommand
            ) `
            -Value ($InvokedCommand -in $CliCommands)
    }
}

$ExampleTextCombined = @(
    $ExamplePaths |
        ForEach-Object {
            [System.IO.File]::ReadAllText($_.FullName)
        }
) -join [Environment]::NewLine

foreach ($ForbiddenExampleCommand in @(
    'install-apply'
    'uninstall-apply'
    'migrate-apply'
)) {
    Test-TrueValue `
        -Name ('Examples avoid mutating command: ' + $ForbiddenExampleCommand) `
        -Value (-not $ExampleTextCombined.Contains($ForbiddenExampleCommand))
}

Write-Host ''
Write-Host 'Public documentation tests passed.' -ForegroundColor Green
