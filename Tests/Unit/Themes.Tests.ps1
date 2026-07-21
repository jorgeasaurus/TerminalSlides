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
}
