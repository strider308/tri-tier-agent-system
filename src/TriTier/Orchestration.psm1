Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$StateModulePath = Join-Path $PSScriptRoot 'State.psm1'
$FindingsModulePath = Join-Path $PSScriptRoot 'Findings.psm1'

foreach ($ModulePath in @(
    $StateModulePath,
    $FindingsModulePath
)) {
    if (-not (Test-Path $ModulePath -PathType Leaf)) {
        throw "Required Tri-Tier module is missing: $ModulePath"
    }
}

Import-Module $StateModulePath
Import-Module $FindingsModulePath

function Get-TriTierPriorityActiveFinding {
    [CmdletBinding()]
    param(
        [Parameter()]
        [object[]]$Findings = @()
    )

    $ActiveFindings = @(
        $Findings |
            Where-Object {
                $_.status -in @(
                    'OPEN',
                    'REPAIRED_PENDING_REVIEW'
                )
            }
    )

    foreach ($Finding in $ActiveFindings) {
        [void](
            Get-TriTierFindingSeverityInfo `
                -Severity ([string]$Finding.severity)
        )
    }

    @(
        $ActiveFindings |
            Sort-Object @(
                @{
                    Expression = {
                        (
                            Get-TriTierFindingSeverityInfo `
                                -Severity ([string]$_.severity)
                        ).rank
                    }
                    Descending = $true
                },
                @{
                    Expression = {
                        if (
                            [string]$_.status -eq
                            'REPAIRED_PENDING_REVIEW'
                        ) {
                            0
                        }
                        else {
                            1
                        }
                    }
                    Descending = $false
                },
                @{
                    Expression = {
                        [string]$_.createdUtc
                    }
                    Descending = $false
                }
            )
    ) | Select-Object -First 1
}

function New-TriTierOrchestrationDecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RunId,

        [Parameter(Mandatory)]
        [string]$RunStatus,

        [Parameter(Mandatory)]
        [ValidateSet(
            'PLAN',
            'IMPLEMENT',
            'REVIEW',
            'REPAIR',
            'FRESH_REVIEW',
            'ADJUDICATE',
            'CONTINUE',
            'PHASE_REVIEW',
            'OWNER_DECISION',
            'WAIT_EXTERNAL',
            'STOP'
        )]
        [string]$Stage,

        [Parameter(Mandatory)]
        [ValidateSet(
            'terra',
            'luna',
            'sol',
            'owner',
            'none'
        )]
        [string]$ResponsibleParty,

        [Parameter(Mandatory)]
        [ValidateSet('NONE', 'TASK', 'PHASE', 'RUN')]
        [string]$BlockedScope,

        [Parameter(Mandatory)]
        [bool]$CanContinue,

        [Parameter(Mandatory)]
        [bool]$OwnerRequired,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Reason,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$NextAction,

        [Parameter()]
        [string]$FindingId = '',

        [Parameter()]
        [string]$TaskStage = '',

        [Parameter()]
        [string]$PhaseId = '',

        [Parameter()]
        [string]$PhaseStatus = ''
    )

    [PSCustomObject][ordered]@{
        schemaVersion = 1
        runId = $RunId
        runStatus = $RunStatus
        stage = $Stage
        responsibleParty = $ResponsibleParty
        blockedScope = $BlockedScope
        canContinue = $CanContinue
        ownerRequired = $OwnerRequired
        findingId = $FindingId
        taskStage = $TaskStage
        phaseId = $PhaseId
        phaseStatus = $PhaseStatus
        reason = $Reason.Trim()
        nextAction = $NextAction.Trim()
        decidedUtc = [DateTime]::UtcNow.ToString('o')
    }
}

function Get-TriTierOrchestrationDecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$RunState
    )

    $RunId = [string]$RunState.runId
    $RunStatus = [string]$RunState.status
    $DefaultNextAction = [string]$RunState.nextAction

    if ([string]::IsNullOrWhiteSpace($DefaultNextAction)) {
        $DefaultNextAction = 'Terra must inspect the durable run state.'
    }

    $Findings = @()

    if ($null -ne $RunState.PSObject.Properties['findings']) {
        $Findings = @($RunState.findings)
    }

    $Gate = $null

    if (
        $null -ne $RunState.PSObject.Properties['findingGate'] -and
        $null -ne $RunState.findingGate
    ) {
        $Gate = $RunState.findingGate
    }
    else {
        $Gate = Test-TriTierFindingGate -Findings $Findings
    }

    $BlockedScope = 'NONE'

    if ([bool]$Gate.taskBlocked) {
        $BlockedScope = 'TASK'
    }

    if ([bool]$Gate.phaseBlocked) {
        $BlockedScope = 'PHASE'
    }

    if ([bool]$Gate.runBlocked) {
        $BlockedScope = 'RUN'
    }

    $PriorityFinding = Get-TriTierPriorityActiveFinding `
        -Findings $Findings

    $FindingId = ''

    if ($null -ne $PriorityFinding) {
        $FindingId = [string]$PriorityFinding.findingId
    }

    $TaskFlow = $null
    $TaskStage = ''

    if (
        $null -ne $RunState.PSObject.Properties['taskFlow'] -and
        $null -ne $RunState.taskFlow
    ) {
        $TaskFlow = $RunState.taskFlow
        $TaskStage = [string]$TaskFlow.stage
    }

    $Phase = $null
    $PhaseId = ''
    $PhaseStatus = ''

    if (
        $null -ne $RunState.PSObject.Properties['phaseGate'] -and
        $null -ne $RunState.phaseGate
    ) {
        $Phase = $RunState.phaseGate
        $PhaseId = [string]$Phase.phaseId
        $PhaseStatus = [string]$Phase.status
    }

    if ($RunStatus -in @(
        'COMPLETE',
        'COMPLETE_WITH_DEFERMENTS'
    )) {
        return New-TriTierOrchestrationDecision `
            -RunId $RunId `
            -RunStatus $RunStatus `
            -Stage 'STOP' `
            -ResponsibleParty 'none' `
            -BlockedScope 'RUN' `
            -CanContinue $false `
            -OwnerRequired $false `
            -Reason 'The run is complete.' `
            -NextAction 'No further action is permitted for this completed run.' `
            -FindingId $FindingId `
            -TaskStage $TaskStage `
            -PhaseId $PhaseId `
            -PhaseStatus $PhaseStatus
    }

    if ($RunStatus -in @(
        'FAILED_VALIDATION',
        'ABORTED_FOR_SAFETY'
    )) {
        return New-TriTierOrchestrationDecision `
            -RunId $RunId `
            -RunStatus $RunStatus `
            -Stage 'STOP' `
            -ResponsibleParty 'sol' `
            -BlockedScope 'RUN' `
            -CanContinue $false `
            -OwnerRequired $false `
            -Reason "The run is terminal with status $RunStatus." `
            -NextAction 'Sol must determine whether a separately authorized new run is appropriate.' `
            -FindingId $FindingId `
            -TaskStage $TaskStage `
            -PhaseId $PhaseId `
            -PhaseStatus $PhaseStatus
    }

    if ($RunStatus -in @(
        'PAUSED_BY_OWNER',
        'BLOCKED_OWNER_DECISION'
    )) {
        return New-TriTierOrchestrationDecision `
            -RunId $RunId `
            -RunStatus $RunStatus `
            -Stage 'OWNER_DECISION' `
            -ResponsibleParty 'owner' `
            -BlockedScope 'RUN' `
            -CanContinue $false `
            -OwnerRequired $true `
            -Reason 'The durable run status requires an owner decision.' `
            -NextAction $DefaultNextAction `
            -FindingId $FindingId `
            -TaskStage $TaskStage `
            -PhaseId $PhaseId `
            -PhaseStatus $PhaseStatus
    }

    if ($RunStatus -eq 'BLOCKED_EXTERNAL_DEPENDENCY') {
        return New-TriTierOrchestrationDecision `
            -RunId $RunId `
            -RunStatus $RunStatus `
            -Stage 'WAIT_EXTERNAL' `
            -ResponsibleParty 'terra' `
            -BlockedScope 'RUN' `
            -CanContinue $false `
            -OwnerRequired $false `
            -Reason 'An external dependency blocks continuation.' `
            -NextAction $DefaultNextAction `
            -FindingId $FindingId `
            -TaskStage $TaskStage `
            -PhaseId $PhaseId `
            -PhaseStatus $PhaseStatus
    }

    if ($null -ne $Phase) {
        if ($PhaseStatus -eq 'OWNER_DECISION_REQUIRED') {
            return New-TriTierOrchestrationDecision `
                -RunId $RunId `
                -RunStatus $RunStatus `
                -Stage 'OWNER_DECISION' `
                -ResponsibleParty 'owner' `
                -BlockedScope 'PHASE' `
                -CanContinue $false `
                -OwnerRequired $true `
                -Reason "Phase $PhaseId requires owner approval." `
                -NextAction ([string]$Phase.nextAction) `
                -FindingId $FindingId `
                -TaskStage $TaskStage `
                -PhaseId $PhaseId `
                -PhaseStatus $PhaseStatus
        }

        if ($PhaseStatus -eq 'READY_FOR_REVIEW') {
            return New-TriTierOrchestrationDecision `
                -RunId $RunId `
                -RunStatus $RunStatus `
                -Stage 'PHASE_REVIEW' `
                -ResponsibleParty 'sol' `
                -BlockedScope $BlockedScope `
                -CanContinue $true `
                -OwnerRequired $false `
                -Reason "Phase $PhaseId is ready for independent review." `
                -NextAction ([string]$Phase.nextAction) `
                -FindingId $FindingId `
                -TaskStage $TaskStage `
                -PhaseId $PhaseId `
                -PhaseStatus $PhaseStatus
        }

        if ($PhaseStatus -eq 'ACCEPTED') {
            return New-TriTierOrchestrationDecision `
                -RunId $RunId `
                -RunStatus $RunStatus `
                -Stage 'CONTINUE' `
                -ResponsibleParty 'terra' `
                -BlockedScope $BlockedScope `
                -CanContinue $true `
                -OwnerRequired $false `
                -Reason "Phase $PhaseId was accepted." `
                -NextAction ([string]$Phase.nextAction) `
                -FindingId $FindingId `
                -TaskStage $TaskStage `
                -PhaseId $PhaseId `
                -PhaseStatus $PhaseStatus
        }

        if ($PhaseStatus -eq 'REJECTED') {
            return New-TriTierOrchestrationDecision `
                -RunId $RunId `
                -RunStatus $RunStatus `
                -Stage 'PLAN' `
                -ResponsibleParty 'terra' `
                -BlockedScope $BlockedScope `
                -CanContinue $true `
                -OwnerRequired $false `
                -Reason "Phase $PhaseId was rejected and requires bounded remediation." `
                -NextAction ([string]$Phase.nextAction) `
                -FindingId $FindingId `
                -TaskStage $TaskStage `
                -PhaseId $PhaseId `
                -PhaseStatus $PhaseStatus
        }

        if ($PhaseStatus -in @(
            'BLOCKED_BY_FINDINGS',
            'BLOCKED_BY_EVIDENCE'
        )) {
            $PhaseBlockedScope = $BlockedScope

            if ($PhaseBlockedScope -eq 'NONE') {
                $PhaseBlockedScope = 'PHASE'
            }

            return New-TriTierOrchestrationDecision `
                -RunId $RunId `
                -RunStatus $RunStatus `
                -Stage 'CONTINUE' `
                -ResponsibleParty 'terra' `
                -BlockedScope $PhaseBlockedScope `
                -CanContinue $false `
                -OwnerRequired $false `
                -Reason "Phase $PhaseId is blocked with status $PhaseStatus." `
                -NextAction ([string]$Phase.nextAction) `
                -FindingId $FindingId `
                -TaskStage $TaskStage `
                -PhaseId $PhaseId `
                -PhaseStatus $PhaseStatus
        }
    }

    if ($null -eq $TaskFlow) {
        return New-TriTierOrchestrationDecision `
            -RunId $RunId `
            -RunStatus $RunStatus `
            -Stage 'PLAN' `
            -ResponsibleParty 'terra' `
            -BlockedScope $BlockedScope `
            -CanContinue ($BlockedScope -eq 'NONE') `
            -OwnerRequired $false `
            -Reason 'Task flow has not been initialized.' `
            -NextAction $DefaultNextAction `
            -FindingId $FindingId `
            -TaskStage '' `
            -PhaseId $PhaseId `
            -PhaseStatus $PhaseStatus
    }

    $RepairStages = @(
        'REPAIR',
        'FRESH_REVIEW',
        'ADJUDICATE'
    )

    if (
        $BlockedScope -ne 'NONE' -and
        $TaskStage -notin $RepairStages
    ) {
        return New-TriTierOrchestrationDecision `
            -RunId $RunId `
            -RunStatus $RunStatus `
            -Stage $TaskStage `
            -ResponsibleParty 'terra' `
            -BlockedScope $BlockedScope `
            -CanContinue $false `
            -OwnerRequired $false `
            -Reason "An unresolved finding blocks the $BlockedScope scope." `
            -NextAction ([string]$Gate.nextAction) `
            -FindingId $FindingId `
            -TaskStage $TaskStage `
            -PhaseId $PhaseId `
            -PhaseStatus $PhaseStatus
    }

    $ResponsibleParty = [string]$TaskFlow.responsibleParty
    $CanContinue = $true
    $Reason = "Task flow is in $TaskStage stage."

    switch ($TaskStage) {
        'PLAN' {
            $ResponsibleParty = 'terra'
        }

        'IMPLEMENT' {
            $ResponsibleParty = 'luna'
        }

        'REVIEW' {
            if ([string]$TaskFlow.reviewOutcome -eq 'FAIL') {
                $ResponsibleParty = 'terra'
                $Reason = 'A failed task review requires Terra to authorize repair.'
            }
            else {
                $ResponsibleParty = 'sol'
            }
        }

        'REPAIR' {
            $ResponsibleParty = 'luna'
        }

        'FRESH_REVIEW' {
            $ResponsibleParty = 'sol'
        }

        'ADJUDICATE' {
            $ResponsibleParty = 'sol'
        }

        'CONTINUE' {
            $ResponsibleParty = 'terra'
            $CanContinue = [bool]$TaskFlow.mayAdvance
        }

        default {
            throw "Unsupported task-flow stage for orchestration: $TaskStage"
        }
    }

    New-TriTierOrchestrationDecision `
        -RunId $RunId `
        -RunStatus $RunStatus `
        -Stage $TaskStage `
        -ResponsibleParty $ResponsibleParty `
        -BlockedScope $BlockedScope `
        -CanContinue $CanContinue `
        -OwnerRequired $false `
        -Reason $Reason `
        -NextAction $DefaultNextAction `
        -FindingId $FindingId `
        -TaskStage $TaskStage `
        -PhaseId $PhaseId `
        -PhaseStatus $PhaseStatus
}

function Get-TriTierRunOrchestrationDecision {
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

    Get-TriTierOrchestrationDecision -RunState $State
}

Export-ModuleMember -Function @(
    'Get-TriTierOrchestrationDecision',
    'Get-TriTierRunOrchestrationDecision'
)
