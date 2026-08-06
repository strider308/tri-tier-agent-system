$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot = Split-Path $PSScriptRoot -Parent
$AgentProfilesPath = Join-Path $RepoRoot 'src\TriTier\AgentProfiles.psm1'

Import-Module $AgentProfilesPath -Force

function Assert-Equal {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter()]
        $Expected,

        [Parameter()]
        $Actual
    )

    $Passed = $Expected -eq $Actual

    [PSCustomObject]@{
        Test = $Name
        Status = if ($Passed) { 'PASS' } else { 'FAIL' }
    } | Format-Table -AutoSize

    if (-not $Passed) {
        throw "$Name failed. Expected: $Expected. Actual: $Actual."
    }
}

function Assert-True {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [bool]$Value
    )

    Assert-Equal -Name $Name -Expected $true -Actual $Value
}

$RunState = [PSCustomObject][ordered]@{
    runId = 'handoff-main'
    currentTask = 'TASK-17'
    nextAction = 'Perform the bounded implementation.'
    unresolvedFindingIds = @('finding-17')
    evidenceIds = @('evidence-17')
    taskFlow = [PSCustomObject]@{
        currentTask = 'TASK-17'
    }
    phaseGate = [PSCustomObject]@{
        phaseId = 'PHASE-5'
        riskClass = 'R3'
    }
}

$ImplementDecision = [PSCustomObject][ordered]@{
    stage = 'IMPLEMENT'
    responsibleParty = 'luna'
    blockedScope = 'NONE'
    ownerRequired = $false
    phaseId = 'PHASE-5'
    nextAction = 'Luna must implement TASK-17 and return deterministic evidence.'
}

$ImplementHandoff = New-TriTierAgentHandoff `
    -RunState $RunState `
    -Decision $ImplementDecision
$ImplementValidation = Test-TriTierAgentHandoff `
    -Handoff $ImplementHandoff

Assert-True `
    -Name 'Implementation handoff is valid' `
    -Value ([bool]$ImplementValidation.valid)
Assert-Equal `
    -Name 'Implementation routes to Luna worker' `
    -Expected 'luna_worker' `
    -Actual $ImplementHandoff.toProfile
Assert-Equal `
    -Name 'Implementation handoff retains task' `
    -Expected 'TASK-17' `
    -Actual $ImplementHandoff.taskId
Assert-Equal `
    -Name 'Implementation handoff retains risk class' `
    -Expected 'R3' `
    -Actual $ImplementHandoff.riskClass
Assert-Equal `
    -Name 'Implementation handoff retains evidence' `
    -Expected 'evidence-17' `
    -Actual $ImplementHandoff.evidenceIds[0]

$ReviewDecision = [PSCustomObject][ordered]@{
    stage = 'REVIEW'
    responsibleParty = 'sol'
    blockedScope = 'NONE'
    ownerRequired = $false
    phaseId = 'PHASE-5'
    nextAction = 'Sol must independently review TASK-17.'
}

$ReviewHandoff = New-TriTierAgentHandoff `
    -RunState $RunState `
    -Decision $ReviewDecision
$ReviewValidation = Test-TriTierAgentHandoff `
    -Handoff $ReviewHandoff

Assert-True `
    -Name 'Independent review handoff is valid' `
    -Value ([bool]$ReviewValidation.valid)
Assert-Equal `
    -Name 'Independent review routes to Sol architect' `
    -Expected 'sol_architect' `
    -Actual $ReviewHandoff.toProfile
Assert-Equal `
    -Name 'Review declares independence requirement' `
    -Expected $true `
    -Actual ([bool]$ReviewHandoff.independentReviewRequired)

Assert-Equal `
    -Name 'Review infers Luna implementation profile' `
    -Expected 'luna_worker' `
    -Actual $ReviewHandoff.implementationProfile

$SelfReview = $ReviewHandoff.PSObject.Copy()
$SelfReview.implementationProfile = 'sol_architect'
$SelfReviewValidation = Test-TriTierAgentHandoff -Handoff $SelfReview

Assert-Equal `
    -Name 'Implementer cannot independently review itself' `
    -Expected $false `
    -Actual ([bool]$SelfReviewValidation.valid)
Assert-True `
    -Name 'Self-review rejection explains independence' `
    -Value (
        ($SelfReviewValidation.errors -join ' ') -match
        'cannot perform its own independent review'
    )

$WeakenedReview = $ReviewHandoff.PSObject.Copy()
$WeakenedReview.independentReviewRequired = $false
$WeakenedReviewValidation = Test-TriTierAgentHandoff `
    -Handoff $WeakenedReview

Assert-Equal `
    -Name 'Review independence flag cannot be weakened' `
    -Expected $false `
    -Actual ([bool]$WeakenedReviewValidation.valid)
Assert-True `
    -Name 'Weakened independence rejection explains expected value' `
    -Value (
        ($WeakenedReviewValidation.errors -join ' ') -match
        'independentReviewRequired must be True'
    )

$FailedReviewDecision = [PSCustomObject][ordered]@{
    stage = 'REVIEW'
    responsibleParty = 'terra'
    blockedScope = 'TASK'
    ownerRequired = $false
    phaseId = 'PHASE-5'
    nextAction = 'Terra must authorize the bounded repair cycle.'
}

$FailedReviewHandoff = New-TriTierAgentHandoff `
    -RunState $RunState `
    -Decision $FailedReviewDecision `
    -FromProfile 'sol_architect' `
    -ImplementationProfile 'luna_worker'

Assert-Equal `
    -Name 'Failed review coordination returns to Terra manager' `
    -Expected 'terra_manager' `
    -Actual $FailedReviewHandoff.toProfile
Assert-Equal `
    -Name 'Failed review retains task block' `
    -Expected 'TASK' `
    -Actual $FailedReviewHandoff.blockedScope

$AdjudicationDecision = [PSCustomObject][ordered]@{
    stage = 'ADJUDICATE'
    responsibleParty = 'sol'
    blockedScope = 'TASK'
    ownerRequired = $false
    phaseId = 'PHASE-5'
    nextAction = 'Sol must adjudicate the failed repair evidence.'
}

$AdjudicationHandoff = New-TriTierAgentHandoff `
    -RunState $RunState `
    -Decision $AdjudicationDecision

Assert-Equal `
    -Name 'Adjudication routes to Sol adjudicator' `
    -Expected 'sol_adjudicator' `
    -Actual $AdjudicationHandoff.toProfile
Assert-True `
    -Name 'Adjudication includes bounded outcomes' `
    -Value (
        ($AdjudicationHandoff.acceptanceCriteria -join ' ') -match
        'REPAIR_AGAIN'
    )

$OwnerDecision = [PSCustomObject][ordered]@{
    stage = 'OWNER_DECISION'
    responsibleParty = 'owner'
    blockedScope = 'RUN'
    ownerRequired = $true
    phaseId = 'PHASE-5'
    nextAction = 'The owner must approve or reject the R4 action.'
}

$OwnerHandoff = New-TriTierAgentHandoff `
    -RunState $RunState `
    -Decision $OwnerDecision
$OwnerValidation = Test-TriTierAgentHandoff -Handoff $OwnerHandoff

Assert-True `
    -Name 'Owner handoff is valid' `
    -Value ([bool]$OwnerValidation.valid)
Assert-Equal `
    -Name 'Owner handoff names no agent' `
    -Expected '' `
    -Actual $OwnerHandoff.toProfile
Assert-Equal `
    -Name 'Owner handoff target type is owner' `
    -Expected 'owner' `
    -Actual $OwnerHandoff.targetType
Assert-Equal `
    -Name 'Owner handoff retains owner requirement' `
    -Expected $true `
    -Actual ([bool]$OwnerHandoff.ownerRequired)

$Tampered = $ImplementHandoff.PSObject.Copy()
$Tampered.toProfile = 'terra_manager'
$TamperedValidation = Test-TriTierAgentHandoff -Handoff $Tampered

Assert-Equal `
    -Name 'Mismatched target profile fails closed' `
    -Expected $false `
    -Actual ([bool]$TamperedValidation.valid)

$BypassedTarget = $ImplementHandoff.PSObject.Copy()
$BypassedTarget.targetType = 'none'
$BypassedTarget.toProfile = ''
$BypassedTargetValidation = Test-TriTierAgentHandoff `
    -Handoff $BypassedTarget

Assert-Equal `
    -Name 'Agent stage cannot bypass dispatch with no target' `
    -Expected $false `
    -Actual ([bool]$BypassedTargetValidation.valid)
Assert-True `
    -Name 'Target bypass rejection explains expected type' `
    -Value (
        ($BypassedTargetValidation.errors -join ' ') -match
        'does not match expected target type agent'
    )

$MissingOwnerGate = $OwnerHandoff.PSObject.Copy()
$MissingOwnerGate.ownerRequired = $false
$MissingOwnerValidation = Test-TriTierAgentHandoff `
    -Handoff $MissingOwnerGate

Assert-Equal `
    -Name 'Owner handoff requires explicit owner gate' `
    -Expected $false `
    -Actual ([bool]$MissingOwnerValidation.valid)

$PhaseReviewDecision = [PSCustomObject][ordered]@{
    stage = 'PHASE_REVIEW'
    responsibleParty = 'sol'
    blockedScope = 'NONE'
    ownerRequired = $false
    phaseId = 'PHASE-5'
    nextAction = 'Sol must independently review the completed phase.'
}

$PhaseReviewHandoff = New-TriTierAgentHandoff `
    -RunState $RunState `
    -Decision $PhaseReviewDecision

Assert-Equal `
    -Name 'Phase review routes to Sol adjudicator' `
    -Expected 'sol_adjudicator' `
    -Actual $PhaseReviewHandoff.toProfile
Assert-Equal `
    -Name 'Phase review infers Terra implementation profile' `
    -Expected 'terra_manager' `
    -Actual $PhaseReviewHandoff.implementationProfile

$StopDecision = [PSCustomObject][ordered]@{
    stage = 'STOP'
    responsibleParty = 'none'
    blockedScope = 'RUN'
    ownerRequired = $false
    phaseId = 'PHASE-5'
    nextAction = 'Preserve terminal evidence and do not continue.'
}

$StopHandoff = New-TriTierAgentHandoff `
    -RunState $RunState `
    -Decision $StopDecision
$StopValidation = Test-TriTierAgentHandoff -Handoff $StopHandoff

Assert-True `
    -Name 'No-agent STOP handoff is valid' `
    -Value ([bool]$StopValidation.valid)
Assert-Equal `
    -Name 'No-agent STOP target type is none' `
    -Expected 'none' `
    -Actual $StopHandoff.targetType
Assert-Equal `
    -Name 'No-agent STOP names no profile' `
    -Expected '' `
    -Actual $StopHandoff.toProfile

Write-Host ''
Write-Host 'Structured agent handoff tests passed.' -ForegroundColor Green
