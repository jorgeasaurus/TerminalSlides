Describe 'Text formatting contracts' {
    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '..' '..' 'TerminalSlides.psd1') -Force
    }

    It 'wraps empty, truncated, scrolled, whitespace, and oversized text safely' {
        InModuleScope TerminalSlides {
            (Format-WordWrap -Text $null -Width 4) | Should -Be @('')
            (Format-WordWrap -Text "one`ntwo" -Width 8) -join ',' | Should -Be 'one,two'
            (Format-WordWrap -Text "$(Get-AnsiBold)abcdef$(Get-AnsiReset)" -Width 3 -OverflowBehavior Truncate) | Should -Be 'abc'
            (Format-WordWrap -Text 'abcdef' -Width 3 -OverflowBehavior Scroll) | Should -Be @('abc', 'def')
            (Format-WordWrap -Text 'alpha beta ' -Width 5).Count | Should -BeGreaterThan 1
            (Format-WordWrap -Text 'abcdefgh ' -Width 3) | Should -Be @('abc', 'def', 'gh')
        }
    }

    It 'uses one logical-row contract for public text, code, wrapping, and highlighting' {
        InModuleScope TerminalSlides {
            $content = "A`rB`r`nC`n`n"
            $expected = @('A', 'B', 'C', '', '')
            $separator = '<ROW>'
            $expectedRows = $expected -join $separator

            ((Split-TerminalLogicalRows -Text $content) -join $separator) | Should -Be $expectedRows
            ((Format-WordWrap -Text $content -Width 20 -OverflowBehavior Wrap) -join $separator) | Should -Be $expectedRows
            ((Format-WordWrap -Text $content -Width 20 -OverflowBehavior Scroll) -join $separator) | Should -Be $expectedRows
            ((Get-SyntaxHighlight -Code $content -Language text -Theme $null) -join $separator) | Should -Be $expectedRows

            $theme = Get-ResolvedTheme Midnight
            $highlighted = @(Get-SyntaxHighlight -Code $content -Language powershell -Theme $theme)
            (@($highlighted | ForEach-Object GetText) -join $separator) | Should -Be $expectedRows

            $capability = [TerminalSlides.Schema.V1.TerminalCapability]@{ Width=40; Height=15; AnsiSupport=$true }
            $textDeck = New-TerminalPresentation -Title 'Text rows' -Width 40 -Height 15
            $textDeck | Add-TerminalSlide -Title 'Slide' -Layout Blank -Content {
                Add-SlideText "A`rB`r`nC`n`n" -OverflowBehavior Scroll
            } | Out-Null
            $textPlan = Get-TerminalSlideLayoutPlan -Presentation $textDeck -SlideIndex 0 -Capability $capability
            (@($textPlan.Placements[0].Lines | ForEach-Object GetText) -join $separator) | Should -Be $expectedRows

            $codeDeck = New-TerminalPresentation -Title 'Code rows' -Width 40 -Height 15
            $codeDeck | Add-TerminalSlide -Title 'Slide' -Layout Blank -Content {
                Add-SlideCode -Code "A`rB`r`nC`n`n" -Language powershell
            } | Out-Null
            $codePlan = Get-TerminalSlideLayoutPlan -Presentation $codeDeck -SlideIndex 0 -Capability $capability
            (@($codePlan.Placements[0].Lines | ForEach-Object GetText) -join $separator) | Should -Be $expectedRows
        }
    }

    It 'validates colors and exposes every ANSI style helper' {
        InModuleScope TerminalSlides {
            { Convert-HexToRgb -Hex 'broken' } | Should -Throw '*Invalid hex color*'
            Get-AnsiItalic | Should -Be "`e[3m"
            Get-AnsiUnderline | Should -Be "`e[4m"
            Strip-AnsiSequences -Text $null | Should -BeNullOrEmpty
        }
    }

    It 'highlights supported language families and theme fallbacks' {
        InModuleScope TerminalSlides {
            (Get-SyntaxHighlight -Code "a`nb" -Language text -Theme $null) -join ',' | Should -Be 'a,b'
            $theme = [TerminalSlides.Schema.V1.ThemeDefinition]::new()
            $theme.Primary = '#112233'
            $theme.Foreground = '#EEEEEE'
            foreach ($language in 'json', 'yaml', 'javascript') {
                (Get-SyntaxHighlight -Code 'function return' -Language $language -Theme $theme).Count | Should -Be 1
            }
            $javascript = @(Get-SyntaxHighlight -Code 'function return' -Language javascript -Theme $theme)[0]
            $javascript.GetType().Name | Should -Be 'TerminalStyledLine'
            $javascript.Runs[0].Foreground | Should -Be $theme.Primary
            $javascript.Runs[0].Bold | Should -BeTrue

            $powerShellKeyword = @(Get-SyntaxHighlight -Code 'function Test {}' -Language powershell -Theme $theme)[0]
            @($powerShellKeyword.Runs | Where-Object Text -eq 'function')[0].Foreground | Should -Be $theme.Primary

            $powershell = @(Get-SyntaxHighlight -Code "'value' # note" -Language powershell -Theme $theme)[0]
            $powershell.GetText() | Should -Be "'value' # note"
            $powershell.GetText() | Should -Not -Match ([regex]::Escape([string][char]27))
            @($powershell.Runs | Where-Object Text -eq "'value'")[0].Foreground | Should -Be $theme.Foreground
            @($powershell.Runs | Where-Object Text -eq '# note')[0].Foreground | Should -Be $theme.Foreground

            $theme.Accent = '#445566'
            $theme.SuccessColor = '#778899'
            $theme.Muted = '#AABBCC'
            $styled = @(Get-SyntaxHighlight -Code "function Test { 'value' # note } " -Language powershell -Theme $theme)[0]
            $styled.GetText() | Should -Be "function Test { 'value' # note } "
            @($styled.Runs | Where-Object Text -eq 'function')[0].Foreground | Should -Be $theme.Accent
            @($styled.Runs | Where-Object Text -eq "'value'")[0].Foreground | Should -Be $theme.SuccessColor
            @($styled.Runs | Where-Object Text -Like '# note*')[0].Foreground | Should -Be $theme.Muted

            $trailingWhitespace = ConvertTo-PowerShellStyledLine -Text "'value' " -Theme $theme
            $trailingWhitespace.GetText() | Should -Be "'value' "
            $trailingWhitespace.Runs[-1].Text | Should -Be ' '
            $trailingWhitespace.Runs[-1].Foreground | Should -BeNullOrEmpty
        }
    }

    It 'preserves multiline PowerShell token styles across canonical logical rows' {
        InModuleScope TerminalSlides {
            $theme = [TerminalSlides.Schema.V1.ThemeDefinition]::new()
            $theme.Foreground = '#EEEEEE'
            $theme.Accent = '#445566'
            $theme.SuccessColor = '#778899'
            $theme.Muted = '#AABBCC'
            $hereString = "@'`nfunction Test {}`n'@"
            $blockComment = "<#`nfunction Test {}`n#>"

            $hereRows = @(Get-SyntaxHighlight -Code $hereString -Language powershell -Theme $theme)
            @($hereRows | ForEach-Object GetText) -join '<ROW>' | Should -Be "@'<ROW>function Test {}<ROW>'@"
            @($hereRows[1].Runs | Where-Object Foreground -ne $theme.SuccessColor).Count | Should -Be 0
            @($hereRows[1].Runs | Where-Object Bold).Count | Should -Be 0

            $commentRows = @(Get-SyntaxHighlight -Code $blockComment -Language powershell -Theme $theme)
            @($commentRows | ForEach-Object GetText) -join '<ROW>' | Should -Be '<#<ROW>function Test {}<ROW>#>'
            @($commentRows[1].Runs | Where-Object Foreground -ne $theme.Muted).Count | Should -Be 0
            @($commentRows[1].Runs | Where-Object Bold).Count | Should -Be 0

            $deck = New-TerminalPresentation -Title 'Multiline tokens' -Width 40 -Height 15
            $deck | Add-TerminalSlide -Title 'Here string' -Layout Blank -Content {
                Add-SlideCode -Code "@'`nfunction Test {}`n'@" -Language powershell
            } | Out-Null
            $plan = Get-TerminalSlideLayoutPlan -Presentation $deck -SlideIndex 0 -Capability (
                [TerminalSlides.Schema.V1.TerminalCapability]@{ Width=40; Height=15; AnsiSupport=$true }
            )
            $codeLines = @($plan.Placements[0].Lines)
            $resolvedTheme = Get-ResolvedTheme Midnight
            @($codeLines[1].Runs | Where-Object Foreground -ne $resolvedTheme.SuccessColor).Count | Should -Be 0
            @($codeLines[1].Runs | Where-Object Bold).Count | Should -Be 0

            $wrappedDeck = New-TerminalPresentation -Title 'Wrapped tokens' -Width 20 -Height 15
            $wrappedDeck | Add-TerminalSlide -Title 'Comment' -Layout Blank -Content {
                Add-SlideCode -Code '# 1234567890123 function Test {}' -Language powershell
            } | Out-Null
            $wrappedPlan = Get-TerminalSlideLayoutPlan -Presentation $wrappedDeck -SlideIndex 0 -Capability (
                [TerminalSlides.Schema.V1.TerminalCapability]@{ Width=20; Height=15; AnsiSupport=$true }
            )
            $wrappedLines = @($wrappedPlan.Placements[0].Lines)
            @($wrappedLines | ForEach-Object GetText) | Should -Be @('# 1234567890123 ', 'function Test {}')
            @($wrappedLines.Runs | Where-Object Foreground -ne $resolvedTheme.Muted).Count | Should -Be 0
            @($wrappedLines.Runs | Where-Object Bold).Count | Should -Be 0
        }
    }

    It 'rejects malformed UTF-16 at plain, styled, render, and validation boundaries' {
        InModuleScope TerminalSlides {
            $invalid = [string][char]0xD800
            { Split-TerminalLogicalRows -Text $invalid } | Should -Throw '*valid UTF-16*'
            { Measure-TextWidth -Text $invalid } | Should -Throw '*valid UTF-16*'
            { ConvertTo-TerminalPreparedLines -Lines @($invalid) -MaxWidth 10 } | Should -Throw '*valid UTF-16*'

            $invalidLine = [TerminalStyledLine]::new()
            $invalidLine.Runs.Add([TerminalStyledRun]::new($invalid, $null, $null, $false, $false, $false))
            { Get-TerminalStyledGraphemes -Line $invalidLine } | Should -Throw '*valid UTF-16*'

            $pair = [char]::ConvertFromUtf32(0x1F680)
            $splitPair = [TerminalStyledLine]::new()
            $splitPair.Runs.Add([TerminalStyledRun]::new([string]$pair[0], '#111111', $null, $false, $false, $false))
            $splitPair.Runs.Add([TerminalStyledRun]::new([string]$pair[1], '#222222', $null, $false, $false, $false))
            $graphemes = @(Get-TerminalStyledGraphemes -Line $splitPair)
            $graphemes.Count | Should -Be 1
            $graphemes[0].Text | Should -Be $pair

            $deck = New-TerminalPresentation -Title 'Invalid text' -Width 40 -Height 15
            $deck | Add-TerminalSlide -Title 'Slide' -Layout Blank -Content { Add-SlideText ([string][char]0xD800) } | Out-Null
            { Render-TerminalPresentationToString -Presentation $deck -PlainText } | Should -Throw '*valid UTF-16*'
            { Test-TerminalPresentation -Presentation $deck -Viewport '40x15' } | Should -Throw '*valid UTF-16*'
        }
    }

}
