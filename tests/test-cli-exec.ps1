$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot = Split-Path $PSScriptRoot -Parent
$CliPath = Join-Path $RepoRoot 'src\tri-agent.ps1'
$StatePath = Join-Path $RepoRoot 'src\TriTier\State.psm1'
$TaskFlowPath = Join-Path $RepoRoot 'src\TriTier\TaskFlow.psm1'
$PwshPath = (Get-Command pwsh -ErrorAction Stop).Source

Import-Module $StatePath -Force
Import-Module $TaskFlowPath -Force

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

function Assert-True {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [bool]$Value
    )

    Assert-Equal -Name $Name -Expected $true -Actual $Value
}

function Invoke-TestCli {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [Parameter()]
        [switch]$ExpectFailure
    )

    $Output = @(
        & $PwshPath `
            -NoLogo `
            -NoProfile `
            -File $CliPath `
            @Arguments `
            2>&1 |
            ForEach-Object {
                [string]$_
            }
    )
    $ExitCode = $LASTEXITCODE
    $Text = $Output -join [Environment]::NewLine

    if ($ExpectFailure) {
        if ($ExitCode -eq 0) {
            throw (
                'CLI command unexpectedly succeeded: ' +
                ($Arguments -join ' ') +
                [Environment]::NewLine +
                $Text
            )
        }

        return [PSCustomObject]@{
            ExitCode = $ExitCode
            Text = $Text
            Json = $null
        }
    }

    if ($ExitCode -ne 0) {
        throw (
            "CLI command failed with exit code ${ExitCode}: " +
            ($Arguments -join ' ') +
            [Environment]::NewLine +
            $Text
        )
    }

    $Parsed = $null

    if ($Arguments -contains '-Json') {
        $Parsed = $Text | ConvertFrom-Json
    }

    [PSCustomObject]@{
        ExitCode = $ExitCode
        Text = $Text
        Json = $Parsed
    }
}

function New-TestRun {
    param(
        [Parameter(Mandatory)]
        [string]$Root,

        [Parameter(Mandatory)]
        [string]$RunId
    )

    [void](
        New-TriTierRun `
            -ProjectPath $Root `
            -RunId $RunId `
            -Title "CLI execution test $RunId" `
            -CurrentTask 'TASK-CLI-001' `
            -NextAction 'Luna must implement the CLI test task.'
    )

    [void](
        Initialize-TriTierRunTaskFlow `
            -ProjectPath $Root `
            -RunId $RunId `
            -InitializedBy 'terra-manager' `
            -EventId "init-$RunId"
    )
}

$TestRoot = Join-Path (
    [System.IO.Path]::GetTempPath()
) (
    'tri-tier-cli-exec-' +
    [guid]::NewGuid().ToString('N')
)
$DispatcherPath = Join-Path $TestRoot 'cli-completion-dispatcher.ps1'

New-Item -ItemType Directory -Path $TestRoot -Force | Out-Null

$DispatcherContent = @'
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$EnvelopePath,

    [Parameter(Mandatory)]
    [string]$ResultPath
)

$ErrorActionPreference = 'Stop'
$Envelope = Get-Content -LiteralPath $EnvelopePath -Raw -Encoding UTF8 |
    ConvertFrom-Json
$State = Get-Content -LiteralPath $Envelope.runStatePath -Raw -Encoding UTF8 |
    ConvertFrom-Json
$State.status = 'COMPLETE'
$State.nextAction = 'CLI execution completed.'
$State.updatedUtc = [DateTime]::UtcNow.ToString('o')
$Encoding = [System.Text.UTF8Encoding]::new($false)

[System.IO.File]::WriteAllText(
    $Envelope.runStatePath,
    ($State | ConvertTo-Json -Depth 100) + [Environment]::NewLine,
    $Encoding
)
[System.IO.File]::WriteAllText(
    $Envelope.nextActionPath,
    $State.nextAction + [Environment]::NewLine,
    $Encoding
)

$Result = [PSCustomObject][ordered]@{
    schemaVersion = 1
    actionKey = [string]$Envelope.actionKey
    outcome = 'STATE_UPDATED'
    summary = 'CLI dispatcher completed the run.'
}

[System.IO.File]::WriteAllText(
    $ResultPath,
    ($Result | ConvertTo-Json -Depth 20) + [Environment]::NewLine,
    $Encoding
)
'@

[System.IO.File]::WriteAllText(
    $DispatcherPath,
    $DispatcherContent,
    [System.Text.UTF8Encoding]::new($false)
)

try {
    $DryRunId = 'cli-exec-dry-run'
    New-TestRun -Root $TestRoot -RunId $DryRunId

    $MissingDispatcher = Invoke-TestCli `
        -Arguments @(
            'exec'
            '-ProjectPath'
            $TestRoot
            '-RunId'
            $DryRunId
            '-Json'
        ) `
        -ExpectFailure

    Assert-True `
        -Name 'exec requires dispatcher outside dry-run' `
        -Value (
            $MissingDispatcher.Text -match
            'requires -DispatcherPath'
        )

    $DryRun = Invoke-TestCli `
        -Arguments @(
            'exec'
            '-ProjectPath'
            $TestRoot
            '-RunId'
            $DryRunId
            '-DryRun'
            '-Json'
        )

    Assert-Equal `
        -Name 'exec dry-run reports dryRun' `
        -Expected $true `
        -Actual ([bool]$DryRun.Json.dryRun)
    Assert-Equal `
        -Name 'exec dry-run reads IMPLEMENT stage' `
        -Expected 'IMPLEMENT' `
        -Actual $DryRun.Json.stage
    Assert-Equal `
        -Name 'exec dry-run assigns Luna' `
        -Expected 'luna' `
        -Actual $DryRun.Json.responsibleParty
    Assert-Equal `
        -Name 'exec dry-run selects Luna worker profile' `
        -Expected 'luna_worker' `
        -Actual $DryRun.Json.profileName
    Assert-Equal `
        -Name 'exec dry-run handoff targets agent' `
        -Expected 'agent' `
        -Actual $DryRun.Json.handoffTargetType
    Assert-Equal `
        -Name 'exec dry-run handoff originates from Terra manager' `
        -Expected 'terra_manager' `
        -Actual $DryRun.Json.handoffFromProfile
    Assert-Equal `
        -Name 'exec dry-run handoff names Luna worker' `
        -Expected 'luna_worker' `
        -Actual $DryRun.Json.handoffToProfile

    $CompleteRunId = 'cli-exec-complete'
    New-TestRun -Root $TestRoot -RunId $CompleteRunId

    $Complete = Invoke-TestCli `
        -Arguments @(
            'exec'
            '-ProjectPath'
            $TestRoot
            '-RunId'
            $CompleteRunId
            '-DispatcherPath'
            $DispatcherPath
            '-MaxSteps'
            '5'
            '-MaxSameDecision'
            '2'
            '-MaxAttemptsPerAction'
            '2'
            '-StepTimeoutSeconds'
            '30'
            '-Json'
        )

    Assert-Equal `
        -Name 'exec reaches COMPLETE loop state' `
        -Expected 'COMPLETE' `
        -Actual $Complete.Json.loopStatus
    Assert-Equal `
        -Name 'exec reaches COMPLETE run state' `
        -Expected 'COMPLETE' `
        -Actual $Complete.Json.runStatus
    Assert-Equal `
        -Name 'exec reports dispatched work' `
        -Expected $true `
        -Actual ([bool]$Complete.Json.dispatched)

    $Status = Invoke-TestCli `
        -Arguments @(
            'exec-status'
            '-ProjectPath'
            $TestRoot
            '-RunId'
            $CompleteRunId
            '-Json'
        )

    Assert-Equal `
        -Name 'exec-status reads durable completion' `
        -Expected 'COMPLETE' `
        -Actual $Status.Json.loopStatus
    Assert-Equal `
        -Name 'exec-status reads terminal STOP decision' `
        -Expected 'STOP' `
        -Actual $Status.Json.stage

    $Resume = Invoke-TestCli `
        -Arguments @(
            'exec-resume'
            '-ProjectPath'
            $TestRoot
            '-RunId'
            $CompleteRunId
            '-MaxSteps'
            '5'
            '-Json'
        )

    Assert-Equal `
        -Name 'exec-resume preserves completed loop' `
        -Expected 'COMPLETE' `
        -Actual $Resume.Json.loopStatus
    Assert-Equal `
        -Name 'exec-resume performs no duplicate dispatch' `
        -Expected $false `
        -Actual ([bool]$Resume.Json.dispatched)

    $Version = Invoke-TestCli -Arguments @('version')

    Assert-Equal `
        -Name 'CLI version advanced' `
        -Expected 'tri-tier-agent-system 0.10.0-alpha' `
        -Actual $Version.Text.Trim()

    Write-Host ''
    Write-Host 'Automatic execution CLI tests passed.' -ForegroundColor Green
}
finally {
    Remove-Item `
        -LiteralPath $TestRoot `
        -Recurse `
        -Force `
        -ErrorAction SilentlyContinue
}
