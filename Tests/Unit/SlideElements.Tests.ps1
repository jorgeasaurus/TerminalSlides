Describe 'Slide element builders' {
    BeforeAll { Import-Module (Join-Path $PSScriptRoot '..' '..' 'TerminalSlides.psd1') -Force }

    It 'creates title elements' {
        $deck = New-TerminalPresentation -Title 'Elements'
        $deck | Add-TerminalSlide -Title 'Slide' -Content { Add-SlideTitle 'Header' } | Out-Null
        $element = $deck.Slides[0].Elements[0]
        $element.Type | Should -Be 'Title'
        $element.Content | Should -Be 'Header'
    }

    It 'creates bullet elements with reveal step' {
        $deck = New-TerminalPresentation -Title 'Elements'
        $deck | Add-TerminalSlide -Title 'Slide' -Content { Add-SlideBullet 'Item' -RevealStep 2 } | Out-Null
        $deck.Slides[0].Elements[0].RevealStep | Should -Be 2
        $deck.Slides[0].MaxRevealStep | Should -Be 2
    }

    It 'creates code elements' {
        $deck = New-TerminalPresentation -Title 'Elements'
        $deck | Add-TerminalSlide -Title 'Slide' -Content { Add-SlideCode -Code 'Write-Host 1' -Language powershell } | Out-Null
        $element = $deck.Slides[0].Elements[0]
        $element.Type | Should -Be 'Code'
        $element.Properties.Language | Should -Be 'powershell'
    }
}
