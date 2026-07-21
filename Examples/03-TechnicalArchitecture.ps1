Import-Module (Join-Path $PSScriptRoot '..' 'TerminalSlides.psd1') -Force
$deck = New-TerminalPresentation -Title 'Architecture' -Theme SolarizedDark
$deck | Add-TerminalSlide -Title 'Pipeline' -Content {
    Add-SlideDiagram -Content {
        Node -Id A -Label 'Builder'
        Node -Id B -Label 'Layout'
        Node -Id C -Label 'Renderer'
        Edge -From A -To B
        Edge -From B -To C
    }
} | Out-Null
Show-TerminalPresentation -Presentation $deck
