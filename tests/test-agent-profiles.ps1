$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot = Split-Path $PSScriptRoot -Parent
$AgentProfilesPath = Join-Path $RepoRoot 'src\TriTier\AgentProfiles.psm1'
$AgentsRoot = Join-Path $RepoRoot 'agents'

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

function Get-TomlScalar {
    param(
        [Parameter(Mandatory)]
        [string]$Content,

        [Parameter(Mandatory)]
        [string]$Name
    )

    $TomlMatches = [regex]::Matches(
        $Content,
        '(?m)^' + [regex]::Escape($Name) + '\s*=\s*"([^"]*)"\s*$'
    )

    if ($TomlMatches.Count -ne 1) {
        throw "Expected one TOML scalar named $Name; found $($TomlMatches.Count)."
    }

    $TomlMatches[0].Groups[1].Value
}

$ExpectedProfiles = [ordered]@{
    'luna-router.toml' = @{
        name = 'luna_router'
        model = 'gpt-5.6-luna'
        effort = 'low'
        sandbox = 'read-only'
        snippets = @(
            'This profile is advisory and read-only.'
            'never owns a durable execution stage'
            'Do not override a persisted orchestration decision'
        )
    }
    'luna-worker.toml' = @{
        name = 'luna_worker'
        model = 'gpt-5.6-luna'
        effort = 'low'
        sandbox = 'workspace-write'
        snippets = @(
            'Durable execution stage authority: IMPLEMENT and REPAIR.'
            'Never perform REVIEW, FRESH_REVIEW, PHASE_REVIEW, or ADJUDICATE.'
            'Never approve your own implementation or repair'
        )
    }
    'terra-manager.toml' = @{
        name = 'terra_manager'
        model = 'gpt-5.6-terra'
        effort = 'medium'
        sandbox = 'workspace-write'
        snippets = @(
            'Durable execution stage authority: PLAN, CONTINUE, WAIT_EXTERNAL'
            'authorize the bounded repair cycle'
            'Never substitute Terra review for a Sol-required independent review'
        )
    }
    'terra-reviewer.toml' = @{
        name = 'terra_reviewer'
        model = 'gpt-5.6-terra'
        effort = 'medium'
        sandbox = 'read-only'
        snippets = @(
            'This profile is an advisory integration reviewer.'
            'does not satisfy REVIEW, FRESH_REVIEW, or PHASE_REVIEW'
            'Do not edit files or mutate durable run state.'
        )
    }
    'sol-architect.toml' = @{
        name = 'sol_architect'
        model = 'gpt-5.6-sol'
        effort = 'high'
        sandbox = 'read-only'
        snippets = @(
            'Durable execution stage authority: REVIEW and FRESH_REVIEW.'
            'reproduce at least one load-bearing claim'
            'Never edit the implementation under review'
        )
    }
    'sol-adjudicator.toml' = @{
        name = 'sol_adjudicator'
        model = 'gpt-5.6-sol'
        effort = 'high'
        sandbox = 'read-only'
        snippets = @(
            'Durable execution stage authority: ADJUDICATE, PHASE_REVIEW, and STOP.'
            'choose REPAIR_AGAIN, OWNER_DECISION, or ABORT_FOR_SAFETY'
            'Never edit files or manufacture approval.'
        )
    }
}

$SeenNames = @()

foreach ($Entry in $ExpectedProfiles.GetEnumerator()) {
    $Path = Join-Path $AgentsRoot $Entry.Key

    Assert-True `
        -Name "$($Entry.Key) exists" `
        -Value (Test-Path -LiteralPath $Path -PathType Leaf)

    $Content = [System.IO.File]::ReadAllText($Path)
    $InstructionMatches = [regex]::Matches(
        $Content,
        'developer_instructions\s*=\s*"""(?<body>[\s\S]*?)"""'
    )

    Assert-Equal `
        -Name "$($Entry.Key) has one instruction block" `
        -Expected 1 `
        -Actual $InstructionMatches.Count
    Assert-Equal `
        -Name "$($Entry.Key) has one role-contract start marker" `
        -Expected 1 `
        -Actual ([regex]::Matches(
            $Content,
            '\[BEGIN DURABLE EXECUTION ROLE CONTRACT\]'
        ).Count)
    Assert-Equal `
        -Name "$($Entry.Key) has one role-contract end marker" `
        -Expected 1 `
        -Actual ([regex]::Matches(
            $Content,
            '\[END DURABLE EXECUTION ROLE CONTRACT\]'
        ).Count)

    $NameValue = Get-TomlScalar -Content $Content -Name 'name'
    $SeenNames += $NameValue

    Assert-Equal `
        -Name "$($Entry.Key) name" `
        -Expected $Entry.Value.name `
        -Actual $NameValue
    Assert-Equal `
        -Name "$($Entry.Key) model" `
        -Expected $Entry.Value.model `
        -Actual (Get-TomlScalar -Content $Content -Name 'model')
    Assert-Equal `
        -Name "$($Entry.Key) reasoning effort" `
        -Expected $Entry.Value.effort `
        -Actual (Get-TomlScalar -Content $Content -Name 'model_reasoning_effort')
    Assert-Equal `
        -Name "$($Entry.Key) sandbox" `
        -Expected $Entry.Value.sandbox `
        -Actual (Get-TomlScalar -Content $Content -Name 'sandbox_mode')

    $InstructionBody = $InstructionMatches[0].Groups['body'].Value

    foreach ($Snippet in $Entry.Value.snippets) {
        Assert-True `
            -Name "$($Entry.Key) contains role rule: $Snippet" `
            -Value $InstructionBody.Contains($Snippet)
    }
}

Assert-Equal `
    -Name 'Agent profile names are unique' `
    -Expected $SeenNames.Count `
    -Actual @($SeenNames | Sort-Object -Unique).Count

$Catalog = @(Get-TriTierAgentProfileCatalog)

Assert-Equal `
    -Name 'Runtime catalog contains six profiles' `
    -Expected 6 `
    -Actual $Catalog.Count

foreach ($Entry in $ExpectedProfiles.GetEnumerator()) {
    $Spec = Get-TriTierAgentProfileSpec -Name $Entry.Value.name

    Assert-Equal `
        -Name "$($Entry.Value.name) catalog file" `
        -Expected $Entry.Key `
        -Actual $Spec.fileName
    Assert-Equal `
        -Name "$($Entry.Value.name) catalog sandbox" `
        -Expected $Entry.Value.sandbox `
        -Actual $Spec.sandboxMode
}

$RoutingCases = @(
    @{ Stage = 'PLAN'; Party = 'terra'; Profile = 'terra_manager' }
    @{ Stage = 'IMPLEMENT'; Party = 'luna'; Profile = 'luna_worker' }
    @{ Stage = 'REVIEW'; Party = 'sol'; Profile = 'sol_architect' }
    @{ Stage = 'REVIEW'; Party = 'terra'; Profile = 'terra_manager' }
    @{ Stage = 'REPAIR'; Party = 'luna'; Profile = 'luna_worker' }
    @{ Stage = 'FRESH_REVIEW'; Party = 'sol'; Profile = 'sol_architect' }
    @{ Stage = 'ADJUDICATE'; Party = 'sol'; Profile = 'sol_adjudicator' }
    @{ Stage = 'CONTINUE'; Party = 'terra'; Profile = 'terra_manager' }
    @{ Stage = 'PHASE_REVIEW'; Party = 'sol'; Profile = 'sol_adjudicator' }
    @{ Stage = 'WAIT_EXTERNAL'; Party = 'terra'; Profile = 'terra_manager' }
    @{ Stage = 'STOP'; Party = 'sol'; Profile = 'sol_adjudicator' }
)

foreach ($Case in $RoutingCases) {
    $ResolvedProfile = Resolve-TriTierAgentProfile `
        -Decision ([PSCustomObject]@{
            stage = $Case.Stage
            responsibleParty = $Case.Party
        })

    Assert-Equal `
        -Name "$($Case.Stage)/$($Case.Party) profile routing" `
        -Expected $Case.Profile `
        -Actual $ResolvedProfile.name
}

$OwnerProfile = Resolve-TriTierAgentProfile `
    -Decision ([PSCustomObject]@{
        stage = 'OWNER_DECISION'
        responsibleParty = 'owner'
    })

Assert-Equal `
    -Name 'Owner decision resolves no agent profile' `
    -Expected $null `
    -Actual $OwnerProfile

Assert-Equal `
    -Name 'Luna router owns no durable stage' `
    -Expected 0 `
    -Actual @((Get-TriTierAgentProfileSpec -Name 'luna_router').runtimeStages).Count
Assert-Equal `
    -Name 'Terra reviewer owns no Sol gate' `
    -Expected 0 `
    -Actual @((Get-TriTierAgentProfileSpec -Name 'terra_reviewer').runtimeStages).Count
$SolArchitectSpec = Get-TriTierAgentProfileSpec -Name 'sol_architect'
$SolAdjudicatorSpec = Get-TriTierAgentProfileSpec -Name 'sol_adjudicator'

Assert-Equal `
    -Name 'Sol architect remains read-only' `
    -Expected $false `
    -Actual ([bool]$SolArchitectSpec.canWrite)
Assert-Equal `
    -Name 'Sol adjudicator remains read-only' `
    -Expected $false `
    -Actual ([bool]$SolAdjudicatorSpec.canWrite)

Write-Host ''
Write-Host 'Agent profile authority tests passed.' -ForegroundColor Green
