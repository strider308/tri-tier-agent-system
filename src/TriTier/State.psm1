Set-StrictMode -Version Latest

$script:AllowedRunStatuses = @(
    "ACTIVE",
    "COMPLETE",
    "COMPLETE_WITH_DEFERMENTS",
    "PAUSED_BY_OWNER",
    "BLOCKED_OWNER_DECISION",
    "BLOCKED_EXTERNAL_DEPENDENCY",
    "FAILED_VALIDATION",
    "ABORTED_FOR_SAFETY"
)

function Write-TriTierAtomicText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Content
    )

    $Directory = Split-Path $Path -Parent

    if (-not (Test-Path $Directory)) {
        New-Item -ItemType Directory -Force -Path $Directory | Out-Null
    }

    $TemporaryPath = Join-Path `
        $Directory `
        ".$([IO.Path]::GetFileName($Path)).$([guid]::NewGuid().ToString('N')).tmp"

    try {
        [IO.File]::WriteAllText(
            $TemporaryPath,
            $Content,
            [Text.UTF8Encoding]::new($false)
        )

        Move-Item -Path $TemporaryPath -Destination $Path -Force
    }
    finally {
        Remove-Item $TemporaryPath -Force -ErrorAction SilentlyContinue
    }
}

function Write-TriTierAtomicJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [object]$InputObject
    )

    $Json = $InputObject | ConvertTo-Json -Depth 30

    Write-TriTierAtomicText `
        -Path $Path `
        -Content ($Json.TrimEnd() + "`n")
}

function Get-TriTierRunDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$')]
        [string]$RunId
    )

    if (-not (Test-Path $ProjectPath -PathType Container)) {
        throw "Project directory does not exist: $ProjectPath"
    }

    $ResolvedProjectPath = (Resolve-Path $ProjectPath).Path

    Join-Path `
        $ResolvedProjectPath `
        (Join-Path ".tri-tier\runs" $RunId)
}

function Get-TriTierGitSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath
    )

    $Snapshot = [ordered]@{
        repositoryDetected = $false
        baselineCommit     = ""
        workingTreeStatus  = "unknown"
    }

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        return [PSCustomObject]$Snapshot
    }

    $InsideRepository = & git -C $ProjectPath rev-parse --is-inside-work-tree 2>$null

    if ($LASTEXITCODE -ne 0 -or $InsideRepository.Trim() -ne "true") {
        return [PSCustomObject]$Snapshot
    }

    $Snapshot.repositoryDetected = $true

    $Commit = & git -C $ProjectPath rev-parse HEAD 2>$null

    if ($LASTEXITCODE -eq 0) {
        $Snapshot.baselineCommit = $Commit.Trim()
    }

    $Status = @(& git -C $ProjectPath status --porcelain 2>$null)

    if ($LASTEXITCODE -eq 0) {
        $Snapshot.workingTreeStatus = if ($Status.Count -eq 0) {
            "clean"
        }
        else {
            "dirty"
        }
    }

    [PSCustomObject]$Snapshot
}

function New-TriTierRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Title,

        [Parameter()]
        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$')]
        [string]$RunId,

        [Parameter()]
        [string]$PlanPath = "",

        [Parameter()]
        [string]$CurrentPhase = "PHASE-01",

        [Parameter()]
        [string]$CurrentTask = "",

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$NextAction =
            "Review the authoritative plan and prepare the first bounded task."
    )

    if ([string]::IsNullOrWhiteSpace($RunId)) {
        $Timestamp = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")
        $Suffix = [guid]::NewGuid().ToString("N").Substring(0, 8)
        $RunId = "$Timestamp-$Suffix"
    }

    $RunDirectory = Get-TriTierRunDirectory `
        -ProjectPath $ProjectPath `
        -RunId $RunId

    if (Test-Path $RunDirectory) {
        throw "Tri-Tier run already exists: $RunDirectory"
    }

    $Directories = @(
        $RunDirectory,
        (Join-Path $RunDirectory "plan"),
        (Join-Path $RunDirectory "state"),
        (Join-Path $RunDirectory "checkpoints"),
        (Join-Path $RunDirectory "tasks"),
        (Join-Path $RunDirectory "phases"),
        (Join-Path $RunDirectory "evidence")
    )

    foreach ($Directory in $Directories) {
        New-Item -ItemType Directory -Force -Path $Directory | Out-Null
    }

    $ResolvedProjectPath = (Resolve-Path $ProjectPath).Path
    $PlanHash = ""
    $StoredPlanPath = ""

    if (-not [string]::IsNullOrWhiteSpace($PlanPath)) {
        if (-not (Test-Path $PlanPath -PathType Leaf)) {
            throw "Plan file does not exist: $PlanPath"
        }

        $ResolvedPlanPath = (Resolve-Path $PlanPath).Path
        $Extension = [IO.Path]::GetExtension($ResolvedPlanPath)

        if ([string]::IsNullOrWhiteSpace($Extension)) {
            $Extension = ".txt"
        }

        $StoredPlanPath = Join-Path `
            $RunDirectory `
            "plan\authoritative-plan$Extension"

        Copy-Item `
            -Path $ResolvedPlanPath `
            -Destination $StoredPlanPath `
            -Force

        $PlanHash = (
            Get-FileHash $ResolvedPlanPath -Algorithm SHA256
        ).Hash
    }

    $Git = Get-TriTierGitSnapshot -ProjectPath $ResolvedProjectPath
    $Now = [DateTime]::UtcNow.ToString("o")

    $State = [ordered]@{
        schemaVersion       = 1
        runId               = $RunId
        title               = $Title
        status              = "ACTIVE"
        createdUtc          = $Now
        updatedUtc          = $Now
        projectPath         = $ResolvedProjectPath
        baselineCommit      = $Git.baselineCommit
        workingTreeStatus   = $Git.workingTreeStatus
        currentPhase        = $CurrentPhase
        currentTask         = $CurrentTask
        completedTasks      = @()
        unresolvedFindings  = @()
        findings            = @()
        findingGate         = $null
        taskFlow            = $null
        blockers            = @()
        planPath            = $StoredPlanPath
        planHash            = $PlanHash
        nextAction          = $NextAction
        lastCheckpointId    = $null
    }

    Write-TriTierAtomicJson `
        -Path (Join-Path $RunDirectory "state\run-state.json") `
        -InputObject $State

    Write-TriTierAtomicText `
        -Path (Join-Path $RunDirectory "state\next-action.txt") `
        -Content ($NextAction.Trim() + "`n")

    [PSCustomObject]@{
        runDirectory = $RunDirectory
        state        = [PSCustomObject]$State
    }
}

function Get-TriTierRunState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$RunId
    )

    $RunDirectory = Get-TriTierRunDirectory `
        -ProjectPath $ProjectPath `
        -RunId $RunId

    $StatePath = Join-Path $RunDirectory "state\run-state.json"

    if (-not (Test-Path $StatePath -PathType Leaf)) {
        throw "Tri-Tier run state does not exist: $StatePath"
    }

    Get-Content $StatePath -Raw |
        ConvertFrom-Json -Depth 30
}

function Set-TriTierNextAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$RunId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$NextAction
    )

    $RunDirectory = Get-TriTierRunDirectory `
        -ProjectPath $ProjectPath `
        -RunId $RunId

    $State = Get-TriTierRunState `
        -ProjectPath $ProjectPath `
        -RunId $RunId

    $State.nextAction = $NextAction.Trim()
    $State.updatedUtc = [DateTime]::UtcNow.ToString("o")

    Write-TriTierAtomicJson `
        -Path (Join-Path $RunDirectory "state\run-state.json") `
        -InputObject $State

    Write-TriTierAtomicText `
        -Path (Join-Path $RunDirectory "state\next-action.txt") `
        -Content ($State.nextAction + "`n")

    $State
}

function New-TriTierCheckpoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$RunId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Summary,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$NextAction,

        [Parameter()]
        [string]$CurrentPhase,

        [Parameter()]
        [string]$CurrentTask,

        [Parameter()]
        [string[]]$CompletedTasks,

        [Parameter()]
        [string[]]$UnresolvedFindings,

        [Parameter()]
        [string[]]$Blockers
    )

    $RunDirectory = Get-TriTierRunDirectory `
        -ProjectPath $ProjectPath `
        -RunId $RunId

    $State = Get-TriTierRunState `
        -ProjectPath $ProjectPath `
        -RunId $RunId

    if ($PSBoundParameters.ContainsKey("CurrentPhase")) {
        $State.currentPhase = $CurrentPhase
    }

    if ($PSBoundParameters.ContainsKey("CurrentTask")) {
        $State.currentTask = $CurrentTask
    }

    if ($PSBoundParameters.ContainsKey("CompletedTasks")) {
        $State.completedTasks = @($CompletedTasks)
    }

    if ($PSBoundParameters.ContainsKey("UnresolvedFindings")) {
        $State.unresolvedFindings = @($UnresolvedFindings)
    }

    if ($PSBoundParameters.ContainsKey("Blockers")) {
        $State.blockers = @($Blockers)
    }

    $Timestamp = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssfffZ")
    $Suffix = [guid]::NewGuid().ToString("N").Substring(0, 8)
    $CheckpointId = "$Timestamp-$Suffix"

    $State.nextAction = $NextAction.Trim()
    $State.lastCheckpointId = $CheckpointId
    $State.updatedUtc = [DateTime]::UtcNow.ToString("o")

    $Checkpoint = [ordered]@{
        schemaVersion = 1
        checkpointId  = $CheckpointId
        runId         = $RunId
        createdUtc    = $State.updatedUtc
        summary       = $Summary
        state         = $State
    }

    Write-TriTierAtomicJson `
        -Path (Join-Path $RunDirectory "checkpoints\$CheckpointId.json") `
        -InputObject $Checkpoint

    Write-TriTierAtomicJson `
        -Path (Join-Path $RunDirectory "state\run-state.json") `
        -InputObject $State

    Write-TriTierAtomicText `
        -Path (Join-Path $RunDirectory "state\next-action.txt") `
        -Content ($State.nextAction + "`n")

    [PSCustomObject]$Checkpoint
}

function Set-TriTierRunStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$RunId,

        [Parameter(Mandatory)]
        [string]$Status
    )

    if ($Status -notin $script:AllowedRunStatuses) {
        throw "Unsupported Tri-Tier run status: $Status"
    }

    $RunDirectory = Get-TriTierRunDirectory `
        -ProjectPath $ProjectPath `
        -RunId $RunId

    $State = Get-TriTierRunState `
        -ProjectPath $ProjectPath `
        -RunId $RunId

    $State.status = $Status
    $State.updatedUtc = [DateTime]::UtcNow.ToString("o")

    Write-TriTierAtomicJson `
        -Path (Join-Path $RunDirectory "state\run-state.json") `
        -InputObject $State

    $State
}

function Set-TriTierRunFindingState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$RunId,

        [Parameter()]
        [object[]]$Findings = @(),

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$FindingGate
    )

    if (
        $null -eq $FindingGate.PSObject.Properties['nextAction'] -or
        [string]::IsNullOrWhiteSpace([string]$FindingGate.nextAction)
    ) {
        throw 'Finding gate must provide a non-empty nextAction.'
    }

    $FindingIds = @(
        $Findings | ForEach-Object {
            if (
                $null -eq $_.PSObject.Properties['findingId'] -or
                [string]::IsNullOrWhiteSpace([string]$_.findingId)
            ) {
                throw 'Every persisted finding must provide a findingId.'
            }

            [string]$_.findingId
        }
    )

    $DuplicateFindingIds = @(
        $FindingIds | Group-Object | Where-Object Count -gt 1 | Select-Object -ExpandProperty Name
    )

    if ($DuplicateFindingIds.Count -gt 0) {
        throw (
            'Duplicate finding IDs cannot be persisted: ' +
            ($DuplicateFindingIds -join ', ')
        )
    }

    $RunDirectory = Get-TriTierRunDirectory `
        -ProjectPath $ProjectPath `
        -RunId $RunId

    $State = Get-TriTierRunState `
        -ProjectPath $ProjectPath `
        -RunId $RunId

    $ActiveFindingIds = @(
        $Findings |
            Where-Object {
                $_.status -in @(
                    'OPEN',
                    'REPAIRED_PENDING_REVIEW'
                )
            } |
            ForEach-Object {
                [string]$_.findingId
            }
    )

    $State.findings = @($Findings)
    $State.unresolvedFindings = $ActiveFindingIds
    $State.findingGate = $FindingGate
    $State.nextAction = ([string]$FindingGate.nextAction).Trim()
    $State.updatedUtc = [DateTime]::UtcNow.ToString('o')

    Write-TriTierAtomicJson `
        -Path (Join-Path $RunDirectory 'state\run-state.json') `
        -InputObject $State

    Write-TriTierAtomicText `
        -Path (Join-Path $RunDirectory 'state\next-action.txt') `
        -Content ($State.nextAction + "`n")

    $State
}
function Set-TriTierRunTaskFlowState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$RunId,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$TaskFlowState
    )

    foreach ($Property in @(
        'schemaVersion',
        'stage',
        'previousStage',
        'responsibleParty',
        'mayAdvance',
        'currentTask',
        'implementationActor',
        'reviewActor',
        'reviewOutcome',
        'nextAction',
        'revision',
        'transitionHistory'
    )) {
        if ($null -eq $TaskFlowState.PSObject.Properties[$Property]) {
            throw "Task flow state is missing required property: $Property"
        }
    }

    if ($TaskFlowState.stage -notin @(
        'PLAN',
        'IMPLEMENT',
        'REVIEW',
        'CONTINUE'
    )) {
        throw "Unsupported task flow stage: $($TaskFlowState.stage)"
    }

    if ([string]::IsNullOrWhiteSpace([string]$TaskFlowState.nextAction)) {
        throw 'Task flow state must provide a non-empty nextAction.'
    }

    $RunDirectory = Get-TriTierRunDirectory `
        -ProjectPath $ProjectPath `
        -RunId $RunId

    $State = Get-TriTierRunState `
        -ProjectPath $ProjectPath `
        -RunId $RunId

    if ($null -eq $State.PSObject.Properties['taskFlow']) {
        $State |
            Add-Member `
                -NotePropertyName taskFlow `
                -NotePropertyValue $null
    }

    $State.taskFlow = $TaskFlowState
    $State.currentTask = [string]$TaskFlowState.currentTask
    $State.nextAction = ([string]$TaskFlowState.nextAction).Trim()
    $State.updatedUtc = [DateTime]::UtcNow.ToString('o')

    Write-TriTierAtomicJson `
        -Path (Join-Path $RunDirectory 'state\run-state.json') `
        -InputObject $State

    Write-TriTierAtomicText `
        -Path (Join-Path $RunDirectory 'state\next-action.txt') `
        -Content ($State.nextAction + "`n")

    $State
}

function Set-TriTierRunIntegratedState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$RunId,

        [Parameter()]
        [object[]]$Findings = @(),

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$FindingGate,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$TaskFlowState,

        [Parameter()]
        [string]$RunStatus = ''
    )

    if (
        $null -eq $FindingGate.PSObject.Properties['nextAction'] -or
        [string]::IsNullOrWhiteSpace([string]$FindingGate.nextAction)
    ) {
        throw 'Finding gate must provide a non-empty nextAction.'
    }

    foreach ($Property in @(
        'schemaVersion',
        'stage',
        'previousStage',
        'responsibleParty',
        'mayAdvance',
        'currentTask',
        'implementationActor',
        'reviewActor',
        'reviewOutcome',
        'nextAction',
        'revision',
        'transitionHistory',
        'activeRepairFindingId',
        'lastRepairFindingId',
        'repairResumeStage',
        'repairActor',
        'repairReviewActor',
        'repairReviewOutcome',
        'adjudicationDecision'
    )) {
        if ($null -eq $TaskFlowState.PSObject.Properties[$Property]) {
            throw "Integrated task flow is missing required property: $Property"
        }
    }

    if ($TaskFlowState.stage -notin @(
        'PLAN',
        'IMPLEMENT',
        'REVIEW',
        'REPAIR',
        'FRESH_REVIEW',
        'ADJUDICATE',
        'CONTINUE'
    )) {
        throw "Unsupported integrated task-flow stage: $($TaskFlowState.stage)"
    }

    if ([string]::IsNullOrWhiteSpace([string]$TaskFlowState.nextAction)) {
        throw 'Integrated task flow must provide a non-empty nextAction.'
    }

    if (
        -not [string]::IsNullOrWhiteSpace($RunStatus) -and
        $RunStatus -notin $script:AllowedRunStatuses
    ) {
        throw "Unsupported Tri-Tier run status: $RunStatus"
    }

    $FindingIds = @(
        $Findings | ForEach-Object {
            if (
                $null -eq $_.PSObject.Properties['findingId'] -or
                [string]::IsNullOrWhiteSpace([string]$_.findingId)
            ) {
                throw 'Every integrated finding must provide a findingId.'
            }

            [string]$_.findingId
        }
    )

    $DuplicateFindingIds = @(
        $FindingIds |
            Group-Object |
            Where-Object Count -gt 1 |
            Select-Object -ExpandProperty Name
    )

    if ($DuplicateFindingIds.Count -gt 0) {
        throw (
            'Duplicate finding IDs cannot be persisted: ' +
            ($DuplicateFindingIds -join ', ')
        )
    }

    $ActiveFindings = @(
        $Findings |
            Where-Object {
                $_.status -in @(
                    'OPEN',
                    'REPAIRED_PENDING_REVIEW'
                )
            }
    )

    $ActiveFindingIds = @(
        $ActiveFindings |
            ForEach-Object {
                [string]$_.findingId
            }
    )

    $RepairStages = @(
        'REPAIR',
        'FRESH_REVIEW',
        'ADJUDICATE'
    )

    $ActiveRepairFindingId = [string]$TaskFlowState.activeRepairFindingId

    if ($TaskFlowState.stage -in $RepairStages) {
        if ([string]::IsNullOrWhiteSpace($ActiveRepairFindingId)) {
            throw (
                "Integrated stage $($TaskFlowState.stage) requires " +
                'activeRepairFindingId.'
            )
        }

        $LinkedFindings = @(
            $ActiveFindings |
                Where-Object {
                    [string]$_.findingId -eq $ActiveRepairFindingId
                }
        )

        if ($LinkedFindings.Count -ne 1) {
            throw (
                "Integrated stage $($TaskFlowState.stage) requires exactly " +
                "one active linked finding '$ActiveRepairFindingId'; found " +
                "$($LinkedFindings.Count)."
            )
        }

        $LinkedFinding = $LinkedFindings[0]

        if (
            $TaskFlowState.stage -eq 'FRESH_REVIEW' -and
            $LinkedFinding.status -ne 'REPAIRED_PENDING_REVIEW'
        ) {
            throw (
                'FRESH_REVIEW requires a linked finding in ' +
                'REPAIRED_PENDING_REVIEW status.'
            )
        }

        if (
            $TaskFlowState.stage -in @('REPAIR', 'ADJUDICATE') -and
            $LinkedFinding.status -ne 'OPEN'
        ) {
            throw (
                "$($TaskFlowState.stage) requires a linked finding " +
                'in OPEN status.'
            )
        }
    }
    else {
        if (-not [string]::IsNullOrWhiteSpace($ActiveRepairFindingId)) {
            throw (
                "Integrated stage $($TaskFlowState.stage) cannot retain " +
                'activeRepairFindingId.'
            )
        }
    }

    $RunDirectory = Get-TriTierRunDirectory `
        -ProjectPath $ProjectPath `
        -RunId $RunId

    $State = Get-TriTierRunState `
        -ProjectPath $ProjectPath `
        -RunId $RunId

    $State.findings = @($Findings)
    $State.unresolvedFindings = $ActiveFindingIds
    $State.findingGate = $FindingGate
    $State.taskFlow = $TaskFlowState
    $State.currentTask = [string]$TaskFlowState.currentTask
    $State.nextAction = ([string]$TaskFlowState.nextAction).Trim()

    if (-not [string]::IsNullOrWhiteSpace($RunStatus)) {
        $State.status = $RunStatus
    }

    $State.updatedUtc = [DateTime]::UtcNow.ToString('o')

    Write-TriTierAtomicJson `
        -Path (Join-Path $RunDirectory 'state\run-state.json') `
        -InputObject $State

    Write-TriTierAtomicText `
        -Path (Join-Path $RunDirectory 'state\next-action.txt') `
        -Content ($State.nextAction + "`n")

    $State
}

function Set-TriTierRunPhaseState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$RunId,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$PhaseState,

        [Parameter()]
        [string]$RunStatus = ''
    )

    foreach ($Property in @(
        'schemaVersion',
        'phaseId',
        'status',
        'riskClass',
        'requiredEvidenceLevel',
        'observedEvidenceLevel',
        'evidenceIndependent',
        'evidenceIds',
        'ownerApprovalRequired',
        'ownerApprovalRecord',
        'reviewActor',
        'reviewDecision',
        'reviewSummary',
        'reviewEvidenceIds',
        'revision',
        'history',
        'nextAction',
        'createdUtc',
        'updatedUtc'
    )) {
        if ($null -eq $PhaseState.PSObject.Properties[$Property]) {
            throw "Phase state is missing required property: $Property"
        }
    }

    if ($PhaseState.status -notin @(
        'ACTIVE',
        'READY_FOR_REVIEW',
        'BLOCKED_BY_FINDINGS',
        'BLOCKED_BY_EVIDENCE',
        'OWNER_DECISION_REQUIRED',
        'ACCEPTED',
        'REJECTED'
    )) {
        throw "Unsupported phase status: $($PhaseState.status)"
    }

    if ($PhaseState.riskClass -notin @(
        'R0',
        'R1',
        'R2',
        'R3',
        'R4'
    )) {
        throw "Unsupported phase risk class: $($PhaseState.riskClass)"
    }

    if (
        [string]::IsNullOrWhiteSpace([string]$PhaseState.phaseId) -or
        [string]::IsNullOrWhiteSpace([string]$PhaseState.nextAction)
    ) {
        throw 'Phase state requires non-empty phaseId and nextAction.'
    }

    if (
        -not [string]::IsNullOrWhiteSpace($RunStatus) -and
        $RunStatus -notin $script:AllowedRunStatuses
    ) {
        throw "Unsupported Tri-Tier run status: $RunStatus"
    }

    $RunDirectory = Get-TriTierRunDirectory `
        -ProjectPath $ProjectPath `
        -RunId $RunId

    $State = Get-TriTierRunState `
        -ProjectPath $ProjectPath `
        -RunId $RunId

    if ($null -eq $State.PSObject.Properties['phaseGate']) {
        $State |
            Add-Member `
                -NotePropertyName phaseGate `
                -NotePropertyValue $null
    }

    if ($null -eq $State.PSObject.Properties['currentPhase']) {
        $State |
            Add-Member `
                -NotePropertyName currentPhase `
                -NotePropertyValue ''
    }

    $State.phaseGate = $PhaseState
    $State.currentPhase = [string]$PhaseState.phaseId
    $State.nextAction = ([string]$PhaseState.nextAction).Trim()

    if (-not [string]::IsNullOrWhiteSpace($RunStatus)) {
        $State.status = $RunStatus
    }

    $State.updatedUtc = [DateTime]::UtcNow.ToString('o')

    Write-TriTierAtomicJson `
        -Path (Join-Path $RunDirectory 'state\run-state.json') `
        -InputObject $State

    Write-TriTierAtomicText `
        -Path (Join-Path $RunDirectory 'state\next-action.txt') `
        -Content ($State.nextAction + "`n")

    $State
}

function Test-TriTierRunState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$RunId
    )

    $Errors = @()

    try {
        $RunDirectory = Get-TriTierRunDirectory `
            -ProjectPath $ProjectPath `
            -RunId $RunId

        $State = Get-TriTierRunState `
            -ProjectPath $ProjectPath `
            -RunId $RunId
    }
    catch {
        return [PSCustomObject]@{
            valid  = $false
            errors = @($_.Exception.Message)
        }
    }

    foreach ($Property in @(
        "schemaVersion",
        "runId",
        "status",
        "createdUtc",
        "updatedUtc",
        "projectPath",
        "currentPhase",
        "nextAction"
    )) {
        if ($null -eq $State.$Property) {
            $Errors += "Required state property is missing: $Property"
        }
    }

    if ($State.status -notin $script:AllowedRunStatuses) {
        $Errors += "Unsupported state status: $($State.status)"
    }

    $NextActionPath = Join-Path $RunDirectory "state\next-action.txt"

    if (-not (Test-Path $NextActionPath -PathType Leaf)) {
        $Errors += "Exact next-action file is missing."
    }
    else {
        $StoredNextAction = (Get-Content $NextActionPath -Raw).Trim()

        if ($StoredNextAction -ne [string]$State.nextAction) {
            $Errors += "next-action.txt does not match run-state.json."
        }
    }

    if (-not [string]::IsNullOrWhiteSpace(
        [string]$State.lastCheckpointId
    )) {
        $CheckpointPath = Join-Path `
            $RunDirectory `
            "checkpoints\$($State.lastCheckpointId).json"

        if (-not (Test-Path $CheckpointPath -PathType Leaf)) {
            $Errors += "The recorded latest checkpoint file is missing."
        }
    }

    [PSCustomObject]@{
        valid  = $Errors.Count -eq 0
        errors = $Errors
    }
}

function Get-TriTierRunResumeData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$RunId
    )

    $Validation = Test-TriTierRunState `
        -ProjectPath $ProjectPath `
        -RunId $RunId

    if (-not $Validation.valid) {
        throw "Run state is invalid: $($Validation.errors -join '; ')"
    }

    $RunDirectory = Get-TriTierRunDirectory `
        -ProjectPath $ProjectPath `
        -RunId $RunId

    $State = Get-TriTierRunState `
        -ProjectPath $ProjectPath `
        -RunId $RunId

    $Checkpoint = $null

    if (-not [string]::IsNullOrWhiteSpace(
        [string]$State.lastCheckpointId
    )) {
        $CheckpointPath = Join-Path `
            $RunDirectory `
            "checkpoints\$($State.lastCheckpointId).json"

        $Checkpoint = Get-Content $CheckpointPath -Raw |
            ConvertFrom-Json -Depth 30
    }

    [PSCustomObject]@{
        runDirectory     = $RunDirectory
        state            = $State
        latestCheckpoint = $Checkpoint
        nextAction       = [string]$State.nextAction
    }
}

Export-ModuleMember -Function @(
    "New-TriTierRun",
    "Get-TriTierRunState",
    "Set-TriTierNextAction",
    "New-TriTierCheckpoint",
    "Set-TriTierRunStatus",
    "Set-TriTierRunFindingState",
    "Set-TriTierRunIntegratedState",
    "Set-TriTierRunPhaseState",
    "Set-TriTierRunTaskFlowState",
    "Test-TriTierRunState",
    "Get-TriTierRunResumeData"
)
