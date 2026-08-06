$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot = Split-Path $PSScriptRoot -Parent
$StatePath = Join-Path $RepoRoot 'src\TriTier\State.psm1'
$TaskFlowPath = Join-Path $RepoRoot 'src\TriTier\TaskFlow.psm1'

Import-Module $StatePath -Force
Import-Module $TaskFlowPath -Force

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

function Assert-Throws {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [scriptblock]$Action
    )

    $Thrown = $false

    try {
        & $Action
    }
    catch {
        $Thrown = $true
    }

    Assert-Equal -Name $Name -Expected $true -Actual $Thrown
}

$TestRoot = Join-Path (
    [System.IO.Path]::GetTempPath()
) (
    'tri-tier-task-flow-' + [guid]::NewGuid().ToString('N')
)

try {
    New-Item -ItemType Directory -Path $TestRoot -Force | Out-Null

    $PassRun = New-TriTierRun `
        -ProjectPath $TestRoot `
        -RunId 'task-flow-pass' `
        -Title 'Task flow pass path' `
        -CurrentTask 'TASK-01' `
        -NextAction 'Luna must implement TASK-01.'

    $Initialized = Initialize-TriTierRunTaskFlow `
        -ProjectPath $TestRoot `
        -RunId $PassRun.state.runId `
        -EventId 'evt-init-pass'

    Assert-Equal -Name 'Current task initializes IMPLEMENT stage' -Expected 'IMPLEMENT' -Actual $Initialized.flow.stage
    Assert-Equal -Name 'IMPLEMENT stage belongs to Luna' -Expected 'luna' -Actual $Initialized.flow.responsibleParty
    Assert-Equal -Name 'Initialization creates one transition' -Expected 1 -Actual @($Initialized.flow.transitionHistory).Count

    $Reinitialized = Initialize-TriTierRunTaskFlow `
        -ProjectPath $TestRoot `
        -RunId $PassRun.state.runId `
        -EventId 'evt-init-ignored'

    Assert-Equal -Name 'Initialization is idempotent' -Expected $true -Actual ([bool]$Reinitialized.replayed)
    Assert-Equal -Name 'Reinitialization preserves history' -Expected 1 -Actual @($Reinitialized.flow.transitionHistory).Count

    $Implementation = Complete-TriTierRunImplementation `
        -ProjectPath $TestRoot `
        -RunId $PassRun.state.runId `
        -ImplementedBy 'luna-worker' `
        -Summary 'Implemented the bounded task.' `
        -EvidenceIds @('E-IMPLEMENT-01') `
        -EventId 'evt-implementation-pass'

    Assert-Equal -Name 'Implementation completion enters REVIEW' -Expected 'REVIEW' -Actual $Implementation.flow.stage
    Assert-Equal -Name 'REVIEW stage belongs to Sol' -Expected 'sol' -Actual $Implementation.flow.responsibleParty
    Assert-Equal -Name 'Implementation actor is persisted' -Expected 'luna-worker' -Actual $Implementation.flow.implementationActor

    $ImplementationReplay = Complete-TriTierRunImplementation `
        -ProjectPath $TestRoot `
        -RunId $PassRun.state.runId `
        -ImplementedBy 'luna-worker' `
        -Summary 'Ignored replay.' `
        -EventId 'evt-implementation-pass'

    Assert-Equal -Name 'Implementation event replay is idempotent' -Expected $true -Actual ([bool]$ImplementationReplay.replayed)
    Assert-Equal -Name 'Implementation replay preserves history' -Expected 2 -Actual @($ImplementationReplay.flow.transitionHistory).Count

    Assert-Throws -Name 'Luna cannot submit independent review' -Action {
        Submit-TriTierRunTaskReview `
            -ProjectPath $TestRoot `
            -RunId $PassRun.state.runId `
            -Reviewer 'luna-worker' `
            -Outcome 'PASS' `
            -Summary 'Invalid self-review.' `
            -EventId 'evt-invalid-review' |
            Out-Null
    }

    $PassedReview = Submit-TriTierRunTaskReview `
        -ProjectPath $TestRoot `
        -RunId $PassRun.state.runId `
        -Reviewer 'sol-adjudicator' `
        -Outcome 'PASS' `
        -Summary 'Independent review passed.' `
        -EvidenceIds @('E-REVIEW-01') `
        -EventId 'evt-review-pass'

    Assert-Equal -Name 'Passing review enters CONTINUE' -Expected 'CONTINUE' -Actual $PassedReview.flow.stage
    Assert-Equal -Name 'CONTINUE stage belongs to Terra' -Expected 'terra' -Actual $PassedReview.flow.responsibleParty
    Assert-Equal -Name 'Passing review permits advancement' -Expected $true -Actual ([bool]$PassedReview.flow.mayAdvance)
    Assert-Equal -Name 'Review actor is persisted' -Expected 'sol-adjudicator' -Actual $PassedReview.flow.reviewActor

    $ResumeState = Get-TriTierRunResumeData `
        -ProjectPath $TestRoot `
        -RunId $PassRun.state.runId

    Assert-Equal -Name 'Resume preserves CONTINUE stage' -Expected 'CONTINUE' -Actual $ResumeState.state.taskFlow.stage
    Assert-Equal -Name 'Resume preserves exact next action' -Expected $PassedReview.flow.nextAction -Actual $ResumeState.state.nextAction

    $Planning = Start-TriTierRunPlanning `
        -ProjectPath $TestRoot `
        -RunId $PassRun.state.runId `
        -StartedBy 'terra-manager' `
        -EventId 'evt-planning-next'

    Assert-Equal -Name 'Approved continuation returns to PLAN' -Expected 'PLAN' -Actual $Planning.flow.stage
    Assert-Equal -Name 'Planning clears current task' -Expected '' -Actual $Planning.flow.currentTask

    $SecondTask = Start-TriTierRunTask `
        -ProjectPath $TestRoot `
        -RunId $PassRun.state.runId `
        -TaskId 'TASK-02' `
        -SelectedBy 'terra-manager' `
        -ImplementationInstruction 'Luna must implement TASK-02.' `
        -EventId 'evt-task-two'

    Assert-Equal -Name 'Task selection enters IMPLEMENT' -Expected 'IMPLEMENT' -Actual $SecondTask.flow.stage
    Assert-Equal -Name 'New task is persisted' -Expected 'TASK-02' -Actual $SecondTask.state.currentTask

    $FailRun = New-TriTierRun `
        -ProjectPath $TestRoot `
        -RunId 'task-flow-fail' `
        -Title 'Task flow fail path' `
        -CurrentTask 'TASK-FAIL' `
        -NextAction 'Luna must implement TASK-FAIL.'

    Initialize-TriTierRunTaskFlow `
        -ProjectPath $TestRoot `
        -RunId $FailRun.state.runId `
        -EventId 'evt-init-fail' |
        Out-Null

    Complete-TriTierRunImplementation `
        -ProjectPath $TestRoot `
        -RunId $FailRun.state.runId `
        -ImplementedBy 'luna-worker' `
        -Summary 'Implemented failing task.' `
        -EventId 'evt-implementation-fail' |
        Out-Null

    $FailedReview = Submit-TriTierRunTaskReview `
        -ProjectPath $TestRoot `
        -RunId $FailRun.state.runId `
        -Reviewer 'sol-adjudicator' `
        -Outcome 'FAIL' `
        -Summary 'Independent review found a blocking defect.' `
        -EventId 'evt-review-fail'

    Assert-Equal -Name 'Failed review remains in REVIEW' -Expected 'REVIEW' -Actual $FailedReview.flow.stage
    Assert-Equal -Name 'Failed review blocks advancement' -Expected $false -Actual ([bool]$FailedReview.flow.mayAdvance)
    Assert-Equal -Name 'Failed review hands control to Terra' -Expected 'terra' -Actual $FailedReview.flow.responsibleParty
    Assert-Equal -Name 'Failed review outcome is durable' -Expected 'FAIL' -Actual $FailedReview.flow.reviewOutcome

    Assert-Throws -Name 'Failed review cannot be overwritten by later pass' -Action {
        Submit-TriTierRunTaskReview `
            -ProjectPath $TestRoot `
            -RunId $FailRun.state.runId `
            -Reviewer 'sol-adjudicator' `
            -Outcome 'PASS' `
            -Summary 'Invalid pass without repair.' `
            -EventId 'evt-review-bypass' |
            Out-Null
    }

    Assert-Throws -Name 'Failed review cannot skip directly to planning' -Action {
        Start-TriTierRunPlanning `
            -ProjectPath $TestRoot `
            -RunId $FailRun.state.runId `
            -StartedBy 'terra-manager' `
            -EventId 'evt-invalid-planning' |
            Out-Null
    }

    $PlanRun = New-TriTierRun `
        -ProjectPath $TestRoot `
        -RunId 'task-flow-plan' `
        -Title 'Task flow plan path'

    $PlanInitialized = Initialize-TriTierRunTaskFlow `
        -ProjectPath $TestRoot `
        -RunId $PlanRun.state.runId `
        -EventId 'evt-init-plan'

    Assert-Equal -Name 'Run without task initializes PLAN' -Expected 'PLAN' -Actual $PlanInitialized.flow.stage
    Assert-Equal -Name 'PLAN stage belongs to Terra' -Expected 'terra' -Actual $PlanInitialized.flow.responsibleParty

    $NextActionPath = Join-Path `
        $ResumeState.runDirectory `
        'state\next-action.txt'

    $StoredNextAction = (Get-Content $NextActionPath -Raw).Trim()

    $CurrentPassState = Get-TriTierRunState `
        -ProjectPath $TestRoot `
        -RunId $PassRun.state.runId

    Assert-Equal -Name 'Task flow synchronizes exact next-action file' -Expected $CurrentPassState.nextAction -Actual $StoredNextAction

    $Validation = Test-TriTierRunState `
        -ProjectPath $TestRoot `
        -RunId $PassRun.state.runId

    Assert-Equal -Name 'Task-flow run state remains valid' -Expected $true -Actual ([bool]$Validation.valid)

    Write-Host 'Task-flow transition tests passed.' -ForegroundColor Green
}
finally {
    if (Test-Path $TestRoot) {
        Remove-Item -LiteralPath $TestRoot -Recurse -Force
    }
}
