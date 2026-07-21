[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'TerminalSlides.psd1'
$testsPath = Join-Path $PSScriptRoot 'Tests'

Import-Module $modulePath -Force
Write-Host 'Module import succeeded.' -ForegroundColor Green

if (-not (Get-Module -ListAvailable -Name Pester)) {
    Write-Host 'Installing Pester...' -ForegroundColor Yellow
    Install-Module Pester -Force -MinimumVersion 5.0.0 -Scope CurrentUser
}

Import-Module Pester -Force
$config = New-PesterConfiguration
$config.Run.Path = $testsPath
$config.Output.Verbosity = 'Detailed'
$result = Invoke-Pester -Configuration $config
if ($result.FailedCount -gt 0) {
    throw "Pester reported $($result.FailedCount) failing test(s)."
}

Write-Host 'Build completed successfully.' -ForegroundColor Green
