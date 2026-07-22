Describe 'New-TerminalPresentation' {
    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '..' '..' 'TerminalSlides.psd1') -Force
    }

    It 'creates presentation with correct properties' {
        $deck = New-TerminalPresentation -Title 'Demo' -Subtitle 'Sub' -Author 'Jorge' -Description 'Desc' -Theme Midnight
        $deck.Title | Should -Be 'Demo'
        $deck.Subtitle | Should -Be 'Sub'
        $deck.Author | Should -Be 'Jorge'
        $deck.Description | Should -Be 'Desc'
        $deck.Theme | Should -Be 'Midnight'
    }

    It 'applies default values' {
        $deck = New-TerminalPresentation -Title 'Defaults'
        $deck.DefaultLayout | Should -Be 'TitleAndContent'
        $deck.DefaultTransition | Should -Be 'None'
        $deck.Width | Should -Be 0
        $deck.Height | Should -Be 0
    }

    It 'validates theme names' {
        { New-TerminalPresentation -Title 'Bad' -Theme Nope } | Should -Throw
    }

    It 'keeps type identity stable across module re-imports' {
        $deck = New-TerminalPresentation -Title 'Identity'
        Remove-Module TerminalSlides -Force
        Import-Module (Join-Path $PSScriptRoot '..' '..' 'TerminalSlides.psd1') -Force
        { $deck | Add-TerminalSlide -Title 'S' -Content { Add-SlideText 'x' } | Out-Null } | Should -Not -Throw
        $deck.Slides.Count | Should -Be 1
    }
}
