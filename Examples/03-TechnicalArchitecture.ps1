Import-Module (Join-Path $PSScriptRoot '..' 'TerminalSlides.psd1') -Force
$deck = New-TerminalPresentation -Title 'Architecture' -Theme SolarizedDark
$deck | Add-TerminalSlide -Title 'Pipeline' -Content {
    Add-SlideDiagram -Content {
        Add-SlideDiagramNode -Id 'A' -Label 'Builder'
        Add-SlideDiagramNode -Id 'B' -Label 'Layout'
        Add-SlideDiagramNode -Id 'C' -Label 'Renderer'
        Add-SlideDiagramEdge -From 'A' -To 'B'
        Add-SlideDiagramEdge -From 'B' -To 'C'
    }
} | Out-Null
Show-TerminalPresentation -Presentation $deck
