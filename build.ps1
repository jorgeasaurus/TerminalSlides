[CmdletBinding()]
param(
    [string[]]$TestPath = @('Tests'),
    [string]$TestResultPath = 'build/TestResults/TestResults.xml',
    [string]$CoverageResultPath = 'build/TestResults/Coverage.xml',
    [switch]$SkipCodeCoverage,
    [switch]$SkipScriptAnalyzer
)

$ErrorActionPreference = 'Stop'
$pesterVersion = [version]'5.8.0'
$scriptAnalyzerVersion = [version]'1.25.0'
$manifestData = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'TerminalSlides.psd1')
$spectreDependency = $manifestData.RequiredModules |
    Where-Object ModuleName -eq 'PwshSpectreConsole' |
    Select-Object -First 1
if (-not $spectreDependency.RequiredVersion) {
    throw 'TerminalSlides.psd1 must pin PwshSpectreConsole with RequiredVersion.'
}
$spectreVersion = [version]$spectreDependency.RequiredVersion

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
        Install-Module -Name $Name -RequiredVersion $Version -Repository PSGallery -Scope CurrentUser -Force -AllowClobber
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

if ($env:TERMINALSLIDES_RUN_TMUX_TESTS -eq '1' -and -not (Get-Command tmux -ErrorAction SilentlyContinue)) {
    throw 'TERMINALSLIDES_RUN_TMUX_TESTS=1 requires tmux to be installed and available on PATH.'
}

Import-ExactModule -Name PwshSpectreConsole -Version $spectreVersion
& (Join-Path $PSScriptRoot 'Scripts/Build-SchemaAssembly.ps1') -Check
& (Join-Path $PSScriptRoot 'Scripts/Update-Documentation.ps1') -Check

if (-not $SkipScriptAnalyzer) {
    Import-ExactModule -Name PSScriptAnalyzer -Version $scriptAnalyzerVersion
    $analysisPaths = @(
        'Classes', 'Layouts', 'Private', 'Public', 'Renderers', 'Themes', 'Scripts', 'Tests', 'TestInfrastructure',
        'build.ps1', 'TerminalSlides.psm1'
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
        $analysisIssues | Format-Table RuleName, ScriptName, Line, Message -Wrap | Out-String | Write-Host
        throw "PSScriptAnalyzer reported $(@($analysisIssues).Count) error(s)."
    }
    Write-Host 'PSScriptAnalyzer completed successfully.' -ForegroundColor Green
}

Import-ExactModule -Name Pester -Version $pesterVersion
$resolvedTestPaths = @($TestPath | ForEach-Object { Resolve-RepositoryPath -Path $_ })
$resolvedTestResultPath = Resolve-RepositoryPath -Path $TestResultPath
$testResultDirectory = Split-Path -Parent $resolvedTestResultPath
New-Item -Path $testResultDirectory -ItemType Directory -Force | Out-Null
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

if (-not $SkipCodeCoverage) {
    $resolvedCoverageResultPath = Resolve-RepositoryPath -Path $CoverageResultPath
    $coverageResultDirectory = Split-Path -Parent $resolvedCoverageResultPath
    New-Item -Path $coverageResultDirectory -ItemType Directory -Force | Out-Null
    if (Test-Path -LiteralPath $resolvedCoverageResultPath) {
        Remove-Item -LiteralPath $resolvedCoverageResultPath -Force
    }

    $coverageDirectories = 'Classes', 'Layouts', 'Private', 'Public', 'Renderers', 'Themes'
    $coverageFiles = @(
        foreach ($coverageDirectory in $coverageDirectories) {
            Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot $coverageDirectory) -Filter '*.ps1' -File -Recurse
        }
        Get-Item -LiteralPath (Join-Path $PSScriptRoot 'TerminalSlides.psm1')
    )
    $config.CodeCoverage.Enabled = $true
    $config.CodeCoverage.Path = @($coverageFiles.FullName)
    $config.CodeCoverage.CoveragePercentTarget = 100
    $config.CodeCoverage.OutputPath = $resolvedCoverageResultPath
    $config.CodeCoverage.OutputFormat = 'JaCoCo'
}

$result = Invoke-Pester -Configuration $config
if ($null -eq $result) {
    throw 'Pester did not return a test result object.'
}
if ($result.Result -ne 'Passed' -or $result.FailedCount -gt 0) {
    throw "Pester reported result '$($result.Result)' with $($result.FailedCount) failing test(s)."
}
if (-not $SkipCodeCoverage) {
    if ($null -eq $result.CodeCoverage) {
        throw 'Pester did not return code coverage results.'
    }
    if ($result.CodeCoverage.CoveragePercent -lt 100) {
        throw "PowerShell line coverage is $($result.CodeCoverage.CoveragePercent)%; 100% is required."
    }
}

Write-Host 'Build completed successfully.' -ForegroundColor Green
