Set-StrictMode -Version Latest

function Get-TriTierEvidenceLevelInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet("E0", "E1", "E2", "E3", "E4", "E5")]
        [string]$EvidenceLevel
    )

    $Definitions = @{
        E0 = @{
            Rank = 0
            Name = "Unsupported statement"
            Description = "A claim without inspectable supporting evidence."
        }
        E1 = @{
            Rank = 1
            Name = "Code inspection"
            Description = "Evidence based on reading source, configuration, or documentation."
        }
        E2 = @{
            Rank = 2
            Name = "Static or targeted validation"
            Description = "Static analysis, parsing, linting, type checking, or a targeted test."
        }
        E3 = @{
            Rank = 3
            Name = "Integrated validation"
            Description = "A relevant integrated test, build, or affected test-suite result."
        }
        E4 = @{
            Rank = 4
            Name = "Runtime verification"
            Description = "Browser, runtime, manual, staging, or equivalent behavioural verification."
        }
        E5 = @{
            Rank = 5
            Name = "Independent reproduction"
            Description = "A separate reviewer independently reproduced the relevant result."
        }
    }

    $Definition = $Definitions[$EvidenceLevel]

    [PSCustomObject]@{
        level = $EvidenceLevel
        rank = $Definition.Rank
        name = $Definition.Name
        description = $Definition.Description
    }
}

function Get-TriTierMinimumEvidenceForRisk {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet("R0", "R1", "R2", "R3", "R4")]
        [string]$RiskClass
    )

    switch ($RiskClass) {
        "R0" { return "E2" }
        "R1" { return "E2" }
        "R2" { return "E3" }
        "R3" { return "E4" }
        "R4" { return "E5" }
    }
}

function Test-TriTierEvidenceSufficiency {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet("R0", "R1", "R2", "R3", "R4")]
        [string]$RiskClass,

        [Parameter(Mandatory)]
        [ValidateSet("E0", "E1", "E2", "E3", "E4", "E5")]
        [string]$EvidenceLevel,

        [Parameter()]
        [switch]$IndependentlyReproduced
    )

    $RequiredLevel = Get-TriTierMinimumEvidenceForRisk -RiskClass $RiskClass
    $Required = Get-TriTierEvidenceLevelInfo -EvidenceLevel $RequiredLevel
    $Actual = Get-TriTierEvidenceLevelInfo -EvidenceLevel $EvidenceLevel

    $Reasons = @()
    $Sufficient = $Actual.rank -ge $Required.rank

    if (-not $Sufficient) {
        $Reasons += "Actual evidence $EvidenceLevel is below required evidence $RequiredLevel."
    }

    if ($EvidenceLevel -eq "E5" -and -not $IndependentlyReproduced) {
        $Sufficient = $false
        $Reasons += "E5 requires independent reproduction by a separate reviewer."
    }

    if ($RiskClass -eq "R4" -and -not $IndependentlyReproduced) {
        $Sufficient = $false
        $Reasons += "R4 requires independently reproduced E5 evidence."
    }

    if ($Sufficient) {
        $Reasons += "Evidence meets the minimum requirement for $RiskClass."
    }

    [PSCustomObject]@{
        sufficient = $Sufficient
        riskClass = $RiskClass
        requiredEvidence = $RequiredLevel
        actualEvidence = $EvidenceLevel
        independentlyReproduced = [bool]$IndependentlyReproduced
        reasons = $Reasons
    }
}

function New-TriTierEvidenceRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet("E0", "E1", "E2", "E3", "E4", "E5")]
        [string]$EvidenceLevel,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Claim,

        [Parameter()]
        [string]$Source = "",

        [Parameter()]
        [string]$Command = "",

        [Parameter()]
        [string]$Result = "",

        [Parameter()]
        [string]$Reviewer = "",

        [Parameter()]
        [switch]$IndependentlyReproduced
    )

    if ($EvidenceLevel -ne "E0" -and [string]::IsNullOrWhiteSpace($Source)) {
        throw "$EvidenceLevel evidence requires an inspectable source."
    }

    if ($EvidenceLevel -eq "E5") {
        if (-not $IndependentlyReproduced) {
            throw "E5 evidence must be independently reproduced."
        }

        if ([string]::IsNullOrWhiteSpace($Reviewer)) {
            throw "E5 evidence requires the independent reviewer identity or role."
        }
    }

    [PSCustomObject]@{
        evidenceId = [guid]::NewGuid().ToString()
        timestampUtc = [DateTime]::UtcNow.ToString("o")
        level = $EvidenceLevel
        claim = $Claim
        source = $Source
        command = $Command
        result = $Result
        reviewer = $Reviewer
        independentlyReproduced = [bool]$IndependentlyReproduced
    }
}

Export-ModuleMember -Function @(
    "Get-TriTierEvidenceLevelInfo",
    "Get-TriTierMinimumEvidenceForRisk",
    "Test-TriTierEvidenceSufficiency",
    "New-TriTierEvidenceRecord"
)
