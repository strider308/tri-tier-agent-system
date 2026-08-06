$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot = Split-Path $PSScriptRoot -Parent
$StatePath = Join-Path $RepoRoot 'src\TriTier\State.psm1'
$FindingsPath = Join-Path $RepoRoot 'src\TriTier\Findings.psm1'

Import-Module $StatePath -Force
Import-Module $FindingsPath -Force

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

$TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('tri-tier-run-finding-state-' + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Path $TestRoot -Force | Out-Null

    $Run = New-TriTierRun `
        -ProjectPath $TestRoot `
        -RunId 'finding-state-test' `
        -Title 'Finding state persistence test' `
        -CurrentTask 'TASK-01' `
        -NextAction 'Perform the initial implementation.'

    $Finding = New-TriTierFinding `
        -Severity 'MEDIUM' `
        -Title 'Repair required' `
        -Description 'A targeted repair is required.' `
        -Reviewer 'sol-reviewer' `
        -TaskId 'TASK-01'

    $Gate = Test-TriTierFindingGate -Findings @($Finding)

    $Persisted = Set-TriTierRunFindingState `
        -ProjectPath $TestRoot `
        -RunId $Run.state.runId `
        -Findings @($Finding) `
        -FindingGate $Gate

    Assert-Equal -Name 'Finding persisted in run state' -Expected 1 -Actual @($Persisted.findings).Count
    Assert-Equal -Name 'Active finding ID persisted' -Expected $Finding.findingId -Actual @($Persisted.unresolvedFindings)[0]
    Assert-Equal -Name 'Finding gate persisted' -Expected $true -Actual ([bool]$Persisted.findingGate.taskBlocked)
    Assert-Equal -Name 'Gate next action persisted' -Expected $Gate.nextAction -Actual $Persisted.nextAction

    $Resume = Get-TriTierRunResumeData -ProjectPath $TestRoot -RunId $Run.state.runId
    Assert-Equal -Name 'Resume returns finding next action' -Expected $Gate.nextAction -Actual $Resume.nextAction

    $NextActionPath = Join-Path $Resume.runDirectory 'state\next-action.txt'
    $StoredNextAction = (Get-Content $NextActionPath -Raw).Trim()
    Assert-Equal -Name 'Exact next-action file synchronized' -Expected $Gate.nextAction -Actual $StoredNextAction

    $Validation = Test-TriTierRunState -ProjectPath $TestRoot -RunId $Run.state.runId
    Assert-Equal -Name 'Persisted run state remains valid' -Expected $true -Actual ([bool]$Validation.valid)

    Write-Host 'Run-finding-state tests passed.' -ForegroundColor Green
}
finally {
    if (Test-Path $TestRoot) {
        Remove-Item -LiteralPath $TestRoot -Recurse -Force
    }
}
