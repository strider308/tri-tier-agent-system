$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = Split-Path $PSScriptRoot -Parent
$ModulePath = Join-Path $RepoRoot "src\TriTier\State.psm1"

Import-Module $ModulePath -Force

$TempRoot = Join-Path `
    ([IO.Path]::GetTempPath()) `
    "tri-tier-state-$([guid]::NewGuid().ToString('N'))"

New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null

$Failures = @()

function Assert-TriTierTest {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [bool]$Condition
    )

    $Status = if ($Condition) { "PASS" } else { "FAIL" }

    [PSCustomObject]@{
        Test   = $Name
        Status = $Status
    } | Format-Table -AutoSize

    if (-not $Condition) {
        $script:Failures += $Name
    }
}

try {
    $Run = New-TriTierRun `
        -ProjectPath $TempRoot `
        -Title "Durable state test" `
        -RunId "state-test" `
        -CurrentPhase "PHASE-01" `
        -NextAction "Prepare TASK-001."

    Assert-TriTierTest `
        -Name "Run directory created" `
        -Condition (Test-Path $Run.runDirectory)

    Assert-TriTierTest `
        -Name "Initial status is ACTIVE" `
        -Condition ($Run.state.status -eq "ACTIVE")

    Assert-TriTierTest `
        -Name "Initial next action persisted" `
        -Condition ($Run.state.nextAction -eq "Prepare TASK-001.")

    Set-TriTierNextAction `
        -ProjectPath $TempRoot `
        -RunId "state-test" `
        -NextAction "Assign TASK-001 to Luna." |
        Out-Null

    $Updated = Get-TriTierRunState `
        -ProjectPath $TempRoot `
        -RunId "state-test"

    Assert-TriTierTest `
        -Name "Next action updated" `
        -Condition (
            $Updated.nextAction -eq "Assign TASK-001 to Luna."
        )

    $Checkpoint = New-TriTierCheckpoint `
        -ProjectPath $TempRoot `
        -RunId "state-test" `
        -Summary "TASK-001 prepared." `
        -NextAction "Luna implements TASK-001." `
        -CurrentPhase "PHASE-01" `
        -CurrentTask "TASK-001" `
        -CompletedTasks @("TASK-000") `
        -UnresolvedFindings @("Review required") `
        -Blockers @()

    Assert-TriTierTest `
        -Name "Checkpoint created" `
        -Condition (
            -not [string]::IsNullOrWhiteSpace(
                $Checkpoint.checkpointId
            )
        )

    $Resume = Get-TriTierRunResumeData `
        -ProjectPath $TempRoot `
        -RunId "state-test"

    Assert-TriTierTest `
        -Name "Resume returns exact next action" `
        -Condition (
            $Resume.nextAction -eq "Luna implements TASK-001."
        )

    Assert-TriTierTest `
        -Name "Resume returns current task" `
        -Condition (
            $Resume.state.currentTask -eq "TASK-001"
        )

    Assert-TriTierTest `
        -Name "Resume returns latest checkpoint" `
        -Condition (
            $null -ne $Resume.latestCheckpoint
        )

    Set-TriTierRunStatus `
        -ProjectPath $TempRoot `
        -RunId "state-test" `
        -Status "COMPLETE" |
        Out-Null

    $Validation = Test-TriTierRunState `
        -ProjectPath $TempRoot `
        -RunId "state-test"

    Assert-TriTierTest `
        -Name "Valid run state accepted" `
        -Condition $Validation.valid

    $NextActionPath = Join-Path `
        $Run.runDirectory `
        "state\next-action.txt"

    Set-Content `
        -Path $NextActionPath `
        -Value "Incorrect next action" `
        -Encoding UTF8

    $TamperedValidation = Test-TriTierRunState `
        -ProjectPath $TempRoot `
        -RunId "state-test"

    Assert-TriTierTest `
        -Name "Mismatched next action rejected" `
        -Condition (-not $TamperedValidation.valid)
}
finally {
    Remove-Item $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

if ($Failures.Count -gt 0) {
    throw "State tests failed: $($Failures -join ', ')"
}

Write-Host ""
Write-Host "Durable-state tests passed." -ForegroundColor Green
