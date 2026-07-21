Describe 'Add-TerminalSlide' {
    BeforeAll { Import-Module (Join-Path $PSScriptRoot '..' '..' 'TerminalSlides.psd1') -Force }

    It 'supports pipeline chaining' {
        $deck = New-TerminalPresentation -Title 'Chain'
        $result = $deck |
            Add-TerminalSlide -Title 'One' -Content { Add-SlideText 'First' } |
            Add-TerminalSlide -Title 'Two' -Content { Add-SlideText 'Second' }
        $result.Slides.Count | Should -Be 2
        $result.Slides[1].Title | Should -Be 'Two'
    }

    It 'executes the content scriptblock and captures elements' {
        $deck = New-TerminalPresentation -Title 'Demo'
        $deck | Add-TerminalSlide -Title 'Hello' -Content {
            Add-SlideTitle 'Hello'
            Add-SlideBullet 'World'
            Add-SlideNotes 'Remember the demo.'
        } | Out-Null
        $deck.Slides.Count | Should -Be 1
        $deck.Slides[0].Elements.Count | Should -Be 2
        $deck.Slides[0].Notes | Should -Be 'Remember the demo.'
    }
}
