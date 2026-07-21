[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'TerminalSlides.psd1'
$testsPath = Join-Path $PSScriptRoot 'Tests'

Import-Module $modulePath -Force
Write-Host 'Module import succeeded.' -ForegroundColor Green

$pesterModule = Get-Module -ListAvailable -Name Pester |
    Sort-Object Version -Descending |
    Select-Object -First 1
if (-not $pesterModule -or $pesterModule.Version -lt [version]'5.0.0') {
    Write-Host 'Installing Pester 5.x...' -ForegroundColor Yellow
    Install-Module Pester -Force -MinimumVersion 5.0.0 -Scope CurrentUser
    $pesterModule = Get-Module -ListAvailable -Name Pester |
        Sort-Object Version -Descending |
        Select-Object -First 1
}

Import-Module Pester -RequiredVersion $pesterModule.Version -Force
$config = New-PesterConfiguration
$config.Run.Path = $testsPath
$config.Output.Verbosity = 'Detailed'
$result = Invoke-Pester -Configuration $config
if ($result.FailedCount -gt 0) {
    throw "Pester reported $($result.FailedCount) failing test(s)."
}

Write-Host 'Build completed successfully.' -ForegroundColor Green
