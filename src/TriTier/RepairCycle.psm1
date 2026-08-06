Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$StateModulePath = Join-Path $PSScriptRoot 'State.psm1'
$TaskFlowModulePath = Join-Path $PSScriptRoot 'TaskFlow.psm1'
$FindingsModulePath = Join-Path $PSScriptRoot 'Findings.psm1'

foreach ($ModulePath in @(
    $StateModulePath,
    $TaskFlowModulePath,
    $FindingsModulePath
)) {
    if (-not (Test-Path $ModulePath -PathType Leaf)) {
        throw "Required Tri-Tier module is missing: $ModulePath"
    }
}

Import-Module $StateModulePath
Import-Module $TaskFlowModulePath
Import-Module $FindingsModulePath

function Copy-TriTierRepairObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$InputObject
    )

    $InputObject |
        ConvertTo-Json -Depth 100 |
        ConvertFrom-Json -Depth 100
}

function Assert-TriTierRepairActor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Actor,

        [Parameter(Mandatory)]
        [ValidateSet('terra', 'luna', 'sol')]
        [string]$ExpectedRole
    )

    $Pattern = '^' + [regex]::Escape($ExpectedRole) + '([_-].*)?$'

    if ($Actor.Trim() -notmatch $Pattern) {
        throw (
            "Repair-cycle transition requires a $ExpectedRole actor; " +
            "received '$Actor'."
        )
    }
}

function Assert-TriTierRepairRunMutable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$State
    )

    if ([string]$State.status -ne 'ACTIVE') {
        throw (
            "Repair-cycle mutation requires ACTIVE run status; current " +
            "status is '$($State.status)'."
        )
    }
}

function Test-TriTierRepairEventApplied {
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

function Add-TriTierRepairTransition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Flow,

        [Parameter(Mandatory)]
        [string]$EventId,

        [Parameter(Mandatory)]
        [string]$EventType,

        [Parameter(Mandatory)]
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
        actor = $Actor.Trim()
        summary = $Summary.Trim()
        evidenceIds = @($EvidenceIds)
        occurredUtc = $OccurredUtc
    }

    $Flow.transitionHistory = @($Flow.transitionHistory) + $Transition
    $Flow.updatedUtc = $OccurredUtc

    $Flow
}

function Get-TriTierRepairState {
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

    $State
}

function Resolve-TriTierRepairFinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Findings,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FindingId
    )

    $Matches = @(
        $Findings |
            Where-Object {
                [string]$_.findingId -eq $FindingId
            }
    )

    if ($Matches.Count -ne 1) {
        throw (
            "Expected one repair finding '$FindingId'; found " +
            "$($Matches.Count)."
        )
    }

    $Matches[0]
}

function New-TriTierRepairCycleResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$State,

        [Parameter()]
        [bool]$Replayed = $false
    )

    $Finding = $null
    $FindingId = [string]$State.taskFlow.activeRepairFindingId

    if ([string]::IsNullOrWhiteSpace($FindingId)) {
        $FindingId = [string]$State.taskFlow.lastRepairFindingId
    }

    if (-not [string]::IsNullOrWhiteSpace($FindingId)) {
        $Matches = @(
            $State.findings |
                Where-Object {
                    [string]$_.findingId -eq $FindingId
                }
        )

        if ($Matches.Count -eq 1) {
            $Finding = $Matches[0]
        }
    }

    [PSCustomObject][ordered]@{
        flow = $State.taskFlow
        finding = $Finding
        gate = $State.findingGate
        state = $State
        replayed = $Replayed
    }
}

function Save-TriTierRepairCycle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$RunId,

        [Parameter(Mandatory)]
        [object[]]$Findings,

        [Parameter(Mandatory)]
        [object]$Flow,

        [Parameter()]
        [string]$RunStatus = ''
    )

    $Gate = Test-TriTierFindingGate -Findings $Findings

    $Arguments = @{
        ProjectPath = $ProjectPath
        RunId = $RunId
        Findings = $Findings
        FindingGate = $Gate
        TaskFlowState = $Flow
    }

    if (-not [string]::IsNullOrWhiteSpace($RunStatus)) {
        $Arguments.RunStatus = $RunStatus
    }

    $State = Set-TriTierRunIntegratedState @Arguments

    New-TriTierRepairCycleResult -State $State
}

function Get-TriTierRunRepairCycle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$RunId
    )

    $State = Get-TriTierRepairState `
        -ProjectPath $ProjectPath `
        -RunId $RunId

    New-TriTierRepairCycleResult -State $State
}

function Start-TriTierRunRepairCycle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$RunId,

        [Parameter(Mandatory)]
        [ValidateSet('MEDIUM', 'HIGH', 'CRITICAL')]
        [string]$Severity,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Title,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Description,

        [Parameter()]
        [string]$AuthorizedBy = 'terra-manager',

        [Parameter()]
        [string[]]$EvidenceIds = @(),

        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$')]
        [string]$EventId
    )

    Assert-TriTierRepairActor `
        -Actor $AuthorizedBy `
        -ExpectedRole 'terra'

    $State = Get-TriTierRepairState `
        -ProjectPath $ProjectPath `
        -RunId $RunId

    if (
        Test-TriTierRepairEventApplied `
            -Flow $State.taskFlow `
            -EventId $EventId
    ) {
        return New-TriTierRepairCycleResult `
            -State $State `
            -Replayed $true
    }

    Assert-TriTierRepairRunMutable -State $State

    $Flow = Copy-TriTierRepairObject -InputObject $State.taskFlow
    $Findings = @(
        Copy-TriTierRepairObject -InputObject @($State.findings)
    )

    if ($Flow.stage -ne 'REVIEW') {
        throw (
            "Repair authorization requires REVIEW stage; current stage is " +
            "'$($Flow.stage)'."
        )
    }

    if ($Flow.reviewOutcome -ne 'FAIL') {
        throw (
            'Repair authorization requires a failed independent task review.'
        )
    }

    if (-not [string]::IsNullOrWhiteSpace(
        [string]$Flow.activeRepairFindingId
    )) {
        throw (
            'A repair cycle is already active for this task review failure.'
        )
    }

    if ([string]::IsNullOrWhiteSpace([string]$Flow.currentTask)) {
        throw 'Repair authorization requires a current task.'
    }

    if ([string]::IsNullOrWhiteSpace([string]$Flow.reviewActor)) {
        throw 'Repair authorization requires the failed task reviewer.'
    }

    Assert-TriTierRepairActor `
        -Actor ([string]$Flow.reviewActor) `
        -ExpectedRole 'sol'

    $CombinedEvidenceIds = @(
        @($Flow.reviewEvidenceIds) + @($EvidenceIds) |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace([string]$_)
            } |
            Select-Object -Unique
    )

    $Finding = New-TriTierFinding `
        -Severity $Severity `
        -Title $Title `
        -Description $Description `
        -Reviewer ([string]$Flow.reviewActor) `
        -TaskId ([string]$Flow.currentTask) `
        -PhaseId ([string]$State.currentPhase) `
        -EvidenceIds $CombinedEvidenceIds

    $Findings = @($Findings) + @($Finding)
    $Gate = Test-TriTierFindingGate -Findings $Findings
    $FromStage = [string]$Flow.stage

    $Flow.previousStage = $FromStage
    $Flow.stage = 'REPAIR'
    $Flow.responsibleParty = 'luna'
    $Flow.mayAdvance = $false
    $Flow.activeRepairFindingId = $Finding.findingId
    $Flow.repairResumeStage = 'REVIEW'
    $Flow.repairActor = ''
    $Flow.repairReviewActor = ''
    $Flow.repairReviewOutcome = 'NOT_STARTED'
    $Flow.adjudicationDecision = ''
    $Flow.nextAction = [string]$Gate.nextAction

    $Flow = Add-TriTierRepairTransition `
        -Flow $Flow `
        -EventId $EventId `
        -EventType 'REPAIR_AUTHORIZED' `
        -FromStage $FromStage `
        -ToStage 'REPAIR' `
        -Actor $AuthorizedBy `
        -Summary (
            "Authorized repair for failed task review using finding " +
            "$($Finding.findingId)."
        ) `
        -EvidenceIds $CombinedEvidenceIds

    Save-TriTierRepairCycle `
        -ProjectPath $ProjectPath `
        -RunId $RunId `
        -Findings $Findings `
        -Flow $Flow
}

function Complete-TriTierRunRepair {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$RunId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RepairedBy,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RepairSummary,

        [Parameter()]
        [string[]]$EvidenceIds = @(),

        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$')]
        [string]$EventId
    )

    Assert-TriTierRepairActor `
        -Actor $RepairedBy `
        -ExpectedRole 'luna'

    $State = Get-TriTierRepairState `
        -ProjectPath $ProjectPath `
        -RunId $RunId

    if (
        Test-TriTierRepairEventApplied `
            -Flow $State.taskFlow `
            -EventId $EventId
    ) {
        return New-TriTierRepairCycleResult `
            -State $State `
            -Replayed $true
    }

    Assert-TriTierRepairRunMutable -State $State

    $Flow = Copy-TriTierRepairObject -InputObject $State.taskFlow
    $Findings = @(
        Copy-TriTierRepairObject -InputObject @($State.findings)
    )

    if ($Flow.stage -ne 'REPAIR') {
        throw (
            "Repair completion requires REPAIR stage; current stage is " +
            "'$($Flow.stage)'."
        )
    }

    $Finding = Resolve-TriTierRepairFinding `
        -Findings $Findings `
        -FindingId ([string]$Flow.activeRepairFindingId)

    $Finding = Repair-TriTierFinding `
        -Finding $Finding `
        -RepairedBy $RepairedBy `
        -RepairSummary $RepairSummary `
        -EvidenceIds $EvidenceIds

    if ($Finding.status -ne 'REPAIRED_PENDING_REVIEW') {
        throw (
            'Blocking task repair must enter REPAIRED_PENDING_REVIEW.'
        )
    }

    $Gate = Test-TriTierFindingGate -Findings $Findings
    $FromStage = [string]$Flow.stage

    $Flow.previousStage = $FromStage
    $Flow.stage = 'FRESH_REVIEW'
    $Flow.responsibleParty = 'sol'
    $Flow.mayAdvance = $false
    $Flow.repairActor = $RepairedBy.Trim()
    $Flow.repairReviewActor = ''
    $Flow.repairReviewOutcome = 'PENDING'
    $Flow.adjudicationDecision = ''
    $Flow.nextAction = [string]$Gate.nextAction

    $Flow = Add-TriTierRepairTransition `
        -Flow $Flow `
        -EventId $EventId `
        -EventType 'REPAIR_COMPLETED' `
        -FromStage $FromStage `
        -ToStage 'FRESH_REVIEW' `
        -Actor $RepairedBy `
        -Summary $RepairSummary `
        -EvidenceIds $EvidenceIds

    Save-TriTierRepairCycle `
        -ProjectPath $ProjectPath `
        -RunId $RunId `
        -Findings $Findings `
        -Flow $Flow
}

function Submit-TriTierRunRepairReview {
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

        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$')]
        [string]$EventId
    )

    Assert-TriTierRepairActor `
        -Actor $Reviewer `
        -ExpectedRole 'sol'

    $State = Get-TriTierRepairState `
        -ProjectPath $ProjectPath `
        -RunId $RunId

    if (
        Test-TriTierRepairEventApplied `
            -Flow $State.taskFlow `
            -EventId $EventId
    ) {
        return New-TriTierRepairCycleResult `
            -State $State `
            -Replayed $true
    }

    Assert-TriTierRepairRunMutable -State $State

    $Flow = Copy-TriTierRepairObject -InputObject $State.taskFlow
    $Findings = @(
        Copy-TriTierRepairObject -InputObject @($State.findings)
    )

    if ($Flow.stage -ne 'FRESH_REVIEW') {
        throw (
            "Repair review requires FRESH_REVIEW stage; current stage is " +
            "'$($Flow.stage)'."
        )
    }

    $Finding = Resolve-TriTierRepairFinding `
        -Findings $Findings `
        -FindingId ([string]$Flow.activeRepairFindingId)

    $Finding = Submit-TriTierFindingFreshReview `
        -Finding $Finding `
        -Reviewer $Reviewer `
        -Outcome $Outcome `
        -Summary $Summary `
        -EvidenceIds $EvidenceIds

    $Gate = Test-TriTierFindingGate -Findings $Findings
    $FromStage = [string]$Flow.stage

    $Flow.previousStage = $FromStage
    $Flow.mayAdvance = $false
    $Flow.repairReviewActor = $Reviewer.Trim()
    $Flow.adjudicationDecision = ''

    if ($Outcome -eq 'PASS') {
        $Flow.stage = 'REVIEW'
        $Flow.responsibleParty = 'sol'
        $Flow.activeRepairFindingId = ''
        $Flow.lastRepairFindingId = $Finding.findingId
        $Flow.repairReviewOutcome = 'PASSED'
        $Flow.reviewActor = ''
        $Flow.reviewOutcome = 'PENDING'
        $Flow.reviewSummary = ''
        $Flow.reviewEvidenceIds = @()
        $Flow.nextAction = (
            "Sol must perform the final independent task review for " +
            "$($Flow.currentTask) after the accepted repair."
        )

        $EventType = 'REPAIR_REVIEW_PASSED'
        $ToStage = 'REVIEW'
    }

    if ($Outcome -eq 'FAIL') {
        $Flow.stage = 'ADJUDICATE'
        $Flow.responsibleParty = 'sol'
        $Flow.repairReviewOutcome = 'FAILED'
        $Flow.nextAction = (
            "Sol must adjudicate failed repair cycle " +
            "$($Finding.reviewCycle) for finding " +
            "$($Finding.findingId)."
        )

        $EventType = 'REPAIR_REVIEW_FAILED'
        $ToStage = 'ADJUDICATE'
    }

    $Flow = Add-TriTierRepairTransition `
        -Flow $Flow `
        -EventId $EventId `
        -EventType $EventType `
        -FromStage $FromStage `
        -ToStage $ToStage `
        -Actor $Reviewer `
        -Summary $Summary `
        -EvidenceIds $EvidenceIds

    Save-TriTierRepairCycle `
        -ProjectPath $ProjectPath `
        -RunId $RunId `
        -Findings $Findings `
        -Flow $Flow
}

function Submit-TriTierRunAdjudication {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$RunId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Adjudicator,

        [Parameter(Mandatory)]
        [ValidateSet(
            'REPAIR_AGAIN',
            'OWNER_DECISION',
            'ABORT_FOR_SAFETY',
            'FAIL_VALIDATION'
        )]
        [string]$Decision,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Summary,

        [Parameter()]
        [string[]]$EvidenceIds = @(),

        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$')]
        [string]$EventId
    )

    Assert-TriTierRepairActor `
        -Actor $Adjudicator `
        -ExpectedRole 'sol'

    $State = Get-TriTierRepairState `
        -ProjectPath $ProjectPath `
        -RunId $RunId

    if (
        Test-TriTierRepairEventApplied `
            -Flow $State.taskFlow `
            -EventId $EventId
    ) {
        return New-TriTierRepairCycleResult `
            -State $State `
            -Replayed $true
    }

    Assert-TriTierRepairRunMutable -State $State

    $Flow = Copy-TriTierRepairObject -InputObject $State.taskFlow
    $Findings = @(
        Copy-TriTierRepairObject -InputObject @($State.findings)
    )

    if ($Flow.stage -ne 'ADJUDICATE') {
        throw (
            "Adjudication requires ADJUDICATE stage; current stage is " +
            "'$($Flow.stage)'."
        )
    }

    if ($Flow.repairReviewOutcome -ne 'FAILED') {
        throw 'Adjudication requires a failed fresh repair review.'
    }

    $Finding = Resolve-TriTierRepairFinding `
        -Findings $Findings `
        -FindingId ([string]$Flow.activeRepairFindingId)

    if ($Finding.status -ne 'OPEN') {
        throw 'Adjudication requires the linked finding to be OPEN.'
    }

    $Gate = Test-TriTierFindingGate -Findings $Findings
    $FromStage = [string]$Flow.stage
    $RunStatus = 'ACTIVE'

    $Flow.previousStage = $FromStage
    $Flow.mayAdvance = $false
    $Flow.adjudicationDecision = $Decision

    switch ($Decision) {
        'REPAIR_AGAIN' {
            $Flow.stage = 'REPAIR'
            $Flow.responsibleParty = 'luna'
            $Flow.repairActor = ''
            $Flow.repairReviewActor = ''
            $Flow.repairReviewOutcome = 'NOT_STARTED'
            $Flow.nextAction = [string]$Gate.nextAction
        }

        'OWNER_DECISION' {
            $Flow.stage = 'ADJUDICATE'
            $Flow.responsibleParty = 'owner'
            $Flow.nextAction = (
                "Owner decision required for finding " +
                "$($Finding.findingId) before the run can continue."
            )
            $RunStatus = 'BLOCKED_OWNER_DECISION'
        }

        'ABORT_FOR_SAFETY' {
            $Flow.stage = 'ADJUDICATE'
            $Flow.responsibleParty = 'sol'
            $Flow.nextAction = (
                'Run aborted for safety. No further automatic action is allowed.'
            )
            $RunStatus = 'ABORTED_FOR_SAFETY'
        }

        'FAIL_VALIDATION' {
            $Flow.stage = 'ADJUDICATE'
            $Flow.responsibleParty = 'sol'
            $Flow.nextAction = (
                'Run failed validation. A new authorized run is required.'
            )
            $RunStatus = 'FAILED_VALIDATION'
        }
    }

    $Flow = Add-TriTierRepairTransition `
        -Flow $Flow `
        -EventId $EventId `
        -EventType ("ADJUDICATION_" + $Decision) `
        -FromStage $FromStage `
        -ToStage ([string]$Flow.stage) `
        -Actor $Adjudicator `
        -Summary $Summary `
        -EvidenceIds $EvidenceIds

    Save-TriTierRepairCycle `
        -ProjectPath $ProjectPath `
        -RunId $RunId `
        -Findings $Findings `
        -Flow $Flow `
        -RunStatus $RunStatus
}

Export-ModuleMember -Function @(
    'Complete-TriTierRunRepair',
    'Get-TriTierRunRepairCycle',
    'Start-TriTierRunRepairCycle',
    'Submit-TriTierRunAdjudication',
    'Submit-TriTierRunRepairReview'
)
