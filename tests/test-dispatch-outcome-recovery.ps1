param([string]$RepositoryRoot = (Split-Path $PSScriptRoot -Parent),
      [ValidateSet('baseline','candidate')][string]$Mode = 'candidate')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $RepositoryRoot 'src/TriTier/State.psm1') -Force
Import-Module (Join-Path $RepositoryRoot 'src/TriTier/TaskFlow.psm1') -Force
Import-Module (Join-Path $RepositoryRoot 'src/TriTier/ExecutionLoop.psm1') -Force
$Root = Join-Path ([IO.Path]::GetTempPath()) ('eos-unknown-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $Root)
try {
    $Dispatcher = Join-Path $Root 'fake-effect.ps1'
    [IO.File]::WriteAllText($Dispatcher, @'
param([string]$EnvelopePath, [string]$ResultPath)
$Envelope = Get-Content -LiteralPath $EnvelopePath -Raw | ConvertFrom-Json
[IO.File]::AppendAllText((Join-Path $Envelope.projectPath 'fake-effects.txt'), "effect`n")
exit 9
'@)
    [void](New-TriTierRun -ProjectPath $Root -RunId 'unknown' -Title 'Synthetic outcome recovery' -CurrentTask 'TASK-001' -NextAction 'Implement fixture')
    [void](Initialize-TriTierRunTaskFlow -ProjectPath $Root -RunId 'unknown' -InitializedBy 'terra-manager' -EventId 'init-unknown')
    $FirstFailed = $false
    try { [void](Invoke-TriTierRunExecutionLoop -ProjectPath $Root -RunId 'unknown' -DispatcherPath $Dispatcher -MaxSteps 1 -StepTimeoutSeconds 10) }
    catch { $FirstFailed = $true }
    if (-not $FirstFailed) { throw 'First dispatch must fail after the synthetic effect.' }
    $Result = $null
    try { $Result = Resume-TriTierRunExecutionLoop -ProjectPath $Root -RunId 'unknown' -MaxSteps 1 -StepTimeoutSeconds 10 }
    catch { if ($Mode -eq 'candidate') { throw } }
    $Count = @(Get-Content -LiteralPath (Join-Path $Root 'fake-effects.txt')).Count
    $Loop = Get-TriTierRunExecutionLoop -ProjectPath $Root -RunId 'unknown'
    if ($Mode -eq 'baseline') {
        if ($Count -ne 2) { throw "Baseline reproduction expected two effects, saw $Count." }
    } else {
        if ($Count -ne 1 -or $Result.loop.status -ne 'PAUSED_BLOCKED' -or $null -eq $Loop.inFlight -or $Result.dispatched) {
            throw 'Candidate must preserve unknown dispatch and block a second effect.'
        }
        # Reopening and repeating resume must continue to block, even with another dispatcher path.
        $Alternate = Join-Path $Root 'another-dispatcher.ps1'
        Copy-Item -LiteralPath $Dispatcher -Destination $Alternate
        $Again = Resume-TriTierRunExecutionLoop -ProjectPath $Root -RunId 'unknown' -DispatcherPath $Alternate -MaxSteps 1
        if ($Again.loop.status -ne 'PAUSED_BLOCKED' -or @(Get-Content (Join-Path $Root 'fake-effects.txt')).Count -ne 1) {
            throw 'Repeated resume lost the unresolved outcome.'
        }
        if ($Again.loop.dispatcherPath -ne $Dispatcher) { throw 'Unresolved original dispatcher identity was overwritten.' }
    }
    [pscustomobject]@{ mode = $Mode; fakeEffectCount = $Count; status = $Loop.status; unresolvedMarkerPreserved = ($null -ne $Loop.inFlight); agentLaunches = 0 } | ConvertTo-Json
} finally { Remove-Item -LiteralPath $Root -Recurse -Force }
