[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("classify", "evidence", "run-init", "run-checkpoint", "run-resume", "run-status", "finding-add", "finding-get", "finding-repair", "finding-review", "finding-defer", "task-flow-init", "task-start", "implementation-complete", "task-review", "task-flow-status", "task-planning-start", "repair-open", "repair-complete", "repair-review", "repair-adjudicate", "repair-status", "orchestration-status", "phase-start", "phase-ready", "phase-review", "phase-accept", "phase-reject", "phase-status", "exec", "exec-resume", "exec-status", "doctor", "version")]
    [string]$Command = "doctor",

    [Parameter()]
    [AllowEmptyString()]
    [string]$Prompt = "",

    [Parameter()]
    [ValidateSet("R0", "R1", "R2", "R3", "R4")]
    [string]$RiskClass = "R2",

    [Parameter()]
    [ValidateSet("E0", "E1", "E2", "E3", "E4", "E5")]
    [string]$EvidenceLevel = "E0",

    [Parameter()]
    [switch]$IndependentlyReproduced,
    [Parameter()]
    [string]$ProjectPath = ".",

    [Parameter()]
    [string]$RunId = "",

    [Parameter()]
    [string]$Title = "",

    [Parameter()]
    [string]$PlanPath = "",

    [Parameter()]
    [string]$CurrentPhase = "PHASE-01",

    [Parameter()]
    [string]$CurrentTask = "",

    [Parameter()]
    [string]$NextAction = "",

    [Parameter()]
    [string]$Summary = "",

    [Parameter()]
    [string[]]$CompletedTasks,

    [Parameter()]
    [string[]]$UnresolvedFindings,

    [Parameter()]
    [string[]]$Blockers,

    [Parameter()]
    [string]$RunStatus = "",

        [Parameter()]
    [string]$FindingId = "",

    [Parameter()]
    [string]$Severity = "",

    [Parameter()]
    [string]$Description = "",

    [Parameter()]
    [string]$Reviewer = "",

    [Parameter()]
    [string]$TaskId = "",

    [Parameter()]
    [string]$PhaseId = "",

    [Parameter()]
    [string[]]$EvidenceIds,

    [Parameter()]
    [string]$RepairedBy = "",

    [Parameter()]
    [string]$RepairSummary = "",

    [Parameter()]
    [string]$Outcome = "",

    [Parameter()]
    [string]$ReviewSummary = "",

    [Parameter()]
    [string]$Reason = "",

    [Parameter()]
    [string]$OwnerApprovalRecord = "",

    [Parameter()]
    [switch]$OwnerApproved,
    [Parameter()]
    [string]$Actor = "",

    [Parameter()]
    [string]$Instruction = "",

    [Parameter()]
    [string]$EventId = "",

    [Parameter()]
    [string]$Decision = "",
    [Parameter()]
    [string]$PhaseRiskClass = "",

    [Parameter()]
    [string]$ObservedEvidenceLevel = "",

    [Parameter()]
    [switch]$EvidenceIndependent,
    [Parameter()]
    [string]$DispatcherPath = "",

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
    [switch]$DryRun,
[Parameter()]
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ModulePaths = @{
    Classification = Join-Path $PSScriptRoot "TriTier\Classification.psm1"
    Risk = Join-Path $PSScriptRoot "TriTier\Risk.psm1"
    Evidence = Join-Path $PSScriptRoot "TriTier\Evidence.psm1"
    Findings = Join-Path $PSScriptRoot "TriTier\Findings.psm1"
    FindingLifecycle = Join-Path $PSScriptRoot "TriTier\FindingLifecycle.psm1"
    TaskFlow = Join-Path $PSScriptRoot "TriTier\TaskFlow.psm1"
    RepairCycle = Join-Path $PSScriptRoot "TriTier\RepairCycle.psm1"
    Orchestration = Join-Path $PSScriptRoot "TriTier\Orchestration.psm1"
    PhaseGate = Join-Path $PSScriptRoot "TriTier\PhaseGate.psm1"
    ExecutionLoop = Join-Path $PSScriptRoot "TriTier\ExecutionLoop.psm1"
    State = Join-Path $PSScriptRoot "TriTier\State.psm1"
}

foreach ($Entry in $ModulePaths.GetEnumerator()) {
    if (-not (Test-Path $Entry.Value)) {
        throw "Tri-Tier module not found: $($Entry.Value)"
    }

    Import-Module $Entry.Value -Force
}

function New-TriTierCliFlowResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Flow,

        [Parameter(Mandatory)]
        [object]$State,

        [Parameter()]
        [object]$Finding = $null,

        [Parameter()]
        [object]$Gate = $null,

        [Parameter()]
        [bool]$Replayed = $false
    )

    $FindingId = ''
    $FindingStatus = ''
    $ReviewCycle = 0

    if ($null -ne $Finding) {
        $FindingId = [string]$Finding.findingId
        $FindingStatus = [string]$Finding.status
        $ReviewCycle = [int]$Finding.reviewCycle
    }

    $TaskBlocked = $false
    $PhaseBlocked = $false
    $RunBlocked = $false
    $BlockedScope = 'NONE'

    if ($null -ne $Gate) {
        $TaskBlocked = [bool]$Gate.taskBlocked
        $PhaseBlocked = [bool]$Gate.phaseBlocked
        $RunBlocked = [bool]$Gate.runBlocked

        if ($TaskBlocked) {
            $BlockedScope = 'TASK'
        }

        if ($PhaseBlocked) {
            $BlockedScope = 'PHASE'
        }

        if ($RunBlocked) {
            $BlockedScope = 'RUN'
        }
    }

    [PSCustomObject][ordered]@{
        runId = [string]$State.runId
        status = [string]$State.status
        stage = [string]$Flow.stage
        responsibleParty = [string]$Flow.responsibleParty
        mayAdvance = [bool]$Flow.mayAdvance
        currentTask = [string]$Flow.currentTask
        blockedScope = $BlockedScope
        taskBlocked = $TaskBlocked
        phaseBlocked = $PhaseBlocked
        runBlocked = $RunBlocked
        findingId = $FindingId
        findingStatus = $FindingStatus
        reviewCycle = $ReviewCycle
        replayed = $Replayed
        nextAction = [string]$State.nextAction
        updatedUtc = [string]$State.updatedUtc
    }
}

function Get-TriTierCliObjectProperty {
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
            "Required CLI result property '$Name' is missing from " +
            "object type $TypeName."
        )
    }

    $DefaultValue
}

function Resolve-TriTierCliPhaseDecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$InputObject
    )

    $Candidates = @()

    foreach ($Candidate in @($InputObject)) {
        if ($null -eq $Candidate) {
            continue
        }

        $Candidates += $Candidate

        $NestedDecision = Get-TriTierCliObjectProperty `
            -InputObject $Candidate `
            -Name 'decision' `
            -DefaultValue $null

        if ($null -ne $NestedDecision) {
            $Candidates += @($NestedDecision)
        }
    }

    $MatchingCandidates = @(
        $Candidates |
            Where-Object {
                $null -ne (
                    Get-TriTierCliObjectProperty `
                        -InputObject $_ `
                        -Name 'stage' `
                        -DefaultValue $null
                )
            }
    )

    if ($MatchingCandidates.Count -ne 1) {
        $Shapes = @(
            $Candidates |
                ForEach-Object {
                    $TypeName = $_.GetType().FullName
                    $PropertyNames = @(
                        $_.PSObject.Properties.Name
                    ) -join ','

                    "$TypeName[$PropertyNames]"
                }
        ) -join '; '

        throw (
            'Expected exactly one orchestration decision object containing ' +
            "a stage property; found $($MatchingCandidates.Count). " +
            "Observed shapes: $Shapes"
        )
    }

    $Decision = $MatchingCandidates[0]

    foreach ($RequiredProperty in @(
        'stage',
        'responsibleParty',
        'canContinue',
        'nextAction'
    )) {
        [void](
            Get-TriTierCliObjectProperty `
                -InputObject $Decision `
                -Name $RequiredProperty `
                -Required
        )
    }

    $Decision
}

function New-TriTierCliPhaseResult {
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$Phase = $null,

        [Parameter(Mandatory)]
        [object]$Decision,

        [Parameter(Mandatory)]
        [object]$State,

        [Parameter()]
        [bool]$Replayed = $false
    )

    $ResolvedDecision = Resolve-TriTierCliPhaseDecision `
        -InputObject $Decision

    $PhaseId = ''
    $PhaseStatus = ''
    $RiskClass = ''
    $RequiredEvidenceLevel = ''
    $ObservedEvidenceLevel = ''
    $EvidenceIndependent = $false
    $OwnerApprovalRequired = $false
    $ReviewActor = ''
    $ReviewDecision = ''

    if ($null -ne $Phase) {
        $PhaseId = [string](
            Get-TriTierCliObjectProperty `
                -InputObject $Phase `
                -Name 'phaseId' `
                -DefaultValue ''
        )
        $PhaseStatus = [string](
            Get-TriTierCliObjectProperty `
                -InputObject $Phase `
                -Name 'status' `
                -DefaultValue ''
        )
        $RiskClass = [string](
            Get-TriTierCliObjectProperty `
                -InputObject $Phase `
                -Name 'riskClass' `
                -DefaultValue ''
        )
        $RequiredEvidenceLevel = [string](
            Get-TriTierCliObjectProperty `
                -InputObject $Phase `
                -Name 'requiredEvidenceLevel' `
                -DefaultValue ''
        )
        $ObservedEvidenceLevel = [string](
            Get-TriTierCliObjectProperty `
                -InputObject $Phase `
                -Name 'observedEvidenceLevel' `
                -DefaultValue ''
        )
        $EvidenceIndependent = [bool](
            Get-TriTierCliObjectProperty `
                -InputObject $Phase `
                -Name 'evidenceIndependent' `
                -DefaultValue $false
        )
        $OwnerApprovalRequired = [bool](
            Get-TriTierCliObjectProperty `
                -InputObject $Phase `
                -Name 'ownerApprovalRequired' `
                -DefaultValue $false
        )
        $ReviewActor = [string](
            Get-TriTierCliObjectProperty `
                -InputObject $Phase `
                -Name 'reviewActor' `
                -DefaultValue ''
        )
        $ReviewDecision = [string](
            Get-TriTierCliObjectProperty `
                -InputObject $Phase `
                -Name 'reviewDecision' `
                -DefaultValue ''
        )
    }

    [PSCustomObject][ordered]@{
        runId = [string](
            Get-TriTierCliObjectProperty `
                -InputObject $State `
                -Name 'runId' `
                -Required
        )
        status = [string](
            Get-TriTierCliObjectProperty `
                -InputObject $State `
                -Name 'status' `
                -Required
        )
        phaseId = $PhaseId
        phaseStatus = $PhaseStatus
        riskClass = $RiskClass
        requiredEvidenceLevel = $RequiredEvidenceLevel
        observedEvidenceLevel = $ObservedEvidenceLevel
        evidenceIndependent = $EvidenceIndependent
        ownerApprovalRequired = $OwnerApprovalRequired
        reviewActor = $ReviewActor
        reviewDecision = $ReviewDecision
        stage = [string](
            Get-TriTierCliObjectProperty `
                -InputObject $ResolvedDecision `
                -Name 'stage' `
                -Required
        )
        responsibleParty = [string](
            Get-TriTierCliObjectProperty `
                -InputObject $ResolvedDecision `
                -Name 'responsibleParty' `
                -Required
        )
        blockedScope = [string](
            Get-TriTierCliObjectProperty `
                -InputObject $ResolvedDecision `
                -Name 'blockedScope' `
                -DefaultValue 'NONE'
        )
        canContinue = [bool](
            Get-TriTierCliObjectProperty `
                -InputObject $ResolvedDecision `
                -Name 'canContinue' `
                -Required
        )
        ownerRequired = [bool](
            Get-TriTierCliObjectProperty `
                -InputObject $ResolvedDecision `
                -Name 'ownerRequired' `
                -DefaultValue $false
        )
        findingId = [string](
            Get-TriTierCliObjectProperty `
                -InputObject $ResolvedDecision `
                -Name 'findingId' `
                -DefaultValue ''
        )
        replayed = $Replayed
        reason = [string](
            Get-TriTierCliObjectProperty `
                -InputObject $ResolvedDecision `
                -Name 'reason' `
                -DefaultValue ''
        )
        nextAction = [string](
            Get-TriTierCliObjectProperty `
                -InputObject $ResolvedDecision `
                -Name 'nextAction' `
                -Required
        )
        updatedUtc = [string](
            Get-TriTierCliObjectProperty `
                -InputObject $State `
                -Name 'updatedUtc' `
                -DefaultValue ''
        )
    }
}

function New-TriTierCliExecutionResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$ExecutionResult
    )

    $LoopState = Get-TriTierCliObjectProperty `
        -InputObject $ExecutionResult `
        -Name 'loop' `
        -Required
    $RunState = Get-TriTierCliObjectProperty `
        -InputObject $ExecutionResult `
        -Name 'state' `
        -Required
    $Decision = Get-TriTierCliObjectProperty `
        -InputObject $ExecutionResult `
        -Name 'decision' `
        -Required
    $Envelope = Get-TriTierCliObjectProperty `
        -InputObject $ExecutionResult `
        -Name 'envelope' `
        -DefaultValue $null

    [PSCustomObject][ordered]@{
        runId = [string](
            Get-TriTierCliObjectProperty `
                -InputObject $RunState `
                -Name 'runId' `
                -Required
        )
        runStatus = [string](
            Get-TriTierCliObjectProperty `
                -InputObject $RunState `
                -Name 'status' `
                -Required
        )
        loopStatus = [string](
            Get-TriTierCliObjectProperty `
                -InputObject $LoopState `
                -Name 'status' `
                -Required
        )
        step = [int](
            Get-TriTierCliObjectProperty `
                -InputObject $LoopState `
                -Name 'currentStep' `
                -DefaultValue 0
        )
        stage = [string](
            Get-TriTierCliObjectProperty `
                -InputObject $Decision `
                -Name 'stage' `
                -Required
        )
        responsibleParty = [string](
            Get-TriTierCliObjectProperty `
                -InputObject $Decision `
                -Name 'responsibleParty' `
                -Required
        )
        blockedScope = [string](
            Get-TriTierCliObjectProperty `
                -InputObject $Decision `
                -Name 'blockedScope' `
                -DefaultValue 'NONE'
        )
        canContinue = [bool](
            Get-TriTierCliObjectProperty `
                -InputObject $Decision `
                -Name 'canContinue' `
                -Required
        )
        ownerRequired = [bool](
            Get-TriTierCliObjectProperty `
                -InputObject $Decision `
                -Name 'ownerRequired' `
                -DefaultValue $false
        )
        findingId = [string](
            Get-TriTierCliObjectProperty `
                -InputObject $Decision `
                -Name 'findingId' `
                -DefaultValue ''
        )
        phaseId = [string](
            Get-TriTierCliObjectProperty `
                -InputObject $Decision `
                -Name 'phaseId' `
                -DefaultValue ''
        )
        dispatched = [bool](
            Get-TriTierCliObjectProperty `
                -InputObject $ExecutionResult `
                -Name 'dispatched' `
                -DefaultValue $false
        )
        dryRun = [bool](
            Get-TriTierCliObjectProperty `
                -InputObject $ExecutionResult `
                -Name 'dryRun' `
                -DefaultValue $false
        )
        actionKey = if ($null -eq $Envelope) {
            ''
        }
        else {
            [string](
                Get-TriTierCliObjectProperty `
                    -InputObject $Envelope `
                    -Name 'actionKey' `
                    -DefaultValue ''
            )
        }
        dispatcherPath = [string](
            Get-TriTierCliObjectProperty `
                -InputObject $LoopState `
                -Name 'dispatcherPath' `
                -DefaultValue ''
        )
        stopReason = [string](
            Get-TriTierCliObjectProperty `
                -InputObject $LoopState `
                -Name 'stopReason' `
                -DefaultValue ''
        )
        nextAction = [string](
            Get-TriTierCliObjectProperty `
                -InputObject $Decision `
                -Name 'nextAction' `
                -Required
        )
        updatedUtc = [string](
            Get-TriTierCliObjectProperty `
                -InputObject $LoopState `
                -Name 'updatedUtc' `
                -DefaultValue ''
        )
    }
}

switch ($Command) {
    "classify" {
        if ([string]::IsNullOrWhiteSpace($Prompt)) {
            throw "The classify command requires -Prompt."
        }

        $Route = Get-TriTierTaskClassification -Prompt $Prompt
        $Risk = Get-TriTierRiskClass -Prompt $Prompt

        $Result = [PSCustomObject]@{
            recommendedTier = $Route.recommendedTier
            riskClass = $Risk.riskClass
            riskName = $Risk.name
            minimumEvidence = $Risk.minimumEvidence
            ownerApprovalRequired = $Risk.ownerApprovalRequired
            freshReviewAfterRepair = $Risk.freshReviewAfterRepair
            minimumIndependentReviewers = $Risk.minimumIndependentReviewers
            reviewPolicy = $Risk.reviewPolicy
            reasons = @(@($Route.reasons) + @($Risk.reasons) | Select-Object -Unique)
        }

        if ($Json) {
            $Result | ConvertTo-Json -Depth 8
        }
        else {
            $Result | Format-List
        }

        break
    }

    "evidence" {
        $Arguments = @{
            RiskClass = $RiskClass
            EvidenceLevel = $EvidenceLevel
        }

        if ($IndependentlyReproduced) {
            $Arguments.IndependentlyReproduced = $true
        }

        $Result = Test-TriTierEvidenceSufficiency @Arguments

        if ($Json) {
            $Result | ConvertTo-Json -Depth 8
        }
        else {
            $Result | Format-List
        }

        if (-not $Result.sufficient) {
            $global:LASTEXITCODE = 1
        }
        else {
            $global:LASTEXITCODE = 0
        }

        break
    }

    "run-init" {
        if ([string]::IsNullOrWhiteSpace($Title)) {
            throw "The run-init command requires -Title."
        }

        $Arguments = @{
            ProjectPath = $ProjectPath
            Title = $Title
            CurrentPhase = $CurrentPhase
        }

        if (-not [string]::IsNullOrWhiteSpace($RunId)) {
            $Arguments.RunId = $RunId
        }

        if (-not [string]::IsNullOrWhiteSpace($PlanPath)) {
            $Arguments.PlanPath = $PlanPath
        }

        if (-not [string]::IsNullOrWhiteSpace($CurrentTask)) {
            $Arguments.CurrentTask = $CurrentTask
        }

        if (-not [string]::IsNullOrWhiteSpace($NextAction)) {
            $Arguments.NextAction = $NextAction
        }

        $Run = New-TriTierRun @Arguments

        $Result = [PSCustomObject]@{
            runId = $Run.state.runId
            title = $Run.state.title
            status = $Run.state.status
            runDirectory = $Run.runDirectory
            currentPhase = $Run.state.currentPhase
            currentTask = $Run.state.currentTask
            nextAction = $Run.state.nextAction
            baselineCommit = $Run.state.baselineCommit
            workingTreeStatus = $Run.state.workingTreeStatus
            planHash = $Run.state.planHash
        }

        if ($Json) {
            $Result | ConvertTo-Json -Depth 10
        }
        else {
            $Result | Format-List
        }

        break
    }

    "run-checkpoint" {
        if ([string]::IsNullOrWhiteSpace($RunId)) {
            throw "The run-checkpoint command requires -RunId."
        }

        if ([string]::IsNullOrWhiteSpace($Summary)) {
            throw "The run-checkpoint command requires -Summary."
        }

        if ([string]::IsNullOrWhiteSpace($NextAction)) {
            throw "The run-checkpoint command requires -NextAction."
        }

        $Arguments = @{
            ProjectPath = $ProjectPath
            RunId = $RunId
            Summary = $Summary
            NextAction = $NextAction
        }

        if (-not [string]::IsNullOrWhiteSpace($CurrentPhase)) {
            $Arguments.CurrentPhase = $CurrentPhase
        }

        if (-not [string]::IsNullOrWhiteSpace($CurrentTask)) {
            $Arguments.CurrentTask = $CurrentTask
        }

        if ($null -ne $CompletedTasks) {
            $Arguments.CompletedTasks = $CompletedTasks
        }

        if ($null -ne $UnresolvedFindings) {
            $Arguments.UnresolvedFindings = $UnresolvedFindings
        }

        if ($null -ne $Blockers) {
            $Arguments.Blockers = $Blockers
        }

        $Checkpoint = New-TriTierCheckpoint @Arguments

        $Result = [PSCustomObject]@{
            checkpointId = $Checkpoint.checkpointId
            runId = $Checkpoint.runId
            createdUtc = $Checkpoint.createdUtc
            summary = $Checkpoint.summary
            currentPhase = $Checkpoint.state.currentPhase
            currentTask = $Checkpoint.state.currentTask
            nextAction = $Checkpoint.state.nextAction
        }

        if ($Json) {
            $Result | ConvertTo-Json -Depth 10
        }
        else {
            $Result | Format-List
        }

        break
    }

    "run-resume" {
        if ([string]::IsNullOrWhiteSpace($RunId)) {
            throw "The run-resume command requires -RunId."
        }

        $Resume = Get-TriTierRunResumeData `
            -ProjectPath $ProjectPath `
            -RunId $RunId

        $Result = [PSCustomObject]@{
            runId = $Resume.state.runId
            title = $Resume.state.title
            status = $Resume.state.status
            currentPhase = $Resume.state.currentPhase
            currentTask = $Resume.state.currentTask
            completedTasks = @($Resume.state.completedTasks)
            unresolvedFindings = @($Resume.state.unresolvedFindings)
            blockers = @($Resume.state.blockers)
            nextAction = $Resume.nextAction
            lastCheckpointId = $Resume.state.lastCheckpointId
            latestCheckpointSummary = if ($null -ne $Resume.latestCheckpoint) {
                $Resume.latestCheckpoint.summary
            }
            else {
                ""
            }
            runDirectory = $Resume.runDirectory
        }

        if ($Json) {
            $Result | ConvertTo-Json -Depth 15
        }
        else {
            $Result | Format-List
        }

        break
    }

    "run-status" {
        if ([string]::IsNullOrWhiteSpace($RunId)) {
            throw "The run-status command requires -RunId."
        }

        if ([string]::IsNullOrWhiteSpace($RunStatus)) {
            $State = Get-TriTierRunState `
                -ProjectPath $ProjectPath `
                -RunId $RunId
        }
        else {
            $State = Set-TriTierRunStatus `
                -ProjectPath $ProjectPath `
                -RunId $RunId `
                -Status $RunStatus
        }

        $Result = [PSCustomObject]@{
            runId = $State.runId
            title = $State.title
            status = $State.status
            currentPhase = $State.currentPhase
            currentTask = $State.currentTask
            nextAction = $State.nextAction
            updatedUtc = $State.updatedUtc
        }

        if ($Json) {
            $Result | ConvertTo-Json -Depth 10
        }
        else {
            $Result | Format-List
        }

        break
    }
    "finding-add" {
        foreach ($RequiredValue in @(
            @{ Name = "RunId"; Value = $RunId },
            @{ Name = "Severity"; Value = $Severity },
            @{ Name = "Title"; Value = $Title },
            @{ Name = "Description"; Value = $Description },
            @{ Name = "Reviewer"; Value = $Reviewer }
        )) {
            if ([string]::IsNullOrWhiteSpace([string]$RequiredValue.Value)) {
                throw "The finding-add command requires -$($RequiredValue.Name)."
            }
        }

        if ($Severity -notin @("INFO", "LOW", "MEDIUM", "HIGH", "CRITICAL")) {
            throw "The finding-add command requires a valid -Severity."
        }

        $Arguments = @{
            ProjectPath = $ProjectPath
            RunId = $RunId
            Severity = $Severity
            Title = $Title
            Description = $Description
            Reviewer = $Reviewer
        }

        if (-not [string]::IsNullOrWhiteSpace($TaskId)) {
            $Arguments.TaskId = $TaskId
        }

        if (-not [string]::IsNullOrWhiteSpace($PhaseId)) {
            $Arguments.PhaseId = $PhaseId
        }

        if ($null -ne $EvidenceIds) {
            $Arguments.EvidenceIds = @($EvidenceIds)
        }

        $Lifecycle = Add-TriTierRunFinding @Arguments

        $Result = [PSCustomObject]@{
            findingId = $Lifecycle.finding.findingId
            severity = $Lifecycle.finding.severity
            status = $Lifecycle.finding.status
            title = $Lifecycle.finding.title
            taskId = $Lifecycle.finding.taskId
            phaseId = $Lifecycle.finding.phaseId
            reviewCycle = $Lifecycle.finding.reviewCycle
            taskBlocked = $Lifecycle.gate.taskBlocked
            phaseBlocked = $Lifecycle.gate.phaseBlocked
            runBlocked = $Lifecycle.gate.runBlocked
            nextAction = $Lifecycle.state.nextAction
            updatedUtc = $Lifecycle.state.updatedUtc
        }

        if ($Json) {
            $Result | ConvertTo-Json -Depth 20
        }
        else {
            $Result | Format-List
        }

        break
    }

    "finding-get" {
        if ([string]::IsNullOrWhiteSpace($RunId)) {
            throw "The finding-get command requires -RunId."
        }

        if ([string]::IsNullOrWhiteSpace($FindingId)) {
            throw "The finding-get command requires -FindingId."
        }

        $Arguments = @{
            ProjectPath = $ProjectPath
            RunId = $RunId
            FindingId = $FindingId
        }

        $Finding = Get-TriTierRunFinding @Arguments

        if ($Json) {
            $Finding | ConvertTo-Json -Depth 30
        }
        else {
            $Finding | Format-List
        }

        break
    }

    "finding-repair" {
        foreach ($RequiredValue in @(
            @{ Name = "RunId"; Value = $RunId },
            @{ Name = "FindingId"; Value = $FindingId },
            @{ Name = "RepairedBy"; Value = $RepairedBy },
            @{ Name = "RepairSummary"; Value = $RepairSummary }
        )) {
            if ([string]::IsNullOrWhiteSpace([string]$RequiredValue.Value)) {
                throw "The finding-repair command requires -$($RequiredValue.Name)."
            }
        }

        $Arguments = @{
            ProjectPath = $ProjectPath
            RunId = $RunId
            FindingId = $FindingId
            RepairedBy = $RepairedBy
            RepairSummary = $RepairSummary
        }

        if ($null -ne $EvidenceIds) {
            $Arguments.EvidenceIds = @($EvidenceIds)
        }

        $Lifecycle = Repair-TriTierRunFinding @Arguments

        $Result = [PSCustomObject]@{
            findingId = $Lifecycle.finding.findingId
            severity = $Lifecycle.finding.severity
            status = $Lifecycle.finding.status
            repairedBy = $Lifecycle.finding.repairedBy
            freshReviewStatus = $Lifecycle.finding.freshReviewStatus
            reviewCycle = $Lifecycle.finding.reviewCycle
            taskBlocked = $Lifecycle.gate.taskBlocked
            phaseBlocked = $Lifecycle.gate.phaseBlocked
            runBlocked = $Lifecycle.gate.runBlocked
            nextAction = $Lifecycle.state.nextAction
            updatedUtc = $Lifecycle.state.updatedUtc
        }

        if ($Json) {
            $Result | ConvertTo-Json -Depth 20
        }
        else {
            $Result | Format-List
        }

        break
    }

    "finding-review" {
        foreach ($RequiredValue in @(
            @{ Name = "RunId"; Value = $RunId },
            @{ Name = "FindingId"; Value = $FindingId },
            @{ Name = "Reviewer"; Value = $Reviewer },
            @{ Name = "Outcome"; Value = $Outcome },
            @{ Name = "ReviewSummary"; Value = $ReviewSummary }
        )) {
            if ([string]::IsNullOrWhiteSpace([string]$RequiredValue.Value)) {
                throw "The finding-review command requires -$($RequiredValue.Name)."
            }
        }

        if ($Outcome -notin @("PASS", "FAIL")) {
            throw "The finding-review command requires -Outcome PASS or FAIL."
        }

        $Arguments = @{
            ProjectPath = $ProjectPath
            RunId = $RunId
            FindingId = $FindingId
            Reviewer = $Reviewer
            Outcome = $Outcome
            Summary = $ReviewSummary
        }

        if ($null -ne $EvidenceIds) {
            $Arguments.EvidenceIds = @($EvidenceIds)
        }

        $Lifecycle = Submit-TriTierRunFindingFreshReview @Arguments

        $Result = [PSCustomObject]@{
            findingId = $Lifecycle.finding.findingId
            severity = $Lifecycle.finding.severity
            status = $Lifecycle.finding.status
            reviewer = $Lifecycle.finding.freshReviewer
            outcome = $Lifecycle.finding.freshReviewStatus
            reviewCycle = $Lifecycle.finding.reviewCycle
            taskBlocked = $Lifecycle.gate.taskBlocked
            phaseBlocked = $Lifecycle.gate.phaseBlocked
            runBlocked = $Lifecycle.gate.runBlocked
            nextAction = $Lifecycle.state.nextAction
            updatedUtc = $Lifecycle.state.updatedUtc
        }

        if ($Json) {
            $Result | ConvertTo-Json -Depth 20
        }
        else {
            $Result | Format-List
        }

        break
    }

    "finding-defer" {
        foreach ($RequiredValue in @(
            @{ Name = "RunId"; Value = $RunId },
            @{ Name = "FindingId"; Value = $FindingId },
            @{ Name = "Reason"; Value = $Reason },
            @{ Name = "OwnerApprovalRecord"; Value = $OwnerApprovalRecord }
        )) {
            if ([string]::IsNullOrWhiteSpace([string]$RequiredValue.Value)) {
                throw "The finding-defer command requires -$($RequiredValue.Name)."
            }
        }

        if (-not $OwnerApproved) {
            throw "The finding-defer command requires -OwnerApproved."
        }

        $Arguments = @{
            ProjectPath = $ProjectPath
            RunId = $RunId
            FindingId = $FindingId
            Reason = $Reason
            OwnerApprovalRecord = $OwnerApprovalRecord
            OwnerApproved = $OwnerApproved
        }

        $Lifecycle = Set-TriTierRunFindingDeferral @Arguments

        $Result = [PSCustomObject]@{
            findingId = $Lifecycle.finding.findingId
            severity = $Lifecycle.finding.severity
            status = $Lifecycle.finding.status
            ownerApprovalRecord = $Lifecycle.finding.ownerApprovalRecord
            taskBlocked = $Lifecycle.gate.taskBlocked
            phaseBlocked = $Lifecycle.gate.phaseBlocked
            runBlocked = $Lifecycle.gate.runBlocked
            nextAction = $Lifecycle.state.nextAction
            updatedUtc = $Lifecycle.state.updatedUtc
        }

        if ($Json) {
            $Result | ConvertTo-Json -Depth 20
        }
        else {
            $Result | Format-List
        }

        break
    }
"task-flow-init" {
    foreach ($RequiredValue in @(
        @{ Name = "RunId"; Value = $RunId },
        @{ Name = "Actor"; Value = $Actor },
        @{ Name = "EventId"; Value = $EventId }
    )) {
        if ([string]::IsNullOrWhiteSpace([string]$RequiredValue.Value)) {
            throw "The task-flow-init command requires -$($RequiredValue.Name)."
        }
    }

    $TaskResult = Initialize-TriTierRunTaskFlow `
        -ProjectPath $ProjectPath `
        -RunId $RunId `
        -InitializedBy $Actor `
        -EventId $EventId

    $Result = New-TriTierCliFlowResult `
        -Flow $TaskResult.flow `
        -State $TaskResult.state `
        -Replayed ([bool]$TaskResult.replayed)

    if ($Json) {
        $Result | ConvertTo-Json -Depth 30
    }
    else {
        $Result | Format-List
    }

    break
}

"task-start" {
    foreach ($RequiredValue in @(
        @{ Name = "RunId"; Value = $RunId },
        @{ Name = "TaskId"; Value = $TaskId },
        @{ Name = "Actor"; Value = $Actor },
        @{ Name = "EventId"; Value = $EventId }
    )) {
        if ([string]::IsNullOrWhiteSpace([string]$RequiredValue.Value)) {
            throw "The task-start command requires -$($RequiredValue.Name)."
        }
    }

    $Arguments = @{
        ProjectPath = $ProjectPath
        RunId = $RunId
        TaskId = $TaskId
        SelectedBy = $Actor
        EventId = $EventId
    }

    if (-not [string]::IsNullOrWhiteSpace($Instruction)) {
        $Arguments.ImplementationInstruction = $Instruction
    }

    $TaskResult = Start-TriTierRunTask @Arguments

    $Result = New-TriTierCliFlowResult `
        -Flow $TaskResult.flow `
        -State $TaskResult.state `
        -Replayed ([bool]$TaskResult.replayed)

    if ($Json) {
        $Result | ConvertTo-Json -Depth 30
    }
    else {
        $Result | Format-List
    }

    break
}

"implementation-complete" {
    foreach ($RequiredValue in @(
        @{ Name = "RunId"; Value = $RunId },
        @{ Name = "Actor"; Value = $Actor },
        @{ Name = "Summary"; Value = $Summary },
        @{ Name = "EventId"; Value = $EventId }
    )) {
        if ([string]::IsNullOrWhiteSpace([string]$RequiredValue.Value)) {
            throw "The implementation-complete command requires -$($RequiredValue.Name)."
        }
    }

    $Arguments = @{
        ProjectPath = $ProjectPath
        RunId = $RunId
        ImplementedBy = $Actor
        Summary = $Summary
        EventId = $EventId
    }

    if ($null -ne $EvidenceIds) {
        $Arguments.EvidenceIds = @($EvidenceIds)
    }

    $TaskResult = Complete-TriTierRunImplementation @Arguments

    $Result = New-TriTierCliFlowResult `
        -Flow $TaskResult.flow `
        -State $TaskResult.state `
        -Replayed ([bool]$TaskResult.replayed)

    if ($Json) {
        $Result | ConvertTo-Json -Depth 30
    }
    else {
        $Result | Format-List
    }

    break
}

"task-review" {
    foreach ($RequiredValue in @(
        @{ Name = "RunId"; Value = $RunId },
        @{ Name = "Actor"; Value = $Actor },
        @{ Name = "Outcome"; Value = $Outcome },
        @{ Name = "Summary"; Value = $Summary },
        @{ Name = "EventId"; Value = $EventId }
    )) {
        if ([string]::IsNullOrWhiteSpace([string]$RequiredValue.Value)) {
            throw "The task-review command requires -$($RequiredValue.Name)."
        }
    }

    if ($Outcome -notin @("PASS", "FAIL")) {
        throw "The task-review command requires -Outcome PASS or FAIL."
    }

    $Arguments = @{
        ProjectPath = $ProjectPath
        RunId = $RunId
        Reviewer = $Actor
        Outcome = $Outcome
        Summary = $Summary
        EventId = $EventId
    }

    if ($null -ne $EvidenceIds) {
        $Arguments.EvidenceIds = @($EvidenceIds)
    }

    $TaskResult = Submit-TriTierRunTaskReview @Arguments

    $Result = New-TriTierCliFlowResult `
        -Flow $TaskResult.flow `
        -State $TaskResult.state `
        -Replayed ([bool]$TaskResult.replayed)

    if ($Json) {
        $Result | ConvertTo-Json -Depth 30
    }
    else {
        $Result | Format-List
    }

    break
}

"task-flow-status" {
    if ([string]::IsNullOrWhiteSpace($RunId)) {
        throw "The task-flow-status command requires -RunId."
    }

    $Flow = Get-TriTierRunTaskFlow `
        -ProjectPath $ProjectPath `
        -RunId $RunId

    $State = Get-TriTierRunState `
        -ProjectPath $ProjectPath `
        -RunId $RunId

    $Result = New-TriTierCliFlowResult `
        -Flow $Flow `
        -State $State `
        -Gate $State.findingGate

    if ($Json) {
        $Result | ConvertTo-Json -Depth 30
    }
    else {
        $Result | Format-List
    }

    break
}

"task-planning-start" {
    foreach ($RequiredValue in @(
        @{ Name = "RunId"; Value = $RunId },
        @{ Name = "Actor"; Value = $Actor },
        @{ Name = "EventId"; Value = $EventId }
    )) {
        if ([string]::IsNullOrWhiteSpace([string]$RequiredValue.Value)) {
            throw "The task-planning-start command requires -$($RequiredValue.Name)."
        }
    }

    $TaskResult = Start-TriTierRunPlanning `
        -ProjectPath $ProjectPath `
        -RunId $RunId `
        -StartedBy $Actor `
        -EventId $EventId

    $Result = New-TriTierCliFlowResult `
        -Flow $TaskResult.flow `
        -State $TaskResult.state `
        -Replayed ([bool]$TaskResult.replayed)

    if ($Json) {
        $Result | ConvertTo-Json -Depth 30
    }
    else {
        $Result | Format-List
    }

    break
}

"repair-open" {
    foreach ($RequiredValue in @(
        @{ Name = "RunId"; Value = $RunId },
        @{ Name = "Actor"; Value = $Actor },
        @{ Name = "Severity"; Value = $Severity },
        @{ Name = "Title"; Value = $Title },
        @{ Name = "Description"; Value = $Description },
        @{ Name = "EventId"; Value = $EventId }
    )) {
        if ([string]::IsNullOrWhiteSpace([string]$RequiredValue.Value)) {
            throw "The repair-open command requires -$($RequiredValue.Name)."
        }
    }

    if ($Severity -notin @("MEDIUM", "HIGH", "CRITICAL")) {
        throw "The repair-open command requires -Severity MEDIUM, HIGH, or CRITICAL."
    }

    $Arguments = @{
        ProjectPath = $ProjectPath
        RunId = $RunId
        Severity = $Severity
        Title = $Title
        Description = $Description
        AuthorizedBy = $Actor
        EventId = $EventId
    }

    if ($null -ne $EvidenceIds) {
        $Arguments.EvidenceIds = @($EvidenceIds)
    }

    $RepairResult = Start-TriTierRunRepairCycle @Arguments

    $Result = New-TriTierCliFlowResult `
        -Flow $RepairResult.flow `
        -State $RepairResult.state `
        -Finding $RepairResult.finding `
        -Gate $RepairResult.gate `
        -Replayed ([bool]$RepairResult.replayed)

    if ($Json) {
        $Result | ConvertTo-Json -Depth 30
    }
    else {
        $Result | Format-List
    }

    break
}

"repair-complete" {
    foreach ($RequiredValue in @(
        @{ Name = "RunId"; Value = $RunId },
        @{ Name = "Actor"; Value = $Actor },
        @{ Name = "Summary"; Value = $Summary },
        @{ Name = "EventId"; Value = $EventId }
    )) {
        if ([string]::IsNullOrWhiteSpace([string]$RequiredValue.Value)) {
            throw "The repair-complete command requires -$($RequiredValue.Name)."
        }
    }

    $Arguments = @{
        ProjectPath = $ProjectPath
        RunId = $RunId
        RepairedBy = $Actor
        RepairSummary = $Summary
        EventId = $EventId
    }

    if ($null -ne $EvidenceIds) {
        $Arguments.EvidenceIds = @($EvidenceIds)
    }

    $RepairResult = Complete-TriTierRunRepair @Arguments

    $Result = New-TriTierCliFlowResult `
        -Flow $RepairResult.flow `
        -State $RepairResult.state `
        -Finding $RepairResult.finding `
        -Gate $RepairResult.gate `
        -Replayed ([bool]$RepairResult.replayed)

    if ($Json) {
        $Result | ConvertTo-Json -Depth 30
    }
    else {
        $Result | Format-List
    }

    break
}

"repair-review" {
    foreach ($RequiredValue in @(
        @{ Name = "RunId"; Value = $RunId },
        @{ Name = "Actor"; Value = $Actor },
        @{ Name = "Outcome"; Value = $Outcome },
        @{ Name = "Summary"; Value = $Summary },
        @{ Name = "EventId"; Value = $EventId }
    )) {
        if ([string]::IsNullOrWhiteSpace([string]$RequiredValue.Value)) {
            throw "The repair-review command requires -$($RequiredValue.Name)."
        }
    }

    if ($Outcome -notin @("PASS", "FAIL")) {
        throw "The repair-review command requires -Outcome PASS or FAIL."
    }

    $Arguments = @{
        ProjectPath = $ProjectPath
        RunId = $RunId
        Reviewer = $Actor
        Outcome = $Outcome
        Summary = $Summary
        EventId = $EventId
    }

    if ($null -ne $EvidenceIds) {
        $Arguments.EvidenceIds = @($EvidenceIds)
    }

    $RepairResult = Submit-TriTierRunRepairReview @Arguments

    $Result = New-TriTierCliFlowResult `
        -Flow $RepairResult.flow `
        -State $RepairResult.state `
        -Finding $RepairResult.finding `
        -Gate $RepairResult.gate `
        -Replayed ([bool]$RepairResult.replayed)

    if ($Json) {
        $Result | ConvertTo-Json -Depth 30
    }
    else {
        $Result | Format-List
    }

    break
}

"repair-adjudicate" {
    foreach ($RequiredValue in @(
        @{ Name = "RunId"; Value = $RunId },
        @{ Name = "Actor"; Value = $Actor },
        @{ Name = "Decision"; Value = $Decision },
        @{ Name = "Summary"; Value = $Summary },
        @{ Name = "EventId"; Value = $EventId }
    )) {
        if ([string]::IsNullOrWhiteSpace([string]$RequiredValue.Value)) {
            throw "The repair-adjudicate command requires -$($RequiredValue.Name)."
        }
    }

    if ($Decision -notin @(
        "REPAIR_AGAIN",
        "OWNER_DECISION",
        "ABORT_FOR_SAFETY",
        "FAIL_VALIDATION"
    )) {
        throw "The repair-adjudicate command received an unsupported -Decision."
    }

    $Arguments = @{
        ProjectPath = $ProjectPath
        RunId = $RunId
        Adjudicator = $Actor
        Decision = $Decision
        Summary = $Summary
        EventId = $EventId
    }

    if ($null -ne $EvidenceIds) {
        $Arguments.EvidenceIds = @($EvidenceIds)
    }

    $RepairResult = Submit-TriTierRunAdjudication @Arguments

    $Result = New-TriTierCliFlowResult `
        -Flow $RepairResult.flow `
        -State $RepairResult.state `
        -Finding $RepairResult.finding `
        -Gate $RepairResult.gate `
        -Replayed ([bool]$RepairResult.replayed)

    if ($Json) {
        $Result | ConvertTo-Json -Depth 30
    }
    else {
        $Result | Format-List
    }

    break
}

"repair-status" {
    if ([string]::IsNullOrWhiteSpace($RunId)) {
        throw "The repair-status command requires -RunId."
    }

    $RepairResult = Get-TriTierRunRepairCycle `
        -ProjectPath $ProjectPath `
        -RunId $RunId

    $Result = New-TriTierCliFlowResult `
        -Flow $RepairResult.flow `
        -State $RepairResult.state `
        -Finding $RepairResult.finding `
        -Gate $RepairResult.gate `
        -Replayed ([bool]$RepairResult.replayed)

    if ($Json) {
        $Result | ConvertTo-Json -Depth 30
    }
    else {
        $Result | Format-List
    }

    break
}

"orchestration-status" {
    if ([string]::IsNullOrWhiteSpace($RunId)) {
        throw "The orchestration-status command requires -RunId."
    }

    $State = Get-TriTierRunState `
        -ProjectPath $ProjectPath `
        -RunId $RunId

    $OrchestrationDecision = Get-TriTierOrchestrationDecision `
        -RunState $State

    $Phase = $null

    if (
        $null -ne $State.PSObject.Properties['phaseGate'] -and
        $null -ne $State.phaseGate
    ) {
        $Phase = $State.phaseGate
    }

    $Result = New-TriTierCliPhaseResult `
        -Phase $Phase `
        -Decision $OrchestrationDecision `
        -State $State

    if ($Json) {
        $Result | ConvertTo-Json -Depth 40
    }
    else {
        $Result | Format-List
    }

    break
}

"phase-start" {
    foreach ($RequiredValue in @(
        @{ Name = "RunId"; Value = $RunId },
        @{ Name = "PhaseId"; Value = $PhaseId },
        @{ Name = "PhaseRiskClass"; Value = $PhaseRiskClass },
        @{ Name = "Actor"; Value = $Actor },
        @{ Name = "EventId"; Value = $EventId }
    )) {
        if ([string]::IsNullOrWhiteSpace([string]$RequiredValue.Value)) {
            throw "The phase-start command requires -$($RequiredValue.Name)."
        }
    }

    if ($PhaseRiskClass -notin @("R0", "R1", "R2", "R3", "R4")) {
        throw "The phase-start command requires -PhaseRiskClass R0 through R4."
    }

    $PhaseResult = Start-TriTierRunPhase `
        -ProjectPath $ProjectPath `
        -RunId $RunId `
        -PhaseId $PhaseId `
        -RiskClass $PhaseRiskClass `
        -StartedBy $Actor `
        -EventId $EventId

    $Result = New-TriTierCliPhaseResult `
        -Phase $PhaseResult.phase `
        -Decision $PhaseResult.decision `
        -State $PhaseResult.state `
        -Replayed ([bool]$PhaseResult.replayed)

    if ($Json) {
        $Result | ConvertTo-Json -Depth 40
    }
    else {
        $Result | Format-List
    }

    break
}

"phase-ready" {
    foreach ($RequiredValue in @(
        @{ Name = "RunId"; Value = $RunId },
        @{ Name = "ObservedEvidenceLevel"; Value = $ObservedEvidenceLevel },
        @{ Name = "Actor"; Value = $Actor },
        @{ Name = "EventId"; Value = $EventId }
    )) {
        if ([string]::IsNullOrWhiteSpace([string]$RequiredValue.Value)) {
            throw "The phase-ready command requires -$($RequiredValue.Name)."
        }
    }

    if ($ObservedEvidenceLevel -notin @(
        "E0", "E1", "E2", "E3", "E4", "E5"
    )) {
        throw "The phase-ready command requires -ObservedEvidenceLevel E0 through E5."
    }

    $Arguments = @{
        ProjectPath = $ProjectPath
        RunId = $RunId
        ObservedEvidenceLevel = $ObservedEvidenceLevel
        IndependentEvidence = [bool]$EvidenceIndependent
        SubmittedBy = $Actor
        EventId = $EventId
    }

    if ($null -ne $EvidenceIds) {
        $Arguments.EvidenceIds = @($EvidenceIds)
    }

    if (-not [string]::IsNullOrWhiteSpace($OwnerApprovalRecord)) {
        $Arguments.OwnerApprovalRecord = $OwnerApprovalRecord
    }

    $PhaseResult = Submit-TriTierRunPhaseReady @Arguments

    $Result = New-TriTierCliPhaseResult `
        -Phase $PhaseResult.phase `
        -Decision $PhaseResult.decision `
        -State $PhaseResult.state `
        -Replayed ([bool]$PhaseResult.replayed)

    if ($Json) {
        $Result | ConvertTo-Json -Depth 40
    }
    else {
        $Result | Format-List
    }

    break
}

"phase-review" {
    foreach ($RequiredValue in @(
        @{ Name = "RunId"; Value = $RunId },
        @{ Name = "Decision"; Value = $Decision },
        @{ Name = "Summary"; Value = $Summary },
        @{ Name = "Actor"; Value = $Actor },
        @{ Name = "EventId"; Value = $EventId }
    )) {
        if ([string]::IsNullOrWhiteSpace([string]$RequiredValue.Value)) {
            throw "The phase-review command requires -$($RequiredValue.Name)."
        }
    }

    if ($Decision -notin @("ACCEPT", "REJECT")) {
        throw "The phase-review command requires -Decision ACCEPT or REJECT."
    }

    $Arguments = @{
        ProjectPath = $ProjectPath
        RunId = $RunId
        Decision = $Decision
        Summary = $Summary
        Reviewer = $Actor
        EventId = $EventId
    }

    if ($null -ne $EvidenceIds) {
        $Arguments.EvidenceIds = @($EvidenceIds)
    }

    $PhaseResult = Submit-TriTierRunPhaseReview @Arguments

    $Result = New-TriTierCliPhaseResult `
        -Phase $PhaseResult.phase `
        -Decision $PhaseResult.decision `
        -State $PhaseResult.state `
        -Replayed ([bool]$PhaseResult.replayed)

    if ($Json) {
        $Result | ConvertTo-Json -Depth 40
    }
    else {
        $Result | Format-List
    }

    break
}

"phase-accept" {
    foreach ($RequiredValue in @(
        @{ Name = "RunId"; Value = $RunId },
        @{ Name = "Summary"; Value = $Summary },
        @{ Name = "Actor"; Value = $Actor },
        @{ Name = "EventId"; Value = $EventId }
    )) {
        if ([string]::IsNullOrWhiteSpace([string]$RequiredValue.Value)) {
            throw "The phase-accept command requires -$($RequiredValue.Name)."
        }
    }

    $Arguments = @{
        ProjectPath = $ProjectPath
        RunId = $RunId
        Decision = "ACCEPT"
        Summary = $Summary
        Reviewer = $Actor
        EventId = $EventId
    }

    if ($null -ne $EvidenceIds) {
        $Arguments.EvidenceIds = @($EvidenceIds)
    }

    $PhaseResult = Submit-TriTierRunPhaseReview @Arguments

    $Result = New-TriTierCliPhaseResult `
        -Phase $PhaseResult.phase `
        -Decision $PhaseResult.decision `
        -State $PhaseResult.state `
        -Replayed ([bool]$PhaseResult.replayed)

    if ($Json) {
        $Result | ConvertTo-Json -Depth 40
    }
    else {
        $Result | Format-List
    }

    break
}

"phase-reject" {
    foreach ($RequiredValue in @(
        @{ Name = "RunId"; Value = $RunId },
        @{ Name = "Summary"; Value = $Summary },
        @{ Name = "Actor"; Value = $Actor },
        @{ Name = "EventId"; Value = $EventId }
    )) {
        if ([string]::IsNullOrWhiteSpace([string]$RequiredValue.Value)) {
            throw "The phase-reject command requires -$($RequiredValue.Name)."
        }
    }

    $Arguments = @{
        ProjectPath = $ProjectPath
        RunId = $RunId
        Decision = "REJECT"
        Summary = $Summary
        Reviewer = $Actor
        EventId = $EventId
    }

    if ($null -ne $EvidenceIds) {
        $Arguments.EvidenceIds = @($EvidenceIds)
    }

    $PhaseResult = Submit-TriTierRunPhaseReview @Arguments

    $Result = New-TriTierCliPhaseResult `
        -Phase $PhaseResult.phase `
        -Decision $PhaseResult.decision `
        -State $PhaseResult.state `
        -Replayed ([bool]$PhaseResult.replayed)

    if ($Json) {
        $Result | ConvertTo-Json -Depth 40
    }
    else {
        $Result | Format-List
    }

    break
}

"phase-status" {
    if ([string]::IsNullOrWhiteSpace($RunId)) {
        throw "The phase-status command requires -RunId."
    }

    $PhaseResult = Get-TriTierRunPhaseGate `
        -ProjectPath $ProjectPath `
        -RunId $RunId

    $Result = New-TriTierCliPhaseResult `
        -Phase $PhaseResult.phase `
        -Decision $PhaseResult.decision `
        -State $PhaseResult.state `
        -Replayed ([bool]$PhaseResult.replayed)

    if ($Json) {
        $Result | ConvertTo-Json -Depth 40
    }
    else {
        $Result | Format-List
    }

    break
}

"exec" {
    if ([string]::IsNullOrWhiteSpace($RunId)) {
        throw "The exec command requires -RunId."
    }

    $ExecutionArguments = @{
        ProjectPath = $ProjectPath
        RunId = $RunId
        MaxSteps = $MaxSteps
        MaxSameDecision = $MaxSameDecision
        MaxAttemptsPerAction = $MaxAttemptsPerAction
        StepTimeoutSeconds = $StepTimeoutSeconds
    }

    if (-not [string]::IsNullOrWhiteSpace($DispatcherPath)) {
        $ExecutionArguments.DispatcherPath = $DispatcherPath
    }

    if ($DryRun) {
        $ExecutionArguments.DryRun = $true
    }

    $ExecutionInvocation = Invoke-TriTierRunExecutionLoop @ExecutionArguments

    $ExecutionOutput = New-TriTierCliExecutionResult `
        -ExecutionResult $ExecutionInvocation

    if ($Json) {
        $ExecutionOutput | ConvertTo-Json -Depth 60
    }
    else {
        $ExecutionOutput | Format-List
    }

    break
}

"exec-resume" {
    if ([string]::IsNullOrWhiteSpace($RunId)) {
        throw "The exec-resume command requires -RunId."
    }

    $ExecutionArguments = @{
        ProjectPath = $ProjectPath
        RunId = $RunId
        MaxSteps = $MaxSteps
        MaxSameDecision = $MaxSameDecision
        MaxAttemptsPerAction = $MaxAttemptsPerAction
        StepTimeoutSeconds = $StepTimeoutSeconds
    }

    if (-not [string]::IsNullOrWhiteSpace($DispatcherPath)) {
        $ExecutionArguments.DispatcherPath = $DispatcherPath
    }

    if ($DryRun) {
        $ExecutionArguments.DryRun = $true
    }

    $ExecutionInvocation = Resume-TriTierRunExecutionLoop @ExecutionArguments

    $ExecutionOutput = New-TriTierCliExecutionResult `
        -ExecutionResult $ExecutionInvocation

    if ($Json) {
        $ExecutionOutput | ConvertTo-Json -Depth 60
    }
    else {
        $ExecutionOutput | Format-List
    }

    break
}

"exec-status" {
    if ([string]::IsNullOrWhiteSpace($RunId)) {
        throw "The exec-status command requires -RunId."
    }

    $ExecutionLoopState = Get-TriTierRunExecutionLoop `
        -ProjectPath $ProjectPath `
        -RunId $RunId
    $ExecutionRunState = Get-TriTierRunState `
        -ProjectPath $ProjectPath `
        -RunId $RunId
    $ExecutionDecision = Get-TriTierRunOrchestrationDecision `
        -ProjectPath $ProjectPath `
        -RunId $RunId

    $ExecutionInvocation = [PSCustomObject][ordered]@{
        loop = $ExecutionLoopState
        state = $ExecutionRunState
        decision = $ExecutionDecision
        envelope = $null
        dispatched = $false
        dryRun = $false
    }

    $ExecutionOutput = New-TriTierCliExecutionResult `
        -ExecutionResult $ExecutionInvocation

    if ($Json) {
        $ExecutionOutput | ConvertTo-Json -Depth 60
    }
    else {
        $ExecutionOutput | Format-List
    }

    break
}

    "doctor" {
        $RequiredAgents = @(
            "luna-router.toml",
            "luna-worker.toml",
            "sol-adjudicator.toml",
            "sol-architect.toml",
            "terra-manager.toml",
            "terra-reviewer.toml"
        )

        $RepositoryRoot = Split-Path $PSScriptRoot -Parent
        $AgentRoot = Join-Path $RepositoryRoot "agents"
        $Checks = @()

        $Checks += [PSCustomObject]@{
            Check = "PowerShell"
            Status = "PASS"
            Detail = $PSVersionTable.PSVersion.ToString()
        }

        foreach ($Entry in $ModulePaths.GetEnumerator()) {
            $Checks += [PSCustomObject]@{
                Check = "$($Entry.Key) module"
                Status = if (Test-Path $Entry.Value) { "PASS" } else { "FAIL" }
                Detail = $Entry.Value
            }
        }

        foreach ($Agent in $RequiredAgents) {
            $Path = Join-Path $AgentRoot $Agent

            $Checks += [PSCustomObject]@{
                Check = "Agent: $Agent"
                Status = if (Test-Path $Path) { "PASS" } else { "FAIL" }
                Detail = $Path
            }
        }

        if ($Json) {
            $Checks | ConvertTo-Json -Depth 5
        }
        else {
            $Checks | Format-Table -AutoSize
        }

        if ($Checks.Status -contains "FAIL") {
            throw "Tri-Tier doctor found one or more failed checks."
        }

        break
    }

    "version" {
        "tri-tier-agent-system 0.8.0-alpha"
        break
    }
}
