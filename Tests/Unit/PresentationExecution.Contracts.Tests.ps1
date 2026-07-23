Describe 'Presentation execution contracts' {
    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '..' '..' 'TerminalSlides.psd1') -Force
    }

    It 'handles path, empty, alternate-buffer, and demo presentation entry points' {
        InModuleScope TerminalSlides {
            $deck = New-TerminalPresentation -Title 'Entry'
            $deck | Add-TerminalSlide -Title 'One' -Content { Add-SlideText 'one' } | Out-Null

            Mock Import-TerminalPresentation { $deck }
            Mock Get-TerminalPresentationCapability {
                [TerminalSlides.Schema.V1.TerminalCapability]@{ AnsiSupport = $false; Interactive = $false; IsRedirected = $true }
            }
            Mock Render-TerminalPresentationToString { 'rendered' }
            (Show-TerminalPresentation -Path 'deck.psd1') | Should -Be 'rendered'

            $empty = New-TerminalPresentation -Title 'Empty'
            $errors = @()
            Show-TerminalPresentation -Presentation $empty -ErrorAction SilentlyContinue -ErrorVariable errors
            $errors.Exception.Message | Should -Contain 'Presentation contains no slides.'

            Mock Get-TerminalPresentationCapability {
                [TerminalSlides.Schema.V1.TerminalCapability]@{ AnsiSupport = $true; Interactive = $true; IsRedirected = $false; AlternateBuffer = $true }
            }
            Mock Read-TerminalPresentationKey { [ConsoleKeyInfo]::new([char]0, [ConsoleKey]::Escape, $false, $false, $false) }
            Mock Write-Host {}
            Show-TerminalPresentation -Presentation $deck
            Should -Invoke Write-Host -ParameterFilter { ([string]$Object).Contains("`e[?1049h") }
            Should -Invoke Write-Host -ParameterFilter { ([string]$Object).Contains("`e[?1049l") }

            Mock New-TerminalSlidesDemoPresentation { $deck }
            Mock Show-TerminalPresentation {}
            Start-TerminalSlidesDemo
            Should -Invoke Show-TerminalPresentation -ParameterFilter { $Presentation -eq $deck }
        }
    }

    It 'reads native console keys through the typed module adapter' {
        InModuleScope TerminalSlides {
            $originalReader = $script:NativePresentationKeyReader
            $expected = [ConsoleKeyInfo]::new('x', [ConsoleKey]::X, $false, $false, $false)
            try {
                $script:NativePresentationKeyReader = [Func[bool,ConsoleKeyInfo]]{
                    param([bool]$Intercept)
                    $Intercept | Should -BeTrue
                    return $expected
                }

                $actual = Read-TerminalPresentationKey
                $actual.Key | Should -Be ([ConsoleKey]::X)
                $actual.KeyChar | Should -Be 'x'
            }
            finally {
                $script:NativePresentationKeyReader = $originalReader
            }
            $script:NativePresentationKeyReader.GetType() | Should -Be ([Func[bool,ConsoleKeyInfo]])
        }
    }

    It 'renders view modes, automatic dimensions, backgrounds, timers, and notes' {
        InModuleScope TerminalSlides {
            $capability = [TerminalSlides.Schema.V1.TerminalCapability]@{ Width=0; Height=0; AnsiSupport=$true }
            $automatic = New-TerminalPresentation -Title 'Automatic'
            $dimensions = Get-SlideRenderDimensions -Presentation $automatic -Capability $capability
            $dimensions.Width | Should -Be 80
            $dimensions.Height | Should -Be 24

            $deck = New-TerminalPresentation -Title 'Modes' -Subtitle 'Deck subtitle' -Width 40 -Height 15
            $deck | Add-TerminalSlide -Title 'First' -Layout Title -Background '#101010' -Content {
                Add-SlideCode -Code 'body' -Border
                Add-SlideNotes 'notes text'
            } | Out-Null
            $deck | Add-TerminalSlide -Title 'Second' -Layout Blank -Content { Add-SlideText 'second' } | Out-Null
            $bordered = New-InternalSlideElement -Kind Text -Payload ([TerminalSlides.Schema.V1.TextPayload]::new('colored border')) -Border -ForegroundColor '#ABCDEF' -BackgroundColor '#123456'
            $deck.Slides[0].Elements.Add($bordered)

            (Render-TerminalPresentationToString -Presentation $deck -SlideIndex 0 -DisplayMode Blank -PlainText).Trim() | Should -Be ''
            Render-TerminalPresentationToString -Presentation $deck -SlideIndex 0 -DisplayMode Overview -PlainText | Should -Match 'Modes'
            $notesOutput = Render-TerminalPresentationToString -Presentation $deck -SlideIndex 0 -ShowNotes -ShowTimer -Elapsed ([timespan]::FromSeconds(5)) -PlainText
            $notesOutput | Should -Match 'notes text'
            $helpFrame = Get-RenderedSlideFrame -Presentation $deck -SlideIndex 0 -DisplayMode Help
            $helpFrame.Width | Should -Be 40
            $helpFrame.GetRowText(3) | Should -Match 'TerminalSlides Help'

            $empty = New-TerminalPresentation -Title 'No slides' -Width 40 -Height 15
            $emptyFrame = [FrameBuffer]::new(40, 15)
            $emptyFrame.Width | Should -Be 40
        }
    }

    It 'measures bordered overflow and uses default validation viewports' {
        $deck = New-TerminalPresentation -Title 'Overflow'
        $deck | Add-TerminalSlide -Title ('T' * 200) -Content { Add-SlideCode -Code ('content ' * 30) -Border } | Out-Null
        $results = Test-TerminalPresentation -Presentation $deck -WarningAction SilentlyContinue
        $results.Count | Should -Be 3
        $results.Fits | Should -Contain $false
    }

}
