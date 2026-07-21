Describe 'Renderer helpers' {
    BeforeAll { Import-Module (Join-Path $PSScriptRoot '..' '..' 'TerminalSlides.psd1') -Force }

    It 'creates frame buffer correctly' {
        InModuleScope TerminalSlides {
            $frame = [FrameBuffer]::new(20, 5)
            $frame.Width | Should -Be 20
            $frame.Height | Should -Be 5
            $frame.Cells[0][0].Char | Should -Be ' '
        }
    }

    It 'wraps words within width' {
        InModuleScope TerminalSlides {
            $lines = Format-WordWrap -Text 'alpha beta gamma' -Width 8
            $lines.Count | Should -BeGreaterThan 1
        }
    }

    It 'generates ANSI sequences' {
        InModuleScope TerminalSlides {
            Get-AnsiReset | Should -Be "`e[0m"
            Get-AnsiFg -Color '#112233' | Should -Match '\[38;2;17;34;51m$'
        }
    }

    It 'strips ANSI sequences' {
        InModuleScope TerminalSlides {
            $text = "$(Get-AnsiFg -Color '#FF0000')red$(Get-AnsiReset)"
            Strip-AnsiSequences -Text $text | Should -Be 'red'
        }
    }
}
