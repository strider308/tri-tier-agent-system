[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Test-PublicationInvariant {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][bool]$Value
    )

    if (-not $Value) {
        throw "$Name failed."
    }

    [PSCustomObject][ordered]@{
        Test = $Name
        Status = 'PASS'
    }
}

function Get-Text {
    param([Parameter(Mandatory)][string]$RelativePath)

    $Path = Join-Path $RepoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required public file is missing: $RelativePath"
    }

    [System.IO.File]::ReadAllText($Path)
}

function Test-MarkdownLinks {
    param([Parameter(Mandatory)][string]$RelativePath)

    $Path = Join-Path $RepoRoot $RelativePath
    $Text = Get-Text $RelativePath

    foreach ($Match in [regex]::Matches($Text, '\[[^\]]+\]\(([^)]+)\)')) {
        $Target = [string]$Match.Groups[1].Value
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

        $Resolved = [System.IO.Path]::GetFullPath(
            (Join-Path (Split-Path -Parent $Path) $TargetPath)
        )
        Test-PublicationInvariant `
            -Name "Markdown link resolves: $RelativePath -> $Target" `
            -Value (Test-Path -LiteralPath $Resolved)
    }
}

$Readme = Get-Text 'README.md'
$Security = Get-Text 'SECURITY.md'
$Support = Get-Text 'SUPPORT.md'
$ReleaseNotes = Get-Text 'docs\release-v0.1.0-alpha.md'
$Workflow = Get-Text '.github\workflows\powershell.yml'
$BugTemplate = Get-Text '.github\ISSUE_TEMPLATE\bug_report.md'
$PullRequestTemplate = Get-Text '.github\pull_request_template.md'
$Gitignore = Get-Text '.gitignore'

foreach ($Path in @(
    'README.md'
    'SECURITY.md'
    'SUPPORT.md'
    'docs\release-v0.1.0-alpha.md'
    '.github\ISSUE_TEMPLATE\bug_report.md'
    '.github\ISSUE_TEMPLATE\feature_request.md'
    '.github\pull_request_template.md'
)) {
    Test-PublicationInvariant `
        -Name "Required public file: $Path" `
        -Value (Test-Path -LiteralPath (Join-Path $RepoRoot $Path) -PathType Leaf)
}

Test-PublicationInvariant `
    -Name 'Apache-2.0 license present' `
    -Value ((Get-Text 'LICENSE') -match 'Apache License\s+Version 2\.0')
Test-PublicationInvariant `
    -Name 'Repository release version is documented' `
    -Value ($ReleaseNotes.Contains('v0.1.0-alpha') -and $Readme.Contains('v0.1.0-alpha'))
Test-PublicationInvariant `
    -Name 'CLI milestone version is distinguished' `
    -Value ($ReleaseNotes.Contains('0.10.0-alpha') -and $Readme.Contains('0.10.0-alpha'))

foreach ($Role in @('Terra', 'Luna', 'Sol')) {
    Test-PublicationInvariant `
        -Name "Release notes role: $Role" `
        -Value $ReleaseNotes.Contains($Role)
}

foreach ($Marker in @('R0', 'R4', 'E0', 'E5')) {
    Test-PublicationInvariant `
        -Name "Release notes model marker: $Marker" `
        -Value $ReleaseNotes.Contains($Marker)
}

foreach ($Marker in @('private', 'public issue', 'secrets', 'alpha')) {
    Test-PublicationInvariant `
        -Name "Security guidance: $Marker" `
        -Value $Security.ToLowerInvariant().Contains($Marker)
}

foreach ($Marker in @('verify-repository.ps1', 'tri-agent.ps1', 'SECURITY.md')) {
    Test-PublicationInvariant `
        -Name "Support guidance: $Marker" `
        -Value $Support.Contains($Marker)
}

foreach ($Marker in @(
    'branches:'
    '- main'
    'contents: read'
    'persist-credentials: false'
    'verify-repository.ps1'
    'tri-agent.ps1 doctor'
)) {
    Test-PublicationInvariant `
        -Name "CI hardening marker: $Marker" `
        -Value $Workflow.Contains($Marker)
}

Test-PublicationInvariant `
    -Name 'CI does not require secrets' `
    -Value (-not ($Workflow -match '(?i)secrets\.'))
Test-PublicationInvariant `
    -Name 'Bug template redirects security reports' `
    -Value ($BugTemplate.Contains('SECURITY.md') -and $BugTemplate.Contains('public issue'))
Test-PublicationInvariant `
    -Name 'Pull request template checks validation and privacy' `
    -Value (
        $PullRequestTemplate.Contains('verify-repository.ps1') -and
        $PullRequestTemplate.Contains('doctor') -and
        $PullRequestTemplate.Contains('diff --check') -and
        $PullRequestTemplate.Contains('private')
    )

foreach ($Path in @(
    '.codegraph/'
    '.tri-tier/runs/'
    '.tri-tier/checkpoints/'
    '_local-audit/'
)) {
    Test-PublicationInvariant `
        -Name "Ignored local path: $Path" `
        -Value $Gitignore.Contains($Path)
}

$TrackedPaths = @(git -C $RepoRoot ls-files)
$PrivateTracked = @(
    $TrackedPaths |
        Where-Object {
            $_ -match '(^|/)(\.codex|\.agent-runs|\.codegraph|_local-audit)(/|$)' -or
            $_ -match '(^|/)\.tri-tier/(runs|checkpoints)(/|$)'
        }
)
Test-PublicationInvariant `
    -Name 'Private/runtime paths are not tracked' `
    -Value ($PrivateTracked.Count -eq 0)

$IndexEntries = @(git -C $RepoRoot ls-files -s)
Test-PublicationInvariant `
    -Name 'No tracked symlinks or submodules' `
    -Value (
        @($IndexEntries | Where-Object {$_ -match '^120000\s|^160000\s'}).Count -eq 0
    )

Test-MarkdownLinks 'README.md'
Test-MarkdownLinks 'SUPPORT.md'
Test-MarkdownLinks 'SECURITY.md'
Test-MarkdownLinks 'docs\release-v0.1.0-alpha.md'
Test-MarkdownLinks '.github\ISSUE_TEMPLATE\bug_report.md'

Write-Host ''
Write-Host 'Publication-readiness tests passed.' -ForegroundColor Green
