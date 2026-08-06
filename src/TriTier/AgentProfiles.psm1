Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:AgentProfileSchemaVersion = 1
$script:AgentHandoffSchemaVersion = 1

$script:AgentProfiles = @(
    [PSCustomObject][ordered]@{
        name = 'luna_router'
        fileName = 'luna-router.toml'
        tier = 'luna'
        purpose = 'routing'
        sandboxMode = 'read-only'
        canWrite = $false
        independentReviewer = $false
        runtimeStages = @()
    }
    [PSCustomObject][ordered]@{
        name = 'luna_worker'
        fileName = 'luna-worker.toml'
        tier = 'luna'
        purpose = 'implementation-repair'
        sandboxMode = 'workspace-write'
        canWrite = $true
        independentReviewer = $false
        runtimeStages = @('IMPLEMENT', 'REPAIR')
    }
    [PSCustomObject][ordered]@{
        name = 'terra_manager'
        fileName = 'terra-manager.toml'
        tier = 'terra'
        purpose = 'coordination-integration'
        sandboxMode = 'workspace-write'
        canWrite = $true
        independentReviewer = $false
        runtimeStages = @('PLAN', 'REVIEW', 'CONTINUE', 'WAIT_EXTERNAL')
    }
    [PSCustomObject][ordered]@{
        name = 'terra_reviewer'
        fileName = 'terra-reviewer.toml'
        tier = 'terra'
        purpose = 'integration-review'
        sandboxMode = 'read-only'
        canWrite = $false
        independentReviewer = $false
        runtimeStages = @()
    }
    [PSCustomObject][ordered]@{
        name = 'sol_architect'
        fileName = 'sol-architect.toml'
        tier = 'sol'
        purpose = 'independent-review'
        sandboxMode = 'read-only'
        canWrite = $false
        independentReviewer = $true
        runtimeStages = @('REVIEW', 'FRESH_REVIEW')
    }
    [PSCustomObject][ordered]@{
        name = 'sol_adjudicator'
        fileName = 'sol-adjudicator.toml'
        tier = 'sol'
        purpose = 'adjudication-phase-review'
        sandboxMode = 'read-only'
        canWrite = $false
        independentReviewer = $true
        runtimeStages = @('ADJUDICATE', 'PHASE_REVIEW', 'STOP')
    }
)

function Get-TriTierAgentProperty {
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
            "Required agent-contract property '$Name' is missing from " +
            "object type $TypeName."
        )
    }

    $DefaultValue
}

function Get-TriTierAgentProfileCatalog {
    [CmdletBinding()]
    param()

    @($script:AgentProfiles)
}

function Get-TriTierAgentProfileSpec {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    $ProfileMatches = @(
        $script:AgentProfiles |
            Where-Object {
                [string]$_.name -eq $Name
            }
    )

    if ($ProfileMatches.Count -ne 1) {
        throw "Unknown or duplicate Tri-Tier agent profile: $Name"
    }

    $ProfileMatches[0]
}

function Resolve-TriTierAgentProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Decision
    )

    $Stage = [string](
        Get-TriTierAgentProperty `
            -InputObject $Decision `
            -Name 'stage' `
            -Required
    )
    $ResponsibleParty = [string](
        Get-TriTierAgentProperty `
            -InputObject $Decision `
            -Name 'responsibleParty' `
            -Required
    )

    $ProfileName = switch ($Stage) {
        'PLAN' {
            if ($ResponsibleParty -ne 'terra') {
                throw 'PLAN must be assigned to Terra.'
            }
            'terra_manager'
        }

        'IMPLEMENT' {
            if ($ResponsibleParty -ne 'luna') {
                throw 'IMPLEMENT must be assigned to Luna.'
            }
            'luna_worker'
        }

        'REVIEW' {
            if ($ResponsibleParty -eq 'terra') {
                'terra_manager'
            }
            elseif ($ResponsibleParty -eq 'sol') {
                'sol_architect'
            }
            else {
                throw 'REVIEW must be assigned to Terra or Sol.'
            }
        }

        'REPAIR' {
            if ($ResponsibleParty -ne 'luna') {
                throw 'REPAIR must be assigned to Luna.'
            }
            'luna_worker'
        }

        'FRESH_REVIEW' {
            if ($ResponsibleParty -ne 'sol') {
                throw 'FRESH_REVIEW must be assigned to Sol.'
            }
            'sol_architect'
        }

        'ADJUDICATE' {
            if ($ResponsibleParty -ne 'sol') {
                throw 'ADJUDICATE must be assigned to Sol.'
            }
            'sol_adjudicator'
        }

        'CONTINUE' {
            if ($ResponsibleParty -ne 'terra') {
                throw 'CONTINUE must be assigned to Terra.'
            }
            'terra_manager'
        }

        'PHASE_REVIEW' {
            if ($ResponsibleParty -ne 'sol') {
                throw 'PHASE_REVIEW must be assigned to Sol.'
            }
            'sol_adjudicator'
        }

        'OWNER_DECISION' {
            if ($ResponsibleParty -ne 'owner') {
                throw 'OWNER_DECISION must be assigned to the owner.'
            }
            ''
        }

        'WAIT_EXTERNAL' {
            if ($ResponsibleParty -ne 'terra') {
                throw 'WAIT_EXTERNAL must be coordinated by Terra.'
            }
            'terra_manager'
        }

        'STOP' {
            if ($ResponsibleParty -notin @('sol', 'none')) {
                throw 'STOP must be assigned to Sol or no agent.'
            }

            if ($ResponsibleParty -eq 'none') {
                ''
            }
            else {
                'sol_adjudicator'
            }
        }

        default {
            throw "Unsupported orchestration stage for agent routing: $Stage"
        }
    }

    if ([string]::IsNullOrWhiteSpace($ProfileName)) {
        return $null
    }

    Get-TriTierAgentProfileSpec -Name $ProfileName
}

function Get-TriTierAgentAcceptanceCriteria {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Stage
    )

    switch ($Stage) {
        'PLAN' {
            @(
                'Select one bounded task consistent with project authority.'
                'Persist the task, dependencies, and exact next action.'
            )
        }
        'IMPLEMENT' {
            @(
                'Implement only the bounded delegated task.'
                'Run deterministic delegated validation.'
                'Return changed files, evidence identifiers, and uncertainty.'
            )
        }
        'REVIEW' {
            @(
                'Review independently from the implementation actor.'
                'Return PASS or FAIL with reproducible evidence.'
                'Register or request findings instead of silently repairing.'
            )
        }
        'REPAIR' {
            @(
                'Repair only the active finding and preserve unrelated work.'
                'Return repair evidence for a fresh independent review.'
            )
        }
        'FRESH_REVIEW' {
            @(
                'Reproduce the repaired claim independently.'
                'Return PASS or FAIL without editing the implementation.'
            )
        }
        'ADJUDICATE' {
            @(
                'Choose REPAIR_AGAIN, OWNER_DECISION, or ABORT_FOR_SAFETY.'
                'State decisive evidence, rejected alternatives, and residual risk.'
            )
        }
        'CONTINUE' {
            @(
                'Confirm all required gates are satisfied.'
                'Persist the next phase, task, wait, or terminal action.'
            )
        }
        'PHASE_REVIEW' {
            @(
                'Review phase evidence independently against the phase gate.'
                'Return ACCEPT or REJECT with decisive evidence.'
            )
        }
        'OWNER_DECISION' {
            @(
                'Present the exact decision, consequences, and safe options.'
                'Do not continue until explicit owner action is recorded.'
            )
        }
        'WAIT_EXTERNAL' {
            @(
                'Record the external dependency and evidence required to resume.'
                'Do not dispatch implementation while the dependency remains unresolved.'
            )
        }
        'STOP' {
            @(
                'Preserve terminal evidence and do not mutate the stopped run.'
                'Require separate authorization before any new run.'
            )
        }
        default {
            throw "Unsupported stage for handoff acceptance criteria: $Stage"
        }
    }
}

function New-TriTierAgentHandoff {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$RunState,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Decision,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$FromProfile = 'terra_manager',

        [Parameter()]
        [string]$ImplementationProfile = ''
    )

    [void](Get-TriTierAgentProfileSpec -Name $FromProfile)

    $Stage = [string](
        Get-TriTierAgentProperty `
            -InputObject $Decision `
            -Name 'stage' `
            -Required
    )
    $ResponsibleParty = [string](
        Get-TriTierAgentProperty `
            -InputObject $Decision `
            -Name 'responsibleParty' `
            -Required
    )
    $ResolvedAgentProfile = Resolve-TriTierAgentProfile -Decision $Decision
    $TargetType = if ($Stage -eq 'OWNER_DECISION') {
        'owner'
    }
    elseif ($null -eq $ResolvedAgentProfile) {
        'none'
    }
    else {
        'agent'
    }

    $Phase = Get-TriTierAgentProperty `
        -InputObject $RunState `
        -Name 'phaseGate' `
        -DefaultValue $null
    $TaskFlow = Get-TriTierAgentProperty `
        -InputObject $RunState `
        -Name 'taskFlow' `
        -DefaultValue $null

    $RiskClass = ''

    if ($null -ne $Phase) {
        $RiskClass = [string](
            Get-TriTierAgentProperty `
                -InputObject $Phase `
                -Name 'riskClass' `
                -DefaultValue ''
        )
    }

    if ([string]::IsNullOrWhiteSpace($RiskClass)) {
        $RiskClass = [string](
            Get-TriTierAgentProperty `
                -InputObject $RunState `
                -Name 'riskClass' `
                -DefaultValue ''
        )
    }

    $CurrentTask = [string](
        Get-TriTierAgentProperty `
            -InputObject $RunState `
            -Name 'currentTask' `
            -DefaultValue ''
    )

    if (
        [string]::IsNullOrWhiteSpace($CurrentTask) -and
        $null -ne $TaskFlow
    ) {
        $CurrentTask = [string](
            Get-TriTierAgentProperty `
                -InputObject $TaskFlow `
                -Name 'currentTask' `
                -DefaultValue ''
        )
    }

    $PhaseId = [string](
        Get-TriTierAgentProperty `
            -InputObject $Decision `
            -Name 'phaseId' `
            -DefaultValue ''
    )
    $UnresolvedFindingIds = @(
        Get-TriTierAgentProperty `
            -InputObject $RunState `
            -Name 'unresolvedFindingIds' `
            -DefaultValue @()
    )
    $EvidenceIds = @(
        Get-TriTierAgentProperty `
            -InputObject $RunState `
            -Name 'evidenceIds' `
            -DefaultValue @()
    )
    $IndependentReviewRequired = $Stage -in @(
        'REVIEW'
        'FRESH_REVIEW'
        'PHASE_REVIEW'
    ) -and $ResponsibleParty -eq 'sol'

    if ([string]::IsNullOrWhiteSpace($ImplementationProfile)) {
        if ($Stage -in @('REVIEW', 'FRESH_REVIEW')) {
            $ImplementationProfile = 'luna_worker'
        }
        elseif ($Stage -eq 'PHASE_REVIEW') {
            $ImplementationProfile = 'terra_manager'
        }
    }

    $ToProfile = if ($null -eq $ResolvedAgentProfile) {
        ''
    }
    else {
        [string]$ResolvedAgentProfile.name
    }

    $Handoff = [PSCustomObject][ordered]@{
        schemaVersion = $script:AgentHandoffSchemaVersion
        runId = [string](
            Get-TriTierAgentProperty `
                -InputObject $RunState `
                -Name 'runId' `
                -Required
        )
        phaseId = $PhaseId
        taskId = $CurrentTask
        fromProfile = $FromProfile
        toProfile = $ToProfile
        targetType = $TargetType
        stage = $Stage
        responsibleParty = $ResponsibleParty
        riskClass = $RiskClass
        blockedScope = [string](
            Get-TriTierAgentProperty `
                -InputObject $Decision `
                -Name 'blockedScope' `
                -DefaultValue 'NONE'
        )
        ownerRequired = [bool](
            Get-TriTierAgentProperty `
                -InputObject $Decision `
                -Name 'ownerRequired' `
                -DefaultValue $false
        )
        instruction = [string](
            Get-TriTierAgentProperty `
                -InputObject $Decision `
                -Name 'nextAction' `
                -Required
        )
        acceptanceCriteria = @(
            Get-TriTierAgentAcceptanceCriteria -Stage $Stage
        )
        evidenceIds = $EvidenceIds
        unresolvedFindingIds = $UnresolvedFindingIds
        independentReviewRequired = $IndependentReviewRequired
        implementationProfile = $ImplementationProfile
        createdUtc = [DateTime]::UtcNow.ToString('o')
    }

    $Validation = Test-TriTierAgentHandoff -Handoff $Handoff

    if (-not $Validation.valid) {
        throw (
            'Generated Tri-Tier handoff is invalid: ' +
            ($Validation.errors -join '; ')
        )
    }

    $Handoff
}

function Test-TriTierAgentHandoff {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Handoff
    )

    $Errors = @()

    foreach ($RequiredField in @(
        'schemaVersion'
        'runId'
        'phaseId'
        'taskId'
        'fromProfile'
        'toProfile'
        'targetType'
        'stage'
        'responsibleParty'
        'riskClass'
        'blockedScope'
        'ownerRequired'
        'instruction'
        'acceptanceCriteria'
        'evidenceIds'
        'unresolvedFindingIds'
        'independentReviewRequired'
        'implementationProfile'
        'createdUtc'
    )) {
        try {
            [void](
                Get-TriTierAgentProperty `
                    -InputObject $Handoff `
                    -Name $RequiredField `
                    -Required
            )
        }
        catch {
            $Errors += $_.Exception.Message
        }
    }

    $SchemaVersion = [int](
        Get-TriTierAgentProperty `
            -InputObject $Handoff `
            -Name 'schemaVersion' `
            -DefaultValue 0
    )

    if ($SchemaVersion -ne $script:AgentHandoffSchemaVersion) {
        $Errors += "Unsupported handoff schema version: $SchemaVersion"
    }

    $RunId = [string](
        Get-TriTierAgentProperty `
            -InputObject $Handoff `
            -Name 'runId' `
            -DefaultValue ''
    )
    $Instruction = [string](
        Get-TriTierAgentProperty `
            -InputObject $Handoff `
            -Name 'instruction' `
            -DefaultValue ''
    )
    $Stage = [string](
        Get-TriTierAgentProperty `
            -InputObject $Handoff `
            -Name 'stage' `
            -DefaultValue ''
    )
    $ResponsibleParty = [string](
        Get-TriTierAgentProperty `
            -InputObject $Handoff `
            -Name 'responsibleParty' `
            -DefaultValue ''
    )
    $TargetType = [string](
        Get-TriTierAgentProperty `
            -InputObject $Handoff `
            -Name 'targetType' `
            -DefaultValue ''
    )
    $ToProfile = [string](
        Get-TriTierAgentProperty `
            -InputObject $Handoff `
            -Name 'toProfile' `
            -DefaultValue ''
    )
    $FromProfile = [string](
        Get-TriTierAgentProperty `
            -InputObject $Handoff `
            -Name 'fromProfile' `
            -DefaultValue ''
    )
    $ImplementationProfile = [string](
        Get-TriTierAgentProperty `
            -InputObject $Handoff `
            -Name 'implementationProfile' `
            -DefaultValue ''
    )
    $IndependentReviewRequired = [bool](
        Get-TriTierAgentProperty `
            -InputObject $Handoff `
            -Name 'independentReviewRequired' `
            -DefaultValue $false
    )
    $AcceptanceCriteria = @(
        Get-TriTierAgentProperty `
            -InputObject $Handoff `
            -Name 'acceptanceCriteria' `
            -DefaultValue @()
    )

    $BlockedScope = [string](
        Get-TriTierAgentProperty `
            -InputObject $Handoff `
            -Name 'blockedScope' `
            -DefaultValue ''
    )
    $OwnerRequired = [bool](
        Get-TriTierAgentProperty `
            -InputObject $Handoff `
            -Name 'ownerRequired' `
            -DefaultValue $false
    )
    $RiskClass = [string](
        Get-TriTierAgentProperty `
            -InputObject $Handoff `
            -Name 'riskClass' `
            -DefaultValue ''
    )

    if ([string]::IsNullOrWhiteSpace($RunId)) {
        $Errors += 'Handoff runId must not be empty.'
    }

    if ([string]::IsNullOrWhiteSpace($Instruction)) {
        $Errors += 'Handoff instruction must not be empty.'
    }

    if ($AcceptanceCriteria.Count -eq 0) {
        $Errors += 'Handoff must include acceptance criteria.'
    }

    foreach ($Criterion in $AcceptanceCriteria) {
        if ([string]::IsNullOrWhiteSpace([string]$Criterion)) {
            $Errors += 'Handoff acceptance criteria must not contain empty values.'
        }
    }

    if ($BlockedScope -notin @('NONE', 'TASK', 'PHASE', 'RUN')) {
        $Errors += "Unsupported handoff blocked scope: $BlockedScope"
    }

    if (
        -not [string]::IsNullOrWhiteSpace($RiskClass) -and
        $RiskClass -notin @('R0', 'R1', 'R2', 'R3', 'R4')
    ) {
        $Errors += "Unsupported handoff risk class: $RiskClass"
    }

    try {
        [void](Get-TriTierAgentProfileSpec -Name $FromProfile)
    }
    catch {
        $Errors += $_.Exception.Message
    }

    if (-not [string]::IsNullOrWhiteSpace($ImplementationProfile)) {
        try {
            [void](
                Get-TriTierAgentProfileSpec -Name $ImplementationProfile
            )
        }
        catch {
            $Errors += $_.Exception.Message
        }
    }

    $ExpectedImplementationProfile = switch ($Stage) {
        'REVIEW' { 'luna_worker' }
        'FRESH_REVIEW' { 'luna_worker' }
        'PHASE_REVIEW' { 'terra_manager' }
        default { '' }
    }

    $ExpectedIndependentReviewRequired = (
        $Stage -in @('REVIEW', 'FRESH_REVIEW', 'PHASE_REVIEW') -and
        $ResponsibleParty -eq 'sol'
    )

    if (
        $IndependentReviewRequired -ne
        $ExpectedIndependentReviewRequired
    ) {
        $Errors += (
            "Handoff independentReviewRequired must be " +
            "$ExpectedIndependentReviewRequired for $Stage/" +
            "$ResponsibleParty."
        )
    }

    if (
        -not [string]::IsNullOrWhiteSpace(
            $ExpectedImplementationProfile
        ) -and
        $ImplementationProfile -ne $ExpectedImplementationProfile
    ) {
        $Errors += (
            "Stage $Stage requires implementationProfile " +
            "$ExpectedImplementationProfile."
        )
    }

    $ExpectedProfile = $null

    try {
        $ExpectedProfile = Resolve-TriTierAgentProfile `
            -Decision ([PSCustomObject]@{
                stage = $Stage
                responsibleParty = $ResponsibleParty
            })
    }
    catch {
        $Errors += $_.Exception.Message
    }

    $ExpectedTargetType = if ($Stage -eq 'OWNER_DECISION') {
        'owner'
    }
    elseif ($null -eq $ExpectedProfile) {
        'none'
    }
    else {
        'agent'
    }

    if ($TargetType -ne $ExpectedTargetType) {
        $Errors += (
            "Handoff target type $TargetType does not match expected " +
            "target type $ExpectedTargetType."
        )
    }

    if ($TargetType -eq 'agent') {
        if ($OwnerRequired) {
            $Errors += 'Agent-target handoff cannot require owner action.'
        }

        if ($null -eq $ExpectedProfile) {
            $Errors += 'Agent-target handoff has no resolvable profile.'
        }
        elseif ($ToProfile -ne [string]$ExpectedProfile.name) {
            $Errors += (
                "Handoff profile $ToProfile does not match expected profile " +
                "$($ExpectedProfile.name)."
            )
        }
        else {
            if ($Stage -notin @($ExpectedProfile.runtimeStages)) {
                $Errors += (
                    "Profile $ToProfile is not authorized for stage $Stage."
                )
            }

            if (
                $Stage -in @('IMPLEMENT', 'REPAIR') -and
                -not [bool]$ExpectedProfile.canWrite
            ) {
                $Errors += "$Stage requires a write-capable profile."
            }

            if (
                $IndependentReviewRequired -and
                -not [bool]$ExpectedProfile.independentReviewer
            ) {
                $Errors += (
                    "$Stage requires an independent-review profile."
                )
            }
        }
    }
    elseif ($TargetType -eq 'owner') {
        if ($Stage -ne 'OWNER_DECISION') {
            $Errors += 'Owner target is valid only for OWNER_DECISION.'
        }

        if (-not $OwnerRequired) {
            $Errors += 'Owner handoff must record ownerRequired=true.'
        }

        if (-not [string]::IsNullOrWhiteSpace($ToProfile)) {
            $Errors += 'Owner handoff must not name an agent profile.'
        }
    }
    elseif ($TargetType -eq 'none') {
        if ($Stage -ne 'STOP' -or $ResponsibleParty -ne 'none') {
            $Errors += (
                'No-agent handoff is valid only for STOP assigned to none.'
            )
        }

        if ($OwnerRequired) {
            $Errors += 'No-agent STOP handoff cannot require owner action.'
        }

        if (-not [string]::IsNullOrWhiteSpace($ToProfile)) {
            $Errors += 'No-agent handoff must not name an agent profile.'
        }
    }
    else {
        $Errors += "Unsupported handoff target type: $TargetType"
    }

    if (
        $IndependentReviewRequired -and
        -not [string]::IsNullOrWhiteSpace($ImplementationProfile) -and
        $ImplementationProfile -eq $ToProfile
    ) {
        $Errors += (
            'The implementation profile cannot perform its own independent ' +
            'review.'
        )
    }

    [PSCustomObject][ordered]@{
        valid = $Errors.Count -eq 0
        errors = @($Errors)
        handoff = $Handoff
    }
}

Export-ModuleMember -Function @(
    'Get-TriTierAgentProfileCatalog'
    'Get-TriTierAgentProfileSpec'
    'New-TriTierAgentHandoff'
    'Resolve-TriTierAgentProfile'
    'Test-TriTierAgentHandoff'
)
