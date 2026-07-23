Describe 'Rendering primitive contracts' {
    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '..' '..' 'TerminalSlides.psd1') -Force
    }

    It 'converts tables, charts, diagrams, and every element representation' {
        InModuleScope TerminalSlides {
            $theme = Get-ResolvedTheme Midnight
            (ConvertTo-TableLines -Content 'scalar') | Should -Be 'scalar'
            (ConvertTo-TableLines -Content @()).Count | Should -Be 1
            (ConvertTo-TableLines -Content ([ordered]@{ Name = 'one'; Value = 1 }))[0] | Should -Match 'Name'
            (ConvertTo-TableLines -Content @([pscustomobject]@{ Name = 'two'; Value = 2 }))[2] | Should -Match 'two'
            $dictionaryRows = [object[]]@(
                [ordered]@{ Name = 'three'; Value = 3 }
                [ordered]@{ Name = 'four'; Value = 4 }
            )
            (ConvertTo-TableLines -Content $dictionaryRows)[2] | Should -Match 'three'

            $positive = @([pscustomobject]@{ Label = 'A'; Value = 25 }, [pscustomobject]@{ Label = 'B'; Value = 75 })
            $zero = @([pscustomobject]@{ Label = 'Zero'; Value = 0 })
            (ConvertTo-ChartLines -Content @() -Properties @{} -Theme $theme -Width 30) | Should -Be 'No chart data'
            foreach ($case in @(
                @{ Type = 'Gauge'; Data = $positive },
                @{ Type = 'Sparkline'; Data = $positive },
                @{ Type = 'Sparkline'; Data = $zero },
                @{ Type = 'Bar'; Data = $positive },
                @{ Type = 'Bar'; Data = $zero },
                @{ Type = 'Line'; Data = $positive },
                @{ Type = 'HorizontalBar'; Data = $positive },
                @{ Type = 'HorizontalBar'; Data = $zero }
            )) {
                (ConvertTo-ChartLines -Content $case.Data -Properties @{ ChartType = $case.Type; Title = 'Chart' } -Theme $theme -Width 30).Count | Should -BeGreaterThan 0
            }
            $theme.ChartPalette = @()
            (ConvertTo-ChartLines -Content $positive -Properties @{ ChartType = 'Bar' } -Theme $theme -Width 30).Count | Should -BeGreaterThan 0

            (ConvertTo-DiagramLines -Content @{ Nodes = @(); Edges = @() }) | Should -Be 'Empty diagram'
            $diagram = @{ Nodes = @([pscustomobject]@{ Id='a'; Label='A' }, [pscustomobject]@{ Id='b'; Label='B' }); Edges = @([pscustomobject]@{ From='a'; To='b'; Label='uses' }, [pscustomobject]@{ From='b'; To='a'; Label=$null }, [pscustomobject]@{ From='b'; To='missing'; Label=$null }) }
            (ConvertTo-DiagramLines -Content $diagram) -join "`n" | Should -Match 'uses'

            $elements = @(
                (New-InternalSlideElement -Kind Title -Payload ([TerminalSlides.Schema.V1.TextPayload]::new('title')))
                (New-InternalSlideElement -Kind Subtitle -Payload ([TerminalSlides.Schema.V1.TextPayload]::new('subtitle')))
                (New-InternalSlideElement -Kind Text -Payload ([TerminalSlides.Schema.V1.TextPayload]::new('long text')) -OverflowBehavior Truncate)
                (New-InternalSlideElement -Kind Bullet -Payload ([TerminalSlides.Schema.V1.TextPayload]::new('a long bullet value')))
                (New-InternalSlideElement -Kind Code -Payload ([TerminalSlides.Schema.V1.CodePayload]::new('plain code', 'text')))
                (New-InternalSlideElement -Kind Code -Payload ([TerminalSlides.Schema.V1.CodePayload]::new('function Test {}', 'powershell')))
                (New-InternalSlideElement -Kind Code -Payload ([TerminalSlides.Schema.V1.CodePayload]::new('return 1', 'javascript')))
                (New-InternalSlideElement -Kind Table -Payload ([TerminalSlides.Schema.V1.TablePayload]::new((ConvertTo-TerminalDataRows @([pscustomobject]@{ A=1 })))))
                (New-InternalSlideElement -Kind Chart -Payload ([TerminalSlides.Schema.V1.ChartPayload]::new([TerminalSlides.Schema.V1.ChartPoint[]]@([TerminalSlides.Schema.V1.ChartPoint]::new('A', 1)), 'Bar', $null)))
                (New-InternalSlideElement -Kind Diagram -Payload ([TerminalSlides.Schema.V1.DiagramPayload]::new([TerminalSlides.Schema.V1.DiagramNode[]]@([TerminalSlides.Schema.V1.DiagramNode]::new('a','A')), [TerminalSlides.Schema.V1.DiagramEdge[]]@())))
                (New-InternalSlideElement -Kind Image -Payload ([TerminalSlides.Schema.V1.ImagePayload]::new('missing-scalar.png', $null)))
                (New-InternalSlideElement -Kind Quote -Payload ([TerminalSlides.Schema.V1.QuotePayload]::new('quote', 'author')))
                (New-InternalSlideElement -Kind Box -Payload ([TerminalSlides.Schema.V1.TextPayload]::new('box')))
            )
            $theme.HeadingStyle = 'banner'
            foreach ($element in $elements) {
                (ConvertTo-ElementLines -Element $element -Theme $theme -Width 12 -Height 4).Count | Should -BeGreaterThan 0
            }
        }
    }

    It 'aligns table headers and values by terminal cells at their actual origins' {
        InModuleScope TerminalSlides {
            $rows = [object[]]@(
                [ordered]@{ '漢字' = 'x'; "A`tB" = "q`t" }
                [ordered]@{ '漢字' = '界'; "A`tB" = 'done' }
            )
            $lines = ConvertTo-TableLines -Content $rows -StartColumn 5
            $widths = @($lines | ForEach-Object { Measure-TextWidth -Text $_ -StartColumn 5 })

            @($widths | Select-Object -Unique).Count | Should -Be 1
            ($lines -join '') | Should -Not -Match "`t"

            $deck = New-TerminalPresentation -Title 'Terminal table' -Width 80 -Height 20
            $deck | Add-TerminalSlide -Title 'Table' -Layout Blank -Content {
                Add-SlideTable -Data @(
                    [ordered]@{ '漢字' = 'x'; "A`tB" = "q`t" }
                    [ordered]@{ '漢字' = '界'; "A`tB" = 'done' }
                )
            } | Out-Null
            $plan = Get-TerminalSlideLayoutPlan -Presentation $deck -SlideIndex 0 -Capability (
                [TerminalSlides.Schema.V1.TerminalCapability]@{ Width=80; Height=20; AnsiSupport=$true }
            )
            $prepared = @($plan.Placements[0].Lines)
            @($prepared.Width | Select-Object -Unique).Count | Should -Be 1
            (@($prepared | ForEach-Object GetText) -join '') | Should -Not -Match "`t"
        }
    }

    It 'renders the deterministic union of columns from every table row' {
        InModuleScope TerminalSlides {
            $rows = [object[]]@(
                [ordered]@{ Name = 'Ada' }
                @{ Role = 'Engineer'; Name = 'Grace' }
            )

            $lines = ConvertTo-TableLines -Content $rows

            $lines[0] | Should -Match 'Name'
            $lines[0] | Should -Match 'Role'
            $lines[3] | Should -Match 'Engineer'
            $lines | Should -Be (ConvertTo-TableLines -Content $rows)

            $unordered = ConvertTo-TableLines -Content @{ Zulu = 1; Alpha = 2 }
            $unordered[0].IndexOf('Alpha', [StringComparison]::Ordinal) |
                Should -BeLessThan $unordered[0].IndexOf('Zulu', [StringComparison]::Ordinal)
        }
    }

    It 'renders multiline table headers and cells as bordered logical continuation rows' {
        InModuleScope TerminalSlides {
            $rows = [object[]]@(
                [ordered]@{
                    "Name`rAlias" = "Ada`r`nLovelace"
                    "A`tB" = "q`t`n界"
                }
                [ordered]@{
                    "Name`rAlias" = 'Grace'
                    "A`tB" = "one`rtwo"
                    Later = 'tail'
                }
            )

            $lines = ConvertTo-TableLines -Content $rows -StartColumn 5
            $widths = @($lines | ForEach-Object { Measure-TextWidth -Text $_ -StartColumn 5 })

            $lines.Count | Should -Be 7
            $lines[0] | Should -Match 'Name'
            $lines[1] | Should -Match 'Alias'
            ($lines -join '') | Should -Match 'Lovelace'
            ($lines -join '') | Should -Match '界'
            ($lines -join '') | Should -Match 'Later'
            ($lines -join '') | Should -Match 'tail'
            ($lines -join '') | Should -Not -Match "`r|`n|`t"
            @($lines | Where-Object { $_ -notmatch '^\|.*\|$' }).Count | Should -Be 0
            @($widths | Select-Object -Unique).Count | Should -Be 1

            $deck = New-TerminalPresentation -Title 'Multiline terminal table' -Width 80 -Height 20
            $deck | Add-TerminalSlide -Title 'Table' -Layout Blank -Content {
                Add-SlideTable -Data $rows
            } | Out-Null
            $plan = Get-TerminalSlideLayoutPlan -Presentation $deck -SlideIndex 0 -Capability (
                [TerminalSlides.Schema.V1.TerminalCapability]@{ Width=80; Height=20; AnsiSupport=$true }
            )
            $prepared = @($plan.Placements[0].Lines)
            $prepared.Count | Should -Be 7
            @($prepared.Width | Select-Object -Unique).Count | Should -Be 1
            (@($prepared | ForEach-Object GetText) -join '') | Should -Not -Match "`r|`n|`t"
        }
    }

    It 'writes styled, aligned, clipped, and ANSI text into frames' {
        InModuleScope TerminalSlides {
            $theme = Get-ResolvedTheme Midnight
            $frame = [FrameBuffer]::new(12, 5)
            $region = @{ X=0; Y=0; Width=12; Height=4 }

            $custom = New-InternalSlideElement -Kind Text -Payload ([TerminalSlides.Schema.V1.TextPayload]::new('')) -ForegroundColor '#010203' -BackgroundColor '#040506' -Alignment Center
            Write-LinesToFrame -FrameBuffer $frame -Lines @('center', 'this line is clipped', 'last', 'ignored') -Region $region -Theme $theme -Element $custom -StartY 0 | Should -Be 4
            $right = New-InternalSlideElement -Kind Text -Payload ([TerminalSlides.Schema.V1.TextPayload]::new('')) -Alignment Right
            Write-LinesToFrame -FrameBuffer $frame -Lines @('right') -Region $region -Theme $theme -Element $right -StartY 0 | Should -Be 1
            $code = New-InternalSlideElement -Kind Code -Payload ([TerminalSlides.Schema.V1.CodePayload]::new('', 'text'))
            $styled = New-TerminalStyledLine -Text 'abcdef' -Foreground '#FF0000' -Bold
            Write-LinesToFrame -FrameBuffer $frame -Lines @($styled) -Region @{ X=0; Y=1; Width=3; Height=1 } -Theme $theme -Element $code -StartY 1 | Should -Be 2
            $subtitle = New-InternalSlideElement -Kind Subtitle -Payload ([TerminalSlides.Schema.V1.TextPayload]::new(''))
            Write-LinesToFrame -FrameBuffer $frame -Lines @('raw') -Region @{ X=0; Y=2; Width=3; Height=1 } -Theme $theme -Element $subtitle -StartY 2 | Should -Be 3

            Set-FrameText -FrameBuffer $frame -X 11 -Y 4 -Text '界'
            Set-FrameText -FrameBuffer $frame -X 0 -Y 4 -Text ([string][char]0)
        }
    }

    It 'normalizes raw and mixed logical rows before frame output' {
        InModuleScope TerminalSlides {
            $theme = Get-ResolvedTheme Midnight
            $element = New-InternalSlideElement -Kind Text -Payload ([TerminalSlides.Schema.V1.TextPayload]::new(''))

            $rawFrame = [FrameBuffer]::new(12, 3)
            Write-LinesToFrame -FrameBuffer $rawFrame -Lines @("A`nB") -Region @{ X=0; Y=0; Width=12; Height=3 } -Theme $theme -Element $element -StartY 0 |
                Should -Be 2
            $rawFrame.Cells[0][0].Char | Should -Be 'A'
            $rawFrame.Cells[1][0].Char | Should -Be 'B'

            $styled = [TerminalStyledLine]::new()
            Add-TerminalStyledRun -Line $styled -Text 'e' -Foreground '#FF0000'
            Add-TerminalStyledRun -Line $styled -Text ("$([char]0x0301)`r") -Foreground '#00FF00'
            Add-TerminalStyledRun -Line $styled -Text "`n`tB" -Foreground '#0000FF'
            $styledFrame = [FrameBuffer]::new(12, 3)
            Write-LinesToFrame -FrameBuffer $styledFrame -Lines @($styled) -Region @{ X=3; Y=0; Width=9; Height=3 } -Theme $theme -Element $element -StartY 0 |
                Should -Be 2
            $styledFrame.Cells[0][3].Char | Should -Be "e$([char]0x0301)"
            $styledFrame.Cells[0][3].Fg | Should -Be '#FF0000'
            $styledFrame.Cells[1][8].Char | Should -Be 'B'
            $styledFrame.Cells[1][8].Fg | Should -Be '#0000FF'

            $preparedSource = New-TerminalStyledLine -Text 'P' -Foreground '#ABCDEF'
            $prepared = ConvertTo-TerminalPreparedLine -Line $preparedSource -StartColumn 0 -MaxWidth 12
            $mixed = @($prepared, "R`n`nS")
            $normalized = ConvertTo-TerminalPreparedLines -Lines $mixed -StartColumn 0 -MaxWidth 12
            $normalized.Count | Should -Be 4
            [object]::ReferenceEquals($normalized[0], $prepared) | Should -BeTrue
            @($normalized | ForEach-Object GetText) | Should -Be @('P', 'R', '', 'S')

            $mixedFrame = [FrameBuffer]::new(12, 4)
            Write-LinesToFrame -FrameBuffer $mixedFrame -Lines $mixed -Region @{ X=0; Y=0; Width=12; Height=3 } -Theme $theme -Element $element -StartY 0 |
                Should -Be 3
            $mixedFrame.Cells[0][0].Char | Should -Be 'P'
            $mixedFrame.Cells[0][0].Fg | Should -Be '#ABCDEF'
            $mixedFrame.Cells[1][0].Char | Should -Be 'R'
            $mixedFrame.GetRowText(2).TrimEnd() | Should -BeNullOrEmpty
            $mixedFrame.GetRowText(3).TrimEnd() | Should -BeNullOrEmpty
        }
    }

    It 'renders typed styles according to terminal color capability' {
        InModuleScope TerminalSlides {
            foreach ($style in 'ascii', 'double', 'rounded', 'unicode') {
                (Get-BoxCharacters -Style $style).Count | Should -Be 6
            }
            $frame = [FrameBuffer]::new(4, 2)
            Draw-FrameBox -FrameBuffer $frame -X 0 -Y 0 -Width 1 -Height 1
            $frame.SetCell(0, 0, 'A', '#010203', '#040506', $true, $true, $true)
            $frame.SetCell(0, 1, 'B', $null, $null, $false, $false, $false)
            $trueColor = $frame.Render($true, $false)
            $color256 = $frame.Render($false, $true)
            $unstyledColor = $frame.Render($false, $false)
            $trueColor | Should -Match "`e\[1m"
            $trueColor | Should -Match "`e\[3m"
            $trueColor | Should -Match "`e\[4m"
            $trueColor | Should -Match "`e\[38;2;1;2;3m"
            $color256 | Should -Match "`e\[38;5;"
            $color256 | Should -Not -Match "`e\[38;2;"
            $unstyledColor | Should -Not -Match "`e\[38;"
        }
    }

}
