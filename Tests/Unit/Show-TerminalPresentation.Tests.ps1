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

    It 'keeps block images as the default and exposes an explicit Sixel renderer' {
        $parameter = (Get-Command Show-TerminalPresentation).Parameters.ImageRenderer
        $validateSet = $parameter.Attributes |
            Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } |
            Select-Object -First 1

        $parameter | Should -Not -BeNullOrEmpty
        $validateSet.ValidValues | Should -Be @('Blocks', 'Sixel')

        InModuleScope TerminalSlides {
            Mock Get-TerminalNativeImageOverlay { 'native-image' }
            Mock Read-TerminalPresentationKey {
                [ConsoleKeyInfo]::new([char]0, [ConsoleKey]::Escape, $false, $false, $false)
            }

            Show-TerminalPresentation -Presentation $script:KeyboardDeck

            Should -Not -Invoke Get-TerminalNativeImageOverlay
        }
    }

    It 'writes opted-in Sixel overlays after the ANSI frame' {
        InModuleScope TerminalSlides {
            $script:Writes = [System.Collections.Generic.List[string]]::new()
            $script:SharedPlan = [pscustomobject]@{ Placements = @() }
            Mock Get-TerminalSlideLayoutPlan { $script:SharedPlan }
            Mock Get-TerminalNativeImageOverlay { 'native-image' }
            Mock Write-Host {
                param($Object)
                if ($null -ne $Object) { $script:Writes.Add([string]$Object) }
            }
            Mock Read-TerminalPresentationKey {
                [ConsoleKeyInfo]::new([char]0, [ConsoleKey]::Escape, $false, $false, $false)
            }

            Show-TerminalPresentation -Presentation $script:KeyboardDeck -ImageRenderer Sixel

            Should -Invoke Get-TerminalNativeImageOverlay -Times 1 -Exactly -ParameterFilter {
                $SlideIndex -eq 0 -and $RevealStep -eq 0 -and $DisplayMode -eq 'Slide' -and
                $LayoutPlan -eq $script:SharedPlan
            }
            Should -Invoke Render-TerminalPresentationToString -Times 1 -Exactly -ParameterFilter {
                $LayoutPlan -eq $script:SharedPlan
            }
            Should -Invoke Get-TerminalSlideLayoutPlan -Times 1 -Exactly
            $frameIndex = $script:Writes.IndexOf('frame')
            $overlayIndex = $script:Writes.IndexOf('native-image')
            $frameIndex | Should -BeGreaterOrEqual 0
            $overlayIndex | Should -BeGreaterThan $frameIndex
        }
    }

    It 'defers and deduplicates Sixel warnings until the presentation buffer closes' {
        InModuleScope TerminalSlides {
            $keys = [System.Collections.Generic.Queue[System.ConsoleKeyInfo]]::new()
            $keys.Enqueue([ConsoleKeyInfo]::new([char]0, [ConsoleKey]::RightArrow, $false, $false, $false))
            $keys.Enqueue([ConsoleKeyInfo]::new([char]0, [ConsoleKey]::Escape, $false, $false, $false))
            Mock Read-TerminalPresentationKey { $keys.Dequeue() }
            Mock Get-TerminalNativeImageOverlay { Write-Warning 'Sixel unavailable' }

            $output = @(Show-TerminalPresentation -Presentation $script:KeyboardDeck `
                -ImageRenderer Sixel -WarningAction Continue 3>&1)
            $warnings = @($output |
                Where-Object { $_ -is [System.Management.Automation.WarningRecord] })

            Should -Invoke Get-TerminalNativeImageOverlay -Times 2 -Exactly
            $warnings | Should -HaveCount 1
            $warnings[0].Message | Should -Be 'Sixel unavailable'
        }
    }
}

Describe 'Native terminal image overlays' {
    BeforeAll {
        $script:RepositoryRoot = Join-Path $PSScriptRoot '..' '..'
        Import-Module (Join-Path $script:RepositoryRoot 'TerminalSlides.psd1') -Force
    }

    It 'calculates a height-bounded Sixel width and rejects invalid dimensions' {
        InModuleScope TerminalSlides {
            $cellSize = [pscustomobject]@{ PixelWidth = 10; PixelHeight = 20 }

            Get-TerminalSixelFitWidth -ImageWidth 1200 -ImageHeight 800 `
                -AvailableWidth 136 -AvailableHeight 25 -CellSize $cellSize |
                Should -Be 75
            Get-TerminalSixelFitWidth -ImageWidth 1 -ImageHeight 1000 `
                -AvailableWidth 10 -AvailableHeight 1 -CellSize $cellSize |
                Should -Be 0
            {
                Get-TerminalSixelFitWidth -ImageWidth 0 -ImageHeight 800 `
                    -AvailableWidth 10 -AvailableHeight 5 -CellSize $cellSize
            } | Should -Throw '*dimensions must be positive*'
        }
    }

    It 'fits a wide Sixel image above the slide progress row' {
        InModuleScope TerminalSlides -Parameters @{ RepositoryRoot = $script:RepositoryRoot } {
            param($RepositoryRoot)
            $path = Join-Path $RepositoryRoot 'Assets/presentation-team-photo.jpg'
            $deck = New-TerminalPresentation -Title 'Native image' -Width 140 -Height 32
            $deck | Add-TerminalSlide -Title 'Photo' -Layout ImageFocus -Content {
                Add-SlideImage -Path $path -AltText 'Presentation team' -Region Image
            } | Out-Null
            $capability = [TerminalSlides.Schema.V1.TerminalCapability]@{
                Width = 140
                Height = 32
                AnsiSupport = $true
                TrueColorSupport = $true
                Color256Support = $true
                UnicodeSupport = $true
                Interactive = $true
                IsRedirected = $false
            }
            $pixelImage = Get-SpectreImage -ImagePath $path -Format Sixel -Force
            $layoutPlan = Get-TerminalSlideLayoutPlan -Presentation $deck -SlideIndex 0 `
                -RevealStep 0 -Capability $capability
            $placement = $layoutPlan.Placements |
                Where-Object {
                    $_.Element.Kind -eq [TerminalSlides.Schema.V1.ElementKind]::Image
                } |
                Select-Object -First 1
            $availableHeight = ($placement.Region.Y + $placement.Region.Height) - $placement.StartY
            $cellSize = [PwshSpectreConsole.Terminal.Compatibility]::GetCellSize()
            $expectedWidth = [Math]::Floor(
                ($availableHeight * $cellSize.PixelHeight * $pixelImage.Width) /
                ($cellSize.PixelWidth * $pixelImage.Height)
            )
            Mock Get-SpectreImage { $pixelImage }

            $overlay = Get-TerminalNativeImageOverlay -Presentation $deck -SlideIndex 0 `
                -RevealStep 0 -DisplayMode Slide -Capability $capability -LayoutPlan $layoutPlan

            $pixelImage.MaxWidth | Should -Be $expectedWidth
            $pixelImage.MaxWidth | Should -BeLessThan $placement.Region.Width
            $overlay | Should -Match ([regex]::Escape("`eP"))
            $sixelHeader = [regex]::Match(
                $overlay,
                [regex]::Escape("`eP") + '[^"]*"1;1;(?<Width>\d+);(?<Height>\d+)'
            )
            $sixelHeader.Success | Should -BeTrue
            $renderedCellHeight = [Math]::Ceiling(
                [int]$sixelHeader.Groups['Height'].Value / $cellSize.PixelHeight
            )
            $renderedBottom = $placement.StartY + $renderedCellHeight - 1
            $progressRow = $layoutPlan.Dimensions.Height - 2
            $renderedBottom | Should -BeLessThan $progressRow
        }
    }

    It 'shares one layout plan between the cell and Sixel renderers' {
        InModuleScope TerminalSlides -Parameters @{ RepositoryRoot = $script:RepositoryRoot } {
            param($RepositoryRoot)
            $path = Join-Path $RepositoryRoot 'Assets/presentation-team-photo.jpg'
            $deck = New-TerminalPresentation -Title 'Native image' -Width 40 -Height 18
            $deck | Add-TerminalSlide -Title 'Photo' -Layout ImageFocus -Content {
                Add-SlideImage -Path $path -AltText 'Presentation team'
            } | Out-Null
            $capability = [TerminalSlides.Schema.V1.TerminalCapability]@{
                Width = 40
                Height = 18
                AnsiSupport = $true
                TrueColorSupport = $true
                Color256Support = $true
                UnicodeSupport = $true
                Interactive = $true
                IsRedirected = $false
            }
            $pixelImage = Get-SpectreImage -ImagePath $path -Format Sixel -Force
            $layoutPlan = Get-TerminalSlideLayoutPlan -Presentation $deck -SlideIndex 0 `
                -RevealStep 0 -Capability $capability
            Mock Get-SpectreImage { $pixelImage }
            Mock Get-TerminalSlideLayoutPlan { throw 'Layout plan should be reused.' }

            $frame = Get-RenderedSlideFrame -Presentation $deck -SlideIndex 0 `
                -RevealStep 0 -Capability $capability -LayoutPlan $layoutPlan
            $overlay = Get-TerminalNativeImageOverlay -Presentation $deck -SlideIndex 0 `
                -RevealStep 0 -DisplayMode Slide -Capability $capability -LayoutPlan $layoutPlan

            $frame | Should -Not -BeNullOrEmpty
            $overlay | Should -Match ([regex]::Escape("`e["))
            $overlay | Should -Match ([regex]::Escape("`eP"))
            $pixelImage.MaxWidth | Should -BeLessOrEqual 36
            Should -Not -Invoke Get-TerminalSlideLayoutPlan
            Should -Invoke Get-SpectreImage -Times 1 -Exactly -ParameterFilter {
                [IO.Path]::GetFullPath($ImagePath) -eq [IO.Path]::GetFullPath($path) -and
                [string]$Format -eq 'Sixel' -and -not $Force
            }
        }
    }

    It 'omits native images outside slide mode and before their reveal step' {
        InModuleScope TerminalSlides -Parameters @{ RepositoryRoot = $script:RepositoryRoot } {
            param($RepositoryRoot)
            $path = Join-Path $RepositoryRoot 'Assets/presentation-team-photo.jpg'
            $deck = New-TerminalPresentation -Title 'Native image' -Width 40 -Height 18
            $deck | Add-TerminalSlide -Title 'Photo' -Layout ImageFocus -Content {
                Add-SlideImage -Path $path -AltText 'Presentation team' -RevealStep 1
            } | Out-Null
            $capability = [TerminalSlides.Schema.V1.TerminalCapability]@{
                Width = 40
                Height = 18
                AnsiSupport = $true
                Interactive = $true
                IsRedirected = $false
            }
            Mock Get-SpectreImage { throw 'should not render' }

            Get-TerminalNativeImageOverlay -Presentation $deck -SlideIndex 0 `
                -RevealStep 0 -DisplayMode Slide -Capability $capability | Should -BeNullOrEmpty
            Get-TerminalNativeImageOverlay -Presentation $deck -SlideIndex 0 `
                -RevealStep 1 -DisplayMode Help -Capability $capability | Should -BeNullOrEmpty

            Should -Not -Invoke Get-SpectreImage
        }
    }

    It 'warns and preserves the block fallback when Sixel is unavailable' {
        InModuleScope TerminalSlides -Parameters @{ RepositoryRoot = $script:RepositoryRoot } {
            param($RepositoryRoot)
            $path = Join-Path $RepositoryRoot 'Assets/presentation-team-photo.jpg'
            $deck = New-TerminalPresentation -Title 'Native image' -Width 40 -Height 18
            $deck | Add-TerminalSlide -Title 'Photo' -Layout ImageFocus -Content {
                Add-SlideImage -Path $path -AltText 'Presentation team'
            } | Out-Null
            $capability = [TerminalSlides.Schema.V1.TerminalCapability]@{
                Width = 40
                Height = 18
                AnsiSupport = $true
                Interactive = $true
                IsRedirected = $false
            }
            $blockImage = Get-SpectreImage -ImagePath $path -Format Blocks
            Mock Get-SpectreImage {
                if ([string]$Format -eq 'Sixel') { throw 'Terminal does not support Sixel' }
                return $blockImage
            }
            $warnings = @()

            $overlay = Get-TerminalNativeImageOverlay -Presentation $deck -SlideIndex 0 `
                -RevealStep 0 -DisplayMode Slide -Capability $capability `
                -WarningVariable warnings -WarningAction Continue

            $overlay | Should -BeNullOrEmpty
            $warnings | Should -HaveCount 1
            $warnings[0].Message | Should -Match 'Sixel rendering is unavailable'
        }
    }

    It 'preserves the fallback when an extreme aspect ratio cannot fit one cell' {
        InModuleScope TerminalSlides -Parameters @{ RepositoryRoot = $script:RepositoryRoot } {
            param($RepositoryRoot)
            $path = Join-Path $RepositoryRoot 'Assets/presentation-team-photo.jpg'
            $deck = New-TerminalPresentation -Title 'Tall image' -Width 40 -Height 18
            $deck | Add-TerminalSlide -Title 'Photo' -Layout ImageFocus -Content {
                Add-SlideImage -Path $path -AltText 'Tall image' -Region Image
            } | Out-Null
            $capability = [TerminalSlides.Schema.V1.TerminalCapability]@{
                Width = 40
                Height = 18
                AnsiSupport = $true
                Interactive = $true
                IsRedirected = $false
            }
            $layoutPlan = Get-TerminalSlideLayoutPlan -Presentation $deck -SlideIndex 0 `
                -RevealStep 0 -Capability $capability
            $tallImage = [pscustomobject]@{ Width = 1; Height = 10000; MaxWidth = 0 }
            Mock Get-SpectreImage { $tallImage }
            $warnings = @()

            Get-TerminalNativeImageOverlay -Presentation $deck -SlideIndex 0 `
                -RevealStep 0 -DisplayMode Slide -Capability $capability `
                -LayoutPlan $layoutPlan -WarningAction SilentlyContinue `
                -WarningVariable warnings | Should -BeNullOrEmpty

            $warnings[-1].Message | Should -Match 'Sixel rendering is unavailable'
        }
    }

    It 'maps reduced color capabilities into Spectre render options' {
        InModuleScope TerminalSlides {
            $eightBit = New-TerminalSpectreRenderOptions -Width 10 -Height 5 -Capability (
                [TerminalSlides.Schema.V1.TerminalCapability]@{ Color256Support = $true }
            )
            $noColor = New-TerminalSpectreRenderOptions -Width 10 -Height 5 -Capability (
                [TerminalSlides.Schema.V1.TerminalCapability]@{}
            )

            $eightBit.ColorSystem | Should -Be ([Spectre.Console.ColorSystem]::EightBit)
            $noColor.ColorSystem | Should -Be ([Spectre.Console.ColorSystem]::NoColors)
            $eightBit.Ansi | Should -BeFalse
            $noColor.Ansi | Should -BeFalse
        }
    }

    It 'falls back when the native image is missing or returns no Sixel stream' {
        InModuleScope TerminalSlides -Parameters @{ RepositoryRoot = $script:RepositoryRoot } {
            param($RepositoryRoot)
            $capability = [TerminalSlides.Schema.V1.TerminalCapability]@{
                Width = 40
                Height = 18
                AnsiSupport = $true
                Interactive = $true
                IsRedirected = $false
            }
            $missingDeck = New-TerminalPresentation -Title 'Missing image' -Width 40 -Height 18
            $missingDeck | Add-TerminalSlide -Title 'Photo' -Layout ImageFocus -Content {
                Add-SlideImage -Path (Join-Path $RepositoryRoot 'Assets/not-present.png') -AltText 'Missing'
            } | Out-Null
            $warnings = @()

            Get-TerminalNativeImageOverlay -Presentation $missingDeck -SlideIndex 0 `
                -RevealStep 0 -DisplayMode Slide -Capability $capability `
                -WarningAction SilentlyContinue -WarningVariable warnings | Should -BeNullOrEmpty
            $warnings[-1].Message | Should -Match 'Sixel rendering is unavailable'

            $path = Join-Path $RepositoryRoot 'Assets/presentation-team-photo.jpg'
            $blockDeck = New-TerminalPresentation -Title 'Cell image' -Width 40 -Height 18
            $blockDeck | Add-TerminalSlide -Title 'Photo' -Layout ImageFocus -Content {
                Add-SlideImage -Path $path -AltText 'Presentation team'
            } | Out-Null
            $blockImage = Get-SpectreImage -ImagePath $path -Format Blocks
            Mock Get-SpectreImage { $blockImage }
            $warnings = @()

            Get-TerminalNativeImageOverlay -Presentation $blockDeck -SlideIndex 0 `
                -RevealStep 0 -DisplayMode Slide -Capability $capability `
                -WarningAction SilentlyContinue -WarningVariable warnings | Should -BeNullOrEmpty
            $warnings[-1].Message | Should -Match 'Sixel rendering is unavailable'
        }
    }
}
