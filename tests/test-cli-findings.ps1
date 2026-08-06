$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot = Split-Path $PSScriptRoot -Parent
$CliPath = Join-Path $RepoRoot 'src\tri-agent.ps1'
$PwshPath = (Get-Command pwsh -ErrorAction Stop).Source

function Invoke-CliJson {
    param(
        [Parameter(Mandatory)]
        [object[]]$Arguments
    )

    $Output = @(
        & $PwshPath -NoProfile -File $CliPath @Arguments 2>&1
    )

    $ExitCode = $LASTEXITCODE
    $OutputText = @(
        $Output | ForEach-Object {
            [string]$_
        }
    ) -join [Environment]::NewLine

    if ($ExitCode -ne 0) {
        throw (
            "CLI command failed with exit code ${ExitCode}: " +
            ($Arguments -join ' ') +
            [Environment]::NewLine +
            $OutputText
        )
    }

    $JsonText = $OutputText.Trim()

    if ([string]::IsNullOrWhiteSpace($JsonText)) {
        throw "CLI command returned no JSON output: $($Arguments -join ' ')"
    }

    $JsonText | ConvertFrom-Json -Depth 40
}

function Assert-Equal {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter()]
        $Expected,

        [Parameter()]
        $Actual
    )

    $Passed = $Expected -eq $Actual

    [PSCustomObject]@{
        Test = $Name
        Status = if ($Passed) { 'PASS' } else { 'FAIL' }
    } | Format-Table -AutoSize

    if (-not $Passed) {
        throw "$Name failed. Expected: $Expected. Actual: $Actual."
    }
}

function Assert-Throws {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [scriptblock]$Action
    )

    $Thrown = $false

    try {
        & $Action
    }
    catch {
        $Thrown = $true
    }

    Assert-Equal -Name $Name -Expected $true -Actual $Thrown
}

$TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    'tri-tier-cli-findings-' + [guid]::NewGuid().ToString('N')
)

try {
    New-Item -ItemType Directory -Path $TestRoot -Force | Out-Null

    $Run = Invoke-CliJson -Arguments @(
        'run-init',
        '-ProjectPath', $TestRoot,
        '-RunId', 'cli-finding-test',
        '-Title', 'CLI finding lifecycle test',
        '-CurrentTask', 'TASK-CLI-01',
        '-NextAction', 'Implement the CLI test task.',
        '-Json'
    )

    $Created = Invoke-CliJson -Arguments @(
        'finding-add',
        '-ProjectPath', $TestRoot,
        '-RunId', $Run.runId,
        '-Severity', 'MEDIUM',
        '-Title', 'CLI repair required',
        '-Description', 'The CLI-created finding requires repair.',
        '-Reviewer', 'sol-reviewer',
        '-TaskId', 'TASK-CLI-01',
        '-Json'
    )

    $FindingId = $Created.findingId

    Assert-Equal -Name 'finding-add returns OPEN status' -Expected 'OPEN' -Actual $Created.status
    Assert-Equal -Name 'finding-add blocks task' -Expected $true -Actual ([bool]$Created.taskBlocked)

    $Fetched = Invoke-CliJson -Arguments @(
        'finding-get',
        '-ProjectPath', $TestRoot,
        '-RunId', $Run.runId,
        '-FindingId', $FindingId,
        '-Json'
    )

    Assert-Equal -Name 'finding-get returns persisted finding' -Expected $FindingId -Actual $Fetched.findingId

    $Repaired = Invoke-CliJson -Arguments @(
        'finding-repair',
        '-ProjectPath', $TestRoot,
        '-RunId', $Run.runId,
        '-FindingId', $FindingId,
        '-RepairedBy', 'luna-worker',
        '-RepairSummary', 'Applied the CLI repair.',
        '-Json'
    )

    Assert-Equal -Name 'finding-repair enters pending review' -Expected 'REPAIRED_PENDING_REVIEW' -Actual $Repaired.status

    Assert-Throws -Name 'finding-review rejects repair actor' -Action {
        Invoke-CliJson -Arguments @(
            'finding-review',
            '-ProjectPath', $TestRoot,
            '-RunId', $Run.runId,
            '-FindingId', $FindingId,
            '-Reviewer', 'luna-worker',
            '-Outcome', 'PASS',
            '-ReviewSummary', 'Invalid same-actor review.',
            '-Json'
        ) | Out-Null
    }

    $FailedReview = Invoke-CliJson -Arguments @(
        'finding-review',
        '-ProjectPath', $TestRoot,
        '-RunId', $Run.runId,
        '-FindingId', $FindingId,
        '-Reviewer', 'sol-reviewer',
        '-Outcome', 'FAIL',
        '-ReviewSummary', 'The first repair did not pass.',
        '-Json'
    )

    Assert-Equal -Name 'failed finding-review reopens finding' -Expected 'OPEN' -Actual $FailedReview.status
    Assert-Equal -Name 'failed finding-review increments cycle' -Expected 1 -Actual ([int]$FailedReview.reviewCycle)

    $SecondRepair = Invoke-CliJson -Arguments @(
        'finding-repair',
        '-ProjectPath', $TestRoot,
        '-RunId', $Run.runId,
        '-FindingId', $FindingId,
        '-RepairedBy', 'luna-worker',
        '-RepairSummary', 'Applied the corrected CLI repair.',
        '-Json'
    )

    $PassedReview = Invoke-CliJson -Arguments @(
        'finding-review',
        '-ProjectPath', $TestRoot,
        '-RunId', $Run.runId,
        '-FindingId', $FindingId,
        '-Reviewer', 'terra-reviewer',
        '-Outcome', 'PASS',
        '-ReviewSummary', 'Independent CLI review passed.',
        '-Json'
    )

    Assert-Equal -Name 'passed finding-review resolves finding' -Expected 'RESOLVED' -Actual $PassedReview.status
    Assert-Equal -Name 'resolved finding advances next action' -Expected 'Proceed to the next task or phase gate.' -Actual $PassedReview.nextAction

    $LowFinding = Invoke-CliJson -Arguments @(
        'finding-add',
        '-ProjectPath', $TestRoot,
        '-RunId', $Run.runId,
        '-Severity', 'LOW',
        '-Title', 'CLI deferrable follow-up',
        '-Description', 'This low finding may be deferred.',
        '-Reviewer', 'sol-reviewer',
        '-TaskId', 'TASK-CLI-01',
        '-Json'
    )

    Assert-Throws -Name 'finding-defer requires owner approval' -Action {
        Invoke-CliJson -Arguments @(
            'finding-defer',
            '-ProjectPath', $TestRoot,
            '-RunId', $Run.runId,
            '-FindingId', $LowFinding.findingId,
            '-Reason', 'Later maintenance window.',
            '-OwnerApprovalRecord', 'owner-cli-001',
            '-Json'
        ) | Out-Null
    }

    $Deferred = Invoke-CliJson -Arguments @(
        'finding-defer',
        '-ProjectPath', $TestRoot,
        '-RunId', $Run.runId,
        '-FindingId', $LowFinding.findingId,
        '-Reason', 'Later maintenance window.',
        '-OwnerApprovalRecord', 'owner-cli-001',
        '-OwnerApproved',
        '-Json'
    )

    Assert-Equal -Name 'finding-defer persists DEFERRED status' -Expected 'DEFERRED' -Actual $Deferred.status

    $Version = @(
        & $PwshPath -NoProfile -File $CliPath version 2>&1
    )

    if ($LASTEXITCODE -ne 0) {
        throw "CLI version command failed with exit code $LASTEXITCODE."
    }

    Assert-Equal -Name 'CLI version advanced' -Expected 'tri-tier-agent-system 0.6.0-alpha' -Actual (($Version -join '').Trim())

    Write-Host 'Finding CLI tests passed.' -ForegroundColor Green
}
finally {
    if (Test-Path $TestRoot) {
        Remove-Item -LiteralPath $TestRoot -Recurse -Force
    }
}
