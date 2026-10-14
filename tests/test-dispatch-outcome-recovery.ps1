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
    if ($Mode -eq 'candidate') {
        $Files = @(Get-ChildItem -LiteralPath $Root -Recurse -File | Sort-Object FullName)
        $BeforeStatus = @($Files | ForEach-Object { $_.FullName + ':' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }) -join "`n"
        $Cli = Join-Path $RepositoryRoot 'src/tri-agent.ps1'
        $StatusText = & (Get-Process -Id $PID).Path -NoProfile -File $Cli exec-status -ProjectPath $Root -RunId 'unknown' -Json
        if ($LASTEXITCODE -ne 0) { throw 'Read-only recovery status failed.' }
        $Status = ($StatusText -join "`n") | ConvertFrom-Json
        if ($Status.canContinue -or -not $Status.orchestrationCanContinue -or $Status.recovery.outcome -ne 'UNRESOLVED' -or $Status.recovery.automaticRetryAllowed) {
            throw 'Recovery status must distinguish orchestration permission from blocked execution.'
        }
        if ([string]::IsNullOrWhiteSpace($Status.actionKey) -or $Status.actionKey -ne $Status.recovery.actionKey -or [string]::IsNullOrWhiteSpace($Status.recovery.envelopePath) -or [string]::IsNullOrWhiteSpace($Status.recovery.resultPath)) {
            throw 'Recovery status omitted the preserved action or evidence paths.'
        }
        $PreviewText = & (Get-Process -Id $PID).Path -NoProfile -File $Cli exec -ProjectPath $Root -RunId 'unknown' -DryRun -Json
        if ($LASTEXITCODE -ne 0) { throw 'Recovery dry-run preview failed.' }
        $Preview = ($PreviewText -join "`n") | ConvertFrom-Json
        if (-not $Preview.dryRun -or $Preview.canContinue -or $null -eq $Preview.recovery -or $Preview.actionKey -ne $Status.actionKey) {
            throw 'Dry-run preview hid the preserved unresolved action.'
        }
        $AfterFiles = @(Get-ChildItem -LiteralPath $Root -Recurse -File | Sort-Object FullName)
        $AfterStatus = @($AfterFiles | ForEach-Object { $_.FullName + ':' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }) -join "`n"
        if ($BeforeStatus -ne $AfterStatus) { throw 'Recovery inspection mutated the fixture evidence.' }
    }
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

if ($Mode -eq 'candidate') {
    # Kill the actual loop-owning process after an effect but before acknowledgement.
    # Resume in a fresh process, so no imported module or process-local state can help.
    $CrashRoot = Join-Path ([IO.Path]::GetTempPath()) ('eos-crash-' + [guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $CrashRoot)
    $Driver = $null
    $Resumer = $null
    function Start-FixtureChild {
        param([string]$Script, [string[]]$Arguments)
        $Info = [Diagnostics.ProcessStartInfo]::new()
        $Info.FileName = (Get-Process -Id $PID).Path
        $Info.UseShellExecute = $false
        $Info.RedirectStandardOutput = $true
        $Info.RedirectStandardError = $true
        foreach ($Arg in @('-NoProfile', '-File', $Script) + $Arguments) { [void]$Info.ArgumentList.Add($Arg) }
        $Child = [Diagnostics.Process]::new()
        $Child.StartInfo = $Info
        [void]$Child.Start()
        [pscustomobject]@{ process = $Child; stdout = $Child.StandardOutput.ReadToEndAsync(); stderr = $Child.StandardError.ReadToEndAsync() }
    }
    try {
        $CrashDispatcher = Join-Path $CrashRoot 'crash-dispatcher.ps1'
        [IO.File]::WriteAllText($CrashDispatcher, @'
param([string]$EnvelopePath, [string]$ResultPath)
$Envelope = Get-Content -LiteralPath $EnvelopePath -Raw | ConvertFrom-Json
[IO.File]::AppendAllText((Join-Path $Envelope.projectPath 'crash-effects.txt'), "effect`n")
[IO.File]::WriteAllText((Join-Path $Envelope.projectPath 'crash-ready.txt'), 'effect committed')
Start-Sleep -Seconds 60
'@)
        $WorkerPath = Join-Path $CrashRoot 'worker.ps1'
        [IO.File]::WriteAllText($WorkerPath, @'
param([string]$RepositoryRoot, [string]$ProjectRoot, [switch]$Resume)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $RepositoryRoot 'src/TriTier/State.psm1') -Force
Import-Module (Join-Path $RepositoryRoot 'src/TriTier/TaskFlow.psm1') -Force
Import-Module (Join-Path $RepositoryRoot 'src/TriTier/ExecutionLoop.psm1') -Force
if ($Resume) {
    $Result = Resume-TriTierRunExecutionLoop -ProjectPath $ProjectRoot -RunId 'crash' -MaxSteps 1 -StepTimeoutSeconds 10
    [IO.File]::WriteAllText((Join-Path $ProjectRoot 'resumed.json'), ($Result | ConvertTo-Json -Depth 100))
} else {
    [void](New-TriTierRun -ProjectPath $ProjectRoot -RunId 'crash' -Title 'Parent crash fixture' -CurrentTask 'TASK-001' -NextAction 'Implement fixture')
    [void](Initialize-TriTierRunTaskFlow -ProjectPath $ProjectRoot -RunId 'crash' -InitializedBy 'terra-manager' -EventId 'init-crash')
    [void](Invoke-TriTierRunExecutionLoop -ProjectPath $ProjectRoot -RunId 'crash' -DispatcherPath (Join-Path $ProjectRoot 'crash-dispatcher.ps1') -MaxSteps 1 -StepTimeoutSeconds 120)
}
'@)
        $Driver = Start-FixtureChild -Script $WorkerPath -Arguments @('-RepositoryRoot', $RepositoryRoot, '-ProjectRoot', $CrashRoot)
        $EffectPath = Join-Path $CrashRoot 'crash-effects.txt'
        $ReadyPath = Join-Path $CrashRoot 'crash-ready.txt'
        $Deadline = [DateTime]::UtcNow.AddSeconds(15)
        while (-not (Test-Path -LiteralPath $ReadyPath)) {
            if ($Driver.process.HasExited -or [DateTime]::UtcNow -ge $Deadline) { throw 'Crash fixture did not reach its effect boundary.' }
            Start-Sleep -Milliseconds 100
        }
        $Before = Get-TriTierRunExecutionLoop -ProjectPath $CrashRoot -RunId 'crash'
        if ($null -eq $Before.inFlight -or $Before.status -ne 'RUNNING') { throw 'Crash boundary lacked an unresolved dispatch marker.' }
        $Driver.process.Kill($true)
        if (-not $Driver.process.WaitForExit(10000)) { throw 'Owned fixture process tree did not exit.' }
        $Resumer = Start-FixtureChild -Script $WorkerPath -Arguments @('-RepositoryRoot', $RepositoryRoot, '-ProjectRoot', $CrashRoot, '-Resume')
        if (-not $Resumer.process.WaitForExit(15000)) { throw 'Fresh-process resume exceeded its bound.' }
        if ($Resumer.process.ExitCode -ne 0) { throw ('Fresh-process resume failed: ' + $Resumer.stderr.Result) }
        $After = Get-Content -LiteralPath (Join-Path $CrashRoot 'resumed.json') -Raw | ConvertFrom-Json
        if ($After.loop.status -ne 'PAUSED_BLOCKED' -or $After.dispatched -or $null -eq $After.loop.inFlight) { throw 'Fresh-process resume lost the unknown outcome.' }
        if ($After.loop.inFlight.actionKey -ne $Before.inFlight.actionKey -or @(Get-Content -LiteralPath $EffectPath).Count -ne 1) { throw 'Crash recovery changed the action or repeated the effect.' }
        Write-Host 'Actual parent-process crash: fresh resume blocked; one fake effect preserved.'
    } finally {
        foreach ($Owned in @($Driver, $Resumer)) {
            if ($null -ne $Owned) {
                if (-not $Owned.process.HasExited) { $Owned.process.Kill($true); [void]$Owned.process.WaitForExit(10000) }
                $Owned.process.Dispose()
            }
        }
        Remove-Item -LiteralPath $CrashRoot -Recurse -Force
    }
}
