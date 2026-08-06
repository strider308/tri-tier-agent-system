Set-StrictMode -Version Latest

function Test-TriTierAnyPattern {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Text,

        [Parameter(Mandatory)]
        [string[]]$Patterns
    )

    foreach ($Pattern in $Patterns) {
        if ($Text -match $Pattern) {
            return $true
        }
    }

    return $false
}

function New-TriTierRiskResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet("R0", "R1", "R2", "R3", "R4")]
        [string]$RiskClass,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateSet("luna", "terra", "sol")]
        [string]$RecommendedTier,

        [Parameter(Mandatory)]
        [ValidateSet("E0", "E1", "E2", "E3", "E4", "E5")]
        [string]$MinimumEvidence,

        [Parameter(Mandatory)]
        [bool]$OwnerApprovalRequired,

        [Parameter(Mandatory)]
        [bool]$FreshReviewAfterRepair,

        [Parameter(Mandatory)]
        [int]$MinimumIndependentReviewers,

        [Parameter(Mandatory)]
        [string]$ReviewPolicy,

        [Parameter(Mandatory)]
        [string[]]$Reasons
    )

    [PSCustomObject]@{
        riskClass                  = $RiskClass
        name                       = $Name
        recommendedTier            = $RecommendedTier
        minimumEvidence            = $MinimumEvidence
        ownerApprovalRequired       = $OwnerApprovalRequired
        freshReviewAfterRepair      = $FreshReviewAfterRepair
        minimumIndependentReviewers = $MinimumIndependentReviewers
        reviewPolicy               = $ReviewPolicy
        reasons                    = $Reasons
    }
}

function Get-TriTierRiskClass {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Prompt = ""
    )

    $Text = $Prompt.ToLowerInvariant().Trim()

    $NegatedOwnerActionPatterns = @(
        "\bdo not\s+(deploy|merge|delete|drop|rotate|publish|charge)\b",
        "\bdon't\s+(deploy|merge|delete|drop|rotate|publish|charge)\b",
        "\bwithout\s+(deploying|merging|deleting|dropping|rotating|publishing|charging)\b",
        "\bnever\s+(deploy|merge|delete|drop|rotate|publish|charge)\b"
    )

    $OwnerControlledPatterns = @(
        "\bdeploy\b(?:\s+\S+){0,12}\s+(?:to\s+)?production\b",
        "\bmerge\s+(?:into|to)\s+(?:main|master|production)\b",
        "\bdelete\s+(?:production|customer|user)\s+data\b",
        "\bdrop\s+(?:the\s+)?(?:production\s+)?database\b",
        "\brotate\s+(?:production\s+)?secrets?\b",
        "\bpublish\s+(?:a\s+)?(?:release|package)\b",
        "\bcharge\s+(?:a\s+)?customer\b",
        "\bchange\s+(?:the\s+)?retention\s+policy\b"
    )

    $OwnerActionIsNegated = Test-TriTierAnyPattern `
        -Text $Text `
        -Patterns $NegatedOwnerActionPatterns

    if (-not $OwnerActionIsNegated -and (
        Test-TriTierAnyPattern -Text $Text -Patterns $OwnerControlledPatterns
    )) {
        return New-TriTierRiskResult `
            -RiskClass "R4" `
            -Name "Owner-controlled action" `
            -RecommendedTier "sol" `
            -MinimumEvidence "E5" `
            -OwnerApprovalRequired $true `
            -FreshReviewAfterRepair $true `
            -MinimumIndependentReviewers 2 `
            -ReviewPolicy "Prepare evidence, rollback, and exact action; stop before execution for owner approval." `
            -Reasons @("Production, destructive, release, billing, secret, or policy-control action detected.")
    }

    $HighRiskPatterns = @(
        "\bauthentication\b",
        "\bauthorization\b",
        "\btenant isolation\b",
        "\bcross-tenant\b",
        "\baccess control\b",
        "\bpermission boundary\b",
        "\bprivacy\b",
        "\bconsent\b",
        "\bretention\b",
        "\bencryption\b",
        "\bcredential\b",
        "\bsecret rotation\b",
        "\bdatabase migration\b",
        "\bproduction migration\b",
        "\bdestructive migration\b",
        "\bdata loss\b",
        "\bpayment\b",
        "\bbilling\b",
        "\bsecurity boundary\b",
        "\btrust boundary\b",
        "\bincident response\b"
    )

    if (Test-TriTierAnyPattern -Text $Text -Patterns $HighRiskPatterns) {
        return New-TriTierRiskResult `
            -RiskClass "R3" `
            -Name "High-risk system change" `
            -RecommendedTier "sol" `
            -MinimumEvidence "E4" `
            -OwnerApprovalRequired $false `
            -FreshReviewAfterRepair $true `
            -MinimumIndependentReviewers 2 `
            -ReviewPolicy "Require architecture or security review, runtime evidence, and fresh independent re-review." `
            -Reasons @("Security, privacy, authorization, migration, billing, or sensitive-data signal detected.")
    }

    $DocumentationPatterns = @(
        "^\s*(update|edit|write|create|fix|proofread|reformat)\s+.*\b(readme|documentation|docs|changelog|headings?|comments?)\b",
        "^\s*(proofread|reformat)\b"
    )

    $CodeChangePatterns = @(
        "\bimplement\b",
        "\bwrite code\b",
        "\bchange code\b",
        "\bmodify code\b",
        "\brefactor\b",
        "\badd feature\b",
        "\bendpoint\b",
        "\bschema\b",
        "\bdatabase\b"
    )

    $NegatedCodeChangePatterns = @(
        "\bdo not\s+(?:modify|change|edit|write|delete|refactor)\s+(?:the\s+)?(?:code|files?)\b",
        "\bdon't\s+(?:modify|change|edit|write|delete|refactor)\s+(?:the\s+)?(?:code|files?)\b",
        "\bwithout\s+(?:modifying|changing|editing|writing|deleting|refactoring)\s+(?:the\s+)?(?:code|files?)\b",
        "\bmake no\s+(?:code changes|changes to the code|file changes)\b"
    )

    $HasCodeChangeSignal = Test-TriTierAnyPattern `
        -Text $Text `
        -Patterns $CodeChangePatterns

    $CodeChangeIsNegated = Test-TriTierAnyPattern `
        -Text $Text `
        -Patterns $NegatedCodeChangePatterns

    $IsDocumentationOnly = (
        Test-TriTierAnyPattern -Text $Text -Patterns $DocumentationPatterns
    ) -and (
        -not $HasCodeChangeSignal -or $CodeChangeIsNegated
    )

    if ($IsDocumentationOnly) {
        return New-TriTierRiskResult `
            -RiskClass "R0" `
            -Name "Documentation-only change" `
            -RecommendedTier "luna" `
            -MinimumEvidence "E2" `
            -OwnerApprovalRequired $false `
            -FreshReviewAfterRepair $false `
            -MinimumIndependentReviewers 1 `
            -ReviewPolicy "Require scope check, content review, and repository verification." `
            -Reasons @("Documentation-only change without an implementation boundary detected.")
    }

    $LowRiskPatterns = @(
        "^\s*(format|reformat|rename|sort|deduplicate|normalize|proofread)\b",
        "\bfix spelling\b",
        "\bupdate headings\b",
        "\bread only\b",
        "\bread-only\b",
        "\bdo not modify\b",
        "\bdo not edit\b",
        "\bwithout modifying\b",
        "\bwithout editing\b",
        "\binspect only\b",
        "\breview only\b",
        "\banalyze only\b"
    )

    if (Test-TriTierAnyPattern -Text $Text -Patterns $LowRiskPatterns) {
        return New-TriTierRiskResult `
            -RiskClass "R1" `
            -Name "Isolated low-risk task" `
            -RecommendedTier "luna" `
            -MinimumEvidence "E2" `
            -OwnerApprovalRequired $false `
            -FreshReviewAfterRepair $false `
            -MinimumIndependentReviewers 1 `
            -ReviewPolicy "Require targeted validation and one independent review." `
            -Reasons @("Bounded, read-only, mechanical, or locally verifiable task signal detected.")
    }

    return New-TriTierRiskResult `
        -RiskClass "R2" `
        -Name "Normal product change" `
        -RecommendedTier "terra" `
        -MinimumEvidence "E3" `
        -OwnerApprovalRequired $false `
        -FreshReviewAfterRepair $true `
        -MinimumIndependentReviewers 1 `
        -ReviewPolicy "Require implementation, independent review, repair when needed, and integrated validation." `
        -Reasons @("Default product or repository change classification.")
}

Export-ModuleMember -Function Get-TriTierRiskClass
