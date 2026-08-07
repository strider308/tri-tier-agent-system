Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$StateModulePath = Join-Path $PSScriptRoot 'State.psm1'
$OrchestrationModulePath = Join-Path $PSScriptRoot 'Orchestration.psm1'
$AgentProfilesModulePath = Join-Path $PSScriptRoot 'AgentProfiles.psm1'

foreach ($RequiredModulePath in @(
    $StateModulePath
    $OrchestrationModulePath
    $AgentProfilesModulePath
)) {
    if (-not (Test-Path -LiteralPath $RequiredModulePath -PathType Leaf)) {
        throw "Required Tri-Tier module is missing: $RequiredModulePath"
    }
}

$StateModule = Import-Module $StateModulePath -PassThru
$OrchestrationModule = Import-Module $OrchestrationModulePath -PassThru
$AgentProfilesModule = Import-Module $AgentProfilesModulePath -PassThru

foreach ($RequiredCommand in @(
    @{
        Module = $StateModule
        Name = 'Get-TriTierRunState'
    }
    @{
        Module = $StateModule
        Name = 'New-TriTierCheckpoint'
    }
    @{
        Module = $AgentProfilesModule
        Name = 'Resolve-TriTierAgentProfile'
    }
    @{
        Module = $AgentProfilesModule
        Name = 'New-TriTierAgentHandoff'
    }
    @{
        Module = $OrchestrationModule
        Name = 'Get-TriTierRunOrchestrationDecision'
    }
)) {
    if (
        $null -eq (
            Get-Command `
                -Module $RequiredCommand.Module.Name `
                -Name $RequiredCommand.Name `
                -ErrorAction SilentlyContinue
        )
    ) {
        throw (
            'Required execution-loop command is unavailable from ' +
            "$($RequiredCommand.Module.Path): $($RequiredCommand.Name)"
        )
    }
}
$script:ExecutionLoopSchemaVersion = 1
$script:ExecutionEnvelopeSchemaVersion = 2
$script:ExecutionResultSchemaVersion = 1
$script:AllowedExecutionStatuses = @(
    'IDLE'
    'RUNNING'
    'RECOVERING'
    'WAITING_OWNER'
    'WAITING_EXTERNAL'
    'PAUSED_BLOCKED'
    'PAUSED_LIMIT'
    'PAUSED_STALLED'
    'COMPLETE'
    'FAILED'
    'ABORTED'
)

function ConvertTo-TriTierExecutionSafeId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Value
    )

    if ($Value -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$') {
        throw (
            'Tri-Tier execution identifiers must start with an alphanumeric ' +
            'character and contain only letters, digits, dot, underscore, ' +
            'or hyphen.'
        )
    }

    $Value
}

function Get-TriTierExecutionProperty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter()]
        [AllowNull()]
        [object]$DefaultValue = $null,

        [Parameter()]
        [switch]$Required
    )

    if ($null -ne $InputObject) {
        if ($InputObject -is [System.Collections.IDictionary]) {
            if ($InputObject.Contains($Name)) {
                return $InputObject[$Name]
            }
        }
        else {
            $Property = $InputObject.PSObject.Properties[$Name]

            if ($null -ne $Property) {
                return $Property.Value
            }
        }
    }

    if ($Required) {
        $TypeName = if ($null -eq $InputObject) {
            '<null>'
        }
        else {
            $InputObject.GetType().FullName
        }

        throw (
            "Required execution property '$Name' is missing from " +
            "object type $TypeName."
        )
    }

    $DefaultValue
}

function Get-TriTierExecutionRunDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RunId
    )

    $ResolvedRunId = ConvertTo-TriTierExecutionSafeId -Value $RunId
    $FullProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)

    Join-Path $FullProjectPath (
        '.tri-tier\runs\' + $ResolvedRunId
    )
}

function Get-TriTierExecutionDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RunId
    )

    Join-Path (
        Get-TriTierExecutionRunDirectory `
            -ProjectPath $ProjectPath `
            -RunId $RunId
    ) 'execution'
}

function Get-TriTierExecutionLockPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RunId
    )

    Join-Path (
        Get-TriTierExecutionDirectory `
            -ProjectPath $ProjectPath `
            -RunId $RunId
    ) 'execution-loop.lock'
}

function Enter-TriTierExecutionLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RunId
    )

    $ExecutionDirectory = Get-TriTierExecutionDirectory `
        -ProjectPath $ProjectPath `
        -RunId $RunId

    if (-not (Test-Path -LiteralPath $ExecutionDirectory)) {
        New-Item `
            -ItemType Directory `
            -Path $ExecutionDirectory `
            -Force |
            Out-Null
    }

    $LockPath = Get-TriTierExecutionLockPath `
        -ProjectPath $ProjectPath `
        -RunId $RunId
    $LockStream = $null

    try {
        $LockStream = [System.IO.FileStream]::new(
            $LockPath,
            [System.IO.FileMode]::OpenOrCreate,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::None
        )
    }
    catch [System.IO.IOException] {
        throw (
            'Another automatic execution invocation already owns the ' +
            "durable run lock for run $RunId."
        )
    }

    try {
        $LockMetadata = (
            'pid={0}{1}acquiredUtc={2}{1}' -f
            $PID,
            [Environment]::NewLine,
            [DateTime]::UtcNow.ToString('o')
        )
        $LockBytes = [System.Text.Encoding]::UTF8.GetBytes($LockMetadata)

        $LockStream.SetLength(0)
        $LockStream.Write($LockBytes, 0, $LockBytes.Length)
        $LockStream.Flush($true)

        $LockStream
    }
    catch {
        $LockStream.Dispose()
        throw
    }
}

function Get-TriTierExecutionStatePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RunId
    )

    Join-Path (
        Get-TriTierExecutionDirectory `
            -ProjectPath $ProjectPath `
            -RunId $RunId
    ) 'execution-loop.json'
}

function Get-TriTierExecutionRunStatePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RunId
    )

    Join-Path (
        Get-TriTierExecutionRunDirectory `
            -ProjectPath $ProjectPath `
            -RunId $RunId
    ) 'state\run-state.json'
}

function Get-TriTierExecutionNextActionPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RunId
    )

    Join-Path (
        Get-TriTierExecutionRunDirectory `
            -ProjectPath $ProjectPath `
            -RunId $RunId
    ) 'state\next-action.txt'
}

function Write-TriTierExecutionAtomicText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Content
    )

    $Directory = Split-Path -Parent $Path

    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    }

    $TemporaryPath = (
        $Path +
        '.tmp.' +
        [guid]::NewGuid().ToString('N')
    )
    $Encoding = [System.Text.UTF8Encoding]::new($false)

    try {
        [System.IO.File]::WriteAllText(
            $TemporaryPath,
            $Content,
            $Encoding
        )

        [System.IO.File]::Move(
            $TemporaryPath,
            $Path,
            $true
        )
    }
    finally {
        if (Test-Path -LiteralPath $TemporaryPath -PathType Leaf) {
            Remove-Item -LiteralPath $TemporaryPath -Force
        }
    }
}

function Write-TriTierExecutionAtomicJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$InputObject
    )

    $Json = $InputObject | ConvertTo-Json -Depth 100

    Write-TriTierExecutionAtomicText `
        -Path $Path `
        -Content ($Json + [Environment]::NewLine)
}

function Read-TriTierExecutionJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter()]
        [AllowNull()]
        [object]$DefaultValue = $null
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $DefaultValue
    }

    try {
        Get-Content `
            -LiteralPath $Path `
            -Raw `
            -Encoding UTF8 |
            ConvertFrom-Json
    }
    catch {
        throw "Execution JSON is invalid: $Path :: $($_.Exception.Message)"
    }
}

function Get-TriTierExecutionHash {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Value
    )

    $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
    $Sha = [System.Security.Cryptography.SHA256]::Create()

    try {
        $Hash = $Sha.ComputeHash($Bytes)

        (
            [System.BitConverter]::ToString($Hash)
        ).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $Sha.Dispose()
    }
}

function Get-TriTierExecutionActionKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$RunState,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Decision
    )

    $Parts = @(
        [string](
            Get-TriTierExecutionProperty `
                -InputObject $RunState `
                -Name 'runId' `
                -Required
        )
        [string](
            Get-TriTierExecutionProperty `
                -InputObject $RunState `
                -Name 'status' `
                -Required
        )
        [string](
            Get-TriTierExecutionProperty `
                -InputObject $RunState `
                -Name 'currentTask' `
                -DefaultValue ''
        )
        [string](
            Get-TriTierExecutionProperty `
                -InputObject $Decision `
                -Name 'stage' `
                -Required
        )
        [string](
            Get-TriTierExecutionProperty `
                -InputObject $Decision `
                -Name 'responsibleParty' `
                -Required
        )
        [string](
            Get-TriTierExecutionProperty `
                -InputObject $Decision `
                -Name 'blockedScope' `
                -DefaultValue 'NONE'
        )
        [string](
            Get-TriTierExecutionProperty `
                -InputObject $Decision `
                -Name 'findingId' `
                -DefaultValue ''
        )
        [string](
            Get-TriTierExecutionProperty `
                -InputObject $Decision `
                -Name 'phaseId' `
                -DefaultValue ''
        )
        [string](
            Get-TriTierExecutionProperty `
                -InputObject $Decision `
                -Name 'nextAction' `
                -Required
        )
    )

    Get-TriTierExecutionHash -Value ($Parts -join "`n")
}

function Add-TriTierExecutionHistoryEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$LoopState,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$EventType,

        [Parameter()]
        [string]$ActionKey = '',

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Summary,

        [Parameter()]
        [AllowNull()]
        [object]$Details = $null
    )

    $History = @(
        Get-TriTierExecutionProperty `
            -InputObject $LoopState `
            -Name 'history' `
            -DefaultValue @()
    )

    $History += [PSCustomObject][ordered]@{
        eventId = [guid]::NewGuid().ToString('N')
        eventType = $EventType
        actionKey = $ActionKey
        summary = $Summary
        details = $Details
        createdUtc = [DateTime]::UtcNow.ToString('o')
    }

    $LoopState.history = @($History)
    $LoopState.revision = [int]$LoopState.revision + 1
    $LoopState.updatedUtc = [DateTime]::UtcNow.ToString('o')

    $LoopState
}

function Test-TriTierExecutionLoopState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$LoopState
    )

    foreach ($RequiredProperty in @(
        'schemaVersion'
        'runId'
        'status'
        'currentStep'
        'sameDecisionCount'
        'lastActionKey'
        'lastCompletedActionKey'
        'inFlight'
        'dispatcherPath'
        'maxSteps'
        'maxSameDecision'
        'maxAttemptsPerAction'
        'stepTimeoutSeconds'
        'history'
        'revision'
        'createdUtc'
        'updatedUtc'
    )) {
        [void](
            Get-TriTierExecutionProperty `
                -InputObject $LoopState `
                -Name $RequiredProperty `
                -Required
        )
    }

    if (
        [int]$LoopState.schemaVersion -ne
        $script:ExecutionLoopSchemaVersion
    ) {
        throw (
            'Unsupported execution-loop schema version: ' +
            [string]$LoopState.schemaVersion
        )
    }

    if ([string]$LoopState.status -notin $script:AllowedExecutionStatuses) {
        throw "Unsupported execution-loop status: $($LoopState.status)"
    }

    [void](ConvertTo-TriTierExecutionSafeId -Value ([string]$LoopState.runId))

    foreach ($RangeCheck in @(
        @{
            Name = 'currentStep'
            Value = [int]$LoopState.currentStep
            Minimum = 0
            Maximum = 1000000
        }
        @{
            Name = 'sameDecisionCount'
            Value = [int]$LoopState.sameDecisionCount
            Minimum = 0
            Maximum = 1000000
        }
        @{
            Name = 'maxSteps'
            Value = [int]$LoopState.maxSteps
            Minimum = 1
            Maximum = 10000
        }
        @{
            Name = 'maxSameDecision'
            Value = [int]$LoopState.maxSameDecision
            Minimum = 1
            Maximum = 100
        }
        @{
            Name = 'maxAttemptsPerAction'
            Value = [int]$LoopState.maxAttemptsPerAction
            Minimum = 1
            Maximum = 20
        }
        @{
            Name = 'stepTimeoutSeconds'
            Value = [int]$LoopState.stepTimeoutSeconds
            Minimum = 1
            Maximum = 86400
        }
    )) {
        if (
            $RangeCheck.Value -lt $RangeCheck.Minimum -or
            $RangeCheck.Value -gt $RangeCheck.Maximum
        ) {
            throw (
                "Execution-loop $($RangeCheck.Name) is outside the " +
                'supported range.'
            )
        }
    }

    if (
        $null -ne $LoopState.inFlight -and
        [string]::IsNullOrWhiteSpace(
            [string](
                Get-TriTierExecutionProperty `
                    -InputObject $LoopState.inFlight `
                    -Name 'actionKey' `
                    -DefaultValue ''
            )
        )
    ) {
        throw 'Execution-loop inFlight state requires an actionKey.'
    }

    $true
}

function Save-TriTierRunExecutionLoop {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RunId,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$LoopState
    )

    $SafeRunId = ConvertTo-TriTierExecutionSafeId -Value $RunId

    [void](Test-TriTierExecutionLoopState -LoopState $LoopState)

    if ([string]$LoopState.runId -ne $SafeRunId) {
        throw (
            'Execution-loop state identity does not match the save target: ' +
            $SafeRunId
        )
    }

    Write-TriTierExecutionAtomicJson `
        -Path (
            Get-TriTierExecutionStatePath `
                -ProjectPath $ProjectPath `
                -RunId $SafeRunId
        ) `
        -InputObject $LoopState

    $LoopState
}

function Get-TriTierRunExecutionLoop {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RunId,

        [Parameter()]
        [switch]$AllowMissing
    )

    $SafeRunId = ConvertTo-TriTierExecutionSafeId -Value $RunId
    $Path = Get-TriTierExecutionStatePath `
        -ProjectPath $ProjectPath `
        -RunId $SafeRunId

    $LoopState = Read-TriTierExecutionJson `
        -Path $Path `
        -DefaultValue $null

    if ($null -eq $LoopState) {
        if ($AllowMissing) {
            return $null
        }

        throw "Execution-loop state does not exist for run: $SafeRunId"
    }

    [void](Test-TriTierExecutionLoopState -LoopState $LoopState)

    if ([string]$LoopState.runId -ne $SafeRunId) {
        throw (
            'Execution-loop state identity does not match the requested ' +
            "run ID: $SafeRunId"
        )
    }

    $LoopState
}

function New-TriTierExecutionLoopState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RunId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DispatcherPath,

        [Parameter(Mandatory)]
        [ValidateRange(1, 10000)]
        [int]$MaxSteps,

        [Parameter(Mandatory)]
        [ValidateRange(1, 100)]
        [int]$MaxSameDecision,

        [Parameter(Mandatory)]
        [ValidateRange(1, 20)]
        [int]$MaxAttemptsPerAction,

        [Parameter(Mandatory)]
        [ValidateRange(1, 86400)]
        [int]$StepTimeoutSeconds
    )

    $Now = [DateTime]::UtcNow.ToString('o')

    [PSCustomObject][ordered]@{
        schemaVersion = $script:ExecutionLoopSchemaVersion
        runId = ConvertTo-TriTierExecutionSafeId -Value $RunId
        status = 'IDLE'
        currentStep = 0
        sameDecisionCount = 0
        lastActionKey = ''
        lastCompletedActionKey = ''
        lastDecision = $null
        lastDispatchResult = $null
        inFlight = $null
        dispatcherPath = [System.IO.Path]::GetFullPath($DispatcherPath)
        maxSteps = $MaxSteps
        maxSameDecision = $MaxSameDecision
        maxAttemptsPerAction = $MaxAttemptsPerAction
        stepTimeoutSeconds = $StepTimeoutSeconds
        stopReason = ''
        history = @()
        revision = 0
        createdUtc = $Now
        updatedUtc = $Now
    }
}

function Initialize-TriTierRunExecutionLoopCore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RunId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DispatcherPath,

        [Parameter()]
        [ValidateRange(1, 10000)]
        [int]$MaxSteps = 25,

        [Parameter()]
        [ValidateRange(1, 100)]
        [int]$MaxSameDecision = 2,

        [Parameter()]
        [ValidateRange(1, 20)]
        [int]$MaxAttemptsPerAction = 2,

        [Parameter()]
        [ValidateRange(1, 86400)]
        [int]$StepTimeoutSeconds = 1800
    )

    if (-not (Test-Path -LiteralPath $DispatcherPath -PathType Leaf)) {
        throw "Execution dispatcher does not exist: $DispatcherPath"
    }

    $RunState = Get-TriTierRunState `
        -ProjectPath $ProjectPath `
        -RunId $RunId

    [void](
        Get-TriTierExecutionProperty `
            -InputObject $RunState `
            -Name 'runId' `
            -Required
    )

    $Existing = Get-TriTierRunExecutionLoop `
        -ProjectPath $ProjectPath `
        -RunId $RunId `
        -AllowMissing

    if ($null -ne $Existing) {
        $Existing.dispatcherPath = [System.IO.Path]::GetFullPath(
            $DispatcherPath
        )
        $Existing.maxSteps = $MaxSteps
        $Existing.maxSameDecision = $MaxSameDecision
        $Existing.maxAttemptsPerAction = $MaxAttemptsPerAction
        $Existing.stepTimeoutSeconds = $StepTimeoutSeconds

        if ($null -ne $Existing.inFlight) {
            $Existing.status = 'RECOVERING'
            $Existing = Add-TriTierExecutionHistoryEvent `
                -LoopState $Existing `
                -EventType 'INTERRUPTED_ACTION_RECOVERED' `
                -ActionKey ([string]$Existing.inFlight.actionKey) `
                -Summary (
                    'Recovered an interrupted in-flight action and will ' +
                    're-evaluate it before dispatch.'
                )
        }
        elseif ($Existing.status -notin @(
            'COMPLETE'
            'ABORTED'
        )) {
            $Existing.status = 'IDLE'
        }

        return Save-TriTierRunExecutionLoop `
            -ProjectPath $ProjectPath `
            -RunId $RunId `
            -LoopState $Existing
    }

    $LoopState = New-TriTierExecutionLoopState `
        -RunId $RunId `
        -DispatcherPath $DispatcherPath `
        -MaxSteps $MaxSteps `
        -MaxSameDecision $MaxSameDecision `
        -MaxAttemptsPerAction $MaxAttemptsPerAction `
        -StepTimeoutSeconds $StepTimeoutSeconds

    $LoopState = Add-TriTierExecutionHistoryEvent `
        -LoopState $LoopState `
        -EventType 'EXECUTION_LOOP_INITIALIZED' `
        -Summary 'Initialized durable automatic execution-loop state.'

    Save-TriTierRunExecutionLoop `
        -ProjectPath $ProjectPath `
        -RunId $RunId `
        -LoopState $LoopState
}

function Initialize-TriTierRunExecutionLoop {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RunId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DispatcherPath,

        [Parameter()]
        [ValidateRange(1, 10000)]
        [int]$MaxSteps = 25,

        [Parameter()]
        [ValidateRange(1, 100)]
        [int]$MaxSameDecision = 2,

        [Parameter()]
        [ValidateRange(1, 20)]
        [int]$MaxAttemptsPerAction = 2,

        [Parameter()]
        [ValidateRange(1, 86400)]
        [int]$StepTimeoutSeconds = 1800
    )

    if (-not (Test-Path -LiteralPath $DispatcherPath -PathType Leaf)) {
        throw "Execution dispatcher does not exist: $DispatcherPath"
    }

    $ExecutionLock = Enter-TriTierExecutionLock `
        -ProjectPath $ProjectPath `
        -RunId $RunId

    try {
        Initialize-TriTierRunExecutionLoopCore `
            -ProjectPath $ProjectPath `
            -RunId $RunId `
            -DispatcherPath $DispatcherPath `
            -MaxSteps $MaxSteps `
            -MaxSameDecision $MaxSameDecision `
            -MaxAttemptsPerAction $MaxAttemptsPerAction `
            -StepTimeoutSeconds $StepTimeoutSeconds
    }
    finally {
        $ExecutionLock.Dispose()
    }
}

function Get-TriTierExecutionCheckpointArguments {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RunId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Summary,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$RunState
    )

    $Command = Get-Command `
        -Module $StateModule.Name `
        -Name 'New-TriTierCheckpoint' `
        -CommandType Function `
        -ErrorAction Stop

    $ExpectedParameters = @(
        'ProjectPath'
        'RunId'
        'Summary'
        'NextAction'
        'CurrentPhase'
        'CurrentTask'
        'CompletedTasks'
        'UnresolvedFindings'
        'Blockers'
    )

    foreach ($ExpectedParameter in $ExpectedParameters) {
        if (-not $Command.Parameters.ContainsKey($ExpectedParameter)) {
            throw (
                'New-TriTierCheckpoint is missing the expected parameter: ' +
                $ExpectedParameter
            )
        }
    }

    $Arguments = @{
        ProjectPath = $ProjectPath
        RunId = $RunId
        Summary = $Summary
        NextAction = [string](
            Get-TriTierExecutionProperty `
                -InputObject $RunState `
                -Name 'nextAction' `
                -DefaultValue 'Continue from the persisted run state.'
        )
        CurrentPhase = [string](
            Get-TriTierExecutionProperty `
                -InputObject $RunState `
                -Name 'currentPhase' `
                -DefaultValue ''
        )
        CurrentTask = [string](
            Get-TriTierExecutionProperty `
                -InputObject $RunState `
                -Name 'currentTask' `
                -DefaultValue ''
        )
        CompletedTasks = @(
            Get-TriTierExecutionProperty `
                -InputObject $RunState `
                -Name 'completedTasks' `
                -DefaultValue @()
        )
        UnresolvedFindings = @(
            Get-TriTierExecutionProperty `
                -InputObject $RunState `
                -Name 'unresolvedFindings' `
                -DefaultValue @()
        )
        Blockers = @(
            Get-TriTierExecutionProperty `
                -InputObject $RunState `
                -Name 'blockers' `
                -DefaultValue @()
        )
    }

    foreach ($Parameter in $Command.Parameters.Values) {
        $IsMandatory = @(
            $Parameter.Attributes |
                Where-Object {
                    (
                        $_ -is
                        [System.Management.Automation.ParameterAttribute]
                    ) -and $_.Mandatory
                }
        ).Count -gt 0

        if (
            $IsMandatory -and
            -not $Arguments.ContainsKey($Parameter.Name)
        ) {
            throw (
                'New-TriTierCheckpoint has an unmapped mandatory parameter: ' +
                $Parameter.Name
            )
        }
    }

    $Arguments
}

function New-TriTierExecutionCheckpoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RunId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Summary,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$RunState
    )

    $Arguments = Get-TriTierExecutionCheckpointArguments `
        -ProjectPath $ProjectPath `
        -RunId $RunId `
        -Summary $Summary `
        -RunState $RunState

    $CheckpointCommand = Get-Command `
        -Module $StateModule.Name `
        -Name 'New-TriTierCheckpoint' `
        -CommandType Function `
        -ErrorAction Stop

    & $CheckpointCommand @Arguments
}

function New-TriTierExecutionEnvelope {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$RunState,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Decision,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$LoopState,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ActionKey,

        [Parameter(Mandatory)]
        [ValidateRange(1, 20)]
        [int]$Attempt,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RunId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ResultPath
    )

    $ResolvedProfile = Resolve-TriTierAgentProfile -Decision $Decision
    $Handoff = New-TriTierAgentHandoff `
        -RunState $RunState `
        -Decision $Decision
    $ResolvedProfileName = if ($null -eq $ResolvedProfile) {
        ''
    }
    else {
        [string]$ResolvedProfile.name
    }

    [PSCustomObject][ordered]@{
        schemaVersion = $script:ExecutionEnvelopeSchemaVersion
        actionKey = $ActionKey
        attempt = $Attempt
        step = [int]$LoopState.currentStep + 1
        projectPath = [System.IO.Path]::GetFullPath($ProjectPath)
        runId = $RunId
        profileName = $ResolvedProfileName
        profile = $ResolvedProfile
        handoff = $Handoff
        runStatePath = Get-TriTierExecutionRunStatePath `
            -ProjectPath $ProjectPath `
            -RunId $RunId
        nextActionPath = Get-TriTierExecutionNextActionPath `
            -ProjectPath $ProjectPath `
            -RunId $RunId
        resultPath = $ResultPath
        runState = $RunState
        decision = $Decision
        issuedUtc = [DateTime]::UtcNow.ToString('o')
    }
}

function Invoke-TriTierExecutionDispatcher {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DispatcherPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$EnvelopePath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ResultPath,

        [Parameter(Mandatory)]
        [ValidateRange(1, 86400)]
        [int]$TimeoutSeconds
    )

    $PwshPath = (Get-Command pwsh -ErrorAction Stop).Source
    $StartInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $StartInfo.FileName = $PwshPath
    $StartInfo.UseShellExecute = $false
    $StartInfo.CreateNoWindow = $true
    $StartInfo.RedirectStandardOutput = $true
    $StartInfo.RedirectStandardError = $true

    foreach ($Argument in @(
        '-NoLogo'
        '-NoProfile'
        '-NonInteractive'
        '-File'
        [System.IO.Path]::GetFullPath($DispatcherPath)
        '-EnvelopePath'
        [System.IO.Path]::GetFullPath($EnvelopePath)
        '-ResultPath'
        [System.IO.Path]::GetFullPath($ResultPath)
    )) {
        [void]$StartInfo.ArgumentList.Add([string]$Argument)
    }

    $Process = [System.Diagnostics.Process]::new()
    $Process.StartInfo = $StartInfo

    try {
        if (-not $Process.Start()) {
            throw 'PowerShell dispatcher process did not start.'
        }

        $StandardOutputTask = $Process.StandardOutput.ReadToEndAsync()
        $StandardErrorTask = $Process.StandardError.ReadToEndAsync()
        $Completed = $Process.WaitForExit($TimeoutSeconds * 1000)

        if (-not $Completed) {
            try {
                $Process.Kill($true)
            }
            catch {}

            [void]$Process.WaitForExit()

            throw (
                "Execution dispatcher timed out after $TimeoutSeconds seconds."
            )
        }

        $StandardOutput = $StandardOutputTask.GetAwaiter().GetResult()
        $StandardError = $StandardErrorTask.GetAwaiter().GetResult()

        [PSCustomObject][ordered]@{
            exitCode = [int]$Process.ExitCode
            stdout = [string]$StandardOutput
            stderr = [string]$StandardError
        }
    }
    finally {
        $Process.Dispose()
    }
}

function Test-TriTierExecutionDispatcherResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Result,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ExpectedActionKey
    )

    foreach ($RequiredProperty in @(
        'schemaVersion'
        'actionKey'
        'outcome'
        'summary'
    )) {
        [void](
            Get-TriTierExecutionProperty `
                -InputObject $Result `
                -Name $RequiredProperty `
                -Required
        )
    }

    if (
        [int]$Result.schemaVersion -ne
        $script:ExecutionResultSchemaVersion
    ) {
        throw (
            'Unsupported dispatcher-result schema version: ' +
            [string]$Result.schemaVersion
        )
    }

    if ([string]$Result.actionKey -ne $ExpectedActionKey) {
        throw 'Dispatcher result does not match the dispatched action key.'
    }

    if ([string]$Result.outcome -notin @(
        'STATE_UPDATED'
        'NO_CHANGE'
    )) {
        throw "Unsupported dispatcher outcome: $($Result.outcome)"
    }

    if ([string]::IsNullOrWhiteSpace([string]$Result.summary)) {
        throw 'Dispatcher result requires a non-empty summary.'
    }

    $true
}

function Get-TriTierExecutionTerminalStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$RunState,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Decision
    )

    $RunStatus = [string](
        Get-TriTierExecutionProperty `
            -InputObject $RunState `
            -Name 'status' `
            -Required
    )
    $Stage = [string](
        Get-TriTierExecutionProperty `
            -InputObject $Decision `
            -Name 'stage' `
            -Required
    )

    if ($Stage -eq 'OWNER_DECISION') {
        return 'WAITING_OWNER'
    }

    if ($Stage -eq 'WAIT_EXTERNAL') {
        return 'WAITING_EXTERNAL'
    }

    if ($Stage -eq 'STOP') {
        if ($RunStatus -in @(
            'COMPLETE'
            'COMPLETE_WITH_DEFERMENTS'
        )) {
            return 'COMPLETE'
        }

        if ($RunStatus -eq 'ABORTED_FOR_SAFETY') {
            return 'ABORTED'
        }

        return 'FAILED'
    }

    if (
        -not [bool](
            Get-TriTierExecutionProperty `
                -InputObject $Decision `
                -Name 'canContinue' `
                -Required
        )
    ) {
        return 'PAUSED_BLOCKED'
    }

    ''
}

function New-TriTierExecutionInvocationResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$LoopState,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$RunState,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Decision,

        [Parameter()]
        [AllowNull()]
        [object]$Envelope = $null,

        [Parameter()]
        [bool]$Dispatched = $false,

        [Parameter()]
        [bool]$DryRun = $false
    )

    [PSCustomObject][ordered]@{
        loop = $LoopState
        state = $RunState
        decision = $Decision
        envelope = $Envelope
        dispatched = $Dispatched
        dryRun = $DryRun
    }
}

function Invoke-TriTierRunExecutionLoopCore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RunId,

        [Parameter()]
        [string]$DispatcherPath = '',

        [Parameter()]
        [ValidateRange(1, 10000)]
        [int]$MaxSteps = 25,

        [Parameter()]
        [ValidateRange(1, 100)]
        [int]$MaxSameDecision = 2,

        [Parameter()]
        [ValidateRange(1, 20)]
        [int]$MaxAttemptsPerAction = 2,

        [Parameter()]
        [ValidateRange(1, 86400)]
        [int]$StepTimeoutSeconds = 1800,

        [Parameter()]
        [switch]$DryRun
    )

    $RunState = Get-TriTierRunState `
        -ProjectPath $ProjectPath `
        -RunId $RunId

    $Decision = Get-TriTierRunOrchestrationDecision `
        -ProjectPath $ProjectPath `
        -RunId $RunId

    if ($DryRun) {
        $DryRunLoop = [PSCustomObject][ordered]@{
            schemaVersion = $script:ExecutionLoopSchemaVersion
            runId = $RunId
            status = 'IDLE'
            currentStep = 0
            sameDecisionCount = 0
            lastActionKey = ''
            lastCompletedActionKey = ''
            lastDecision = $Decision
            lastDispatchResult = $null
            inFlight = $null
            dispatcherPath = $DispatcherPath
            maxSteps = $MaxSteps
            maxSameDecision = $MaxSameDecision
            maxAttemptsPerAction = $MaxAttemptsPerAction
            stepTimeoutSeconds = $StepTimeoutSeconds
            stopReason = 'Dry run; no durable execution state was written.'
            history = @()
            revision = 0
            createdUtc = [DateTime]::UtcNow.ToString('o')
            updatedUtc = [DateTime]::UtcNow.ToString('o')
        }

        $DryRunActionKey = Get-TriTierExecutionActionKey `
            -RunState $RunState `
            -Decision $Decision

        $DryRunResultPath = Join-Path (
            Get-TriTierExecutionDirectory `
                -ProjectPath $ProjectPath `
                -RunId $RunId
        ) 'dry-run-result.json'

        $DryRunEnvelope = New-TriTierExecutionEnvelope `
            -RunState $RunState `
            -Decision $Decision `
            -LoopState $DryRunLoop `
            -ActionKey $DryRunActionKey `
            -Attempt 1 `
            -ProjectPath $ProjectPath `
            -RunId $RunId `
            -ResultPath $DryRunResultPath

        return New-TriTierExecutionInvocationResult `
            -LoopState $DryRunLoop `
            -RunState $RunState `
            -Decision $Decision `
            -Envelope $DryRunEnvelope `
            -DryRun $true
    }

    if ([string]::IsNullOrWhiteSpace($DispatcherPath)) {
        throw (
            'Automatic execution requires -DispatcherPath unless -DryRun ' +
            'is used.'
        )
    }

    $LoopState = Initialize-TriTierRunExecutionLoopCore `
        -ProjectPath $ProjectPath `
        -RunId $RunId `
        -DispatcherPath $DispatcherPath `
        -MaxSteps $MaxSteps `
        -MaxSameDecision $MaxSameDecision `
        -MaxAttemptsPerAction $MaxAttemptsPerAction `
        -StepTimeoutSeconds $StepTimeoutSeconds

    $WasDispatched = $false
    $LastEnvelope = $null

    for ($Iteration = 0; $Iteration -lt $MaxSteps; $Iteration++) {
        $RunState = Get-TriTierRunState `
            -ProjectPath $ProjectPath `
            -RunId $RunId

        $Decision = Get-TriTierRunOrchestrationDecision `
            -ProjectPath $ProjectPath `
            -RunId $RunId

        $TerminalStatus = Get-TriTierExecutionTerminalStatus `
            -RunState $RunState `
            -Decision $Decision

        if (-not [string]::IsNullOrWhiteSpace($TerminalStatus)) {
            $LoopState.status = $TerminalStatus
            $LoopState.stopReason = [string]$Decision.reason
            $LoopState.lastDecision = $Decision
            $LoopState.inFlight = $null
            $LoopState = Add-TriTierExecutionHistoryEvent `
                -LoopState $LoopState `
                -EventType 'EXECUTION_STOPPED' `
                -Summary (
                    "Execution stopped with status $TerminalStatus."
                ) `
                -Details $Decision

            $LoopState = Save-TriTierRunExecutionLoop `
                -ProjectPath $ProjectPath `
                -RunId $RunId `
                -LoopState $LoopState

            return New-TriTierExecutionInvocationResult `
                -LoopState $LoopState `
                -RunState $RunState `
                -Decision $Decision `
                -Envelope $LastEnvelope `
                -Dispatched $WasDispatched
        }

        if ([int]$LoopState.currentStep -ge $MaxSteps) {
            $LoopState.status = 'PAUSED_LIMIT'
            $LoopState.stopReason = (
                "Execution reached the configured $MaxSteps-step limit."
            )
            $LoopState.lastDecision = $Decision
            $LoopState.inFlight = $null
            $LoopState = Add-TriTierExecutionHistoryEvent `
                -LoopState $LoopState `
                -EventType 'STEP_LIMIT_REACHED' `
                -Summary $LoopState.stopReason `
                -Details $Decision

            $LoopState = Save-TriTierRunExecutionLoop `
                -ProjectPath $ProjectPath `
                -RunId $RunId `
                -LoopState $LoopState

            return New-TriTierExecutionInvocationResult `
                -LoopState $LoopState `
                -RunState $RunState `
                -Decision $Decision `
                -Envelope $LastEnvelope `
                -Dispatched $WasDispatched
        }

        $ActionKey = Get-TriTierExecutionActionKey `
            -RunState $RunState `
            -Decision $Decision

        if ([string]$LoopState.lastCompletedActionKey -eq $ActionKey) {
            $LoopState.sameDecisionCount = (
                [int]$LoopState.sameDecisionCount + 1
            )
        }
        else {
            $LoopState.sameDecisionCount = 0
        }

        if (
            [int]$LoopState.sameDecisionCount -ge
            $MaxSameDecision
        ) {
            $LoopState.status = 'PAUSED_STALLED'
            $LoopState.stopReason = (
                'The same durable orchestration decision repeated without ' +
                'progress.'
            )
            $LoopState.lastDecision = $Decision
            $LoopState.inFlight = $null
            $LoopState = Add-TriTierExecutionHistoryEvent `
                -LoopState $LoopState `
                -EventType 'STALL_DETECTED' `
                -ActionKey $ActionKey `
                -Summary $LoopState.stopReason `
                -Details $Decision

            $LoopState = Save-TriTierRunExecutionLoop `
                -ProjectPath $ProjectPath `
                -RunId $RunId `
                -LoopState $LoopState

            return New-TriTierExecutionInvocationResult `
                -LoopState $LoopState `
                -RunState $RunState `
                -Decision $Decision `
                -Envelope $LastEnvelope `
                -Dispatched $WasDispatched
        }

        $Attempt = @(
            $LoopState.history |
                Where-Object {
                    [string]$_.eventType -eq 'DISPATCH_STARTED' -and
                    [string]$_.actionKey -eq $ActionKey
                }
        ).Count + 1

        if ($Attempt -gt $MaxAttemptsPerAction) {
            $LoopState.status = 'FAILED'
            $LoopState.stopReason = (
                "Action $ActionKey exceeded the configured retry limit."
            )
            $LoopState.lastDecision = $Decision
            $LoopState.inFlight = $null
            $LoopState = Add-TriTierExecutionHistoryEvent `
                -LoopState $LoopState `
                -EventType 'ACTION_RETRY_LIMIT_REACHED' `
                -ActionKey $ActionKey `
                -Summary $LoopState.stopReason `
                -Details $Decision

            $LoopState = Save-TriTierRunExecutionLoop `
                -ProjectPath $ProjectPath `
                -RunId $RunId `
                -LoopState $LoopState

            return New-TriTierExecutionInvocationResult `
                -LoopState $LoopState `
                -RunState $RunState `
                -Decision $Decision `
                -Envelope $LastEnvelope `
                -Dispatched $WasDispatched
        }

        $ExecutionDirectory = Get-TriTierExecutionDirectory `
            -ProjectPath $ProjectPath `
            -RunId $RunId
        $DispatchDirectory = Join-Path $ExecutionDirectory 'dispatches'

        if (-not (Test-Path -LiteralPath $DispatchDirectory)) {
            New-Item `
                -ItemType Directory `
                -Path $DispatchDirectory `
                -Force |
                Out-Null
        }

        $ActionPrefix = $ActionKey.Substring(0, 12)
        $StepNumber = [int]$LoopState.currentStep + 1
        $BaseName = (
            'step-{0:D4}-{1}-attempt-{2:D2}' -f
            $StepNumber,
            $ActionPrefix,
            $Attempt
        )
        $EnvelopePath = Join-Path $DispatchDirectory (
            $BaseName + '-envelope.json'
        )
        $ResultPath = Join-Path $DispatchDirectory (
            $BaseName + '-result.json'
        )

        $Envelope = New-TriTierExecutionEnvelope `
            -RunState $RunState `
            -Decision $Decision `
            -LoopState $LoopState `
            -ActionKey $ActionKey `
            -Attempt $Attempt `
            -ProjectPath $ProjectPath `
            -RunId $RunId `
            -ResultPath $ResultPath

        Write-TriTierExecutionAtomicJson `
            -Path $EnvelopePath `
            -InputObject $Envelope

        if (Test-Path -LiteralPath $ResultPath -PathType Leaf) {
            Remove-Item -LiteralPath $ResultPath -Force
        }

        $LoopState.status = 'RUNNING'
        $LoopState.lastActionKey = $ActionKey
        $LoopState.lastDecision = $Decision
        $LoopState.inFlight = [PSCustomObject][ordered]@{
            actionKey = $ActionKey
            attempt = $Attempt
            step = $StepNumber
            envelopePath = $EnvelopePath
            resultPath = $ResultPath
            startedUtc = [DateTime]::UtcNow.ToString('o')
        }
        $LoopState = Add-TriTierExecutionHistoryEvent `
            -LoopState $LoopState `
            -EventType 'DISPATCH_STARTED' `
            -ActionKey $ActionKey `
            -Summary (
                "Started execution dispatch for stage $($Decision.stage)."
            ) `
            -Details $LoopState.inFlight

        $LoopState = Save-TriTierRunExecutionLoop `
            -ProjectPath $ProjectPath `
            -RunId $RunId `
            -LoopState $LoopState

        [void](
            New-TriTierExecutionCheckpoint `
                -ProjectPath $ProjectPath `
                -RunId $RunId `
                -Summary (
                    "Before automatic execution step ${StepNumber}: " +
                    [string]$Decision.stage
                ) `
                -RunState $RunState
        )

        try {
            $ProcessResult = Invoke-TriTierExecutionDispatcher `
                -DispatcherPath $LoopState.dispatcherPath `
                -EnvelopePath $EnvelopePath `
                -ResultPath $ResultPath `
                -TimeoutSeconds $StepTimeoutSeconds

            if ([int]$ProcessResult.exitCode -ne 0) {
                throw (
                    'Execution dispatcher returned exit code ' +
                    "$($ProcessResult.exitCode). STDERR: " +
                    [string]$ProcessResult.stderr
                )
            }

            if (-not (Test-Path -LiteralPath $ResultPath -PathType Leaf)) {
                throw (
                    'Execution dispatcher completed without writing the ' +
                    'required result file.'
                )
            }

            $DispatcherResult = Read-TriTierExecutionJson `
                -Path $ResultPath

            [void](
                Test-TriTierExecutionDispatcherResult `
                    -Result $DispatcherResult `
                    -ExpectedActionKey $ActionKey
            )

            $UpdatedRunState = Get-TriTierRunState `
                -ProjectPath $ProjectPath `
                -RunId $RunId
            $UpdatedDecision = Get-TriTierRunOrchestrationDecision `
                -ProjectPath $ProjectPath `
                -RunId $RunId
            $UpdatedActionKey = Get-TriTierExecutionActionKey `
                -RunState $UpdatedRunState `
                -Decision $UpdatedDecision

            if (
                [string]$DispatcherResult.outcome -eq 'STATE_UPDATED' -and
                $UpdatedActionKey -eq $ActionKey
            ) {
                throw (
                    'Dispatcher claimed STATE_UPDATED, but the durable ' +
                    'orchestration action did not change.'
                )
            }

            if (
                [string]$DispatcherResult.outcome -eq 'NO_CHANGE' -and
                $UpdatedActionKey -ne $ActionKey
            ) {
                throw (
                    'Dispatcher claimed NO_CHANGE, but the durable ' +
                    'orchestration action changed.'
                )
            }

            $LoopState.currentStep = $StepNumber
            $LoopState.lastCompletedActionKey = $ActionKey
            $LoopState.lastDispatchResult = $DispatcherResult
            $LoopState.inFlight = $null
            $LoopState.lastDecision = $UpdatedDecision
            $LoopState = Add-TriTierExecutionHistoryEvent `
                -LoopState $LoopState `
                -EventType 'DISPATCH_COMPLETED' `
                -ActionKey $ActionKey `
                -Summary ([string]$DispatcherResult.summary) `
                -Details ([PSCustomObject][ordered]@{
                    process = $ProcessResult
                    dispatcher = $DispatcherResult
                })

            $LoopState = Save-TriTierRunExecutionLoop `
                -ProjectPath $ProjectPath `
                -RunId $RunId `
                -LoopState $LoopState

            [void](
                New-TriTierExecutionCheckpoint `
                    -ProjectPath $ProjectPath `
                    -RunId $RunId `
                    -Summary (
                        "After automatic execution step ${StepNumber}: " +
                        [string]$UpdatedDecision.stage
                    ) `
                    -RunState $UpdatedRunState
            )

            $WasDispatched = $true
            $LastEnvelope = $Envelope
        }
        catch {
            $FailureMessage = $_.Exception.Message
            $LoopState.status = 'FAILED'
            $LoopState.stopReason = $FailureMessage
            $LoopState.inFlight = $null
            $LoopState = Add-TriTierExecutionHistoryEvent `
                -LoopState $LoopState `
                -EventType 'DISPATCH_FAILED' `
                -ActionKey $ActionKey `
                -Summary $FailureMessage `
                -Details $Decision

            [void](
                Save-TriTierRunExecutionLoop `
                    -ProjectPath $ProjectPath `
                    -RunId $RunId `
                    -LoopState $LoopState
            )

            throw
        }
    }

    $RunState = Get-TriTierRunState `
        -ProjectPath $ProjectPath `
        -RunId $RunId
    $Decision = Get-TriTierRunOrchestrationDecision `
        -ProjectPath $ProjectPath `
        -RunId $RunId

    $LoopState.status = 'PAUSED_LIMIT'
    $LoopState.stopReason = (
        "Execution invocation reached the configured $MaxSteps-step limit."
    )
    $LoopState.lastDecision = $Decision
    $LoopState.inFlight = $null
    $LoopState = Add-TriTierExecutionHistoryEvent `
        -LoopState $LoopState `
        -EventType 'STEP_LIMIT_REACHED' `
        -Summary $LoopState.stopReason `
        -Details $Decision

    $LoopState = Save-TriTierRunExecutionLoop `
        -ProjectPath $ProjectPath `
        -RunId $RunId `
        -LoopState $LoopState

    New-TriTierExecutionInvocationResult `
        -LoopState $LoopState `
        -RunState $RunState `
        -Decision $Decision `
        -Envelope $LastEnvelope `
        -Dispatched $WasDispatched
}

function Invoke-TriTierRunExecutionLoop {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RunId,

        [Parameter()]
        [string]$DispatcherPath = '',

        [Parameter()]
        [ValidateRange(1, 10000)]
        [int]$MaxSteps = 25,

        [Parameter()]
        [ValidateRange(1, 100)]
        [int]$MaxSameDecision = 2,

        [Parameter()]
        [ValidateRange(1, 20)]
        [int]$MaxAttemptsPerAction = 2,

        [Parameter()]
        [ValidateRange(1, 86400)]
        [int]$StepTimeoutSeconds = 1800,

        [Parameter()]
        [switch]$DryRun
    )

    $Arguments = @{
        ProjectPath = $ProjectPath
        RunId = $RunId
        MaxSteps = $MaxSteps
        MaxSameDecision = $MaxSameDecision
        MaxAttemptsPerAction = $MaxAttemptsPerAction
        StepTimeoutSeconds = $StepTimeoutSeconds
    }

    if (-not [string]::IsNullOrWhiteSpace($DispatcherPath)) {
        $Arguments.DispatcherPath = $DispatcherPath
    }

    if ($DryRun) {
        $Arguments.DryRun = $true

        return Invoke-TriTierRunExecutionLoopCore @Arguments
    }

    if ([string]::IsNullOrWhiteSpace($DispatcherPath)) {
        throw (
            'Automatic execution requires -DispatcherPath unless -DryRun ' +
            'is used.'
        )
    }

    if (-not (Test-Path -LiteralPath $DispatcherPath -PathType Leaf)) {
        throw "Execution dispatcher does not exist: $DispatcherPath"
    }

    $ExecutionLock = Enter-TriTierExecutionLock `
        -ProjectPath $ProjectPath `
        -RunId $RunId

    try {
        Invoke-TriTierRunExecutionLoopCore @Arguments
    }
    finally {
        $ExecutionLock.Dispose()
    }
}

function Resume-TriTierRunExecutionLoop {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RunId,

        [Parameter()]
        [string]$DispatcherPath = '',

        [Parameter()]
        [ValidateRange(1, 10000)]
        [int]$MaxSteps = 25,

        [Parameter()]
        [ValidateRange(1, 100)]
        [int]$MaxSameDecision = 2,

        [Parameter()]
        [ValidateRange(1, 20)]
        [int]$MaxAttemptsPerAction = 2,

        [Parameter()]
        [ValidateRange(1, 86400)]
        [int]$StepTimeoutSeconds = 1800,

        [Parameter()]
        [switch]$DryRun
    )

    if ($DryRun) {
        return Invoke-TriTierRunExecutionLoop `
            -ProjectPath $ProjectPath `
            -RunId $RunId `
            -DispatcherPath $DispatcherPath `
            -MaxSteps $MaxSteps `
            -MaxSameDecision $MaxSameDecision `
            -MaxAttemptsPerAction $MaxAttemptsPerAction `
            -StepTimeoutSeconds $StepTimeoutSeconds `
            -DryRun
    }

    $Existing = Get-TriTierRunExecutionLoop `
        -ProjectPath $ProjectPath `
        -RunId $RunId

    if ([string]::IsNullOrWhiteSpace($DispatcherPath)) {
        $DispatcherPath = [string]$Existing.dispatcherPath
    }

    Invoke-TriTierRunExecutionLoop `
        -ProjectPath $ProjectPath `
        -RunId $RunId `
        -DispatcherPath $DispatcherPath `
        -MaxSteps $MaxSteps `
        -MaxSameDecision $MaxSameDecision `
        -MaxAttemptsPerAction $MaxAttemptsPerAction `
        -StepTimeoutSeconds $StepTimeoutSeconds
}

Export-ModuleMember -Function @(
    'Get-TriTierRunExecutionLoop'
    'Initialize-TriTierRunExecutionLoop'
    'Invoke-TriTierRunExecutionLoop'
    'Resume-TriTierRunExecutionLoop'
)
