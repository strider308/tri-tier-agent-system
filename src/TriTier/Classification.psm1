Set-StrictMode -Version Latest

<#
.SYNOPSIS
Classifies Tri-Tier tasks and recommends Luna, Terra, or Sol.

.DESCRIPTION
This module contains the initial routing logic extracted from the original
local Tri-Tier Agent System implementation.

The classifier is advisory. Security boundaries, owner-controlled actions,
project authority documents, and explicit user instructions take precedence.
#>

function Get-TriTierTaskClassification {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Prompt = ""
    )

    $text = $Prompt.ToLowerInvariant()

    $solTerms = @(
        "security", "cybersecurity", "privacy", "authorization",
        "authentication", "tenant isolation", "cross-tenant",
        "credential", "secret rotation", "encryption",
        "production migration", "database migration", "destructive",
        "data loss", "incident response", "access control",
        "permission boundary", "trust boundary", "system architecture",
        "repository-wide", "rollback", "retention policy",
        "consent architecture"
    )

    $lunaTerms = @(
        "format", "reformat", "rename", "classify", "extract",
        "convert", "transform", "tag", "sort", "deduplicate",
        "generate fixtures", "fix spelling", "proofread",
        "normalize", "update headings"
    )

    $implementationTerms = @(
        "implement", "build", "create", "modify", "change",
        "fix", "refactor", "delete", "add feature", "write code",
        "edit file", "update file", "install", "deploy", "migrate"
    )

    $advisoryTerms = @(
        "explain", "analyze", "review", "summarize", "compare",
        "research", "tell me", "what is", "how does", "inspect",
        "identify"
    )

    # Explicit non-modification intent must be recognized before raw
    # implementation keywords such as "modify", "change", and "edit".
    # Otherwise phrases like "do not modify files" are misclassified as
    # implementation and read_only is unreachable.
    $readOnlyTerms = @(
        "read only", "read-only",
        "without editing", "without modifying", "without changing",
        "without making changes", "without making edits",
        "do not edit", "do not modify", "do not change",
        "make no edits", "make no changes",
        "inspect only", "review only", "analyze only",
        "only inspect", "only read",
        "report only", "findings only"
    )

    $recommendedTier = "terra"
    $riskLevel = "medium"
    $reasons = @("Default integrated task route")

    foreach ($term in $solTerms) {
        if ($text.Contains($term)) {
            $recommendedTier = "sol"
            $riskLevel = "high"
            $reasons = @(
                "High-impact, architectural, security, privacy, authorization, production, or irreversible signal detected"
            )
            break
        }
    }

    if ($recommendedTier -ne "sol") {
        $trimmed = $text.TrimStart()
        foreach ($term in $lunaTerms) {
            if ($trimmed.StartsWith($term)) {
                $recommendedTier = "luna"
                $riskLevel = "low"
                $reasons = @("Bounded and mechanically verifiable task signal detected")
                break
            }
        }
    }

    $taskMode = "unknown"

    foreach ($term in $readOnlyTerms) {
        if ($text.Contains($term)) {
            $taskMode = "read_only"
            break
        }
    }

    if ($taskMode -eq "unknown") {
        foreach ($term in $implementationTerms) {
            if ($text.Contains($term)) {
                $taskMode = "implementation"
                break
            }
        }
    }

    if ($taskMode -eq "unknown") {
        foreach ($term in $advisoryTerms) {
            if ($text.Contains($term)) {
                $taskMode = "advisory"
                break
            }
        }
    }

    return [pscustomobject]@{
        recommendedTier = $recommendedTier
        riskLevel        = $riskLevel
        taskMode         = $taskMode
        reasons          = $reasons
    }
}

Export-ModuleMember -Function Get-TriTierTaskClassification
