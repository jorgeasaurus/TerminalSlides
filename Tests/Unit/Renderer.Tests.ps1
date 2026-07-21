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

    It 'supports diff rendering with a real cell snapshot' {
        InModuleScope TerminalSlides {
            $frame = [FrameBuffer]::new(10, 3)
            Set-FrameText -FrameBuffer $frame -X 0 -Y 0 -Text 'hello'
            $null = $frame.Render($false)
            $snapshot = $frame.PreviousCells
            $snapshot[0][0].Char | Should -Be 'h'
            # Mutating live cells must not alter the snapshot.
            Set-FrameText -FrameBuffer $frame -X 0 -Y 0 -Text 'j'
            $snapshot[0][0].Char | Should -Be 'h'
            # Diff render of unchanged rows emits nothing for them.
            $diff = $frame.Render($true)
            $diff | Should -Match 'j'
            ($diff -split "`e\[\d+;1H").Count | Should -BeLessThan 4
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

    It 'renders box elements with the theme box drawing style' {
        InModuleScope TerminalSlides {
            $theme = Get-ResolvedTheme -Name Midnight
            $theme.BoxDrawingStyle = 'rounded'
            $element = New-InternalSlideElement -Type 'Box' -Content 'hi'
            $lines = ConvertTo-ElementLines -Element $element -Width 12 -Theme $theme
            $lines[0] | Should -Match ([regex]::Escape([string][char]0x256D))
            $theme.BoxDrawingStyle = 'ascii'
            $ascii = ConvertTo-ElementLines -Element $element -Width 12 -Theme $theme
            $ascii[0] | Should -Match '^\+'
        }
    }

    It 'renders bordered elements without overwriting the border' {
        InModuleScope TerminalSlides {
            $deck = New-TerminalPresentation -Title 'B' -Width 40 -Height 15
            $deck | Add-TerminalSlide -Title 'S' -Content { Add-SlideCode -Code "line1`nline2`nline3`nline4" -Language text -Border } | Out-Null
            $frame = Get-RenderedSlideFrame -Presentation $deck -SlideIndex 0 -RevealStep 10
            $rowText = -join ($frame.Cells[5] | ForEach-Object { $_.Char })
            # Top border row should be box-drawing, content rows should contain code text
            $all = (0..($frame.Height - 1) | ForEach-Object { -join ($frame.Cells[$_] | ForEach-Object { $_.Char }) }) -join "`n"
            $all | Should -Match 'line1'
            $all | Should -Match 'line4'
            $all | Should -Match '┌'
        }
    }

    It 'applies ANSI syntax colors to frame buffer cells' {
        InModuleScope TerminalSlides {
            $deck = New-TerminalPresentation -Title 'C' -Width 40 -Height 15
            $deck | Add-TerminalSlide -Title 'S' -Content { Add-SlideCode -Code 'function foo {}' -Language powershell } | Out-Null
            $frame = Get-RenderedSlideFrame -Presentation $deck -SlideIndex 0 -RevealStep 10
            $slide = $deck.Slides[0]
            $theme = Get-ResolvedTheme -Presentation $deck -Slide $slide
            $baseFg = $theme.Foreground
            $colored = @{}
            for ($r = 0; $r -lt $frame.Height; $r++) {
                foreach ($cell in $frame.Cells[$r]) {
                    if ($cell.Char -ne ' ' -and $cell.Fg -and $cell.Fg -ne $baseFg) {
                        $colored[$cell.Fg] = $true
                    }
                }
            }
            $colored.Count | Should -BeGreaterThan 0
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
