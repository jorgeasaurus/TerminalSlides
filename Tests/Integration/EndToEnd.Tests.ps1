Describe 'End-to-end presentation flow' {
    BeforeAll { Import-Module (Join-Path $PSScriptRoot '..' '..' 'TerminalSlides.psd1') -Force }

    It 'builds, validates, and exports a presentation' {
        $deck = New-TerminalPresentation -Title 'Demo'
        $deck |
            Add-TerminalSlide -Title 'Hello' -Content {
                Add-SlideTitle 'Hello, Terminal'
                Add-SlideText 'This presentation is running entirely in PowerShell.'
            } |
            Add-TerminalSlide -Title 'Features' -Content {
                Add-SlideBullet 'Cross-platform'
                Add-SlideBullet 'Keyboard navigation'
                Add-SlideBullet 'ANSI rendering'
            } | Out-Null
        $deck.Slides.Count | Should -Be 2
        $results = Test-TerminalPresentation -Presentation $deck -Viewport @('80x24')
        ($results | Measure-Object).Count | Should -Be 2
        InModuleScope TerminalSlides -Parameters @{ deck = $deck } {
            $output = Render-TerminalPresentationToString -Presentation $deck -SlideIndex 0 -RevealStep 0 -PlainText
            $output | Should -Match 'Hello, Terminal'
        }
    }
}
