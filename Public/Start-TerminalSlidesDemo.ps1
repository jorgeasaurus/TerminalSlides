function New-TerminalSlidesDemoPresentation {
    $presentation = New-TerminalPresentation -Title 'TerminalSlides Feature Tour' -Subtitle 'A guided walkthrough of terminal-native presentations' -Author 'TerminalSlides' -Theme Midnight
    $photoPath = Join-Path $script:ModuleRoot 'Assets/presentation-team-photo.jpg'

    $presentation | Add-TerminalSlide -Title 'Welcome' -Content {
        Add-SlideTitle 'Present from the terminal'
        Add-SlideSubtitle 'Press Right to reveal each point'
        Add-SlideText 'TerminalSlides turns familiar PowerShell objects into a focused, keyboard-driven presentation.'
        Add-SlideBullet 'Build decks with PowerShell' -RevealStep 1
        Add-SlideBullet 'Reveal ideas at your pace' -RevealStep 2
        Add-SlideBullet 'Use Q or Escape to exit at any time' -RevealStep 3
        Add-SlideNotes 'Introduce the deck, then use Right Arrow to show incremental reveals.'
    } | Out-Null

    $presentation | Add-TerminalSlide -Title 'Code' -Content {
        Add-SlideCode -Language powershell -Border -Code @'
$deck = New-TerminalPresentation -Title 'Demo'
$deck | Add-TerminalSlide -Title 'Hello' -Content {
    Add-SlideText 'Built in PowerShell'
}
Show-TerminalPresentation -Presentation $deck
'@
    } | Out-Null

    $presentation | Add-TerminalSlide -Title 'Tables' -Content {
        Add-SlideTable -Border -Data @(
            [pscustomobject]@{ Feature = 'Text'; Purpose = 'Narrative and annotations' }
            [pscustomobject]@{ Feature = 'Code'; Purpose = 'Syntax-highlighted snippets' }
            [pscustomobject]@{ Feature = 'Data'; Purpose = 'Tables and charts' }
        )
    } | Out-Null

    $presentation | Add-TerminalSlide -Title 'Charts' -Content {
        Add-SlideChart -ChartType HorizontalBar -Title 'Build confidence' -Data @(
            [pscustomobject]@{ Label = 'Design'; Value = 35 }
            [pscustomobject]@{ Label = 'Data'; Value = 65 }
            [pscustomobject]@{ Label = 'Delivery'; Value = 90 }
        )
    } | Out-Null

    $presentation | Add-TerminalSlide -Title 'Diagrams' -Content {
        Add-SlideDiagram -Content {
            Add-SlideDiagramNode -Id 'idea' -Label 'Idea'
            Add-SlideDiagramNode -Id 'deck' -Label 'Deck'
            Add-SlideDiagramNode -Id 'terminal' -Label 'Terminal'
            Add-SlideDiagramEdge -From 'idea' -To 'deck' -Label 'compose'
            Add-SlideDiagramEdge -From 'deck' -To 'terminal' -Label 'present'
        }
    } | Out-Null

    $presentation | Add-TerminalSlide -Title 'Callouts and media' -Content {
        Add-SlideQuote -Text 'The best presentation tool is the one already in your workflow.' -Attribution 'TerminalSlides'
        Add-SlideBox -Text 'Use callout boxes to make a decision, warning, or takeaway impossible to miss.'
    } | Out-Null

    $presentation | Add-TerminalSlide -Title 'Visual storytelling' -Layout ImageFocus -Content {
        Add-SlideImage -Path $photoPath -AltText 'Three software engineers collaborating around a laptop during a presentation rehearsal.' -Region Image
    } | Out-Null

    $presentation | Add-TerminalSlide -Title 'Presentation controls' -Content {
        Add-SlideText 'Navigate with arrows, Space, N, PageUp, PageDown, Home, and End.'
        Add-SlideText 'Toggle notes, overview, blanking, timer, and help with S, O, B, T, and H.' -RevealStep 1
        Add-SlideBox -Text 'Try ? for the in-presentation control reference, then Q to return to PowerShell.' -RevealStep 2
    } | Out-Null

    return $presentation
}

function Start-TerminalSlidesDemo {
    [CmdletBinding()]
    param([switch]$PassThru)

    $presentation = New-TerminalSlidesDemoPresentation
    if ($PassThru) { return $presentation }

    Show-TerminalPresentation -Presentation $presentation
}
