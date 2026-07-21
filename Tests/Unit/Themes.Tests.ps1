Describe 'Themes' {
    BeforeAll { Import-Module (Join-Path $PSScriptRoot '..' '..' 'TerminalSlides.psd1') -Force }

    It 'loads built-in themes' {
        $themes = Get-TerminalPresentationTheme
        $themes.Name | Should -Contain 'Midnight'
        $themes.Name | Should -Contain 'PowerShell'
    }

    It 'returns required theme properties' {
        $theme = Get-TerminalPresentationTheme -Name Midnight
        $theme.Background | Should -Match '^#'
        $theme.Foreground | Should -Match '^#'
        $theme.ChartPalette.Count | Should -BeGreaterThan 0
    }

    It 'creates custom themes' {
        $theme = New-TerminalPresentationTheme -Name Custom -Background '#000000' -Foreground '#FFFFFF' -Primary '#111111'
        $theme.Name | Should -Be 'Custom'
        $theme.BoxDrawingStyle | Should -Be 'unicode'
    }

    It 'registers custom themes so they resolve by name' {
        $null = New-TerminalPresentationTheme -Name RegisteredCustom -Background '#000000' -Foreground '#FFFFFF' -Primary '#111111'
        $resolved = Get-TerminalPresentationTheme -Name RegisteredCustom
        $resolved.Name | Should -Be 'RegisteredCustom'
    }

    It 'accepts custom themes in New-TerminalPresentation' {
        $null = New-TerminalPresentationTheme -Name DeckTheme -Background '#000000' -Foreground '#FFFFFF' -Primary '#111111'
        $deck = New-TerminalPresentation -Title 'Custom Theme Deck' -Theme DeckTheme
        $deck.Theme | Should -Be 'DeckTheme'
    }

    It 'preserves CodeBackground and CodeForeground from theme files' {
        $theme = Get-TerminalPresentationTheme -Name Midnight
        $theme.CodeBackground | Should -Be '#0D1F33'
        $theme.CodeForeground | Should -Be '#E5F1FF'
    }
}
