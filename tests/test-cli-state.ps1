$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = Split-Path $PSScriptRoot -Parent
$CliPath = Join-Path $RepoRoot "src\tri-agent.ps1"

$TempRoot = Join-Path `
    ([IO.Path]::GetTempPath()) `
    "tri-tier-cli-$([guid]::NewGuid().ToString('N'))"

New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null

$Failures = @()

function Assert-CliStateTest {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [bool]$Condition
    )

    [PSCustomObject]@{
        Test = $Name
        Status = if ($Condition) { "PASS" } else { "FAIL" }
    } | Format-Table -AutoSize

    if (-not $Condition) {
        $script:Failures += $Name
    }
}

try {
    $InitJson = & $CliPath run-init `
        -ProjectPath $TempRoot `
        -RunId "cli-state-test" `
        -Title "CLI state test" `
        -CurrentPhase "PHASE-01" `
        -NextAction "Prepare TASK-001." `
        -Json |
        Out-String

    $Init = $InitJson | ConvertFrom-Json

    Assert-CliStateTest `
        -Name "run-init returns ACTIVE state" `
        -Condition ($Init.status -eq "ACTIVE")

    Assert-CliStateTest `
        -Name "run-init returns exact next action" `
        -Condition ($Init.nextAction -eq "Prepare TASK-001.")

    Assert-CliStateTest `
        -Name "run-init creates local state" `
        -Condition (
            Test-Path (
                Join-Path `
                    $TempRoot `
                    ".tri-tier\runs\cli-state-test\state\run-state.json"
            )
        )

    $CheckpointJson = & $CliPath run-checkpoint `
        -ProjectPath $TempRoot `
        -RunId "cli-state-test" `
        -Summary "TASK-001 prepared." `
        -NextAction "Luna implements TASK-001." `
        -CurrentPhase "PHASE-01" `
        -CurrentTask "TASK-001" `
        -CompletedTasks "TASK-000" `
        -UnresolvedFindings "Independent review required" `
        -Json |
        Out-String

    $Checkpoint = $CheckpointJson | ConvertFrom-Json

    Assert-CliStateTest `
        -Name "run-checkpoint returns checkpoint ID" `
        -Condition (
            -not [string]::IsNullOrWhiteSpace(
                [string]$Checkpoint.checkpointId
            )
        )

    $ResumeJson = & $CliPath run-resume `
        -ProjectPath $TempRoot `
        -RunId "cli-state-test" `
        -Json |
        Out-String

    $Resume = $ResumeJson | ConvertFrom-Json

    Assert-CliStateTest `
        -Name "run-resume returns current task" `
        -Condition ($Resume.currentTask -eq "TASK-001")

    Assert-CliStateTest `
        -Name "run-resume returns exact next action" `
        -Condition (
            $Resume.nextAction -eq "Luna implements TASK-001."
        )

    Assert-CliStateTest `
        -Name "run-resume returns checkpoint summary" `
        -Condition (
            $Resume.latestCheckpointSummary -eq "TASK-001 prepared."
        )

    $StatusJson = & $CliPath run-status `
        -ProjectPath $TempRoot `
        -RunId "cli-state-test" `
        -Json |
        Out-String

    $Status = $StatusJson | ConvertFrom-Json

    Assert-CliStateTest `
        -Name "run-status reads current status" `
        -Condition ($Status.status -eq "ACTIVE")

    $CompletedJson = & $CliPath run-status `
        -ProjectPath $TempRoot `
        -RunId "cli-state-test" `
        -RunStatus "COMPLETE" `
        -Json |
        Out-String

    $Completed = $CompletedJson | ConvertFrom-Json

    Assert-CliStateTest `
        -Name "run-status updates status" `
        -Condition ($Completed.status -eq "COMPLETE")

    $InvalidStatusRejected = $false

    try {
        & $CliPath run-status `
            -ProjectPath $TempRoot `
            -RunId "cli-state-test" `
            -RunStatus "INVALID_STATUS" |
            Out-Null
    }
    catch {
        $InvalidStatusRejected = $true
    }

    Assert-CliStateTest `
        -Name "Invalid run status rejected" `
        -Condition $InvalidStatusRejected
}
finally {
    Remove-Item `
        $TempRoot `
        -Recurse `
        -Force `
        -ErrorAction SilentlyContinue
}

if ($Failures.Count -gt 0) {
    throw "State CLI tests failed: $($Failures -join ', ')"
}

Write-Host ""
Write-Host "State CLI tests passed." -ForegroundColor Green
