Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepositoryRoot = Split-Path $PSScriptRoot -Parent
$CliPath = Join-Path $RepositoryRoot 'src\tri-agent.ps1'
$PwshPath = (Get-Command pwsh -ErrorAction Stop).Source

function Invoke-EvidenceChild {
    $Output = @(
        & $PwshPath -NoLogo -NoProfile -File $CliPath evidence -RiskClass R2 -EvidenceLevel E3 -Json 2>&1 |
            ForEach-Object { [string]$_ }
    )

    $ExitCode = $LASTEXITCODE
    $Text = $Output -join [Environment]::NewLine
    $Parsed = $null

    try { $Parsed = $Text | ConvertFrom-Json -Depth 20 } catch { }

    [PSCustomObject]@{
        exitCode = $ExitCode
        parsed = $Parsed
        text = $Text
        valid = (
            $ExitCode -eq 0 -and
            $null -ne $Parsed -and
            [bool]$Parsed.sufficient -and
            $Text -notmatch 'not recognized|ParserError|Exception:'
        )
    }
}

$Failures = [System.Collections.Generic.List[string]]::new()

1..50 | ForEach-Object {
    $Result = Invoke-EvidenceChild
    if (-not $Result.valid) {
        $Failures.Add("fresh process `$($_): $($Result.text)")
    }
}

1..5 | ForEach-Object {
    $SameOutput = @(& $CliPath evidence -RiskClass R2 -EvidenceLevel E3 -Json | ForEach-Object { [string]$_ })
    $Result = ($SameOutput -join [Environment]::NewLine) | ConvertFrom-Json -Depth 20
    if (-not $Result.sufficient) {
        $Failures.Add("same process $($_)")
    }
}

$ModulePath = Join-Path $RepositoryRoot 'src\TriTier\Evidence.psm1'
$Before = Import-Module $ModulePath -PassThru
$BeforePath = [string]$Before.Path
$BeforeExport = [bool]$Before.ExportedFunctions.ContainsKey('Test-TriTierEvidenceSufficiency')
$PreservationOutput = @(& $CliPath evidence -RiskClass R2 -EvidenceLevel E3 -Json | ForEach-Object { [string]$_ })
$PreservationResult = ($PreservationOutput -join [Environment]::NewLine) | ConvertFrom-Json -Depth 20
$After = Get-Module | Where-Object { $_.Path -eq $BeforePath } | Select-Object -First 1
$AfterExport = $null -ne $After -and $After.ExportedFunctions.ContainsKey('Test-TriTierEvidenceSufficiency')
if (-not $BeforeExport -or -not $AfterExport -or -not $PreservationResult.sufficient) {
    $Failures.Add('already loaded evidence dependency was not preserved')
}

$ModuleRoot = Join-Path $RepositoryRoot 'src\TriTier'
foreach ($Order in @(
    @('State.psm1','PhaseGate.psm1','Evidence.psm1')
    @('Evidence.psm1','PhaseGate.psm1','State.psm1')
    @('PhaseGate.psm1','State.psm1','Evidence.psm1')
)) {
    $Preload = $Order | ForEach-Object { Join-Path $ModuleRoot $_ }
    $Imports = $Preload | ForEach-Object {
        "Import-Module '$($_.Replace("'", "''"))'"
    }
    $ImportCommand = ($Imports + @(
        "if (-not (Get-Command Test-TriTierEvidenceSufficiency -ErrorAction SilentlyContinue)) { exit 1 }; 'ok'"
    )) -join '; '
    $ImportOutput = @(& $PwshPath -NoLogo -NoProfile -Command $ImportCommand 2>&1 | ForEach-Object { [string]$_ })
    if ($LASTEXITCODE -ne 0 -or ($ImportOutput -join ' ') -notmatch 'ok') {
        $Failures.Add("import order $($Order -join ',') exit=$LASTEXITCODE text=$($ImportOutput -join ' ')")
    }
}

$VersionOutput = @(& $PwshPath -NoLogo -NoProfile -File $CliPath version 2>&1 | ForEach-Object { [string]$_ })
if ($LASTEXITCODE -ne 0 -or ($VersionOutput -join ' ') -notmatch '0\.10\.0-alpha') {
    $Failures.Add('version command regression')
}

if ($Failures.Count -gt 0) {
    throw "CLI evidence reliability failed: $($Failures -join ' | ')"
}

Write-Host 'CLI evidence reliability passed: 50/50 fresh processes.' -ForegroundColor Green
