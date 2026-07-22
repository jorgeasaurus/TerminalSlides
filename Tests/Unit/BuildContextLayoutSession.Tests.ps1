Describe 'Build context, layout plan, and presentation session' {
    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '..' '..' 'TerminalSlides.psd1') -Force
    }

    It 'preserves an outer slide while a nested slide is composed' {
        $deck = New-TerminalPresentation -Title 'Nested slides'
        $deck | Add-TerminalSlide -Title 'Outer' -Content {
            Add-SlideText 'before'
            $deck | Add-TerminalSlide -Title 'Inner' -Content { Add-SlideText 'inside' } | Out-Null
            Add-SlideText 'after'
        } | Out-Null

        $deck.Slides.Title | Should -Be @('Inner', 'Outer')
        @($deck.Slides[1].Elements.Payload.Text) | Should -Be @('before', 'after')
        @($deck.Slides[0].Elements.Payload.Text) | Should -Be @('inside')
    }

    It 'preserves an outer diagram while a nested diagram is composed' {
        $deck = New-TerminalPresentation -Title 'Nested diagrams'
        $deck | Add-TerminalSlide -Title 'Slide' -Content {
            Add-SlideDiagram -Content {
                Add-SlideDiagramNode -Id outer1 -Label 'Outer one'
                Add-SlideDiagram -Content {
                    Add-SlideDiagramNode -Id inner -Label 'Inner'
                }
                Add-SlideDiagramNode -Id outer2 -Label 'Outer two'
                Add-SlideDiagramEdge -From outer1 -To outer2
            }
        } | Out-Null

        $deck.Slides[0].Elements.Count | Should -Be 2
        @($deck.Slides[0].Elements[0].Payload.Nodes.Id) | Should -Be @('inner')
        @($deck.Slides[0].Elements[1].Payload.Nodes.Id) | Should -Be @('outer1', 'outer2')
        @($deck.Slides[0].Elements[1].Payload.Edges).Count | Should -Be 1
    }

    It 'unwinds failed builders without corrupting the next build' {
        $deck = New-TerminalPresentation -Title 'Recovery'
        { $deck | Add-TerminalSlide -Title 'Failed' -Content { throw 'stop' } } | Should -Throw '*stop*'
        $deck | Add-TerminalSlide -Title 'Healthy' -Content { Add-SlideText 'kept' } | Out-Null

        $deck.Slides.Count | Should -Be 1
        $deck.Slides[0].Elements[0].Payload.Text | Should -Be 'kept'
    }

    It 'merges returned elements and notes into the active context contract' {
        InModuleScope TerminalSlides {
            $deck = New-TerminalPresentation -Title 'Returned values'
            $returnedElement = New-InternalSlideElement -Kind Text -Payload ([TerminalSlides.Schema.V1.TextPayload]::new('returned')) -RevealStep 3
            $returnedNote = [pscustomobject]@{ __TerminalSlidesNote = $true; Text = 'speaker note' }

            $deck | Add-TerminalSlide -Title 'Slide' -Content {
                Add-SlideText 'queued' -RevealStep 2
                $returnedElement
                $returnedNote
            } | Out-Null

            @($deck.Slides[0].Elements.Payload.Text) | Should -Be @('queued', 'returned')
            $deck.Slides[0].MaxRevealStep | Should -Be 3
            $deck.Slides[0].Notes | Should -Be 'speaker note'
        }
    }

    It 'supports empty slides and assigns identity to a returned raw element' {
        InModuleScope TerminalSlides {
            $deck = New-TerminalPresentation -Title 'Raw values'
            $deck | Add-TerminalSlide -Title 'Empty' | Out-Null
            $raw = [TerminalSlides.Schema.V1.SlideElement]::new('Text', [TerminalSlides.Schema.V1.TextPayload]::new('identity'))
            $deck | Add-TerminalSlide -Title 'Raw' -Content { $raw } | Out-Null

            $deck.Slides[0].Elements.Count | Should -Be 0
            $deck.Slides[1].Elements[0].Id | Should -Not -BeNullOrEmpty
        }
    }

    It 'restores identity when a caller clears an element ID inside a build context' {
        InModuleScope TerminalSlides {
            $context = Push-TerminalSlidesBuildContext -Kind Slide
            try {
                $element = New-InternalSlideElement -Kind Text -Payload ([TerminalSlides.Schema.V1.TextPayload]::new('identity'))
                $element.Id = $null
                Add-CurrentSlideElement -Element $element
                $context.Elements[0].Id | Should -Not -BeNullOrEmpty
            }
            finally {
                Pop-TerminalSlidesBuildContext -Context $context
            }
        }
    }

    It 'rejects build contexts closed out of nesting order' {
        InModuleScope TerminalSlides {
            $outer = Push-TerminalSlidesBuildContext -Kind Slide
            $inner = Push-TerminalSlidesBuildContext -Kind Diagram
            try {
                { Pop-TerminalSlidesBuildContext -Context $outer } | Should -Throw '*nesting order*'
            }
            finally {
                Pop-TerminalSlidesBuildContext -Context $inner
                Pop-TerminalSlidesBuildContext -Context $outer
            }
        }
    }

    It 'uses the render layout plan as the validator result' {
        InModuleScope TerminalSlides {
            $deck = New-TerminalPresentation -Title 'Overflow' -Width 40 -Height 10
            $deck | Add-TerminalSlide -Title 'Slide' -Content {
                Add-SlideText ((1..40 | ForEach-Object { "line $_" }) -join "`n")
            } | Out-Null
            $capability = [TerminalSlides.Schema.V1.TerminalCapability]::new()
            $capability.Width = 40
            $capability.Height = 10
            $view = New-TerminalPresentationView -Presentation $deck
            $plan = Get-TerminalSlideLayoutPlan -Presentation $view -SlideIndex 0 -Capability $capability

            $result = Test-TerminalPresentation -Presentation $deck -Viewport '40x10'
            $result.OverflowLines | Should -Be $plan.OverflowLines
            $result.Fits | Should -BeFalse
            Render-TerminalPresentationToString -Presentation $view -SlideIndex 0 -PlainText -Capability $capability |
                Should -Match 'line 1'
        }
    }

    It 'rejects negative and region-infeasible padding at the layout boundary' {
        $negative = New-TerminalPresentation -Title 'Negative padding' -Width 20 -Height 10
        $negative | Add-TerminalSlide -Title 'Slide' -Layout Blank -Content { Add-SlideText 'X' -RevealStep 2 } | Out-Null
        $negative.Slides[0].Elements[0].Padding = -1

        InModuleScope TerminalSlides -Parameters @{ Deck = $negative } {
            $capability = [TerminalSlides.Schema.V1.TerminalCapability]@{ Width=20; Height=10 }
            { Get-TerminalSlideLayoutPlan -Presentation $Deck -SlideIndex 0 -RevealStep 0 -Capability $capability } |
                Should -Throw '*padding*-1*between 0*'
        }

        $infeasible = New-TerminalPresentation -Title 'Imported padding' -Width 20 -Height 10
        $infeasible | Add-TerminalSlide -Title 'Slide' -Layout Blank -Content { Add-SlideText 'X' } | Out-Null
        $infeasible.Slides[0].Elements[0].Padding = 20
        $path = Join-Path $TestDrive 'padding.json'
        Export-TerminalPresentation -Presentation $infeasible -Path $path -Format Json -Force | Out-Null
        $imported = Import-TerminalPresentation -Path $path

        { Test-TerminalPresentation -Presentation $imported -Viewport '20x10' } |
            Should -Throw '*padding*20*region*width*'
        InModuleScope TerminalSlides -Parameters @{ Deck = $imported } {
            $capability = [TerminalSlides.Schema.V1.TerminalCapability]@{ Width=20; Height=10 }
            { Get-TerminalSlideLayoutPlan -Presentation $Deck -SlideIndex 0 -Capability $capability } |
                Should -Throw '*padding*20*region*width*'
        }
    }

    It 'keeps every feasible padded origin within its bordered or unbordered region' {
        InModuleScope TerminalSlides {
            $capability = [TerminalSlides.Schema.V1.TerminalCapability]@{ Width=20; Height=10 }
            foreach ($border in $false, $true) {
                $deck = New-TerminalPresentation -Title 'Padding bounds' -Width 20 -Height 10
                $deck | Add-TerminalSlide -Title 'Slide' -Layout Blank -Content {
                    Add-SlideText 'X'
                } | Out-Null
                $element = $deck.Slides[0].Elements[0]
                $element.Border = $border
                $element.Padding = if ($border) { 7 } else { 8 }

                $plan = Get-TerminalSlideLayoutPlan -Presentation $deck -SlideIndex 0 -Capability $capability
                $placement = $plan.Placements[0]
                $line = $placement.Lines[0]
                $line.StartColumn | Should -BeGreaterOrEqual $placement.Region.X
                ($line.StartColumn + $line.RenderedWidth) |
                    Should -BeLessOrEqual ($placement.Region.X + $placement.Region.Width)
            }
        }
    }

    It 'omits exhausted borders and clips partial borders inside the content region' {
        InModuleScope TerminalSlides {
            $capability = [TerminalSlides.Schema.V1.TerminalCapability]@{ Width=20; Height=10; AnsiSupport=$true }

            $exhausted = New-TerminalPresentation -Title 'Exhausted' -Width 20 -Height 10
            $exhausted | Add-TerminalSlide -Title 'Slide' -Content {
                Add-SlideText 'one'
                Add-SlideText 'two'
                Add-SlideCode -Code 'boxed' -Border
            } | Out-Null
            $exhaustedPlan = Get-TerminalSlideLayoutPlan -Presentation $exhausted -SlideIndex 0 -Capability $capability
            @($exhaustedPlan.Placements | Where-Object { $_.Element.Kind -eq [TerminalSlides.Schema.V1.ElementKind]::Code }).Count |
                Should -Be 0
            $exhaustedPlan.OverflowLines | Should -Be 3
            $exhaustedOutput = Render-TerminalPresentationToString -Presentation $exhausted -SlideIndex 0 -PlainText -Capability $capability
            $exhaustedOutput | Should -Not -Match 'boxed'

            $partial = New-TerminalPresentation -Title 'Partial' -Width 20 -Height 10
            $partial | Add-TerminalSlide -Title 'Slide' -Content {
                Add-SlideCode -Code "one`ntwo`nthree`nfour" -Border
            } | Out-Null
            $partial.Slides[0].Elements[0].ForegroundColor = '#ABCDEF'
            $partial.Slides[0].Elements[0].BackgroundColor = '#123456'
            $partialPlan = Get-TerminalSlideLayoutPlan -Presentation $partial -SlideIndex 0 -Capability $capability
            $content = $partialPlan.Regions.Content
            $bordered = $partialPlan.Placements | Where-Object { $_.Element.Kind -eq [TerminalSlides.Schema.V1.ElementKind]::Code }
            $bordered.BorderRegion.Height | Should -Be 3
            ($bordered.BorderRegion.Y + $bordered.BorderRegion.Height) |
                Should -BeLessOrEqual ($content.Y + $content.Height)
            $bordered.Region.Height | Should -Be 1
            $partialPlan.OverflowLines | Should -Be 3
            $partialFrame = Get-RenderedSlideFrame -Presentation $partial -SlideIndex 0 -Capability $capability
            $partialFrame.Cells[$bordered.BorderRegion.Y][$bordered.BorderRegion.X].Fg | Should -Be '#ABCDEF'
            $partialFrame.Cells[$bordered.BorderRegion.Y][$bordered.BorderRegion.X].Bg | Should -Be '#123456'
            $partialOutput = Render-TerminalPresentationToString -Presentation $partial -SlideIndex 0 -PlainText -Capability $capability
            $partialOutput | Should -Match 'one'
            $partialOutput | Should -Not -Match 'two'
            $partialOutput | Should -Not -Match 'three'
            $partialOutput | Should -Not -Match 'four'
        }
    }

    It 'rejects unknown layouts and unplaceable element regions' {
        { New-TerminalPresentation -Title 'Invalid' -DefaultLayout Missing } |
            Should -Throw '*Unknown slide layout*Missing*'

        $deck = New-TerminalPresentation -Title 'Regions'
        { $deck | Add-TerminalSlide -Title 'Invalid' -Layout Missing } |
            Should -Throw '*Unknown slide layout*Missing*'
        $deck.Slides.Count | Should -Be 0

        $deck | Add-TerminalSlide -Title 'Valid' -Content {
            Add-SlideText 'must not disappear' -Region Contnet
        } | Out-Null
        { Test-TerminalPresentation -Presentation $deck -Viewport '80x24' } |
            Should -Throw "*Region 'Contnet' is not available*"
        { Show-TerminalPresentation -Presentation $deck } |
            Should -Throw "*Region 'Contnet' is not available*"

        $originalLayout = $deck.Slides[0].Layout
        { Set-TerminalSlide -Presentation $deck -Index 1 -Layout Missing } |
            Should -Throw '*Unknown slide layout*Missing*'
        $deck.Slides[0].Layout | Should -Be $originalLayout
    }

    It 'maps every revealed element to exactly one supported layout region' {
        InModuleScope TerminalSlides {
            $deck = New-TerminalPresentation -Title 'Regions' -Width 60 -Height 20
            $deck | Add-TerminalSlide -Title 'Columns' -Layout TwoColumn -Content {
                Add-SlideText 'left' -Region Left
                Add-SlideText 'right' -Region Right
                Add-SlideText 'later' -Region Left -RevealStep 2
            } | Out-Null

            $plan = Get-TerminalSlideLayoutPlan -Presentation $deck -SlideIndex 0 -RevealStep 0 -Capability ([TerminalSlides.Schema.V1.TerminalCapability]::new())
            $placed = @($plan.Placements | Where-Object { $_.Element.Kind -eq [TerminalSlides.Schema.V1.ElementKind]::Text })

            $placed.Count | Should -Be 2
            @($placed.Element.Id | Sort-Object -Unique).Count | Should -Be 2
            @($placed.Element.Payload.Text) | Should -Contain 'left'
            @($placed.Element.Payload.Text) | Should -Contain 'right'
            @($placed.Element.Payload.Text) | Should -Not -Contain 'later'

            $fallbackDeck = New-TerminalPresentation -Title 'Fallback' -Width 60 -Height 20
            $fallbackDeck | Add-TerminalSlide -Title 'Content' -Content {
                Add-SlideText 'blank defaults to content' -Region ''
            } | Out-Null
            $fallbackPlan = Get-TerminalSlideLayoutPlan -Presentation $fallbackDeck -SlideIndex 0 -Capability ([TerminalSlides.Schema.V1.TerminalCapability]::new())
            @($fallbackPlan.Placements.Element.Payload.Text) | Should -Contain 'blank defaults to content'
        }
    }

    It 'rejects overlapping region modes and renders disjoint specialized regions cleanly' {
        InModuleScope TerminalSlides {
            foreach ($case in @(
                @{ Layout='TwoColumn'; Region='Left' },
                @{ Layout='ThreeColumn'; Region='Center' },
                @{ Layout='CodeFocus'; Region='Code' },
                @{ Layout='ImageFocus'; Region='Image' },
                @{ Layout='Quote'; Region='Quote' }
            )) {
                $deck = New-TerminalPresentation -Title $case.Layout -Width 60 -Height 20
                $specialRegion = $case.Region
                $deck | Add-TerminalSlide -Title 'Overlap' -Layout $case.Layout -Content {
                    Add-SlideText 'LONG_BACKGROUND_VALUE' -Region Content
                    Add-SlideText 'SHORT' -Region $specialRegion
                } | Out-Null

                { Get-TerminalSlideLayoutPlan -Presentation $deck -SlideIndex 0 -Capability ([TerminalSlides.Schema.V1.TerminalCapability]::new()) } |
                    Should -Throw '*cannot combine overlapping element regions*'
            }

            $columns = New-TerminalPresentation -Title 'Columns' -Width 60 -Height 20
            $columns | Add-TerminalSlide -Title 'Disjoint' -Layout ThreeColumn -Content {
                Add-SlideText 'LEFT_VALUE' -Region Left
                Add-SlideText 'CENTER_VALUE' -Region Center
                Add-SlideText 'RIGHT_VALUE' -Region Right
            } | Out-Null
            $output = Render-TerminalPresentationToString -Presentation $columns -PlainText
            $output | Should -Match 'LEFT_VALUE'
            $output | Should -Match 'CENTER_VALUE'
            $output | Should -Match 'RIGHT_VALUE'
            $output | Should -Not -Match 'SHORTBACKGROUND_VALUE'
        }
    }

    It 'keeps SectionHeader content above the footer and reports excess lines at 20x10' {
        InModuleScope TerminalSlides {
            $deck = New-TerminalPresentation -Title 'Deck'
            $deck | Add-TerminalSlide -Title 'Section' -Layout SectionHeader -Content {
                Add-SlideText "SECTION_LINE_1`nSECTION_LINE_2`nSECTION_LINE_3`nSECTION_LINE_4"
            } | Out-Null
            $capability = [TerminalSlides.Schema.V1.TerminalCapability]@{ Width=1; Height=1; AnsiSupport=$false }

            $plan = Get-TerminalSlideLayoutPlan -Presentation $deck -SlideIndex 0 -Capability $capability
            $plan.Regions.Content.Y + $plan.Regions.Content.Height | Should -BeLessOrEqual ($plan.Dimensions.Height - 2)
            $plan.OverflowLines | Should -Be 3

            $rows = (Render-TerminalPresentationToString -Presentation $deck -PlainText -Capability $capability) -split "`r?`n" |
                ForEach-Object Trim
            $rows | Should -Contain 'SECTION_LINE_1'
            $rows | Should -Not -Contain 'SECTION_LINE_2'
            $rows | Should -Not -Contain 'SECTION_LINE_3'
            $rows | Should -Not -Contain 'SECTION_LINE_4'
            ($rows -join "`n") | Should -Match 'Slide 1 of 1'
        }
    }

    It 'keeps Title-layout title, deck subtitle, and content disjoint at the minimum viewport' {
        InModuleScope TerminalSlides {
            $deck = New-TerminalPresentation -Title 'Deck' -Subtitle 'UNIQUE_SUBTITLE'
            $deck | Add-TerminalSlide -Title 'Slide' -Layout Title -Content {
                Add-SlideText 'UNIQUE_CONTENT'
            } | Out-Null
            $capability = [TerminalSlides.Schema.V1.TerminalCapability]@{ Width=1; Height=1; AnsiSupport=$false }

            $plan = Get-TerminalSlideLayoutPlan -Presentation $deck -SlideIndex 0 -Capability $capability
            $subtitle = $plan.Placements | Where-Object { $_.Element.Kind -eq [TerminalSlides.Schema.V1.ElementKind]::Subtitle }
            $content = $plan.Placements | Where-Object { $_.Element.Kind -eq [TerminalSlides.Schema.V1.ElementKind]::Text }
            ($subtitle.Region.Y + $subtitle.Region.Height) | Should -BeLessOrEqual $content.Region.Y

            $rows = (Render-TerminalPresentationToString -Presentation $deck -PlainText -Capability $capability) -split "`r?`n" |
                ForEach-Object Trim
            $rows | Should -Contain 'UNIQUE_SUBTITLE'
            $rows | Should -Contain 'UNIQUE_CONTENT'
            $rows | Should -Not -Contain 'UNIQUE_CONTENTE'
        }
    }

    It 'builds a correctly reindexed hidden-slide view without mutating the source' {
        InModuleScope TerminalSlides {
            $deck = New-TerminalPresentation -Title 'Visibility'
            $deck | Add-TerminalSlide -Title 'Hidden' -Hidden -Content { Add-SlideText 'secret' } | Out-Null
            $deck | Add-TerminalSlide -Title 'Visible' -Content { Add-SlideText 'public' } | Out-Null

            $view = New-TerminalPresentationView -Presentation $deck

            $view.Slides.Count | Should -Be 1
            $view.Slides[0].Index | Should -Be 1
            $view.Slides[0].Title | Should -Be 'Visible'
            $deck.Slides[0].Index | Should -Be 1
            $deck.Slides[1].Index | Should -Be 2
        }
    }

    It 'reduces normalized actions without mutating the prior session' {
        InModuleScope TerminalSlides {
            $deck = New-TerminalPresentation -Title 'Controls'
            $deck | Add-TerminalSlide -Title 'One' -Content { Add-SlideText 'reveal' -RevealStep 1 } | Out-Null
            $deck | Add-TerminalSlide -Title 'Two' -Content { Add-SlideText 'second' } | Out-Null
            $session = New-TerminalPresentationSession

            $revealed = Invoke-TerminalPresentationAction -Session $session -Action NextStep -Presentation $deck
            $advanced = Invoke-TerminalPresentationAction -Session $revealed -Action NextStep -Presentation $deck

            $session.RevealStep | Should -Be 0
            $revealed.RevealStep | Should -Be 1
            $advanced.SlideIndex | Should -Be 1
            $help = Invoke-TerminalPresentationAction -Session $advanced -Action ToggleHelp -Presentation $deck
            $overview = Invoke-TerminalPresentationAction -Session $help -Action ToggleOverview -Presentation $deck
            $closedOverview = Invoke-TerminalPresentationAction -Session $overview -Action ToggleOverview -Presentation $deck
            $closedHelp = Invoke-TerminalPresentationAction -Session $help -Action ToggleHelp -Presentation $deck
            $blank = Invoke-TerminalPresentationAction -Session $advanced -Action ToggleBlank -Presentation $deck
            $closedBlank = Invoke-TerminalPresentationAction -Session $blank -Action ToggleBlank -Presentation $deck
            $help.DisplayMode | Should -Be 'Help'
            $closedHelp.DisplayMode | Should -Be 'Slide'
            $overview.DisplayMode | Should -Be 'Overview'
            $closedOverview.DisplayMode | Should -Be 'Slide'
            $blank.DisplayMode | Should -Be 'Blank'
            $closedBlank.DisplayMode | Should -Be 'Slide'
            ConvertTo-TerminalPresentationAction -Key ([ConsoleKeyInfo]::new('?', [ConsoleKey]::Oem2, $false, $false, $false)) |
                Should -Be 'ToggleHelp'
            ConvertTo-TerminalPresentationAction -Key ([ConsoleKeyInfo]::new('x', [ConsoleKey]::X, $false, $false, $false)) |
                Should -Be 'None'
        }
    }

    It 'derives reveal bounds from elements and normalizes stale persisted state' {
        $path = Join-Path $TestDrive 'stale-reveal.json'
        InModuleScope TerminalSlides -Parameters @{ Path = $path } {
            $deck = New-TerminalPresentation -Title 'Canonical reveals'
            $deck | Add-TerminalSlide -Title 'One' -Content { Add-SlideText 'reveal' -RevealStep 1 } | Out-Null
            $deck.Slides[0].MaxRevealStep = 100

            $view = New-TerminalPresentationView -Presentation $deck
            $copy = Copy-TerminalSlideModel -Slide $deck.Slides[0]
            $view.Slides[0].MaxRevealStep | Should -Be 1
            $copy.MaxRevealStep | Should -Be 1
            $deck.Slides[0].MaxRevealStep | Should -Be 100

            $session = New-TerminalPresentationSession
            $session = Invoke-TerminalPresentationAction -Session $session -Action NextStep -Presentation $deck
            $session = Invoke-TerminalPresentationAction -Session $session -Action NextStep -Presentation $deck
            $session.RevealStep | Should -Be 1

            $data = ConvertTo-PresentationData -Presentation $deck
            $data.Presentation.Slides[0].MaxRevealStep = 100
            [IO.File]::WriteAllText($Path, (ConvertTo-TerminalWireJson -Data $data), [Text.UTF8Encoding]::new($false))
            $imported = Import-TerminalPresentation -Path $Path
            $imported.Slides[0].MaxRevealStep | Should -Be 1
        }
    }

    It 'rejects negative reveal steps from builders, imports, and session models' {
        $path = Join-Path $TestDrive 'negative-reveal.json'
        InModuleScope TerminalSlides -Parameters @{ Path = $path } {
            $builderDeck = New-TerminalPresentation -Title 'Invalid builder'
            { $builderDeck | Add-TerminalSlide -Title 'Invalid' -Content { Add-SlideText 'bad' -RevealStep -1 } } |
                Should -Throw '*reveal step*-1*non-negative*'
            $builderDeck.Slides.Count | Should -Be 0

            $wireDeck = New-TerminalPresentation -Title 'Invalid import'
            $wireDeck | Add-TerminalSlide -Title 'Slide' -Content { Add-SlideText 'valid' } | Out-Null
            $data = ConvertTo-PresentationData -Presentation $wireDeck
            $data.Presentation.Slides[0].Elements[0].RevealStep = -1
            $data.Presentation.Slides[0].MaxRevealStep = -1
            [IO.File]::WriteAllText($Path, (ConvertTo-TerminalWireJson -Data $data), [Text.UTF8Encoding]::new($false))
            { Import-TerminalPresentation -Path $Path } | Should -Throw '*reveal step*-1*non-negative*'

            $sessionDeck = New-TerminalPresentation -Title 'Invalid session'
            $sessionDeck | Add-TerminalSlide -Title 'Slide' -Content { Add-SlideText 'valid' } | Out-Null
            $sessionDeck.Slides[0].Elements[0].RevealStep = -1
            { Invoke-TerminalPresentationAction -Session (New-TerminalPresentationSession) -Action NextStep -Presentation $sessionDeck } |
                Should -Throw '*reveal step*-1*non-negative*'
            { Render-TerminalPresentationToString -Presentation $sessionDeck -PlainText } |
                Should -Throw '*reveal step*-1*non-negative*'
            { Test-TerminalPresentation -Presentation $sessionDeck -Viewport '80x24' } |
                Should -Throw '*reveal step*-1*non-negative*'
        }
    }

    It 'returns explicit styled lines without encoding ANSI control text' {
        InModuleScope TerminalSlides {
            $theme = Get-ResolvedTheme Midnight
            $line = (Get-SyntaxHighlight -Code "function Test { 'value' # note }" -Language PowerShell -Theme $theme)[0]

            $line.GetType().Name | Should -Be 'TerminalStyledLine'
            $line.GetText() | Should -Be "function Test { 'value' # note }"
            $line.GetText() | Should -Not -Match ([regex]::Escape([string][char]27))
            $line.Runs[0].Text | Should -Be 'function'
            $line.Runs[0].Bold | Should -BeTrue
            $line.Runs[0].Foreground | Should -Be $theme.Accent
            @($line.Runs | Where-Object Text -eq "'value'")[0].Foreground | Should -Be $theme.SuccessColor
        }
    }

    It 'makes display modes mutually exclusive and rejects invalid state' {
        InModuleScope TerminalSlides {
            $deck = New-TerminalPresentation -Title 'Modes'
            $deck | Add-TerminalSlide -Title 'One' | Out-Null
            $session = New-TerminalPresentationSession
            $help = Invoke-TerminalPresentationAction -Session $session -Action ToggleHelp -Presentation $deck
            $blank = Invoke-TerminalPresentationAction -Session $help -Action ToggleBlank -Presentation $deck

            $help.DisplayMode | Should -Be 'Help'
            $blank.DisplayMode | Should -Be 'Blank'
            $blank.PSObject.Properties.Name | Should -Not -Contain 'ShowHelp'
            $blank.PSObject.Properties.Name | Should -Not -Contain 'OverviewMode'
            $blank.DisplayMode = 'Corrupt'
            { Invoke-TerminalPresentationAction -Session $blank -Action None -Presentation $deck } | Should -Throw '*display mode*'
        }
    }
}
