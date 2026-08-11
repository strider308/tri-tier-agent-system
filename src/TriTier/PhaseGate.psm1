Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$StateModulePath = Join-Path $PSScriptRoot 'State.psm1'
$FindingsModulePath = Join-Path $PSScriptRoot 'Findings.psm1'
$EvidenceModulePath = Join-Path $PSScriptRoot 'Evidence.psm1'
$OrchestrationModulePath = Join-Path $PSScriptRoot 'Orchestration.psm1'

foreach ($ModulePath in @(
    $StateModulePath,
    $FindingsModulePath,
    $EvidenceModulePath,
    $OrchestrationModulePath
)) {
    if (-not (Test-Path $ModulePath -PathType Leaf)) {
        throw "Required Tri-Tier module is missing: $ModulePath"
    }
}

Import-Module $StateModulePath
Import-Module $FindingsModulePath
$EvidenceModule = Import-Module $EvidenceModulePath -PassThru
Import-Module $OrchestrationModulePath

function Copy-TriTierPhaseObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$InputObject
    )

    $InputObject |
        ConvertTo-Json -Depth 100 |
        ConvertFrom-Json -Depth 100
}

function Assert-TriTierPhaseActor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Actor,

        [Parameter(Mandatory)]
        [ValidateSet('terra', 'sol')]
        [string]$ExpectedRole
    )

    $Pattern = '^' + [regex]::Escape($ExpectedRole) + '([_-].*)?$'

    if ($Actor.Trim() -notmatch $Pattern) {
        throw (
            "Phase transition requires a $ExpectedRole actor; " +
            "received '$Actor'."
        )
    }
}

function Test-TriTierPhaseEventApplied {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Phase,

        [Parameter(Mandatory)]
        [string]$EventId
    )

    @(
        $Phase.history |
            Where-Object {
                [string]$_.eventId -eq $EventId
            }
    ).Count -gt 0
}

function Add-TriTierPhaseTransition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Phase,

        [Parameter(Mandatory)]
        [string]$EventId,

        [Parameter(Mandatory)]
        [string]$EventType,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$FromStatus,

        [Parameter(Mandatory)]
        [string]$ToStatus,

        [Parameter(Mandatory)]
        [string]$Actor,

        [Parameter(Mandatory)]
        [string]$Summary,

        [Parameter()]
        [string[]]$EvidenceIds = @()
    )

    $Phase.revision = [int]$Phase.revision + 1
    $OccurredUtc = [DateTime]::UtcNow.ToString('o')

    $Transition = [PSCustomObject][ordered]@{
        sequence = $Phase.revision
        eventId = $EventId
        eventType = $EventType
        fromStatus = $FromStatus
        toStatus = $ToStatus
        actor = $Actor.Trim()
        summary = $Summary.Trim()
        evidenceIds = @($EvidenceIds)
        occurredUtc = $OccurredUtc
    }

    $Phase.history = @($Phase.history) + $Transition
    $Phase.updatedUtc = $OccurredUtc

    $Phase
}

function ConvertFrom-TriTierPhaseEvidenceResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Result
    )

    if ($Result -is [bool]) {
        return [bool]$Result
    }

    if ($Result -is [string]) {
        if (
            $Result -match
            '^(?i:true|pass|passed|sufficient|accepted|allowed|valid)$'
        ) {
            return $true
        }

        if (
            $Result -match
            '^(?i:false|fail|failed|insufficient|rejected|blocked|invalid)$'
        ) {
            return $false
        }
    }

    if ($null -ne $Result) {
        foreach ($PropertyName in @(
            'passed',
            'sufficient',
            'isSufficient',
            'satisfied',
            'isSatisfied',
            'meetsRequirement',
            'meetsMinimum',
            'meetsEvidenceRequirement',
            'evidenceSatisfied',
            'accepted',
            'allowed',
            'valid',
            'isValid'
        )) {
            if ($null -ne $Result.PSObject.Properties[$PropertyName]) {
                return [bool]$Result.$PropertyName
            }
        }
    }

    throw 'Evidence command returned an unsupported result shape.'
}

function Get-TriTierPhaseEvidenceParameterName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.CommandInfo]$Command,

        [Parameter(Mandatory)]
        [ValidateSet('Risk', 'Evidence', 'Independent')]
        [string]$Kind
    )

    $ExactCandidates = switch ($Kind) {
        'Risk' {
            @(
                'RiskClass',
                'Risk',
                'RiskLevel'
            )
        }

        'Evidence' {
            @(
                'EvidenceLevel',
                'ObservedEvidenceLevel',
                'ObservedLevel',
                'ProvidedEvidenceLevel',
                'ActualEvidenceLevel',
                'Evidence',
                'Level'
            )
        }

        'Independent' {
            @(
                'IndependentEvidence',
                'Independent',
                'IsIndependent',
                'IndependentReview',
                'IndependentReviewer'
            )
        }
    }

    foreach ($Candidate in $ExactCandidates) {
        if ($Command.Parameters.ContainsKey($Candidate)) {
            return $Candidate
        }
    }

    $Matches = @(
        $Command.Parameters.Keys |
            Where-Object {
                if ($Kind -eq 'Risk') {
                    return (
                        $_ -match 'Risk' -and
                        $_ -notmatch 'Evidence'
                    )
                }

                if ($Kind -eq 'Evidence') {
                    return (
                        $_ -match 'Evidence|Level' -and
                        $_ -notmatch 'Independent|Risk'
                    )
                }

                $_ -match 'Independent'
            }
    )

    if ($Matches.Count -eq 1) {
        return [string]$Matches[0]
    }

    ''
}

function New-TriTierPhaseEvidenceArguments {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.CommandInfo]$Command,

        [Parameter(Mandatory)]
        [string]$RiskClass,

        [Parameter(Mandatory)]
        [string]$EvidenceLevel,

        [Parameter(Mandatory)]
        [bool]$IndependentEvidence
    )

    $RiskParameter = Get-TriTierPhaseEvidenceParameterName `
        -Command $Command `
        -Kind 'Risk'

    $EvidenceParameter = Get-TriTierPhaseEvidenceParameterName `
        -Command $Command `
        -Kind 'Evidence'

    $IndependentParameter = Get-TriTierPhaseEvidenceParameterName `
        -Command $Command `
        -Kind 'Independent'

    if (
        [string]::IsNullOrWhiteSpace($RiskParameter) -or
        [string]::IsNullOrWhiteSpace($EvidenceParameter)
    ) {
        return $null
    }

    $Arguments = @{}
    $Arguments[$RiskParameter] = $RiskClass
    $Arguments[$EvidenceParameter] = $EvidenceLevel

    if (-not [string]::IsNullOrWhiteSpace($IndependentParameter)) {
        $ParameterType = $Command.Parameters[
            $IndependentParameter
        ].ParameterType

        if (
            $ParameterType -eq
            [System.Management.Automation.SwitchParameter]
        ) {
            if ($IndependentEvidence) {
                $Arguments[$IndependentParameter] = $true
            }
        }
        elseif ($ParameterType -eq [string]) {
            $Arguments[$IndependentParameter] = if ($IndependentEvidence) {
                'sol-independent-review'
            }
            else {
                ''
            }
        }
        else {
            $Arguments[$IndependentParameter] = $IndependentEvidence
        }
    }

    $AssignedNames = @($Arguments.Keys)

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
            $Parameter.Name -notin $AssignedNames
        ) {
            return $null
        }
    }

    $Arguments
}

function Resolve-TriTierPhaseEvidenceCommand {
    [CmdletBinding()]
    param()

    $Candidates = @(
        Get-Command -Module $EvidenceModule.Name |
            Where-Object {
                $_.CommandType -eq 'Function'
            } |
            Sort-Object Name
    )

    $ProbeCases = @(
        @{
            risk = 'R2'
            evidence = 'E2'
            independent = $true
            expected = $false
        },
        @{
            risk = 'R2'
            evidence = 'E3'
            independent = $true
            expected = $true
        },
        @{
            risk = 'R4'
            evidence = 'E5'
            independent = $false
            expected = $false
        },
        @{
            risk = 'R4'
            evidence = 'E5'
            independent = $true
            expected = $true
        }
    )

    $PassingCandidates = @()

    foreach ($Candidate in $Candidates) {
        $CandidatePassed = $true

        foreach ($Probe in $ProbeCases) {
            $Arguments = New-TriTierPhaseEvidenceArguments `
                -Command $Candidate `
                -RiskClass $Probe.risk `
                -EvidenceLevel $Probe.evidence `
                -IndependentEvidence ([bool]$Probe.independent)

            if ($null -eq $Arguments) {
                $CandidatePassed = $false
                break
            }

            try {
                $Observed = ConvertFrom-TriTierPhaseEvidenceResult `
                    -Result (& $Candidate @Arguments)
            }
            catch {
                $CandidatePassed = $false
                break
            }

            if ($Observed -ne [bool]$Probe.expected) {
                $CandidatePassed = $false
                break
            }
        }

        if ($CandidatePassed) {
            $PassingCandidates += $Candidate
        }
    }

    if ($PassingCandidates.Count -ne 1) {
        $ExportNames = @($Candidates.Name) -join ', '

        throw (
            'Expected exactly one exported evidence decision command matching ' +
            'the R2/R4 behavioral contract; found ' +
            "$($PassingCandidates.Count). Exports: $ExportNames"
        )
    }

    $PassingCandidates[0]
}

$script:TriTierPhaseEvidenceCommand = Resolve-TriTierPhaseEvidenceCommand

function Test-TriTierPhaseEvidenceSufficiency {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('R0', 'R1', 'R2', 'R3', 'R4')]
        [string]$RiskClass,

        [Parameter(Mandatory)]
        [ValidateSet('E0', 'E1', 'E2', 'E3', 'E4', 'E5')]
        [string]$EvidenceLevel,

        [Parameter()]
        [bool]$IndependentEvidence = $false
    )

    $Arguments = New-TriTierPhaseEvidenceArguments `
        -Command $script:TriTierPhaseEvidenceCommand `
        -RiskClass $RiskClass `
        -EvidenceLevel $EvidenceLevel `
        -IndependentEvidence $IndependentEvidence

    if ($null -eq $Arguments) {
        throw (
            'Resolved evidence command no longer satisfies its parameter ' +
            'contract.'
        )
    }

    ConvertFrom-TriTierPhaseEvidenceResult `
        -Result (
            & $script:TriTierPhaseEvidenceCommand @Arguments
        )
}

function Get-TriTierPhaseEvidenceRequirement {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('R0', 'R1', 'R2', 'R3', 'R4')]
        [string]$RiskClass
    )

    foreach ($EvidenceLevel in @(
        'E0',
        'E1',
        'E2',
        'E3',
        'E4',
        'E5'
    )) {
        if (
            Test-TriTierPhaseEvidenceSufficiency `
                -RiskClass $RiskClass `
                -EvidenceLevel $EvidenceLevel `
                -IndependentEvidence $true
        ) {
            return $EvidenceLevel
        }
    }

    throw (
        "No sufficient evidence level is defined for risk class $RiskClass."
    )
}

function Get-TriTierPhaseRunState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$RunId
    )

    Get-TriTierRunState `
        -ProjectPath $ProjectPath `
        -RunId $RunId
}

function Get-TriTierPhaseFromState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$State
    )

    if (
        $null -eq $State.PSObject.Properties['phaseGate'] -or
        $null -eq $State.phaseGate
    ) {
        throw "Phase gate is not initialized for run '$($State.runId)'."
    }

    $State.phaseGate
}

function New-TriTierPhaseResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$State,

        [Parameter(Mandatory)]
        [object]$Decision,

        [Parameter()]
        [bool]$Replayed = $false
    )

    [PSCustomObject][ordered]@{
        phase = $State.phaseGate
        decision = $Decision
        state = $State
        replayed = $Replayed
    }
}

function Save-TriTierRunPhaseGate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$RunId,

        [Parameter(Mandatory)]
        [object]$Phase,

        [Parameter()]
        [string]$RunStatus = ''
    )

    $CurrentState = Get-TriTierRunState `
        -ProjectPath $ProjectPath `
        -RunId $RunId

    $ProjectedState = Copy-TriTierPhaseObject `
        -InputObject $CurrentState

    if ($null -eq $ProjectedState.PSObject.Properties['phaseGate']) {
        $ProjectedState |
            Add-Member `
                -NotePropertyName phaseGate `
                -NotePropertyValue $null
    }

    if ($null -eq $ProjectedState.PSObject.Properties['currentPhase']) {
        $ProjectedState |
            Add-Member `
                -NotePropertyName currentPhase `
                -NotePropertyValue ''
    }

    $ProjectedState.phaseGate = $Phase
    $ProjectedState.currentPhase = [string]$Phase.phaseId
    $ProjectedState.nextAction = [string]$Phase.nextAction

    if (-not [string]::IsNullOrWhiteSpace($RunStatus)) {
        $ProjectedState.status = $RunStatus
    }

    $Decision = Get-TriTierOrchestrationDecision `
        -RunState $ProjectedState

    $Phase.nextAction = [string]$Decision.nextAction

    $Arguments = @{
        ProjectPath = $ProjectPath
        RunId = $RunId
        PhaseState = $Phase
    }

    if (-not [string]::IsNullOrWhiteSpace($RunStatus)) {
        $Arguments.RunStatus = $RunStatus
    }

    $State = Set-TriTierRunPhaseState @Arguments

    New-TriTierPhaseResult `
        -State $State `
        -Decision (
            Get-TriTierOrchestrationDecision `
                -RunState $State
        )
}

function Get-TriTierRunPhaseGate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$RunId
    )

    $State = Get-TriTierPhaseRunState `
        -ProjectPath $ProjectPath `
        -RunId $RunId

    [void](Get-TriTierPhaseFromState -State $State)

    New-TriTierPhaseResult `
        -State $State `
        -Decision (
            Get-TriTierOrchestrationDecision `
                -RunState $State
        )
}

function Start-TriTierRunPhase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$RunId,

        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$')]
        [string]$PhaseId,

        [Parameter(Mandatory)]
        [ValidateSet('R0', 'R1', 'R2', 'R3', 'R4')]
        [string]$RiskClass,

        [Parameter()]
        [string]$StartedBy = 'terra-manager',

        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$')]
        [string]$EventId
    )

    Assert-TriTierPhaseActor `
        -Actor $StartedBy `
        -ExpectedRole 'terra'

    $State = Get-TriTierPhaseRunState `
        -ProjectPath $ProjectPath `
        -RunId $RunId

    if ([string]$State.status -ne 'ACTIVE') {
        throw (
            "Starting a phase requires ACTIVE run status; current status is " +
            "'$($State.status)'."
        )
    }

    if (
        $null -ne $State.PSObject.Properties['phaseGate'] -and
        $null -ne $State.phaseGate
    ) {
        $ExistingPhase = $State.phaseGate

        if (
            Test-TriTierPhaseEventApplied `
                -Phase $ExistingPhase `
                -EventId $EventId
        ) {
            return New-TriTierPhaseResult `
                -State $State `
                -Decision (
                    Get-TriTierOrchestrationDecision `
                        -RunState $State
                ) `
                -Replayed $true
        }

        if ($ExistingPhase.status -notin @(
            'ACCEPTED',
            'REJECTED'
        )) {
            throw (
                "Cannot start phase $PhaseId while phase " +
                "$($ExistingPhase.phaseId) is $($ExistingPhase.status)."
            )
        }
    }

    $Now = [DateTime]::UtcNow.ToString('o')
    $RequiredEvidenceLevel = Get-TriTierPhaseEvidenceRequirement `
        -RiskClass $RiskClass

    $Phase = [PSCustomObject][ordered]@{
        schemaVersion = 1
        phaseId = $PhaseId
        status = 'ACTIVE'
        riskClass = $RiskClass
        requiredEvidenceLevel = $RequiredEvidenceLevel
        observedEvidenceLevel = 'E0'
        evidenceIndependent = $false
        evidenceIds = @()
        ownerApprovalRequired = ($RiskClass -eq 'R4')
        ownerApprovalRecord = ''
        reviewActor = ''
        reviewDecision = 'NOT_STARTED'
        reviewSummary = ''
        reviewEvidenceIds = @()
        revision = 0
        history = @()
        nextAction = (
            "Terra must complete task work and submit evidence for phase " +
            "$PhaseId."
        )
        createdUtc = $Now
        updatedUtc = $Now
    }

    $Phase = Add-TriTierPhaseTransition `
        -Phase $Phase `
        -EventId $EventId `
        -EventType 'PHASE_STARTED' `
        -FromStatus '' `
        -ToStatus 'ACTIVE' `
        -Actor $StartedBy `
        -Summary "Started phase $PhaseId with risk class $RiskClass."

    Save-TriTierRunPhaseGate `
        -ProjectPath $ProjectPath `
        -RunId $RunId `
        -Phase $Phase
}

function Submit-TriTierRunPhaseReady {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$RunId,

        [Parameter(Mandatory)]
        [ValidateSet('E0', 'E1', 'E2', 'E3', 'E4', 'E5')]
        [string]$ObservedEvidenceLevel,

        [Parameter()]
        [string[]]$EvidenceIds = @(),

        [Parameter()]
        [bool]$IndependentEvidence = $false,

        [Parameter()]
        [string]$OwnerApprovalRecord = '',

        [Parameter()]
        [string]$SubmittedBy = 'terra-manager',

        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$')]
        [string]$EventId
    )

    Assert-TriTierPhaseActor `
        -Actor $SubmittedBy `
        -ExpectedRole 'terra'

    $State = Get-TriTierPhaseRunState `
        -ProjectPath $ProjectPath `
        -RunId $RunId

    if ($State.status -notin @(
        'ACTIVE',
        'BLOCKED_OWNER_DECISION'
    )) {
        throw (
            "Phase readiness requires ACTIVE or BLOCKED_OWNER_DECISION " +
            "run status; current status is '$($State.status)'."
        )
    }

    $Phase = Copy-TriTierPhaseObject `
        -InputObject (
            Get-TriTierPhaseFromState -State $State
        )

    if (
        Test-TriTierPhaseEventApplied `
            -Phase $Phase `
            -EventId $EventId
    ) {
        return New-TriTierPhaseResult `
            -State $State `
            -Decision (
                Get-TriTierOrchestrationDecision `
                    -RunState $State
            ) `
            -Replayed $true
    }

    if ($Phase.status -notin @(
        'ACTIVE',
        'BLOCKED_BY_FINDINGS',
        'BLOCKED_BY_EVIDENCE',
        'OWNER_DECISION_REQUIRED'
    )) {
        throw (
            "Phase readiness cannot be submitted from status " +
            "'$($Phase.status)'."
        )
    }

    $Phase.observedEvidenceLevel = $ObservedEvidenceLevel
    $Phase.evidenceIds = @($EvidenceIds)
    $Phase.evidenceIndependent = $IndependentEvidence
    $Phase.ownerApprovalRecord = $OwnerApprovalRecord.Trim()
    $Phase.reviewActor = ''
    $Phase.reviewDecision = 'NOT_STARTED'
    $Phase.reviewSummary = ''
    $Phase.reviewEvidenceIds = @()

    $Findings = @()

    if ($null -ne $State.PSObject.Properties['findings']) {
        $Findings = @($State.findings)
    }

    $Gate = Test-TriTierFindingGate -Findings $Findings

    $TaskReady = $false

    if (
        $null -ne $State.PSObject.Properties['taskFlow'] -and
        $null -ne $State.taskFlow
    ) {
        $TaskReady = (
            [string]$State.taskFlow.stage -eq 'CONTINUE' -and
            [bool]$State.taskFlow.mayAdvance
        )
    }

    $EvidencePassed = Test-TriTierPhaseEvidenceSufficiency `
        -RiskClass ([string]$Phase.riskClass) `
        -EvidenceLevel $ObservedEvidenceLevel `
        -IndependentEvidence $IndependentEvidence

    $IndependentRequired = (
        [string]$Phase.riskClass -in @('R3', 'R4')
    )

    $FromStatus = [string]$Phase.status
    $RunStatus = 'ACTIVE'

    if (
        -not $TaskReady -or
        [bool]$Gate.taskBlocked -or
        [bool]$Gate.phaseBlocked -or
        [bool]$Gate.runBlocked
    ) {
        $Phase.status = 'BLOCKED_BY_FINDINGS'

        if (
            [bool]$Gate.taskBlocked -or
            [bool]$Gate.phaseBlocked -or
            [bool]$Gate.runBlocked
        ) {
            $Phase.nextAction = [string]$Gate.nextAction
        }
        else {
            $Phase.nextAction = (
                "Complete final task review before phase " +
                "$($Phase.phaseId) can be reviewed."
            )
        }
    }
    elseif (
        -not $EvidencePassed -or
        ($IndependentRequired -and -not $IndependentEvidence)
    ) {
        $Phase.status = 'BLOCKED_BY_EVIDENCE'

        if (
            $IndependentRequired -and
            -not $IndependentEvidence
        ) {
            $Phase.nextAction = (
                "Provide independent evidence for risk class " +
                "$($Phase.riskClass) before phase review."
            )
        }
        else {
            $Phase.nextAction = (
                "Raise phase evidence from $ObservedEvidenceLevel to at " +
                "least $($Phase.requiredEvidenceLevel)."
            )
        }
    }
    elseif (
        [bool]$Phase.ownerApprovalRequired -and
        [string]::IsNullOrWhiteSpace(
            [string]$Phase.ownerApprovalRecord
        )
    ) {
        $Phase.status = 'OWNER_DECISION_REQUIRED'
        $Phase.nextAction = (
            "Owner approval is required for R4 phase " +
            "$($Phase.phaseId) before independent review."
        )
        $RunStatus = 'BLOCKED_OWNER_DECISION'
    }
    else {
        $Phase.status = 'READY_FOR_REVIEW'
        $Phase.reviewDecision = 'PENDING'
        $Phase.nextAction = (
            "Sol must independently review phase $($Phase.phaseId) " +
            "against risk $($Phase.riskClass) and evidence " +
            "$ObservedEvidenceLevel."
        )
    }

    $Phase = Add-TriTierPhaseTransition `
        -Phase $Phase `
        -EventId $EventId `
        -EventType 'PHASE_READINESS_EVALUATED' `
        -FromStatus $FromStatus `
        -ToStatus ([string]$Phase.status) `
        -Actor $SubmittedBy `
        -Summary (
            "Evaluated phase readiness using evidence " +
            "$ObservedEvidenceLevel."
        ) `
        -EvidenceIds $EvidenceIds

    Save-TriTierRunPhaseGate `
        -ProjectPath $ProjectPath `
        -RunId $RunId `
        -Phase $Phase `
        -RunStatus $RunStatus
}

function Submit-TriTierRunPhaseReview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$RunId,

        [Parameter(Mandatory)]
        [ValidateSet('ACCEPT', 'REJECT')]
        [string]$Decision,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Summary,

        [Parameter()]
        [string[]]$EvidenceIds = @(),

        [Parameter()]
        [string]$Reviewer = 'sol-adjudicator',

        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$')]
        [string]$EventId
    )

    Assert-TriTierPhaseActor `
        -Actor $Reviewer `
        -ExpectedRole 'sol'

    $State = Get-TriTierPhaseRunState `
        -ProjectPath $ProjectPath `
        -RunId $RunId

    if ([string]$State.status -ne 'ACTIVE') {
        throw (
            "Phase review requires ACTIVE run status; current status is " +
            "'$($State.status)'."
        )
    }

    $Phase = Copy-TriTierPhaseObject `
        -InputObject (
            Get-TriTierPhaseFromState -State $State
        )

    if (
        Test-TriTierPhaseEventApplied `
            -Phase $Phase `
            -EventId $EventId
    ) {
        return New-TriTierPhaseResult `
            -State $State `
            -Decision (
                Get-TriTierOrchestrationDecision `
                    -RunState $State
            ) `
            -Replayed $true
    }

    if ($Phase.status -ne 'READY_FOR_REVIEW') {
        throw (
            "Phase review requires READY_FOR_REVIEW status; current " +
            "status is '$($Phase.status)'."
        )
    }

    $Findings = @()

    if ($null -ne $State.PSObject.Properties['findings']) {
        $Findings = @($State.findings)
    }

    $Gate = Test-TriTierFindingGate -Findings $Findings

    if (
        [bool]$Gate.taskBlocked -or
        [bool]$Gate.phaseBlocked -or
        [bool]$Gate.runBlocked
    ) {
        throw 'Phase review cannot proceed while blocking findings remain.'
    }

    $EvidencePassed = Test-TriTierPhaseEvidenceSufficiency `
        -RiskClass ([string]$Phase.riskClass) `
        -EvidenceLevel ([string]$Phase.observedEvidenceLevel) `
        -IndependentEvidence ([bool]$Phase.evidenceIndependent)

    if (-not $EvidencePassed) {
        throw 'Phase review cannot proceed with insufficient evidence.'
    }

    if (
        [string]$Phase.riskClass -in @('R3', 'R4') -and
        -not [bool]$Phase.evidenceIndependent
    ) {
        throw 'R3 and R4 phase review requires independent evidence.'
    }

    if (
        [bool]$Phase.ownerApprovalRequired -and
        [string]::IsNullOrWhiteSpace(
            [string]$Phase.ownerApprovalRecord
        )
    ) {
        throw 'R4 phase review requires an owner approval record.'
    }

    $FromStatus = [string]$Phase.status
    $Phase.reviewActor = $Reviewer.Trim()
    $Phase.reviewSummary = $Summary.Trim()
    $Phase.reviewEvidenceIds = @($EvidenceIds)

    if ($Decision -eq 'ACCEPT') {
        $Phase.status = 'ACCEPTED'
        $Phase.reviewDecision = 'ACCEPTED'
        $Phase.nextAction = (
            "Terra may start the next phase or prepare run completion " +
            "after accepted phase $($Phase.phaseId)."
        )
        $EventType = 'PHASE_ACCEPTED'
    }

    if ($Decision -eq 'REJECT') {
        $Phase.status = 'REJECTED'
        $Phase.reviewDecision = 'REJECTED'
        $Phase.nextAction = (
            "Terra must return to planning and select bounded remediation " +
            "for rejected phase $($Phase.phaseId)."
        )
        $EventType = 'PHASE_REJECTED'
    }

    $Phase = Add-TriTierPhaseTransition `
        -Phase $Phase `
        -EventId $EventId `
        -EventType $EventType `
        -FromStatus $FromStatus `
        -ToStatus ([string]$Phase.status) `
        -Actor $Reviewer `
        -Summary $Summary `
        -EvidenceIds $EvidenceIds

    Save-TriTierRunPhaseGate `
        -ProjectPath $ProjectPath `
        -RunId $RunId `
        -Phase $Phase `
        -RunStatus 'ACTIVE'
}

Export-ModuleMember -Function @(
    'Get-TriTierRunPhaseGate',
    'Start-TriTierRunPhase',
    'Submit-TriTierRunPhaseReady',
    'Submit-TriTierRunPhaseReview'
)
