Describe 'Renderer helpers' {
    BeforeAll { Import-Module (Join-Path $PSScriptRoot '..' '..' 'TerminalSlides.psd1') -Force }

    It 'creates frame buffer correctly' {
        InModuleScope TerminalSlides {
            $frame = [FrameBuffer]::new(20, 5)
            $frame.Width | Should -Be 20
            $frame.Height | Should -Be 5
            $frame.Cells[0][0].Char | Should -Be ' '
            $frame.GetRowText(-1) | Should -BeNullOrEmpty
            $frame.GetRowText($frame.Height) | Should -BeNullOrEmpty
        }
    }

    It 'renders complete frames without retaining unused snapshots' {
        InModuleScope TerminalSlides {
            $frame = [FrameBuffer]::new(10, 3)
            Set-FrameText -FrameBuffer $frame -X 0 -Y 0 -Text 'hello'
            $rendered = $frame.Render($true, $false)

            Strip-AnsiSequences $rendered | Should -Match 'hello'
            ($rendered -split "`e\[\d+;1H").Count | Should -Be 4
            $frame.PSObject.Properties.Name | Should -Not -Contain 'PreviousCells'
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
            Get-AnsiBg -Color '#A1B2C3' | Should -Be "`e[48;2;161;178;195m"
        }
    }

    It 'renders Spectre styles for true-color, 256-color, and colorless terminals' {
        InModuleScope TerminalSlides {
            $markup = [Spectre.Console.Markup]::new('[bold italic underline #112233 on #445566]styled[/]')
            $capabilities = @(
                [TerminalSlides.Schema.V1.TerminalCapability]@{ AnsiSupport=$true; TrueColorSupport=$true; Color256Support=$true; UnicodeSupport=$true },
                [TerminalSlides.Schema.V1.TerminalCapability]@{ AnsiSupport=$true; TrueColorSupport=$false; Color256Support=$true; UnicodeSupport=$true },
                [TerminalSlides.Schema.V1.TerminalCapability]@{ AnsiSupport=$false; TrueColorSupport=$false; Color256Support=$false; UnicodeSupport=$false }
            )

            foreach ($capability in $capabilities) {
                $line = @(ConvertTo-SpectreRenderableLines -Renderable $markup -Width 20 -Height 1 -Capability $capability)[0]
                $line.GetText() | Should -Be 'styled'
                $line.Runs[0].Bold | Should -BeTrue
                $line.Runs[0].Italic | Should -BeTrue
                $line.Runs[0].Underline | Should -BeTrue
                $line.Runs[0].Foreground | Should -Be '#112233'
                $line.Runs[0].Background | Should -Be '#445566'
            }
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
            $element = New-InternalSlideElement -Kind Image -Payload ([TerminalSlides.Schema.V1.ImagePayload]::new('diagram.png', $null))
            $lines = ConvertTo-ElementLines -Element $element -Width 40 -Theme $theme
            $lines[0] | Should -Be 'Image: diagram.png'
            $lines.Count | Should -Be 2
        }
    }

    It 'renders an image as colored terminal cells' {
        $imagePath = Join-Path $TestDrive 'pixel.png'
        $pixel = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='
        [System.IO.File]::WriteAllBytes($imagePath, [Convert]::FromBase64String($pixel))

        InModuleScope TerminalSlides -Parameters @{ ImagePath = $imagePath } {
            $deck = New-TerminalPresentation -Title 'Images' -Width 60 -Height 20
            $deck | Add-TerminalSlide -Title 'Architecture' -Layout ImageFocus -Content {
                Add-SlideImage -Path $ImagePath -AltText 'Architecture diagram' -Region Image
            } | Out-Null
            $capability = [TerminalSlides.Schema.V1.TerminalCapability]@{ Width=60; Height=20; AnsiSupport=$true; TrueColorSupport=$true; UnicodeSupport=$true }
            $output = Render-TerminalPresentationToString -Presentation $deck -Capability $capability

            $output | Should -Match '[▀▄]'
            $output | Should -Match ([regex]::Escape("`e[38;2;"))
            $output | Should -Match ([regex]::Escape("`e[48;2;"))
            $output | Should -Not -Match ([regex]::Escape("Image: $ImagePath"))
        }
    }

    It 'falls back to accessible text when an image cannot be decoded' {
        $imagePath = Join-Path $TestDrive 'invalid.png'
        [System.IO.File]::WriteAllText($imagePath, 'not an image')

        InModuleScope TerminalSlides -Parameters @{ ImagePath = $imagePath } {
            $deck = New-TerminalPresentation -Title 'Images' -Width 60 -Height 20
            $deck | Add-TerminalSlide -Title 'Architecture' -Layout ImageFocus -Content {
                Add-SlideImage -Path $ImagePath -AltText 'Architecture diagram' -Region Image
            } | Out-Null

            $output = Render-TerminalPresentationToString -Presentation $deck -PlainText

            $output | Should -Match 'Image:'
            $output | Should -Match 'Architecture diagram'
        }
    }

    It 'renders box elements with the theme box drawing style' {
        InModuleScope TerminalSlides {
            $theme = Get-ResolvedTheme -Name Midnight
            $theme.BoxDrawingStyle = 'rounded'
            $element = New-InternalSlideElement -Kind Box -Payload ([TerminalSlides.Schema.V1.TextPayload]::new('hi'))
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

    It 'renders the help overlay with its blank separator line' {
        InModuleScope TerminalSlides {
            $deck = New-TerminalPresentation -Title 'Help' -Width 60 -Height 20
            $deck | Add-TerminalSlide -Title 'Slide' -Content { Add-SlideText 'Content' } | Out-Null

            $output = Render-TerminalPresentationToString -Presentation $deck -DisplayMode Help -PlainText

            $output | Should -Match 'TerminalSlides Help'
            $output | Should -Match 'Q / Esc'
        }
    }

    It 'applies ANSI syntax colors to frame buffer cells' {
        InModuleScope TerminalSlides {
            $deck = New-TerminalPresentation -Title 'C' -Width 40 -Height 15
            $deck | Add-TerminalSlide -Title 'S' -Content { Add-SlideCode -Code 'function foo {}' -Language powershell } | Out-Null
            $frame = Get-RenderedSlideFrame -Presentation $deck -SlideIndex 0 -RevealStep 10
            $slide = $deck.Slides[0]
            $theme = Get-ResolvedTheme -Name $deck.Theme
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

    It 'carries color through typed styled runs' {
        InModuleScope TerminalSlides {
            $line = [TerminalStyledLine]::new()
            Add-TerminalStyledRun -Line $line -Text 'red' -Foreground '#FF0000' -Background '#0000FF'
            Add-TerminalStyledRun -Line $line -Text ' plain'

            $line.Runs.Count | Should -Be 2
            $line.GetText() | Should -Be 'red plain'
            $line.Runs[0].Foreground | Should -Be '#FF0000'
            $line.Runs[0].Background | Should -Be '#0000FF'
            $line.Runs[1].Foreground | Should -BeNullOrEmpty
        }
    }

    It 'does not retain an ANSI parser in the rendering path' {
        InModuleScope TerminalSlides {
            Get-Command ConvertFrom-AnsiToSegments -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
            Get-Command ConvertTo-TerminalStyledRuns -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        }
    }

    It 'applies syntax highlighting to code elements' {
        InModuleScope TerminalSlides {
            $theme = Get-ResolvedTheme -Name Midnight
            $element = New-InternalSlideElement -Kind Code -Payload ([TerminalSlides.Schema.V1.CodePayload]::new('function Test {}', 'powershell'))
            $lines = ConvertTo-ElementLines -Element $element -Width 60 -Theme $theme
            $lines[0].GetType().Name | Should -Be 'TerminalStyledLine'
            $lines[0].GetText() | Should -Be 'function Test {}'
            $lines[0].GetText() | Should -Not -Match ([regex]::Escape([string][char]27))
            $lines[0].Runs[0].Bold | Should -BeTrue
        }
    }
}
