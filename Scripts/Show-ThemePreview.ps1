#Requires -Version 7.4

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet(
        'HighContrast',
        'Midnight',
        'Minimal',
        'Monochrome',
        'PowerShell',
        'RetroTerminal',
        'SolarizedDark',
        'SolarizedLight'
    )]
    [string]$Theme,

    [ValidateRange(80, 240)]
    [int]$Width = 128,

    [ValidateRange(24, 80)]
    [int]$Height = 32
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repositoryRoot 'TerminalSlides.psd1') -Force

$presentation = New-TerminalPresentation `
    -Title "$Theme Theme Preview" `
    -Subtitle 'TerminalSlides built-in theme gallery' `
    -Author 'TerminalSlides' `
    -Theme $Theme `
    -Width $Width `
    -Height $Height

switch ($Theme) {
    'Midnight' {
        $health = @(
            [pscustomobject]@{ Label = 'API'; Value = 98 }
            [pscustomobject]@{ Label = 'Queue'; Value = 76 }
            [pscustomobject]@{ Label = 'Cache'; Value = 92 }
        )
        $presentation | Add-TerminalSlide -Title 'MIDNIGHT OPERATIONS' -Content {
            Add-SlideTitle 'Incident response, at a glance'
            Add-SlideSubtitle 'A calm command center for noisy systems.'
            Add-SlideChart -Data $health -ChartType HorizontalBar -Title 'Service health'
            Add-SlideBox 'STATUS  ●  3 SERVICES  ●  ALL REGIONS'
        } | Out-Null
    }
    'PowerShell' {
        $presentation | Add-TerminalSlide -Title 'POWERSHELL' -Content {
            Add-SlideTitle 'Automate the release'
            Add-SlideSubtitle 'One pipeline from source to gallery.'
            Add-SlideCode -Language powershell -Border -Code @'
Invoke-Pester
Publish-Module -Path ./dist/TerminalSlides
gh release create v0.2.0
'@
            Add-SlideBox 'BUILD 142  ▶  TESTS 326/326  ▶  READY'
        } | Out-Null
    }
    'SolarizedDark' {
        $presentation | Add-TerminalSlide -Title 'SOLARIZED DARK' -Content {
            Add-SlideTitle 'Terminal-native presentations'
            Add-SlideSubtitle 'Readable, expressive, and built entirely with PowerShell.'
            Add-SlideBullet 'Compose decks as code'
            Add-SlideBullet 'Present interactively in any modern terminal'
            Add-SlideBullet 'Export repeatable artifacts for documentation'
            Add-SlideCode `
                -Code "Get-Process | Sort-Object CPU -Descending`nSelect-Object -First 5" `
                -Language powershell `
                -Border
            Add-SlideBox 'TRUECOLOR  •  CROSS-PLATFORM  •  SOLARIZED DARK'
        } | Out-Null
    }
    'SolarizedLight' {
        $releaseData = @(
            [pscustomobject]@{ Workstream = 'Module'; Owner = 'Jorge'; Status = 'Ready' }
            [pscustomobject]@{ Workstream = 'Docs'; Owner = 'Avery'; Status = 'Ready' }
            [pscustomobject]@{ Workstream = 'Demo'; Owner = 'Riley'; Status = 'Review' }
        )
        $presentation | Add-TerminalSlide -Title 'SOLARIZED LIGHT' -Content {
            Add-SlideTitle 'Release readiness'
            Add-SlideSubtitle 'The launch plan, visible in one frame.'
            Add-SlideTable -Data $releaseData -Border
            Add-SlideBox 'TUESDAY 09:00  •  THREE OWNERS  •  ONE RELEASE'
        } | Out-Null
    }
    'RetroTerminal' {
        $presentation | Add-TerminalSlide -Title 'RETRO TERMINAL' -Content {
            Add-SlideTitle 'SYSTEM BOOT SEQUENCE'
            Add-SlideSubtitle 'TerminalSlides runtime initialization'
            Add-SlideCode -Language text -Border -Code @'
CHECK MEMORY ............... OK
MOUNT /WORKSPACE ........... OK
LOAD TERMINALSLIDES ........ OK
START PRESENTATION ......... READY
'@
            Add-SlideBox 'SESSION 1984  >  SIGNAL LOCKED  >  AWAITING INPUT'
        } | Out-Null
    }
    'Minimal' {
        $presentation | Add-TerminalSlide -Title 'MINIMAL' -Content {
            Add-SlideTitle 'Less interface. More signal.'
            Add-SlideSubtitle 'A quiet canvas for the decision that matters.'
            Add-SlideQuote `
                -Text 'Remove everything that competes with the idea.' `
                -Attribution 'TerminalSlides'
            Add-SlideBullet 'One message'
            Add-SlideBullet 'One decision'
            Add-SlideBullet 'One next step'
        } | Out-Null
    }
    'Monochrome' {
        $presentation | Add-TerminalSlide -Title 'MONOCHROME' -Content {
            Add-SlideTitle 'Architecture, in plain text'
            Add-SlideSubtitle 'A portable path from idea to terminal.'
            Add-SlideDiagram -Content {
                Add-SlideDiagramNode -Id 'source' -Label 'PowerShell DSL'
                Add-SlideDiagramNode -Id 'schema' -Label 'Typed schema'
                Add-SlideDiagramNode -Id 'render' -Label 'ANSI renderer'
                Add-SlideDiagramEdge -From 'source' -To 'schema' -Label 'compose'
                Add-SlideDiagramEdge -From 'schema' -To 'render' -Label 'project'
            }
            Add-SlideBox 'SOURCE  *  SCHEMA  *  RENDER'
        } | Out-Null
    }
    'HighContrast' {
        $presentation | Add-TerminalSlide -Title 'HIGH CONTRAST' -Content {
            Add-SlideTitle 'ACCESSIBILITY IS A SYSTEM REQUIREMENT'
            Add-SlideSubtitle 'Every control. Every state. Every audience.'
            Add-SlideBullet 'Keyboard navigation from start to finish'
            Add-SlideBullet 'Readable status without color-only signals'
            Add-SlideBullet 'Strong foreground and border contrast'
            Add-SlideBox 'CONTRAST CHECKED  ■  KEYBOARD READY  ■  CLEAR BY DESIGN'
        } | Out-Null
    }
}

Show-TerminalPresentation -Presentation $presentation
