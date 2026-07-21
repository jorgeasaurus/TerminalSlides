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

    It 'highlights PowerShell code regardless of language casing' {
        InModuleScope TerminalSlides {
            $theme = Get-ResolvedTheme -Name Midnight
            $lower = Get-SyntaxHighlight -Code 'function # comment' -Language 'powershell' -Theme $theme
            $upper = Get-SyntaxHighlight -Code 'function # comment' -Language 'PowerShell' -Theme $theme
            ($lower -join "`n") | Should -Be ($upper -join "`n")
            ($upper -join "`n") | Should -Match 'comment'
        }
    }

    It 'renders image elements without alt text' {
        InModuleScope TerminalSlides {
            $theme = Get-ResolvedTheme -Name Midnight
            $element = New-InternalSlideElement -Type 'Image' -Content @{ Path = 'diagram.png' }
            $lines = ConvertTo-ElementLines -Element $element -Width 40 -Theme $theme
            $lines[0] | Should -Be 'Image: diagram.png'
            $lines.Count | Should -Be 2
        }
    }

    It 'blocks disallowed commands in SafeMode via AST analysis' {
        InModuleScope TerminalSlides {
            { Invoke-SafeScriptBlock -ScriptBlock { Get-Process } -SafeMode } | Should -Throw '*SafeMode*'
            { Invoke-SafeScriptBlock -ScriptBlock { Add-SlideText 'ok' } -SafeMode } | Should -Not -Throw
        }
    }

    It 'blocks dynamic command invocation in SafeMode' {
        InModuleScope TerminalSlides {
            { Invoke-SafeScriptBlock -ScriptBlock { & 'Get-Process' } -SafeMode } | Should -Throw '*SafeMode*'
            { Invoke-SafeScriptBlock -ScriptBlock { & $someVariable } -SafeMode } | Should -Throw '*SafeMode*'
        }
    }

    It 'parses ANSI-colored text into styled segments' {
        InModuleScope TerminalSlides {
            $text = "$(Get-AnsiFg -Color '#FF0000')red$(Get-AnsiReset) plain"
            $segments = ConvertFrom-AnsiToSegments -Text $text
            $segments.Count | Should -Be 2
            $segments[0].Text | Should -Be 'red'
            $segments[0].Foreground | Should -Be '#FF0000'
            $segments[1].Text | Should -Be ' plain'
            $segments[1].Foreground | Should -BeNullOrEmpty
        }
    }

    It 'treats bare ESC[m as a reset' {
        InModuleScope TerminalSlides {
            $segments = ConvertFrom-AnsiToSegments -Text "$([char]27)[38;2;255;0;0mred$([char]27)[m plain"
            $segments.Count | Should -Be 2
            $segments[1].Text | Should -Be ' plain'
            $segments[1].Foreground | Should -BeNullOrEmpty
        }
    }

    It 'applies syntax highlighting to code elements' {
        InModuleScope TerminalSlides {
            $theme = Get-ResolvedTheme -Name Midnight
            $element = New-InternalSlideElement -Type 'Code' -Content ([ordered]@{ Code = 'function Test {}'; Language = 'powershell' })
            $lines = ConvertTo-ElementLines -Element $element -Width 60 -Theme $theme
            ($lines -join "`n") | Should -Match "`e\["
        }
    }
}
