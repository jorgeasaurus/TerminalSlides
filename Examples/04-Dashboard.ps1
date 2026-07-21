Import-Module (Join-Path $PSScriptRoot '..' 'TerminalSlides.psd1') -Force
$deck = New-TerminalPresentation -Title 'Dashboard' -Theme Minimal
$deck | Add-TerminalSlide -Title 'KPIs' -Layout TwoColumn -Content {
    Add-SlideChart -ChartType HorizontalBar -Data @(
        @{ Label = 'Coverage'; Value = 82 }
        @{ Label = 'Build'; Value = 96 }
        @{ Label = 'Docs'; Value = 74 }
    ) -Region Left
    Add-SlideTable -Data @(
        [pscustomobject]@{ Metric = 'Open Issues'; Value = 12 }
        [pscustomobject]@{ Metric = 'PRs'; Value = 4 }
        [pscustomobject]@{ Metric = 'Velocity'; Value = 'High' }
    ) -Region Right
} | Out-Null
Show-TerminalPresentation -Presentation $deck
