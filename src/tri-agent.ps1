[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("classify", "evidence", "run-init", "run-checkpoint", "run-resume", "run-status", "finding-add", "finding-get", "finding-repair", "finding-review", "finding-defer", "task-flow-init", "task-start", "implementation-complete", "task-review", "task-flow-status", "task-planning-start", "repair-open", "repair-complete", "repair-review", "repair-adjudicate", "repair-status", "doctor", "version")]
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
        "tri-tier-agent-system 0.6.0-alpha"
        break
    }
}
