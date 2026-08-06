Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$StateModulePath = Join-Path $PSScriptRoot 'State.psm1'
$FindingsModulePath = Join-Path $PSScriptRoot 'Findings.psm1'

foreach ($ModulePath in @($StateModulePath, $FindingsModulePath)) {
    if (-not (Test-Path $ModulePath -PathType Leaf)) {
        throw "Required Tri-Tier module is missing: $ModulePath"
    }

    Import-Module $ModulePath
}

function Get-TriTierRunFindingCollection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$RunId
    )

    $StateArguments = @{
        ProjectPath = $ProjectPath
        RunId = $RunId
    }

    $State = Get-TriTierRunState @StateArguments

    if ($null -eq $State.PSObject.Properties['findings']) {
        return @()
    }

    @($State.findings)
}

function Resolve-TriTierRunFinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Findings,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FindingId
    )

    $Matches = @(
        $Findings | Where-Object {
            [string]$_.findingId -eq $FindingId
        }
    )

    if ($Matches.Count -eq 0) {
        throw "Finding was not found in the run: $FindingId"
    }

    if ($Matches.Count -gt 1) {
        throw "Duplicate finding IDs exist in the run: $FindingId"
    }

    $Matches[0]
}

function Save-TriTierRunFindingLifecycle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$RunId,

        [Parameter(Mandatory)]
        [object[]]$Findings,

        [Parameter(Mandatory)]
        [object]$Finding
    )

    $Gate = Test-TriTierFindingGate -Findings $Findings

    $PersistenceArguments = @{
        ProjectPath = $ProjectPath
        RunId = $RunId
        Findings = $Findings
        FindingGate = $Gate
    }

    $State = Set-TriTierRunFindingState @PersistenceArguments

    [PSCustomObject][ordered]@{
        finding = $Finding
        gate = $Gate
        state = $State
    }
}

function Get-TriTierRunFinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$RunId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FindingId
    )

    $CollectionArguments = @{
        ProjectPath = $ProjectPath
        RunId = $RunId
    }

    $Findings = @(Get-TriTierRunFindingCollection @CollectionArguments)

    $ResolveArguments = @{
        Findings = $Findings
        FindingId = $FindingId
    }

    Resolve-TriTierRunFinding @ResolveArguments
}

function Add-TriTierRunFinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$RunId,

        [Parameter(Mandatory)]
        [ValidateSet('INFO', 'LOW', 'MEDIUM', 'HIGH', 'CRITICAL')]
        [string]$Severity,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Title,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Description,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Reviewer,

        [Parameter()]
        [string]$TaskId = '',

        [Parameter()]
        [string]$PhaseId = '',

        [Parameter()]
        [string[]]$EvidenceIds = @()
    )

    $CollectionArguments = @{
        ProjectPath = $ProjectPath
        RunId = $RunId
    }

    $Findings = @(Get-TriTierRunFindingCollection @CollectionArguments)

    $NewFindingArguments = @{
        Severity = $Severity
        Title = $Title
        Description = $Description
        Reviewer = $Reviewer
        TaskId = $TaskId
        PhaseId = $PhaseId
        EvidenceIds = $EvidenceIds
    }

    $Finding = New-TriTierFinding @NewFindingArguments
    $UpdatedFindings = @($Findings) + @($Finding)

    $SaveArguments = @{
        ProjectPath = $ProjectPath
        RunId = $RunId
        Findings = $UpdatedFindings
        Finding = $Finding
    }

    Save-TriTierRunFindingLifecycle @SaveArguments
}

function Repair-TriTierRunFinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$RunId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FindingId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RepairedBy,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RepairSummary,

        [Parameter()]
        [string[]]$EvidenceIds = @()
    )

    $CollectionArguments = @{
        ProjectPath = $ProjectPath
        RunId = $RunId
    }

    $Findings = @(Get-TriTierRunFindingCollection @CollectionArguments)

    $ResolveArguments = @{
        Findings = $Findings
        FindingId = $FindingId
    }

    $Finding = Resolve-TriTierRunFinding @ResolveArguments

    $RepairArguments = @{
        Finding = $Finding
        RepairedBy = $RepairedBy
        RepairSummary = $RepairSummary
        EvidenceIds = $EvidenceIds
    }

    $Finding = Repair-TriTierFinding @RepairArguments

    $SaveArguments = @{
        ProjectPath = $ProjectPath
        RunId = $RunId
        Findings = $Findings
        Finding = $Finding
    }

    Save-TriTierRunFindingLifecycle @SaveArguments
}

function Submit-TriTierRunFindingFreshReview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$RunId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FindingId,

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
        [string[]]$EvidenceIds = @()
    )

    $CollectionArguments = @{
        ProjectPath = $ProjectPath
        RunId = $RunId
    }

    $Findings = @(Get-TriTierRunFindingCollection @CollectionArguments)

    $ResolveArguments = @{
        Findings = $Findings
        FindingId = $FindingId
    }

    $Finding = Resolve-TriTierRunFinding @ResolveArguments

    $ReviewArguments = @{
        Finding = $Finding
        Reviewer = $Reviewer
        Outcome = $Outcome
        Summary = $Summary
        EvidenceIds = $EvidenceIds
    }

    $Finding = Submit-TriTierFindingFreshReview @ReviewArguments

    $SaveArguments = @{
        ProjectPath = $ProjectPath
        RunId = $RunId
        Findings = $Findings
        Finding = $Finding
    }

    Save-TriTierRunFindingLifecycle @SaveArguments
}

function Set-TriTierRunFindingDeferral {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath,

        [Parameter(Mandatory)]
        [string]$RunId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FindingId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Reason,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$OwnerApprovalRecord,

        [Parameter()]
        [switch]$OwnerApproved
    )

    $CollectionArguments = @{
        ProjectPath = $ProjectPath
        RunId = $RunId
    }

    $Findings = @(Get-TriTierRunFindingCollection @CollectionArguments)

    $ResolveArguments = @{
        Findings = $Findings
        FindingId = $FindingId
    }

    $Finding = Resolve-TriTierRunFinding @ResolveArguments

    $DeferralArguments = @{
        Finding = $Finding
        Reason = $Reason
        OwnerApprovalRecord = $OwnerApprovalRecord
        OwnerApproved = $OwnerApproved
    }

    $Finding = Set-TriTierFindingDeferral @DeferralArguments

    $SaveArguments = @{
        ProjectPath = $ProjectPath
        RunId = $RunId
        Findings = $Findings
        Finding = $Finding
    }

    Save-TriTierRunFindingLifecycle @SaveArguments
}

Export-ModuleMember -Function @(
    'Get-TriTierRunFinding',
    'Add-TriTierRunFinding',
    'Repair-TriTierRunFinding',
    'Submit-TriTierRunFindingFreshReview',
    'Set-TriTierRunFindingDeferral'
)
