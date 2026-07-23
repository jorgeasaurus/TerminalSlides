[CmdletBinding()]
param(
    [string[]]$TestPath = @('Tests'),
    [string]$TestResultPath = 'build/TestResults/TestResults.xml',
    [switch]$SkipScriptAnalyzer
)

$ErrorActionPreference = 'Stop'
$pesterVersion = [version]'5.8.0'
$scriptAnalyzerVersion = [version]'1.25.0'

function Import-ExactModule {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][version]$Version
    )

    $installedModule = Get-Module -ListAvailable -Name $Name |
        Where-Object Version -eq $Version |
        Select-Object -First 1
    if (-not $installedModule) {
        Write-Host "Installing $Name $Version..." -ForegroundColor Yellow
        Install-Module -Name $Name -RequiredVersion $Version -Repository PSGallery `
            -Scope CurrentUser -Force -AllowClobber
    }

    Get-Module -Name $Name |
        Where-Object Version -ne $Version |
        Remove-Module -Force
    Import-Module -Name $Name -RequiredVersion $Version -Force
}

function Resolve-RepositoryPath {
    param([Parameter(Mandatory)][string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
    return Join-Path $PSScriptRoot $Path
}

if ($env:TERMINALSLIDES_RUN_TMUX_TESTS -eq '1' -and
    -not (Get-Command tmux -ErrorAction SilentlyContinue)) {
    throw 'TERMINALSLIDES_RUN_TMUX_TESTS=1 requires tmux to be installed and available on PATH.'
}

if (-not $SkipScriptAnalyzer) {
    Import-ExactModule -Name PSScriptAnalyzer -Version $scriptAnalyzerVersion
    $analysisPaths = @(
        'Classes', 'Layouts', 'Private', 'Public', 'Renderers', 'Themes', 'Tests',
        'TestInfrastructure', 'build.ps1', 'TerminalSlides.psm1'
    )
    $analysisIssues = foreach ($analysisPath in $analysisPaths) {
        $resolvedAnalysisPath = Resolve-RepositoryPath -Path $analysisPath
        if (Test-Path -LiteralPath $resolvedAnalysisPath -PathType Container) {
            Invoke-ScriptAnalyzer -Path $resolvedAnalysisPath -Recurse -Severity Error
        }
        elseif (Test-Path -LiteralPath $resolvedAnalysisPath -PathType Leaf) {
            Invoke-ScriptAnalyzer -Path $resolvedAnalysisPath -Severity Error
        }
    }
    if ($analysisIssues) {
        $analysisIssues | Format-Table RuleName, ScriptName, Line, Message -Wrap |
            Out-String | Write-Host
        throw "PSScriptAnalyzer reported $(@($analysisIssues).Count) error(s)."
    }
}

Import-ExactModule -Name Pester -Version $pesterVersion
$resolvedTestPaths = @($TestPath | ForEach-Object { Resolve-RepositoryPath -Path $_ })
$resolvedTestResultPath = Resolve-RepositoryPath -Path $TestResultPath
New-Item -Path (Split-Path -Parent $resolvedTestResultPath) -ItemType Directory -Force |
    Out-Null
if (Test-Path -LiteralPath $resolvedTestResultPath) {
    Remove-Item -LiteralPath $resolvedTestResultPath -Force
}

$config = New-PesterConfiguration
$config.Run.Path = $resolvedTestPaths
$config.Run.PassThru = $true
$config.Output.Verbosity = 'Detailed'
$config.TestResult.Enabled = $true
$config.TestResult.OutputPath = $resolvedTestResultPath
$config.TestResult.OutputFormat = 'NUnitXml'

$result = Invoke-Pester -Configuration $config
if ($null -eq $result) {
    throw 'Pester did not return a test result object.'
}
if ($result.Result -ne 'Passed' -or $result.FailedCount -gt 0) {
    throw "Pester reported result '$($result.Result)' with $($result.FailedCount) failing test(s)."
}

Write-Host 'Build completed successfully.' -ForegroundColor Green
