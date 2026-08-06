Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$StateModulePath = Join-Path $PSScriptRoot 'State.psm1'

if (-not (Test-Path $StateModulePath -PathType Leaf)) {
    throw "Required Tri-Tier module is missing: $StateModulePath"
}

Import-Module $StateModulePath

$script:TaskFlowStages = @(
    'PLAN',
    'IMPLEMENT',
    'REVIEW',
    'CONTINUE'
)

function Resolve-TriTierTaskFlowEventId {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$EventId = ''
    )

    if (-not [string]::IsNullOrWhiteSpace($EventId)) {
        if ($EventId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$') {
            throw 'Task-flow EventId contains unsupported characters.'
        }

        return $EventId
    }

    'evt-' + [guid]::NewGuid().ToString('N')
}

function Assert-TriTierTaskFlowActor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Actor,

        [Parameter(Mandatory)]
        [ValidateSet('terra', 'luna', 'sol')]
        [string]$ExpectedRole
    )

    $Pattern = '^' + [regex]::Escape($ExpectedRole) + '([_-].*)?$'

    if ($Actor -notmatch $Pattern) {
        throw "Task-flow transition requires a $ExpectedRole actor; received '$Actor'."
    }
}

function Test-TriTierTaskFlowEventApplied {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Flow,

        [Parameter(Mandatory)]
        [string]$EventId
    )

    @(
        $Flow.transitionHistory |
            Where-Object {
                [string]$_.eventId -eq $EventId
            }
    ).Count -gt 0
}

function Add-TriTierTaskFlowTransition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Flow,

        [Parameter(Mandatory)]
        [string]$EventId,

        [Parameter(Mandatory)]
        [string]$EventType,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$FromStage,

        [Parameter(Mandatory)]
        [string]$ToStage,

        [Parameter(Mandatory)]
        [string]$Actor,

        [Parameter(Mandatory)]
        [string]$Summary,

        [Parameter()]
        [string[]]$EvidenceIds = @()
    )

    $Flow.revision = [int]$Flow.revision + 1
    $OccurredUtc = [DateTime]::UtcNow.ToString('o')

    $Transition = [PSCustomObject][ordered]@{
        sequence = $Flow.revision
        eventId = $EventId
        eventType = $EventType
        fromStage = $FromStage
        toStage = $ToStage
        actor = $Actor
        summary = $Summary
        evidenceIds = @($EvidenceIds)
        occurredUtc = $OccurredUtc
    }

    $Flow.transitionHistory = @($Flow.transitionHistory) + $Transition
    $Flow.updatedUtc = $OccurredUtc

    $Flow
}

function Save-TriTierRunTaskFlow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$RunId,

        [Parameter(Mandatory)]
        [object]$Flow,

        [Parameter()]
        [bool]$Replayed = $false
    )

    $State = Set-TriTierRunTaskFlowState `
        -ProjectPath $ProjectPath `
        -RunId $RunId `
        -TaskFlowState $Flow

    [PSCustomObject][ordered]@{
        flow = $Flow
        state = $State
        replayed = $Replayed
    }
}

function Get-TriTierRunTaskFlow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$RunId
    )

    $State = Get-TriTierRunState `
        -ProjectPath $ProjectPath `
        -RunId $RunId

    if (
        $null -eq $State.PSObject.Properties['taskFlow'] -or
        $null -eq $State.taskFlow
    ) {
        throw "Task flow is not initialized for run '$RunId'."
    }

    $State.taskFlow
}

function Initialize-TriTierRunTaskFlow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$RunId,

        [Parameter()]
        [string]$InitializedBy = 'terra-manager',

        [Parameter()]
        [string]$EventId = ''
    )

    Assert-TriTierTaskFlowActor `
        -Actor $InitializedBy `
        -ExpectedRole 'terra'

    $State = Get-TriTierRunState `
        -ProjectPath $ProjectPath `
        -RunId $RunId

    if (
        $null -ne $State.PSObject.Properties['taskFlow'] -and
        $null -ne $State.taskFlow
    ) {
        return [PSCustomObject][ordered]@{
            flow = $State.taskFlow
            state = $State
            replayed = $true
        }
    }

    $ResolvedEventId = Resolve-TriTierTaskFlowEventId -EventId $EventId
    $CurrentTask = [string]$State.currentTask
    $Stage = 'PLAN'
    $ResponsibleParty = 'terra'
    $NextAction = 'Terra must select and persist the next bounded task.'

    if (-not [string]::IsNullOrWhiteSpace($CurrentTask)) {
        $Stage = 'IMPLEMENT'
        $ResponsibleParty = 'luna'
        $NextAction = [string]$State.nextAction
    }

    $CreatedUtc = [DateTime]::UtcNow.ToString('o')

    $Flow = [PSCustomObject][ordered]@{
        schemaVersion = 1
        stage = $Stage
        previousStage = ''
        responsibleParty = $ResponsibleParty
        mayAdvance = $false
        currentTask = $CurrentTask
        implementationActor = ''
        implementationSummary = ''
        implementationEvidenceIds = @()
        reviewActor = ''
        reviewOutcome = 'NOT_STARTED'
        reviewSummary = ''
        reviewEvidenceIds = @()
        activeRepairFindingId = ''
        lastRepairFindingId = ''
        repairResumeStage = ''
        repairActor = ''
        repairReviewActor = ''
        repairReviewOutcome = 'NOT_STARTED'
        adjudicationDecision = ''
        nextAction = $NextAction
        revision = 0
        transitionHistory = @()
        createdUtc = $CreatedUtc
        updatedUtc = $CreatedUtc
    }

    $Flow = Add-TriTierTaskFlowTransition `
        -Flow $Flow `
        -EventId $ResolvedEventId `
        -EventType 'FLOW_INITIALIZED' `
        -FromStage '' `
        -ToStage $Stage `
        -Actor $InitializedBy `
        -Summary 'Initialized durable task flow.'

    Save-TriTierRunTaskFlow `
        -ProjectPath $ProjectPath `
        -RunId $RunId `
        -Flow $Flow
}

function Start-TriTierRunTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$RunId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$TaskId,

        [Parameter()]
        [string]$SelectedBy = 'terra-manager',

        [Parameter()]
        [string]$ImplementationInstruction = '',

        [Parameter()]
        [string]$EventId = ''
    )

    Assert-TriTierTaskFlowActor `
        -Actor $SelectedBy `
        -ExpectedRole 'terra'

    $ResolvedEventId = Resolve-TriTierTaskFlowEventId -EventId $EventId
    $Flow = Get-TriTierRunTaskFlow -ProjectPath $ProjectPath -RunId $RunId

    if (Test-TriTierTaskFlowEventApplied -Flow $Flow -EventId $ResolvedEventId) {
        return Save-TriTierRunTaskFlow `
            -ProjectPath $ProjectPath `
            -RunId $RunId `
            -Flow $Flow `
            -Replayed $true
    }

    if ($Flow.stage -ne 'PLAN') {
        throw "Task selection requires PLAN stage; current stage is '$($Flow.stage)'."
    }

    $NextAction = $ImplementationInstruction

    if ([string]::IsNullOrWhiteSpace($NextAction)) {
        $NextAction = "Luna must implement bounded task $TaskId."
    }

    $FromStage = [string]$Flow.stage
    $Flow.previousStage = $FromStage
    $Flow.stage = 'IMPLEMENT'
    $Flow.responsibleParty = 'luna'
    $Flow.mayAdvance = $false
    $Flow.currentTask = $TaskId
    $Flow.implementationActor = ''
    $Flow.implementationSummary = ''
    $Flow.implementationEvidenceIds = @()
    $Flow.reviewActor = ''
    $Flow.reviewOutcome = 'NOT_STARTED'
    $Flow.reviewSummary = ''
    $Flow.reviewEvidenceIds = @()
    $Flow.activeRepairFindingId = ''
    $Flow.lastRepairFindingId = ''
    $Flow.repairResumeStage = ''
    $Flow.repairActor = ''
    $Flow.repairReviewActor = ''
    $Flow.repairReviewOutcome = 'NOT_STARTED'
    $Flow.adjudicationDecision = ''
    $Flow.nextAction = $NextAction

    $Flow = Add-TriTierTaskFlowTransition `
        -Flow $Flow `
        -EventId $ResolvedEventId `
        -EventType 'TASK_SELECTED' `
        -FromStage $FromStage `
        -ToStage 'IMPLEMENT' `
        -Actor $SelectedBy `
        -Summary "Selected bounded task $TaskId."

    Save-TriTierRunTaskFlow `
        -ProjectPath $ProjectPath `
        -RunId $RunId `
        -Flow $Flow
}

function Complete-TriTierRunImplementation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$RunId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ImplementedBy,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Summary,

        [Parameter()]
        [string[]]$EvidenceIds = @(),

        [Parameter()]
        [string]$EventId = ''
    )

    Assert-TriTierTaskFlowActor `
        -Actor $ImplementedBy `
        -ExpectedRole 'luna'

    $ResolvedEventId = Resolve-TriTierTaskFlowEventId -EventId $EventId
    $Flow = Get-TriTierRunTaskFlow -ProjectPath $ProjectPath -RunId $RunId

    if (Test-TriTierTaskFlowEventApplied -Flow $Flow -EventId $ResolvedEventId) {
        return Save-TriTierRunTaskFlow `
            -ProjectPath $ProjectPath `
            -RunId $RunId `
            -Flow $Flow `
            -Replayed $true
    }

    if ($Flow.stage -ne 'IMPLEMENT') {
        throw "Implementation completion requires IMPLEMENT stage; current stage is '$($Flow.stage)'."
    }

    if ([string]::IsNullOrWhiteSpace([string]$Flow.currentTask)) {
        throw 'Implementation completion requires a current bounded task.'
    }

    $FromStage = [string]$Flow.stage
    $Flow.previousStage = $FromStage
    $Flow.stage = 'REVIEW'
    $Flow.responsibleParty = 'sol'
    $Flow.mayAdvance = $false
    $Flow.implementationActor = $ImplementedBy
    $Flow.implementationSummary = $Summary
    $Flow.implementationEvidenceIds = @($EvidenceIds)
    $Flow.reviewActor = ''
    $Flow.reviewOutcome = 'PENDING'
    $Flow.reviewSummary = ''
    $Flow.reviewEvidenceIds = @()
    $Flow.nextAction = (
        "Sol must independently review task $($Flow.currentTask) " +
        "using the implementation evidence."
    )

    $Flow = Add-TriTierTaskFlowTransition `
        -Flow $Flow `
        -EventId $ResolvedEventId `
        -EventType 'IMPLEMENTATION_COMPLETED' `
        -FromStage $FromStage `
        -ToStage 'REVIEW' `
        -Actor $ImplementedBy `
        -Summary $Summary `
        -EvidenceIds $EvidenceIds

    Save-TriTierRunTaskFlow `
        -ProjectPath $ProjectPath `
        -RunId $RunId `
        -Flow $Flow
}

function Submit-TriTierRunTaskReview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$RunId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Reviewer,

        [Parameter(Mandatory)]
        [ValidateSet('PASS', 'FAIL')]
        [string]$Outcome,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Summary,

        [Parameter()]
        [string[]]$EvidenceIds = @(),

        [Parameter()]
        [string]$EventId = ''
    )

    Assert-TriTierTaskFlowActor `
        -Actor $Reviewer `
        -ExpectedRole 'sol'

    $ResolvedEventId = Resolve-TriTierTaskFlowEventId -EventId $EventId
    $Flow = Get-TriTierRunTaskFlow -ProjectPath $ProjectPath -RunId $RunId

    if (Test-TriTierTaskFlowEventApplied -Flow $Flow -EventId $ResolvedEventId) {
        return Save-TriTierRunTaskFlow `
            -ProjectPath $ProjectPath `
            -RunId $RunId `
            -Flow $Flow `
            -Replayed $true
    }

    if ($Flow.stage -ne 'REVIEW') {
        throw "Task review requires REVIEW stage; current stage is '$($Flow.stage)'."
    }

    if ($Flow.reviewOutcome -eq 'FAIL') {
        throw 'A failed task review is blocked until finding integration authorizes repair.'
    }

    if ([string]$Flow.implementationActor -eq $Reviewer) {
        throw 'The implementation actor cannot perform the independent task review.'
    }

    $FromStage = [string]$Flow.stage
    $Flow.previousStage = $FromStage
    $Flow.reviewActor = $Reviewer
    $Flow.reviewOutcome = $Outcome
    $Flow.reviewSummary = $Summary
    $Flow.reviewEvidenceIds = @($EvidenceIds)

    if ($Outcome -eq 'PASS') {
        $Flow.stage = 'CONTINUE'
        $Flow.responsibleParty = 'terra'
        $Flow.mayAdvance = $true
        $Flow.nextAction = 'Terra may advance to the next task or phase gate.'
        $EventType = 'REVIEW_PASSED'
        $ToStage = 'CONTINUE'
    }
    else {
        $Flow.stage = 'REVIEW'
        $Flow.responsibleParty = 'terra'
        $Flow.mayAdvance = $false
        $Flow.nextAction = (
            "Terra must register a blocking finding for task " +
            "$($Flow.currentTask) before implementation may resume."
        )
        $EventType = 'REVIEW_FAILED'
        $ToStage = 'REVIEW'
    }

    $Flow = Add-TriTierTaskFlowTransition `
        -Flow $Flow `
        -EventId $ResolvedEventId `
        -EventType $EventType `
        -FromStage $FromStage `
        -ToStage $ToStage `
        -Actor $Reviewer `
        -Summary $Summary `
        -EvidenceIds $EvidenceIds

    Save-TriTierRunTaskFlow `
        -ProjectPath $ProjectPath `
        -RunId $RunId `
        -Flow $Flow
}

function Start-TriTierRunPlanning {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$RunId,

        [Parameter()]
        [string]$StartedBy = 'terra-manager',

        [Parameter()]
        [string]$EventId = ''
    )

    Assert-TriTierTaskFlowActor `
        -Actor $StartedBy `
        -ExpectedRole 'terra'

    $ResolvedEventId = Resolve-TriTierTaskFlowEventId -EventId $EventId
    $Flow = Get-TriTierRunTaskFlow -ProjectPath $ProjectPath -RunId $RunId

    if (Test-TriTierTaskFlowEventApplied -Flow $Flow -EventId $ResolvedEventId) {
        return Save-TriTierRunTaskFlow `
            -ProjectPath $ProjectPath `
            -RunId $RunId `
            -Flow $Flow `
            -Replayed $true
    }

    if ($Flow.stage -ne 'CONTINUE') {
        throw "Planning can restart only from CONTINUE stage; current stage is '$($Flow.stage)'."
    }

    if (-not [bool]$Flow.mayAdvance) {
        throw 'Task flow cannot advance because independent review has not passed.'
    }

    $CompletedTask = [string]$Flow.currentTask
    $FromStage = [string]$Flow.stage
    $Flow.previousStage = $FromStage
    $Flow.stage = 'PLAN'
    $Flow.responsibleParty = 'terra'
    $Flow.mayAdvance = $false
    $Flow.currentTask = ''
    $Flow.implementationActor = ''
    $Flow.implementationSummary = ''
    $Flow.implementationEvidenceIds = @()
    $Flow.reviewActor = ''
    $Flow.reviewOutcome = 'NOT_STARTED'
    $Flow.reviewSummary = ''
    $Flow.reviewEvidenceIds = @()
    $Flow.activeRepairFindingId = ''
    $Flow.lastRepairFindingId = ''
    $Flow.repairResumeStage = ''
    $Flow.repairActor = ''
    $Flow.repairReviewActor = ''
    $Flow.repairReviewOutcome = 'NOT_STARTED'
    $Flow.adjudicationDecision = ''
    $Flow.nextAction = 'Terra must select and persist the next bounded task.'

    $Flow = Add-TriTierTaskFlowTransition `
        -Flow $Flow `
        -EventId $ResolvedEventId `
        -EventType 'PLANNING_STARTED' `
        -FromStage $FromStage `
        -ToStage 'PLAN' `
        -Actor $StartedBy `
        -Summary "Completed task $CompletedTask and returned to planning."

    Save-TriTierRunTaskFlow `
        -ProjectPath $ProjectPath `
        -RunId $RunId `
        -Flow $Flow
}

Export-ModuleMember -Function @(
    'Complete-TriTierRunImplementation',
    'Get-TriTierRunTaskFlow',
    'Initialize-TriTierRunTaskFlow',
    'Start-TriTierRunPlanning',
    'Start-TriTierRunTask',
    'Submit-TriTierRunTaskReview'
)
