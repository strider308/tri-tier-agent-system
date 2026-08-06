Set-StrictMode -Version Latest

$script:FindingSeverities = @(
    "INFO",
    "LOW",
    "MEDIUM",
    "HIGH",
    "CRITICAL"
)

$script:FindingStatuses = @(
    "OPEN",
    "REPAIRED_PENDING_REVIEW",
    "RESOLVED",
    "DEFERRED"
)

function Get-TriTierFindingSeverityInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet("INFO", "LOW", "MEDIUM", "HIGH", "CRITICAL")]
        [string]$Severity
    )

    $Definitions = @{
        INFO = @{
            Rank                = 0
            Name                = "Informational"
            BlocksTask          = $false
            BlocksPhase         = $false
            BlocksRun           = $false
            RequiresFreshReview = $false
            OwnerDeferrable     = $true
        }
        LOW = @{
            Rank                = 1
            Name                = "Low"
            BlocksTask          = $false
            BlocksPhase         = $false
            BlocksRun           = $false
            RequiresFreshReview = $false
            OwnerDeferrable     = $true
        }
        MEDIUM = @{
            Rank                = 2
            Name                = "Medium"
            BlocksTask          = $true
            BlocksPhase         = $false
            BlocksRun           = $false
            RequiresFreshReview = $true
            OwnerDeferrable     = $true
        }
        HIGH = @{
            Rank                = 3
            Name                = "High"
            BlocksTask          = $true
            BlocksPhase         = $true
            BlocksRun           = $false
            RequiresFreshReview = $true
            OwnerDeferrable     = $true
        }
        CRITICAL = @{
            Rank                = 4
            Name                = "Critical"
            BlocksTask          = $true
            BlocksPhase         = $true
            BlocksRun           = $true
            RequiresFreshReview = $true
            OwnerDeferrable     = $false
        }
    }

    $Definition = $Definitions[$Severity]

    [PSCustomObject]@{
        severity            = $Severity
        rank                = $Definition.Rank
        name                = $Definition.Name
        blocksTask          = $Definition.BlocksTask
        blocksPhase         = $Definition.BlocksPhase
        blocksRun           = $Definition.BlocksRun
        requiresFreshReview = $Definition.RequiresFreshReview
        ownerDeferrable     = $Definition.OwnerDeferrable
    }
}

function New-TriTierFinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet("INFO", "LOW", "MEDIUM", "HIGH", "CRITICAL")]
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
        [string]$TaskId = "",

        [Parameter()]
        [string]$PhaseId = "",

        [Parameter()]
        [string[]]$EvidenceIds = @()
    )

    $SeverityInfo = Get-TriTierFindingSeverityInfo `
        -Severity $Severity

    [PSCustomObject][ordered]@{
        findingId            = [guid]::NewGuid().ToString()
        createdUtc           = [DateTime]::UtcNow.ToString("o")
        updatedUtc           = [DateTime]::UtcNow.ToString("o")
        severity             = $Severity
        status               = "OPEN"
        title                = $Title.Trim()
        description          = $Description.Trim()
        reviewer             = $Reviewer.Trim()
        taskId               = $TaskId.Trim()
        phaseId              = $PhaseId.Trim()
        evidenceIds          = @($EvidenceIds)
        requiresFreshReview  = $SeverityInfo.requiresFreshReview
        repairedUtc          = $null
        repairedBy           = ""
        repairSummary        = ""
        repairEvidenceIds    = @()
        freshReviewStatus    = if (
            $SeverityInfo.requiresFreshReview
        ) {
            "NOT_STARTED"
        }
        else {
            "NOT_REQUIRED"
        }
        freshReviewer        = ""
        freshReviewUtc       = $null
        freshReviewSummary   = ""
        reviewCycle          = 0
        reviewHistory        = @()
        deferredUtc          = $null
        deferralReason       = ""
        ownerApprovalRecord  = ""
    }
}

function Repair-TriTierFinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Finding,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RepairedBy,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RepairSummary,

        [Parameter()]
        [string[]]$EvidenceIds = @()
    )

    if ($Finding.status -ne "OPEN") {
        throw "Only OPEN findings can be repaired. Current status: $($Finding.status)"
    }

    $SeverityInfo = Get-TriTierFindingSeverityInfo `
        -Severity $Finding.severity

    $Finding.repairedUtc = [DateTime]::UtcNow.ToString("o")
    $Finding.repairedBy = $RepairedBy.Trim()
    $Finding.repairSummary = $RepairSummary.Trim()
    $Finding.repairEvidenceIds = @($EvidenceIds)
    $Finding.updatedUtc = [DateTime]::UtcNow.ToString("o")

    if ($SeverityInfo.requiresFreshReview) {
        $Finding.status = "REPAIRED_PENDING_REVIEW"
        $Finding.freshReviewStatus = "PENDING"
    }

    if (-not $SeverityInfo.requiresFreshReview) {
        $Finding.status = "RESOLVED"
        $Finding.freshReviewStatus = "NOT_REQUIRED"
    }

    $Finding
}

function Submit-TriTierFindingFreshReview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Finding,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Reviewer,

        [Parameter(Mandatory)]
        [ValidateSet("PASS", "FAIL")]
        [string]$Outcome,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Summary,

        [Parameter()]
        [string[]]$EvidenceIds = @()
    )

    if ($Finding.status -ne "REPAIRED_PENDING_REVIEW") {
        throw "Finding is not awaiting fresh review. Current status: $($Finding.status)"
    }

    if (
        $Reviewer.Trim().ToLowerInvariant() -eq
        $Finding.repairedBy.Trim().ToLowerInvariant()
    ) {
        throw "Fresh review must be performed by someone other than the repair actor."
    }

    $Now = [DateTime]::UtcNow.ToString("o")
    $Finding.reviewCycle = [int]$Finding.reviewCycle + 1

    $ReviewRecord = [PSCustomObject][ordered]@{
        reviewCycle = $Finding.reviewCycle
        reviewedUtc = $Now
        reviewer     = $Reviewer.Trim()
        outcome      = $Outcome
        summary      = $Summary.Trim()
        evidenceIds  = @($EvidenceIds)
    }

    $History = @($Finding.reviewHistory)
    $History += $ReviewRecord

    $Finding.reviewHistory = $History
    $Finding.freshReviewer = $Reviewer.Trim()
    $Finding.freshReviewUtc = $Now
    $Finding.freshReviewSummary = $Summary.Trim()
    $Finding.updatedUtc = $Now

    if ($Outcome -eq "PASS") {
        $Finding.status = "RESOLVED"
        $Finding.freshReviewStatus = "PASSED"
    }

    if ($Outcome -eq "FAIL") {
        $Finding.status = "OPEN"
        $Finding.freshReviewStatus = "FAILED"
    }

    $Finding
}

function Set-TriTierFindingDeferral {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Finding,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Reason,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$OwnerApprovalRecord,

        [Parameter()]
        [switch]$OwnerApproved
    )

    if ($Finding.status -notin @(
        "OPEN",
        "REPAIRED_PENDING_REVIEW"
    )) {
        throw "Only unresolved findings can be deferred."
    }

    $SeverityInfo = Get-TriTierFindingSeverityInfo `
        -Severity $Finding.severity

    if (-not $SeverityInfo.ownerDeferrable) {
        throw "$($Finding.severity) findings cannot be deferred."
    }

    if (-not $OwnerApproved) {
        throw "Deferring a finding requires explicit owner approval."
    }

    $Finding.status = "DEFERRED"
    $Finding.deferredUtc = [DateTime]::UtcNow.ToString("o")
    $Finding.deferralReason = $Reason.Trim()
    $Finding.ownerApprovalRecord = $OwnerApprovalRecord.Trim()
    $Finding.updatedUtc = [DateTime]::UtcNow.ToString("o")

    $Finding
}

function Test-TriTierFindingGate {
    [CmdletBinding()]
    param(
        [Parameter()]
        [object[]]$Findings = @()
    )

    $ActiveFindings = @(
        $Findings |
            Where-Object {
                $_.status -in @(
                    "OPEN",
                    "REPAIRED_PENDING_REVIEW"
                )
            }
    )

    $TaskBlocked = $false
    $PhaseBlocked = $false
    $RunBlocked = $false
    $RequiresRepair = $false
    $RequiresFreshReview = $false

    $Counts = [ordered]@{
        INFO     = 0
        LOW      = 0
        MEDIUM   = 0
        HIGH     = 0
        CRITICAL = 0
    }

    foreach ($Finding in $ActiveFindings) {
        $SeverityInfo = Get-TriTierFindingSeverityInfo `
            -Severity $Finding.severity

        $Counts[$Finding.severity]++

        if ($SeverityInfo.blocksTask) {
            $TaskBlocked = $true
        }

        if ($SeverityInfo.blocksPhase) {
            $PhaseBlocked = $true
        }

        if ($SeverityInfo.blocksRun) {
            $RunBlocked = $true
        }

        if (
            $Finding.status -eq "OPEN" -and
            $SeverityInfo.rank -ge 1
        ) {
            $RequiresRepair = $true
        }

        if ($Finding.status -eq "REPAIRED_PENDING_REVIEW") {
            $RequiresFreshReview = $true
        }
    }

    $OrderedCandidates = @(
        $ActiveFindings |
            Sort-Object `
                @{
                    Expression = {
                        (
                            Get-TriTierFindingSeverityInfo `
                                -Severity $_.severity
                        ).rank
                    }
                    Descending = $true
                },
                @{
                    Expression = {
                        if (
                            $_.status -eq
                            "REPAIRED_PENDING_REVIEW"
                        ) {
                            0
                        }
                        else {
                            1
                        }
                    }
                    Descending = $false
                },
                createdUtc
    )

    $NextAction = "Proceed to the next task or phase gate."

    if ($OrderedCandidates.Count -gt 0) {
        $PriorityFinding = $OrderedCandidates[0]

        if (
            $PriorityFinding.status -eq
            "REPAIRED_PENDING_REVIEW"
        ) {
            $NextAction =
                "Assign a fresh independent review for finding " +
                "$($PriorityFinding.findingId): " +
                "$($PriorityFinding.title)."
        }

        if ($PriorityFinding.status -eq "OPEN") {
            if ($PriorityFinding.severity -eq "INFO") {
                $NextAction =
                    "Record or acknowledge informational finding " +
                    "$($PriorityFinding.findingId): " +
                    "$($PriorityFinding.title)."
            }

            if ($PriorityFinding.severity -ne "INFO") {
                $NextAction =
                    "Repair finding $($PriorityFinding.findingId): " +
                    "$($PriorityFinding.title)."
            }
        }
    }

    [PSCustomObject]@{
        passed                   = -not $TaskBlocked
        taskBlocked              = $TaskBlocked
        phaseBlocked             = $PhaseBlocked
        runBlocked               = $RunBlocked
        requiresRepair           = $RequiresRepair
        requiresFreshReview      = $RequiresFreshReview
        activeFindingCount       = $ActiveFindings.Count
        activeFindingsBySeverity = [PSCustomObject]$Counts
        nextAction               = $NextAction
    }
}

Export-ModuleMember -Function @(
    "Get-TriTierFindingSeverityInfo",
    "New-TriTierFinding",
    "Repair-TriTierFinding",
    "Submit-TriTierFindingFreshReview",
    "Set-TriTierFindingDeferral",
    "Test-TriTierFindingGate"
)
