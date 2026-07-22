Describe 'Core review remediation' {
    BeforeAll {
        $script:ModulePath = Join-Path $PSScriptRoot '..' '..' 'TerminalSlides.psd1'
        Import-Module $script:ModulePath -Force
    }

    It 'blocks .NET method calls in SafeMode' {
        $deck = New-TerminalPresentation -Title 'Safe'

        {
            $deck | Add-TerminalSlide -Title 'Blocked' -SafeMode -Content {
                [System.Environment]::GetEnvironmentVariables()
            } | Out-Null
        } | Should -Throw '*restricted language*'

        $deck.Slides.Count | Should -Be 0
    }

    It 'does not export generic diagram helper commands' {
        Get-Command -Name Node -Module TerminalSlides -ErrorAction SilentlyContinue |
            Should -BeNullOrEmpty
        Get-Command -Name Edge -Module TerminalSlides -ErrorAction SilentlyContinue |
            Should -BeNullOrEmpty
        Get-Command -Name Add-SlideDiagramNode -Module TerminalSlides |
            Should -Not -BeNullOrEmpty
        Get-Command -Name Add-SlideDiagramEdge -Module TerminalSlides |
            Should -Not -BeNullOrEmpty
    }

    It 'excludes hidden slides from presentation output' {
        $deck = New-TerminalPresentation -Title 'Hidden slides'
        $deck | Add-TerminalSlide -Title 'Visible' -Content {
            Add-SlideText 'VISIBLE-CONTENT'
        } | Out-Null
        $deck | Add-TerminalSlide -Title 'Hidden' -Hidden -Content {
            Add-SlideText 'HIDDEN-CONTENT'
        } | Out-Null

        $output = Show-TerminalPresentation -Presentation $deck | Out-String

        $output | Should -Match 'VISIBLE-CONTENT'
        $output | Should -Not -Match 'HIDDEN-CONTENT'
        $output | Should -Match 'Slide 1 of 1'
    }

    It 'reports vertically clipped slide content' {
        $deck = New-TerminalPresentation -Title 'Overflow'
        $content = (1..100 | ForEach-Object { "line $_" }) -join "`n"
        $deck | Add-TerminalSlide -Title 'Overflow' -Content {
            Add-SlideText $content
        } | Out-Null

        $result = Test-TerminalPresentation -Presentation $deck -Viewport '40x10'

        $result.Fits | Should -BeFalse
        $result.OverflowLines | Should -BeGreaterThan 0
    }

    It 'accepts automatic dimensions and rejects unsupported fixed dimensions' {
        { New-TerminalPresentation -Title 'Automatic' -Width 0 -Height 0 } |
            Should -Not -Throw
        { New-TerminalPresentation -Title 'Too narrow' -Width 19 } |
            Should -Throw
        { New-TerminalPresentation -Title 'Too short' -Height 9 } |
            Should -Throw
    }

    It 'measures and places Unicode grapheme clusters by terminal cell width' {
        InModuleScope TerminalSlides {
            Measure-TextWidth -Text '界' | Should -Be 2
            Measure-TextWidth -Text "e$([char]0x0301)" | Should -Be 1

            $frame = [FrameBuffer]::new(6, 1)
            Set-FrameText -FrameBuffer $frame -X 0 -Y 0 -Text '界X'
            $frame.Cells[0][0].Char | Should -Be '界'
            $frame.Cells[0][1].Char | Should -Be ' '
            $frame.Cells[0][1].Continuation | Should -BeTrue
            $frame.Cells[0][2].Char | Should -Be 'X'
            Measure-TextWidth -Text $frame.GetRowText(0) | Should -Be $frame.Width
            Measure-TextWidth -Text (Strip-AnsiSequences $frame.Render($true, $false)) | Should -Be $frame.Width

            $edge = [FrameBuffer]::new(1, 1)
            Set-FrameText -FrameBuffer $edge -X 0 -Y 0 -Text '界'
            $edge.GetRowText(0) | Should -Be ' '

            Set-FrameText -FrameBuffer $frame -X 0 -Y 0 -Text '語'
            $frame.GetRowText(0) | Should -Be '語X   '
            Set-FrameText -FrameBuffer $frame -X 0 -Y 0 -Text 'A'
            $frame.Cells[0][1].Continuation | Should -BeFalse
            $frame.GetRowText(0) | Should -Be 'A X   '
            Set-FrameText -FrameBuffer $frame -X 0 -Y 0 -Text '界'
            Set-FrameText -FrameBuffer $frame -X 1 -Y 0 -Text 'B'
            $frame.Cells[0][0].Char | Should -Be ' '
            $frame.Cells[0][1].Char | Should -Be 'B'
            Measure-TextWidth -Text $frame.GetRowText(0) | Should -Be $frame.Width

            Set-FrameText -FrameBuffer $frame -X 0 -Y 0 -Text '界'
            Fill-FrameRegion -FrameBuffer $frame -X 1 -Y 0 -Width 1 -Height 1 -Char '.'
            $frame.Cells[0][0].Char | Should -Be ' '
            $frame.Cells[0][1].Char | Should -Be '.'
            $boxFrame = [FrameBuffer]::new(6, 2)
            Set-FrameText -FrameBuffer $boxFrame -X 0 -Y 0 -Text '界'
            Draw-FrameBox -FrameBuffer $boxFrame -X 1 -Y 0 -Width 3 -Height 2
            @($boxFrame.Cells[0] | Where-Object Continuation).Count | Should -Be 0
            Measure-TextWidth -Text $boxFrame.GetRowText(0) | Should -Be $boxFrame.Width
        }
    }

    It 'places emoji-presentation graphemes in their two terminal cells' {
        InModuleScope TerminalSlides {
            foreach ($grapheme in '🇺🇸', '1️⃣', '❤️', '©️', '☕', '⚽', '⏰', '⌚') {
                Measure-TextWidth -Text $grapheme | Should -Be 2
                Limit-TextToCellWidth -Text $grapheme -Width 1 | Should -BeNullOrEmpty
                Limit-TextToCellWidth -Text $grapheme -Width 2 | Should -Be $grapheme

                $frame = [FrameBuffer]::new(6, 1)
                Set-FrameText -FrameBuffer $frame -X 0 -Y 0 -Text ($grapheme + 'X')
                $frame.Cells[0][0].Char | Should -Be $grapheme
                $frame.Cells[0][1].Continuation | Should -BeTrue
                $frame.Cells[0][2].Char | Should -Be 'X'
                Measure-TextWidth -Text $frame.GetRowText(0) | Should -Be $frame.Width

                Set-FrameText -FrameBuffer $frame -X 0 -Y 0 -Text 'A'
                $frame.Cells[0][1].Continuation | Should -BeFalse
                $frame.GetRowText(0) | Should -Be 'A X   '

                Set-FrameText -FrameBuffer $frame -X 0 -Y 0 -Text $grapheme
                Set-FrameText -FrameBuffer $frame -X 1 -Y 0 -Text 'B'
                $frame.Cells[0][0].Char | Should -Be ' '
                $frame.Cells[0][1].Continuation | Should -BeFalse
                $frame.Cells[0][1].Char | Should -Be 'B'

                $edge = [FrameBuffer]::new(1, 1)
                Set-FrameText -FrameBuffer $edge -X 0 -Y 0 -Text $grapheme
                $edge.GetRowText(0) | Should -Be ' '
            }

            $standaloneVariationSelector = [string][char]0xFE0F
            $combiningVariationSelector = "$([char]0x0301)$([char]0xFE0F)"
            $standaloneKeycap = [string][char]0x20E3
            $combiningKeycap = "$([char]0x0301)$([char]0x20E3)"
            foreach ($zeroWidthText in $standaloneVariationSelector, $combiningVariationSelector, $standaloneKeycap, $combiningKeycap) {
                Measure-TextWidth -Text $zeroWidthText | Should -Be 0
                Limit-TextToCellWidth -Text ($zeroWidthText + 'X') -Width 0 | Should -Be $zeroWidthText
                Limit-TextToCellWidth -Text ($zeroWidthText + 'X') -Width 1 | Should -Be ($zeroWidthText + 'X')

                $frame = [FrameBuffer]::new(3, 1)
                Set-FrameText -FrameBuffer $frame -X 0 -Y 0 -Text ($zeroWidthText + 'X')
                $frame.Cells[0][0].Char | Should -Be 'X'
                @($frame.Cells[0] | Where-Object Continuation).Count | Should -Be 0
                $frame.GetRowText(0) | Should -Be 'X  '
            }

            $textKeycap = '1' + $standaloneKeycap
            Measure-TextWidth -Text $textKeycap | Should -Be 1
            Limit-TextToCellWidth -Text $textKeycap -Width 0 | Should -BeNullOrEmpty
            Limit-TextToCellWidth -Text $textKeycap -Width 1 | Should -Be $textKeycap
            $textKeycapFrame = [FrameBuffer]::new(3, 1)
            Set-FrameText -FrameBuffer $textKeycapFrame -X 0 -Y 0 -Text ($textKeycap + 'X')
            $textKeycapFrame.Cells[0][0].Char | Should -Be $textKeycap
            $textKeycapFrame.Cells[0][1].Char | Should -Be 'X'
            @($textKeycapFrame.Cells[0] | Where-Object Continuation).Count | Should -Be 0

            Measure-TextWidth -Text 'A' | Should -Be 1
            Measure-TextWidth -Text '界' | Should -Be 2
            Measure-TextWidth -Text '👨‍👩‍👧‍👦' | Should -Be 2
            foreach ($presentation in @(
                @{ Plain = '☀'; Emoji = '☀️' }
                @{ Plain = '©'; Emoji = '©️' }
                @{ Plain = '™'; Emoji = '™️' }
            )) {
                Measure-TextWidth -Text $presentation.Plain | Should -Be 1
                Measure-TextWidth -Text $presentation.Emoji | Should -Be 2
            }
        }
    }

    It 'keeps the generated terminal-wide bounds ordered and disjoint' {
        InModuleScope TerminalSlides {
            ($script:TerminalWideIntervalBounds.Count % 2) | Should -Be 0
            $previousEnd = -1
            for ($index = 0; $index -lt $script:TerminalWideIntervalBounds.Count; $index += 2) {
                $start = $script:TerminalWideIntervalBounds[$index]
                $end = $script:TerminalWideIntervalBounds[$index + 1]
                $start | Should -BeGreaterThan $previousEnd
                ($start -le $end) | Should -BeTrue
                $previousEnd = $end
            }
        }
    }

    It 'expands tabs at terminal-compatible cell stops' {
        InModuleScope TerminalSlides {
            Measure-TextWidth -Text "`t" | Should -Be 8
            Measure-TextWidth -Text "`t" -StartColumn 3 | Should -Be 5
            Measure-TextWidth -Text "A`tB" | Should -Be 9
            Measure-TextWidth -Text "`t`t" | Should -Be 16
            Measure-TextWidth -Text "界`tX" | Should -Be 9
            Expand-TerminalTabs -Text "界`tX" | Should -Be ('界' + (' ' * 6) + 'X')
            Limit-TextToCellWidth -Text "界`tX" -Width 8 | Should -Be ('界' + (' ' * 6))
            Limit-TextToCellWidth -Text "界`tX" -Width 9 | Should -Be ('界' + (' ' * 6) + 'X')
            Format-WordWrap -Text "`tWrite-Host" -Width 20 -OverflowBehavior Scroll |
                Should -Be "`tWrite-Host"
            Format-WordWrap -Text "`tWrite-Host" -Width 20 -OverflowBehavior Scroll -StartColumn 3 |
                Should -Be "`tWrite-Host"

            Limit-TextToCellWidth -Text "`tX" -Width 4 | Should -Be (' ' * 4)
            $splitTab = Split-TextByCellWidth -Text "`tX" -Width 4
            $splitTab.Count | Should -Be 3
            $splitTab[0] | Should -Be (' ' * 4)
            $splitTab[1] | Should -Be (' ' * 4)
            $splitTab[2] | Should -Be 'X'

            $preservedElements = Get-TerminalTextElements -Text "`tX" -StartColumn 3 -PreserveTabs
            $preservedElements.Count | Should -Be 2
            $preservedElements[0].Text | Should -Be "`t"
            $preservedElements[0].Width | Should -Be 5
            Limit-TextToCellWidth -Text "`tX" -Width 5 -StartColumn 3 -PreserveTabs | Should -Be "`t"
            $preservedSplit = Split-TextByCellWidth -Text "A`tB" -Width 8 -PreserveTabs
            $preservedSplit.Count | Should -Be 2
            $preservedSplit[0] | Should -Be "A`t"
            $preservedSplit[1] | Should -Be 'B'

            $wrappedAtOffset = Format-WordWrap -Text "A`tB" -Width 20 -OverflowBehavior Scroll -StartColumn 2
            $wrappedAtOffset | Should -Be "A`tB"
            $rawFrame = [FrameBuffer]::new(14, 1)
            $wrappedFrame = [FrameBuffer]::new(14, 1)
            Set-FrameText -FrameBuffer $rawFrame -X 2 -Y 0 -Text "A`tB"
            Set-FrameText -FrameBuffer $wrappedFrame -X 2 -Y 0 -Text $wrappedAtOffset[0]
            $rawFrame.Cells[0][8].Char | Should -Be 'B'
            $wrappedFrame.Cells[0][8].Char | Should -Be 'B'

            $escape = [string][char]0x1B
            $ansiText = "$escape[31mA`tB$escape[0m"
            Measure-TextWidth -Text $ansiText -StartColumn 2 | Should -Be 7
            Format-WordWrap -Text $ansiText -Width 20 -OverflowBehavior Scroll -StartColumn 2 |
                Should -Be "A`tB"

            $offsetFrame = [FrameBuffer]::new(20, 1)
            Set-FrameText -FrameBuffer $offsetFrame -X 3 -Y 0 -Text "`tX" -Foreground '#123456'
            $offsetFrame.Cells[0][8].Char | Should -Be 'X'
            @($offsetFrame.Cells[0] | Where-Object Continuation).Count | Should -Be 0
            foreach ($column in 3..7) {
                $offsetFrame.Cells[0][$column].Char | Should -Be ' '
                $offsetFrame.Cells[0][$column].Fg | Should -Be '#123456'
            }

            $repeatedFrame = [FrameBuffer]::new(20, 1)
            Set-FrameText -FrameBuffer $repeatedFrame -X 2 -Y 0 -Text "`t`tX"
            $repeatedFrame.Cells[0][16].Char | Should -Be 'X'

            $wideFrame = [FrameBuffer]::new(12, 1)
            Set-FrameText -FrameBuffer $wideFrame -X 1 -Y 0 -Text "界`tX"
            $wideFrame.Cells[0][1].Char | Should -Be '界'
            $wideFrame.Cells[0][2].Continuation | Should -BeTrue
            $wideFrame.Cells[0][8].Char | Should -Be 'X'

            $deck = New-TerminalPresentation -Title 'Tabs' -Width 20 -Height 10
            $deck | Add-TerminalSlide -Title 'Slide' -Content { Add-SlideText "A`tB" -OverflowBehavior Scroll } | Out-Null
            $plan = Get-TerminalSlideLayoutPlan -Presentation $deck -SlideIndex 0 -Capability ([TerminalSlides.Schema.V1.TerminalCapability]::new())
            $textPlacement = $plan.Placements | Where-Object { (Get-TerminalElementPayload $_.Element).Kind -eq 'Text' }
            (Get-TerminalStyledLineText $textPlacement.Lines[0]) | Should -Be ('A' + (' ' * 5) + 'B')
        }
    }

    It 'prepares every render line at its placement origin before layout and clipping' {
        InModuleScope TerminalSlides {
            $styled = [TerminalStyledLine]::new()
            Add-TerminalStyledRun -Line $styled -Text 'A' -Foreground '#FF0000'
            Add-TerminalStyledRun -Line $styled -Text "`tB" -Foreground '#00FF00' -Bold

            $prepared = ConvertTo-TerminalPreparedLine -Line $styled -StartColumn 2 -MaxWidth 4
            $prepared.Width | Should -Be 7
            $prepared.RenderedWidth | Should -Be 4
            $prepared.AvailableWidth | Should -Be 4
            $prepared.StartColumn | Should -Be 2
            $prepared.GetText() | Should -Be ('A' + (' ' * 3))
            $prepared.Runs.Count | Should -Be 2
            $prepared.Runs[0].Foreground | Should -Be '#FF0000'
            $prepared.Runs[1].Foreground | Should -Be '#00FF00'
            $prepared.Runs[1].Bold | Should -BeTrue
            $prepared.Runs[1].Width | Should -Be 3
            $prepared.ToString() | Should -Be $prepared.GetText()
            Get-TerminalStyledLineText $styled | Should -Be "A`tB"
            Get-TerminalStyledLineText 'plain' | Should -Be 'plain'

            $escape = [string][char]0x1B
            $unbounded = ConvertTo-TerminalPreparedLine -Line "$escape[31mA`tB$escape[0m" -StartColumn 2
            $unbounded.AvailableWidth | Should -Be ([int]::MaxValue)
            $unbounded.Width | Should -Be 7
            $unbounded.GetText() | Should -Be ('A' + (' ' * 5) + 'B')

            $theme = Get-ResolvedTheme Midnight
            $rightElement = New-InternalSlideElement -Kind Text -Payload ([TerminalSlides.Schema.V1.TextPayload]::new('')) -Alignment Right
            $rightLine = ConvertTo-TerminalPreparedLine -Line "A`tB" -StartColumn 2 -MaxWidth 16 -Alignment Right
            $rightLine.StartColumn | Should -Be 14
            $rightLine.Width | Should -Be 3
            $rightLine.RenderedWidth | Should -Be 3
            $rightFrame = [FrameBuffer]::new(20, 1)
            Write-LinesToFrame -FrameBuffer $rightFrame -Lines @($rightLine) -Region @{ X=2; Y=0; Width=16; Height=1 } -Theme $theme -Element $rightElement -StartY 0 | Should -Be 1
            $rightFrame.Cells[0][14].Char | Should -Be 'A'
            $rightFrame.Cells[0][16].Char | Should -Be 'B'
            $rightFrame.Cells[0][18].Char | Should -Be ' '

            $quoteDeck = New-TerminalPresentation -Title 'Quote' -Width 20 -Height 10
            $quoteDeck | Add-TerminalSlide -Title 'Slide' -Layout Quote -Content {
                Add-SlideQuote -Text 'Q' -Attribution "A`t" -Region Quote
            } | Out-Null
            $quoteDeck.Slides[0].Elements[0].ForegroundColor = '#123456'
            $capability = [TerminalSlides.Schema.V1.TerminalCapability]@{ Width=20; Height=10; AnsiSupport=$true }
            $quotePlan = Get-TerminalSlideLayoutPlan -Presentation $quoteDeck -SlideIndex 0 -Capability $capability
            $quotePlacement = $quotePlan.Placements | Where-Object { (Get-TerminalElementPayload $_.Element).Kind -eq 'Quote' }
            $attribution = $quotePlacement.Lines[1]
            $attribution.GetType().Name | Should -Be 'TerminalPreparedLine'
            $attribution.StartColumn | Should -Be 6
            $attribution.Width | Should -Be 10
            $attribution.RenderedWidth | Should -Be 8
            $attribution.GetText() | Should -Not -Match "`t|$([char]0x1B)"
            $quotePlan.OverflowLines | Should -BeGreaterThan 0
            (Test-TerminalPresentation -Presentation $quoteDeck -Viewport '20x10').Fits | Should -BeFalse

            $quoteFrame = Get-RenderedSlideFrame -Presentation $quoteDeck -SlideIndex 0 -Capability $capability
            $quoteFrame.Cells[$quotePlacement.StartY + 1][13].Fg | Should -Be '#123456'
            $quoteFrame.Cells[$quotePlacement.StartY + 1][14].Fg | Should -Not -Be '#123456'

            $imageDeck = New-TerminalPresentation -Title 'Image' -Width 20 -Height 10
            $imageDeck | Add-TerminalSlide -Title 'Slide' -Layout ImageFocus -Content {
                Add-SlideImage -Path 'missing-prepared-line.png' -AltText "A`tB" -Region Image
            } | Out-Null
            $imagePlan = Get-TerminalSlideLayoutPlan -Presentation $imageDeck -SlideIndex 0 -Capability $capability -WarningAction SilentlyContinue
            $imagePlacement = $imagePlan.Placements | Where-Object { (Get-TerminalElementPayload $_.Element).Kind -eq 'Image' }
            $imagePlacement.Lines[1].GetType().Name | Should -Be 'TerminalPreparedLine'
            $imagePlacement.Lines[1].StartColumn | Should -Be 2
            $imagePlacement.Lines[1].Width | Should -Be 7
            $imagePlacement.Lines[1].GetText() | Should -Be ('A' + (' ' * 5) + 'B')
        }
    }

    It 'selects one feasible tab-aware origin for centered and right-aligned lines' {
        InModuleScope TerminalSlides {
            $centeredTab = ConvertTo-TerminalPreparedLine -Line "A`tB" -StartColumn 2 -MaxWidth 16 -Alignment Center
            $centeredTab.StartColumn | Should -Be 7
            $centeredTab.Width | Should -Be 10
            $centeredTab.AvailableWidth | Should -Be 11

            $centerTie = ConvertTo-TerminalPreparedLine -Line 'AB' -StartColumn 2 -MaxWidth 5 -Alignment Center
            $centerTie.StartColumn | Should -Be 3
            $centerTie.Width | Should -Be 2

            $rightTie = ConvertTo-TerminalPreparedLine -Line "A`tB" -StartColumn 2 -MaxWidth 16 -Alignment Right
            $rightTie.StartColumn | Should -Be 14
            $rightTie.StartColumn + $rightTie.Width | Should -Be 17

            $noFeasibleOrigin = ConvertTo-TerminalPreparedLine -Line "— A`t" -StartColumn 6 -MaxWidth 8 -Alignment Center
            $noFeasibleOrigin.StartColumn | Should -Be 6
            $noFeasibleOrigin.AvailableWidth | Should -Be 8
            $noFeasibleOrigin.Width | Should -BeGreaterThan $noFeasibleOrigin.AvailableWidth

            $unboundedRight = ConvertTo-TerminalPreparedLine -Line 'A' -StartColumn 4 -Alignment Right
            $unboundedRight.StartColumn | Should -Be 4

            $deck = New-TerminalPresentation -Title 'Aligned tabs' -Width 26 -Height 10
            $deck | Add-TerminalSlide -Title 'Slide' -Layout Quote -Content {
                Add-SlideQuote -Text 'Q' -Attribution "AAAAAA`t" -Region Quote
            } | Out-Null
            $capability = [TerminalSlides.Schema.V1.TerminalCapability]@{ Width=26; Height=10; AnsiSupport=$true }
            $plan = Get-TerminalSlideLayoutPlan -Presentation $deck -SlideIndex 0 -Capability $capability
            $quotePlacement = $plan.Placements | Where-Object { (Get-TerminalElementPayload $_.Element).Kind -eq 'Quote' }
            $attribution = $quotePlacement.Lines[1]

            $attribution.StartColumn | Should -Be 7
            $attribution.Width | Should -Be 9
            $attribution.AvailableWidth | Should -Be 13
            $attribution.GetText() | Should -Be ('— AAAAAA' + ' ')
            $plan.OverflowLines | Should -Be 0
            (Test-TerminalPresentation -Presentation $deck -Viewport '26x10').Fits | Should -BeTrue
        }
    }

    It 'clips same-run and cross-style wide graphemes as atomic prefixes' {
        InModuleScope TerminalSlides {
            $sameRunCjk = ConvertTo-TerminalPreparedLine -Line 'AAA界B' -StartColumn 0 -MaxWidth 4
            $sameRunCjk.Width | Should -Be 6
            $sameRunCjk.RenderedWidth | Should -Be 3
            $sameRunCjk.GetText() | Should -Be 'AAA'

            $sameRunEmoji = ConvertTo-TerminalPreparedLine -Line 'A❤️B' -StartColumn 0 -MaxWidth 2
            $sameRunEmoji.Width | Should -Be 4
            $sameRunEmoji.RenderedWidth | Should -Be 1
            $sameRunEmoji.GetText() | Should -Be 'A'

            $crossStyleCjk = [TerminalStyledLine]::new()
            Add-TerminalStyledRun -Line $crossStyleCjk -Text 'AAA' -Foreground '#FF0000'
            Add-TerminalStyledRun -Line $crossStyleCjk -Text '界' -Foreground '#00FF00'
            Add-TerminalStyledRun -Line $crossStyleCjk -Text 'B' -Foreground '#0000FF'
            $preparedCjk = ConvertTo-TerminalPreparedLine -Line $crossStyleCjk -StartColumn 0 -MaxWidth 4
            $preparedCjk.Width | Should -Be 6
            $preparedCjk.GetText() | Should -Be 'AAA'
            $preparedCjk.Runs.Count | Should -Be 1
            $preparedCjk.Runs[0].Foreground | Should -Be '#FF0000'

            $crossStyleEmoji = [TerminalStyledLine]::new()
            Add-TerminalStyledRun -Line $crossStyleEmoji -Text 'A' -Foreground '#FF0000'
            Add-TerminalStyledRun -Line $crossStyleEmoji -Text '❤️' -Foreground '#00FF00'
            Add-TerminalStyledRun -Line $crossStyleEmoji -Text 'B' -Foreground '#0000FF'
            $preparedEmoji = ConvertTo-TerminalPreparedLine -Line $crossStyleEmoji -StartColumn 0 -MaxWidth 2
            $preparedEmoji.Width | Should -Be 4
            $preparedEmoji.GetText() | Should -Be 'A'
            $preparedEmoji.Runs.Count | Should -Be 1

            $deck = New-TerminalPresentation -Title 'Wide prefix' -Width 20 -Height 10
            $deck | Add-TerminalSlide -Title 'Slide' -Layout Quote -Content {
                Add-SlideQuote -Text 'Q' -Attribution 'AAAAA界B' -Region Quote
            } | Out-Null
            $capability = [TerminalSlides.Schema.V1.TerminalCapability]@{ Width=20; Height=10; AnsiSupport=$true }
            $plan = Get-TerminalSlideLayoutPlan -Presentation $deck -SlideIndex 0 -Capability $capability
            $quotePlacement = $plan.Placements | Where-Object { (Get-TerminalElementPayload $_.Element).Kind -eq 'Quote' }
            $attribution = $quotePlacement.Lines[1]

            $attribution.Width | Should -Be 10
            $attribution.RenderedWidth | Should -Be 7
            $attribution.GetText() | Should -Be '— AAAAA'
            $attribution.GetText() | Should -Not -Match 'B'
            $plan.OverflowLines | Should -BeGreaterThan 0
        }
    }

    It 'preserves tabs through formatting and applies final-origin alignment to public elements' {
        InModuleScope TerminalSlides {
            foreach ($behavior in 'Wrap', 'Scroll', 'Truncate') {
                Format-WordWrap -Text "A`tB" -Width 16 -OverflowBehavior $behavior -StartColumn 2 |
                    Should -Be "A`tB"
            }
            Format-WordWrap -Text "`tX" -Width 8 -OverflowBehavior Truncate |
                Should -Be "`t"

            $capability = [TerminalSlides.Schema.V1.TerminalCapability]@{ Width=20; Height=10; AnsiSupport=$true }
            $textDeck = New-TerminalPresentation -Title 'Aligned text tabs' -Width 20 -Height 10
            $textDeck | Add-TerminalSlide -Title 'Slide' -Content {
                Add-SlideText "A`tB" -Alignment Center -OverflowBehavior Scroll
                Add-SlideText "A`tB" -Alignment Right -OverflowBehavior Scroll
            } | Out-Null
            $textPlan = Get-TerminalSlideLayoutPlan -Presentation $textDeck -SlideIndex 0 -Capability $capability
            $textPlacements = @($textPlan.Placements | Where-Object { (Get-TerminalElementPayload $_.Element).Kind -eq 'Text' })
            $textPlacements[0].Lines[0].StartColumn | Should -Be 7
            $textPlacements[0].Lines[0].Width | Should -Be 10
            $textPlacements[0].Lines[0].GetText() | Should -Be ('A' + (' ' * 8) + 'B')
            $textPlacements[1].Lines[0].StartColumn | Should -Be 14
            $textPlacements[1].Lines[0].Width | Should -Be 3
            $textPlacements[1].Lines[0].GetText() | Should -Be 'A B'

            $codeDeck = New-TerminalPresentation -Title 'Aligned code tabs' -Width 20 -Height 10
            $codeDeck | Add-TerminalSlide -Title 'Slide' -Layout CodeFocus -Content {
                Add-SlideCode -Code "A`tB" -Language text -Region Code
            } | Out-Null
            $codeDeck.Slides[0].Elements[0].Alignment = 'Center'
            $codePlan = Get-TerminalSlideLayoutPlan -Presentation $codeDeck -SlideIndex 0 -Capability $capability
            $codePlacement = $codePlan.Placements | Where-Object { (Get-TerminalElementPayload $_.Element).Kind -eq 'Code' }
            $codePlacement.Lines[0].StartColumn | Should -Be 7
            $codePlacement.Lines[0].Width | Should -Be 10
            $codePlacement.Lines[0].GetText() | Should -Be ('A' + (' ' * 8) + 'B')

            $quoteDeck = New-TerminalPresentation -Title 'Quote tab parity' -Width 26 -Height 10
            $quoteDeck | Add-TerminalSlide -Title 'Slide' -Layout Quote -Content {
                Add-SlideQuote -Text "A`tB" -Attribution "A`tB" -Region Quote
            } | Out-Null
            $quoteCapability = [TerminalSlides.Schema.V1.TerminalCapability]@{ Width=26; Height=10; AnsiSupport=$true }
            $quotePlan = Get-TerminalSlideLayoutPlan -Presentation $quoteDeck -SlideIndex 0 -Capability $quoteCapability
            $quotePlacement = $quotePlan.Placements | Where-Object { (Get-TerminalElementPayload $_.Element).Kind -eq 'Quote' }
            $quoteFrame = Get-RenderedSlideFrame -Presentation $quoteDeck -SlideIndex 0 -Capability $quoteCapability
            $quoteFrame.Cells[$quotePlacement.StartY][16].Char | Should -Be 'B'
            $quoteFrame.Cells[$quotePlacement.StartY + 1][16].Char | Should -Be 'B'
            $quotePlacement.Lines[0].GetText() | Should -Not -Match "`t"
            $quotePlacement.Lines[1].GetText() | Should -Not -Match "`t"
        }
    }

    It 'bounds aligned origin measurement by the terminal tab-stop period' {
        InModuleScope TerminalSlides {
            $plainLine = New-TerminalStyledLine -Text 'plain'
            $tabbedLine = New-TerminalStyledLine -Text "A`tB"
            $script:originMeasureCalls = 0
            Mock Measure-TerminalStyledLineWidth {
                $script:originMeasureCalls++
                return 3
            }

            Resolve-TerminalPreparedLineOrigin -Line $plainLine -StartColumn 2 -MaxWidth 1000000 -Alignment Center | Out-Null
            $script:originMeasureCalls | Should -Be 1

            $script:originMeasureCalls = 0
            Resolve-TerminalPreparedLineOrigin -Line $tabbedLine -StartColumn 2 -MaxWidth 1000000 -Alignment Right | Out-Null
            $script:originMeasureCalls | Should -Be $script:TerminalTabStopWidth
        }
    }

    It 'keeps grapheme clusters atomic across styled-run boundaries' {
        InModuleScope TerminalSlides {
            $theme = Get-ResolvedTheme Midnight
            $element = New-InternalSlideElement -Kind Text -Payload ([TerminalSlides.Schema.V1.TextPayload]::new(''))

            $combiningLine = [TerminalStyledLine]::new()
            Add-TerminalStyledRun -Line $combiningLine -Text 'e' -Foreground '#FF0000'
            Add-TerminalStyledRun -Line $combiningLine -Text ([string][char]0x0301) -Foreground '#00FF00'
            $preparedCombining = ConvertTo-TerminalPreparedLine -Line $combiningLine -StartColumn 0 -MaxWidth 2
            $preparedCombining.Width | Should -Be 1
            $preparedCombining.RenderedWidth | Should -Be 1
            $preparedCombining.GetText() | Should -Be "e$([char]0x0301)"
            $preparedCombining.Runs.Count | Should -Be 1
            $preparedCombining.Runs[0].Foreground | Should -Be '#FF0000'

            $combiningFrame = [FrameBuffer]::new(2, 1)
            Write-LinesToFrame -FrameBuffer $combiningFrame -Lines @($preparedCombining) -Region @{ X=0; Y=0; Width=2; Height=1 } -Theme $theme -Element $element -StartY 0 | Out-Null
            $combiningFrame.Cells[0][0].Char | Should -Be "e$([char]0x0301)"

            $zwj = [string][char]0x200D
            $emojiLine = [TerminalStyledLine]::new()
            Add-TerminalStyledRun -Line $emojiLine -Text '👩' -Foreground '#FF0000'
            Add-TerminalStyledRun -Line $emojiLine -Text ($zwj + '💻') -Foreground '#00FF00'
            $preparedEmoji = ConvertTo-TerminalPreparedLine -Line $emojiLine -StartColumn 0 -MaxWidth 2
            $preparedEmoji.Width | Should -Be 2
            $preparedEmoji.RenderedWidth | Should -Be 2
            $preparedEmoji.GetText() | Should -Be "👩$zwj💻"
            $preparedEmoji.Runs.Count | Should -Be 1
            $preparedEmoji.Runs[0].Foreground | Should -Be '#FF0000'

            $emojiFrame = [FrameBuffer]::new(2, 1)
            Write-LinesToFrame -FrameBuffer $emojiFrame -Lines @($preparedEmoji) -Region @{ X=0; Y=0; Width=2; Height=1 } -Theme $theme -Element $element -StartY 0 | Out-Null
            $emojiFrame.Cells[0][0].Char | Should -Be "👩$zwj💻"
            $emojiFrame.Cells[0][1].Continuation | Should -BeTrue

            $clippedEmoji = ConvertTo-TerminalPreparedLine -Line $emojiLine -StartColumn 0 -MaxWidth 1
            $clippedEmoji.Width | Should -Be 2
            $clippedEmoji.RenderedWidth | Should -Be 0
            $clippedEmoji.GetText() | Should -BeNullOrEmpty
        }
    }

    It 'splits styled logical rows before single-row preparation' {
        InModuleScope TerminalSlides {
            $line = [TerminalStyledLine]::new()
            Add-TerminalStyledRun -Line $line -Text 'e' -Foreground '#FF0000'
            Add-TerminalStyledRun -Line $line -Text ("$([char]0x0301)`r") -Foreground '#00FF00'
            Add-TerminalStyledRun -Line $line -Text "`n`tB`n`r" -Foreground '#0000FF'

            $rows = ConvertTo-TerminalPreparedLines -Lines @($line) -StartColumn 3 -MaxWidth 10

            $rows.Count | Should -Be 4
            $rows[0].GetText() | Should -Be "e$([char]0x0301)"
            $rows[0].Width | Should -Be 1
            $rows[0].Runs.Count | Should -Be 1
            $rows[0].Runs[0].Foreground | Should -Be '#FF0000'
            $rows[1].GetText() | Should -Be ((' ' * 5) + 'B')
            $rows[1].Width | Should -Be 6
            $rows[1].Runs.Count | Should -Be 1
            $rows[1].Runs[0].Foreground | Should -Be '#0000FF'
            $rows[2].GetText() | Should -BeNullOrEmpty
            $rows[2].Runs.Count | Should -Be 0
            $rows[3].GetText() | Should -BeNullOrEmpty
            $rows[3].Runs.Count | Should -Be 0
            @($rows | Where-Object { $_.GetText() -match "[`r`n]" }).Count | Should -Be 0

            $rawElements = Get-TerminalTextElements -Text "A`r`n`tB" -StartColumn 3 -PreserveTabs
            $rawElements.Count | Should -Be 4
            $rawElements[1].Text | Should -Be "`r`n"
            $rawElements[1].Width | Should -Be 0
            $rawElements[2].Width | Should -Be 5

            { ConvertTo-TerminalPreparedLine -Line $line -StartColumn 3 -MaxWidth 10 } |
                Should -Throw '*exactly one logical row*'
        }
    }

    It 'lays out multiline quote attributions and chart titles as distinct rows' {
        InModuleScope TerminalSlides {
            $capability = [TerminalSlides.Schema.V1.TerminalCapability]@{ Width=26; Height=12; AnsiSupport=$true }

            $quoteDeck = New-TerminalPresentation -Title 'Multiline quote' -Width 26 -Height 12
            $quoteDeck | Add-TerminalSlide -Title 'Quote' -Layout Quote -Content {
                Add-SlideQuote -Text 'Body' -Attribution "A`r`n`tB`n" -Region Quote
            } | Out-Null
            $quotePlan = Get-TerminalSlideLayoutPlan -Presentation $quoteDeck -SlideIndex 0 -Capability $capability
            $quotePlacement = $quotePlan.Placements | Where-Object { (Get-TerminalElementPayload $_.Element).Kind -eq 'Quote' }
            $quoteFrame = Get-RenderedSlideFrame -Presentation $quoteDeck -SlideIndex 0 -Capability $capability

            $quotePlacement.Lines.Count | Should -Be 4
            $quotePlacement.Lines[1].GetText() | Should -Be '— A'
            $quotePlacement.Lines[2].StartColumn | Should -Be 9
            $quotePlacement.Lines[2].GetText() | Should -Be ((' ' * 7) + 'B')
            $quotePlacement.Lines[3].GetText() | Should -BeNullOrEmpty
            $quoteFrame.Cells[$quotePlacement.StartY + 2][16].Char | Should -Be 'B'
            $quotePlan.OverflowLines | Should -Be 0

            $chartDeck = New-TerminalPresentation -Title 'Multiline chart' -Width 26 -Height 12
            $chartDeck | Add-TerminalSlide -Title 'Chart' -Content {
                Add-SlideChart -Title "A`r`n`tB`n" -Data @([pscustomobject]@{ Label='Metric'; Value=100 })
            } | Out-Null
            $chartPlan = Get-TerminalSlideLayoutPlan -Presentation $chartDeck -SlideIndex 0 -Capability $capability
            $chartPlacement = $chartPlan.Placements | Where-Object { (Get-TerminalElementPayload $_.Element).Kind -eq 'Chart' }
            $chartFrame = Get-RenderedSlideFrame -Presentation $chartDeck -SlideIndex 0 -Capability $capability

            $chartPlacement.Lines.Count | Should -Be 4
            $chartPlacement.Lines[0].GetText() | Should -Be 'A'
            $chartPlacement.Lines[1].GetText() | Should -Be ((' ' * 6) + 'B')
            $chartPlacement.Lines[1].Runs[0].Bold | Should -BeTrue
            $chartPlacement.Lines[2].GetText() | Should -BeNullOrEmpty
            $chartFrame.Cells[$chartPlacement.StartY + 1][8].Char | Should -Be 'B'
            $chartFrame.GetRowText($chartPlacement.StartY + 3) | Should -Match 'Metric'
            $chartPlan.OverflowLines | Should -Be 0
        }
    }

    It 'renders chart titles and the configured chart palette' {
        InModuleScope TerminalSlides {
            $deck = New-TerminalPresentation -Title 'Charts' -Width 60 -Height 20
            $deck | Add-TerminalSlide -Title 'Slide' -Content {
                Add-SlideChart -Title 'SUCCESS RATE' -Data @(
                    [pscustomobject]@{ Label = 'Build'; Value = 80 }
                    [pscustomobject]@{ Label = 'Test'; Value = 90 }
                )
            } | Out-Null

            $output = Render-TerminalPresentationToString -Presentation $deck -PlainText
            $capability = [TerminalSlides.Schema.V1.TerminalCapability]@{ Width=60; Height=20; AnsiSupport=$true; TrueColorSupport=$true }
            $ansi = Render-TerminalPresentationToString -Presentation $deck -Capability $capability
            $theme = Get-ResolvedTheme -Name Midnight

            $output | Should -Match 'SUCCESS RATE'
            $ansi | Should -Match ([regex]::Escape((Get-AnsiFg -Color $theme.ChartPalette[0])))
            $ansi | Should -Match ([regex]::Escape((Get-AnsiFg -Color $theme.ChartPalette[1])))

            $zeroLine = (ConvertTo-ChartLines -Content @([pscustomobject]@{ Label='Zero'; Value=0 }) -Properties @{ ChartType='HorizontalBar' } -Theme $theme -Width 30)[0]
            $zeroLine.GetText() | Should -Not -Match '█'

            $box = New-InternalSlideElement -Kind Box -Payload ([TerminalSlides.Schema.V1.TextPayload]::new('界'))
            $boxLine = (ConvertTo-ElementLines -Element $box -Theme $theme -Width 10)[1]
            Measure-TextWidth -Text $boxLine | Should -Be 10
        }
    }

    It 'normalizes tiny automatic terminal capabilities once for layout and rendering' {
        InModuleScope TerminalSlides {
            $deck = New-TerminalPresentation -Title 'Tiny'
            $deck | Add-TerminalSlide -Title 'Slide' -Content { Add-SlideText 'Body' } | Out-Null
            $capability = [TerminalSlides.Schema.V1.TerminalCapability]@{ Width=1; Height=1; AnsiSupport=$true }

            $frame = Get-RenderedSlideFrame -Presentation $deck -SlideIndex 0 -Capability $capability
            $plan = Get-TerminalSlideLayoutPlan -Presentation $deck -SlideIndex 0 -Capability $capability

            $frame.Width | Should -Be 20
            $frame.Height | Should -Be 10
            $plan.Dimensions.Width | Should -Be $frame.Width
            $plan.Dimensions.Height | Should -Be $frame.Height
        }
    }

    It 'removes inert public options and applies heading styles' {
        (Get-Command New-TerminalPresentation).Parameters.Keys | Should -Not -Contain 'DefaultTransition'
        (Get-Command Add-TerminalSlide).Parameters.Keys | Should -Not -Contain 'Transition'
        (Get-Command Set-TerminalSlide).Parameters.Keys | Should -Not -Contain 'Transition'
        (Get-Command Add-SlideBullet).Parameters.Keys | Should -Not -Contain 'Style'
        (Get-Command New-TerminalPresentationTheme).Parameters.Keys | Should -Not -Contain 'CodeTheme'

        InModuleScope TerminalSlides {
            $deck = New-TerminalPresentation -Title 'Heading' -Theme HighContrast -Width 40 -Height 15
            $deck | Add-TerminalSlide -Title 'Mixed Case' -Content { Add-SlideText 'Body' } | Out-Null
            $output = Render-TerminalPresentationToString -Presentation $deck -PlainText
            $output | Should -Match 'MIXED CASE'

            $plainDeck = New-TerminalPresentation -Title 'Heading' -Theme Minimal -Width 40 -Height 15
            $plainDeck | Add-TerminalSlide -Title 'Plain' -Content { Add-SlideText 'Body' } | Out-Null
            $frame = Get-RenderedSlideFrame -Presentation $plainDeck -SlideIndex 0
            @($frame.Cells[1] | Where-Object { $_.Char -ne ' ' -and $_.Bold }).Count | Should -Be 0
        }
    }

    It 'uses a versioned namespace and assembly identity for public data types' {
        $deck = New-TerminalPresentation -Title 'Types'

        $deck.GetType().FullName | Should -Be 'TerminalSlides.Schema.V1.TerminalPresentation'
        $deck.GetType().Assembly.GetName().Version | Should -Be ([version]'1.0.0.0')
    }
}
