Describe 'Show-TerminalPresentation' {
    BeforeAll { Import-Module (Join-Path $PSScriptRoot '..' '..' 'TerminalSlides.psd1') -Force }

    BeforeEach {
        InModuleScope TerminalSlides {
            $script:KeyboardDeck = New-TerminalPresentation -Title 'Controls'
            $script:KeyboardDeck | Add-TerminalSlide -Title 'One' -Content {
                Add-SlideText 'Visible'
                Add-SlideText 'Reveal' -RevealStep 1
            } | Out-Null
            $script:KeyboardDeck | Add-TerminalSlide -Title 'Two' -Content { Add-SlideText 'Second' } | Out-Null
            $script:KeyboardRenderCalls = [System.Collections.Generic.List[object]]::new()

            Mock Get-TerminalPresentationCapability {
                [TerminalSlides.Schema.V1.TerminalCapability]@{
                    AnsiSupport = $true
                    Interactive = $true
                    IsRedirected = $false
                    AlternateBuffer = $false
                }
            }
            Mock Render-TerminalPresentationToString {
                param(
                    $Presentation, $SlideIndex, $RevealStep, $PlainText, $ShowNotes,
                    $DisplayMode, $Elapsed, $ShowTimer, $Capability
                )
                $script:KeyboardRenderCalls.Add([pscustomobject]@{
                    SlideIndex = $SlideIndex
                    RevealStep = $RevealStep
                    ShowNotes = [bool]$ShowNotes
                    DisplayMode = $DisplayMode
                    ShowTimer = [bool]$ShowTimer
                })
                return 'frame'
            }
            Mock Write-Host {}
        }
    }

    It 'reveals content before advancing with <Name>' -TestCases @(
        @{ Name = 'Right Arrow'; Key = [ConsoleKey]::RightArrow; Character = [char]0 }
        @{ Name = 'Space'; Key = [ConsoleKey]::Spacebar; Character = ' ' }
        @{ Name = 'N'; Key = [ConsoleKey]::N; Character = 'n' }
    ) {
        param($Name, $Key, $Character)

        InModuleScope TerminalSlides -Parameters @{ Key = $Key; Character = $Character } {
            param($Key, $Character)
            $keys = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
            $keys.Enqueue([ConsoleKeyInfo]::new($Character, $Key, $false, $false, $false))
            $keys.Enqueue([ConsoleKeyInfo]::new([char]0, [ConsoleKey]::Escape, $false, $false, $false))
            Mock Read-TerminalPresentationKey { $keys.Dequeue() }

            Show-TerminalPresentation -Presentation $script:KeyboardDeck

            $script:KeyboardRenderCalls.Count | Should -Be 2
            $script:KeyboardRenderCalls[-1].SlideIndex | Should -Be 0
            $script:KeyboardRenderCalls[-1].RevealStep | Should -Be 1
        }
    }

    It 'advances after the reveal is complete with <Name>' -TestCases @(
        @{ Name = 'Right Arrow'; Key = [ConsoleKey]::RightArrow; Character = [char]0 }
        @{ Name = 'Space'; Key = [ConsoleKey]::Spacebar; Character = ' ' }
        @{ Name = 'N'; Key = [ConsoleKey]::N; Character = 'n' }
    ) {
        param($Name, $Key, $Character)

        InModuleScope TerminalSlides -Parameters @{ Key = $Key; Character = $Character } {
            param($Key, $Character)
            $keys = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
            1..2 | ForEach-Object {
                $keys.Enqueue([ConsoleKeyInfo]::new($Character, $Key, $false, $false, $false))
            }
            $keys.Enqueue([ConsoleKeyInfo]::new([char]0, [ConsoleKey]::Escape, $false, $false, $false))
            Mock Read-TerminalPresentationKey { $keys.Dequeue() }

            Show-TerminalPresentation -Presentation $script:KeyboardDeck

            $script:KeyboardRenderCalls.Count | Should -Be 3
            $script:KeyboardRenderCalls[-1].SlideIndex | Should -Be 1
            $script:KeyboardRenderCalls[-1].RevealStep | Should -Be 0
        }
    }

    It 'uses Page Down to advance without stepping through reveals' {
        InModuleScope TerminalSlides {
            $keys = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
            $keys.Enqueue([ConsoleKeyInfo]::new([char]0, [ConsoleKey]::PageDown, $false, $false, $false))
            $keys.Enqueue([ConsoleKeyInfo]::new([char]0, [ConsoleKey]::Escape, $false, $false, $false))
            Mock Read-TerminalPresentationKey { $keys.Dequeue() }

            Show-TerminalPresentation -Presentation $script:KeyboardDeck

            $script:KeyboardRenderCalls[-1].SlideIndex | Should -Be 1
            $script:KeyboardRenderCalls[-1].RevealStep | Should -Be 0
        }
    }

    It 'moves to the previous slide with <Name> and restores its final reveal' -TestCases @(
        @{ Name = 'Left Arrow'; Key = [ConsoleKey]::LeftArrow; Character = [char]0 }
        @{ Name = 'Backspace'; Key = [ConsoleKey]::Backspace; Character = [char]0 }
        @{ Name = 'P'; Key = [ConsoleKey]::P; Character = 'p' }
        @{ Name = 'Page Up'; Key = [ConsoleKey]::PageUp; Character = [char]0 }
    ) {
        param($Name, $Key, $Character)

        InModuleScope TerminalSlides -Parameters @{ Key = $Key; Character = $Character } {
            param($Key, $Character)
            $keys = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
            $keys.Enqueue([ConsoleKeyInfo]::new([char]0, [ConsoleKey]::End, $false, $false, $false))
            $keys.Enqueue([ConsoleKeyInfo]::new($Character, $Key, $false, $false, $false))
            $keys.Enqueue([ConsoleKeyInfo]::new([char]0, [ConsoleKey]::Escape, $false, $false, $false))
            Mock Read-TerminalPresentationKey { $keys.Dequeue() }

            Show-TerminalPresentation -Presentation $script:KeyboardDeck

            $script:KeyboardRenderCalls[-1].SlideIndex | Should -Be 0
            $script:KeyboardRenderCalls[-1].RevealStep | Should -Be 1
        }
    }

    It 'moves to the first reveal with <Name>' -TestCases @(
        @{ Name = 'Left Arrow'; Key = [ConsoleKey]::LeftArrow; Character = [char]0 }
        @{ Name = 'Backspace'; Key = [ConsoleKey]::Backspace; Character = [char]0 }
        @{ Name = 'P'; Key = [ConsoleKey]::P; Character = 'p' }
    ) {
        param($Name, $Key, $Character)

        InModuleScope TerminalSlides -Parameters @{ Key = $Key; Character = $Character } {
            param($Key, $Character)
            $keys = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
            $keys.Enqueue([ConsoleKeyInfo]::new([char]0, [ConsoleKey]::RightArrow, $false, $false, $false))
            $keys.Enqueue([ConsoleKeyInfo]::new($Character, $Key, $false, $false, $false))
            $keys.Enqueue([ConsoleKeyInfo]::new([char]0, [ConsoleKey]::Escape, $false, $false, $false))
            Mock Read-TerminalPresentationKey { $keys.Dequeue() }

            Show-TerminalPresentation -Presentation $script:KeyboardDeck

            $script:KeyboardRenderCalls[-1].SlideIndex | Should -Be 0
            $script:KeyboardRenderCalls[-1].RevealStep | Should -Be 0
        }
    }

    It 'jumps to the last slide and back to the first slide' {
        InModuleScope TerminalSlides {
            $keys = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
            foreach ($key in [ConsoleKey]::End, [ConsoleKey]::Home, [ConsoleKey]::Escape) {
                $keys.Enqueue([ConsoleKeyInfo]::new([char]0, $key, $false, $false, $false))
            }
            Mock Read-TerminalPresentationKey { $keys.Dequeue() }

            Show-TerminalPresentation -Presentation $script:KeyboardDeck

            $script:KeyboardRenderCalls[1].SlideIndex | Should -Be 1
            $script:KeyboardRenderCalls[-1].SlideIndex | Should -Be 0
            $script:KeyboardRenderCalls[-1].RevealStep | Should -Be 0
        }
    }

    It 'toggles <Name> and renders the resulting state' -TestCases @(
        @{ Name = 'notes'; Key = [ConsoleKey]::S; Character = 's'; Property = 'ShowNotes'; Expected = $true }
        @{ Name = 'overview'; Key = [ConsoleKey]::O; Character = 'o'; Property = 'DisplayMode'; Expected = 'Overview' }
        @{ Name = 'blank screen'; Key = [ConsoleKey]::B; Character = 'b'; Property = 'DisplayMode'; Expected = 'Blank' }
        @{ Name = 'timer'; Key = [ConsoleKey]::T; Character = 't'; Property = 'ShowTimer'; Expected = $true }
        @{ Name = 'help with H'; Key = [ConsoleKey]::H; Character = 'h'; Property = 'DisplayMode'; Expected = 'Help' }
        @{ Name = 'help with question mark'; Key = [ConsoleKey]::Oem2; Character = '?'; Property = 'DisplayMode'; Expected = 'Help' }
    ) {
        param($Name, $Key, $Character, $Property, $Expected)

        InModuleScope TerminalSlides -Parameters @{ Key = $Key; Character = $Character; Property = $Property; Expected = $Expected } {
            param($Key, $Character, $Property, $Expected)
            $keys = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
            $keys.Enqueue([ConsoleKeyInfo]::new($Character, $Key, $false, $false, $false))
            $keys.Enqueue([ConsoleKeyInfo]::new([char]0, [ConsoleKey]::Escape, $false, $false, $false))
            Mock Read-TerminalPresentationKey { $keys.Dequeue() }

            Show-TerminalPresentation -Presentation $script:KeyboardDeck

            $script:KeyboardRenderCalls.Count | Should -Be 2
            $script:KeyboardRenderCalls[-1].$Property | Should -Be $Expected
        }
    }

    It 'quits immediately with <Name>' -TestCases @(
        @{ Name = 'Q'; Key = [ConsoleKey]::Q; Character = 'q' }
        @{ Name = 'Escape'; Key = [ConsoleKey]::Escape; Character = [char]0 }
    ) {
        param($Name, $Key, $Character)

        InModuleScope TerminalSlides -Parameters @{ Key = $Key; Character = $Character } {
            param($Key, $Character)
            Mock Read-TerminalPresentationKey {
                [ConsoleKeyInfo]::new($Character, $Key, $false, $false, $false)
            }

            Show-TerminalPresentation -Presentation $script:KeyboardDeck

            $script:KeyboardRenderCalls.Count | Should -Be 1
        }
    }

    It 'renders every slide once in a non-interactive terminal' {
        InModuleScope TerminalSlides {
            Mock Get-TerminalPresentationCapability {
                [TerminalSlides.Schema.V1.TerminalCapability]@{
                    AnsiSupport = $false
                    Interactive = $false
                    IsRedirected = $true
                    AlternateBuffer = $false
                }
            }
            Mock Render-TerminalPresentationToString {
                param($Presentation, $SlideIndex)
                return "slide-$SlideIndex"
            }

            $output = @(Show-TerminalPresentation -Presentation $script:KeyboardDeck)

            Should -Invoke Render-TerminalPresentationToString -Times 2 -Exactly
            $output[0] | Should -Be 'slide-0'
            $output[-1] | Should -Be 'slide-1'
        }
    }
}
