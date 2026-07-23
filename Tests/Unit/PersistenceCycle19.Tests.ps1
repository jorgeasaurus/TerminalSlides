Describe 'Cycle 19 persistence boundaries' {
    BeforeAll {
        $script:ModulePath = Join-Path $PSScriptRoot '..' '..' 'TerminalSlides.psd1'
        Import-Module $script:ModulePath -Force

        function Write-Cycle19CurrentWireFile {
            param(
                [Parameter(Mandatory)][System.Collections.IDictionary]$Data,
                [Parameter(Mandatory)][ValidateSet('Json','Psd1','Markdown')][string]$Format,
                [Parameter(Mandatory)][string]$Path
            )

            $content = & (Get-Module TerminalSlides) {
                param($WireData, $WireFormat)
                switch ($WireFormat) {
                    'Json' { ConvertTo-TerminalWireJson $WireData }
                    'Psd1' { "@{ TerminalSlidesEnvelope = '$(ConvertTo-TerminalDataMarker $WireData)' }`n" }
                    'Markdown' {
                        $marker = [ordered]@{ MarkerVersion = 1; Presentation = $WireData }
                        '<!-- terminalslides:envelope ' + (ConvertTo-TerminalDataMarker $marker) + ' -->'
                    }
                }
            } $Data $Format
            [IO.File]::WriteAllText($Path, $content, [Text.UTF8Encoding]::new($false))
        }
    }

    It 'rejects every invalid renderer-facing current-wire domain before construction' {
        $invalidCases = & (Get-Module TerminalSlides) {
            $deck = New-TerminalPresentation -Title InvalidDomains
            $deck | Add-TerminalSlide -Title Code -Layout CodeFocus -Content {
                Add-SlideCode -Code 'Get-Date' -Language powershell -Region Code -Border
            } | Out-Null
            $base = ConvertTo-PresentationData $deck
            $copy = { ConvertFrom-TerminalWireJson (ConvertTo-TerminalWireJson $base) }

            $theme = & $copy; $theme.Presentation.Theme = 'MissingTheme'
            $language = & $copy; $language.Presentation.Slides[0].Elements[0].Payload.Language = '   '
            $vertical = & $copy; $vertical.Presentation.Slides[0].Elements[0].VerticalAlignment = 'UpsideDown'
            $foreground = & $copy; $foreground.Presentation.Slides[0].Elements[0].ForegroundColor = 'red'
            $background = & $copy; $background.Presentation.Slides[0].Elements[0].BackgroundColor = '#12345'
            $slideBackground = & $copy; $slideBackground.Presentation.Slides[0].Background = '#nothex'
            $border = & $copy; $border.Presentation.Slides[0].Elements[0].BorderStyle = 'Explode'
            $nullRegion = & $copy; $nullRegion.Presentation.Slides[0].Elements[0].Region = $null
            $blankRegion = & $copy; $blankRegion.Presentation.Slides[0].Elements[0].Region = '   '
            $unavailableRegion = & $copy; $unavailableRegion.Presentation.Slides[0].Layout = 'TitleAndContent'
            $overlappingRegions = & $copy
            $overlappingRegions.Presentation.Slides[0].Layout = 'TwoColumn'
            $overlappingRegions.Presentation.Slides[0].Elements[0].Region = 'Left'
            $secondElement = & $copy
            $secondElement.Presentation.Slides[0].Elements[0].Region = 'Content'
            $overlappingRegions.Presentation.Slides[0].Elements = @(
                $overlappingRegions.Presentation.Slides[0].Elements[0],
                $secondElement.Presentation.Slides[0].Elements[0]
            )

            return ,([object[]]@(
                $theme, $language, $vertical, $foreground, $background, $slideBackground,
                $border, $nullRegion, $blankRegion, $unavailableRegion, $overlappingRegions
            ))
        }

        foreach ($caseIndex in 0..($invalidCases.Count - 1)) {
            foreach ($format in 'Json','Psd1','Markdown') {
                $path = Join-Path $TestDrive "invalid-renderer-domain-$caseIndex.$($format.ToLowerInvariant())"
                Write-Cycle19CurrentWireFile -Data $invalidCases[$caseIndex] -Format $format -Path $path
                { Import-TerminalPresentation $path } | Should -Throw '*current wire*'
            }
        }
    }

    It 'canonicalizes case-insensitive renderer domains through every structured format' {
        foreach ($format in 'Json','Psd1','Markdown') {
            $deck = New-TerminalPresentation -Title CanonicalDomains -Theme midnight -DefaultLayout titleandcontent
            $deck | Add-TerminalSlide -Title Content -Layout titleandcontent -Background aabbcc -Content {
                Add-SlideText -Text value -Region content -Alignment left -OverflowBehavior wrap
            } | Out-Null
            $element = $deck.Slides[0].Elements[0]
            $element.VerticalAlignment = 'bottom'
            $element.ForegroundColor = 'abcdef'
            $element.BackgroundColor = '#a1b2c3'
            $element.BorderStyle = 'DOUBLE'

            $path = Join-Path $TestDrive "canonical-domains.$($format.ToLowerInvariant())"
            Export-TerminalPresentation -Presentation $deck -Path $path -Format $format -Force | Out-Null
            $imported = Import-TerminalPresentation $path
            $actual = $imported.Slides[0].Elements[0]

            $imported.Theme | Should -BeExactly Midnight
            $imported.DefaultLayout | Should -BeExactly TitleAndContent
            $imported.Slides[0].Layout | Should -BeExactly TitleAndContent
            $imported.Slides[0].Background | Should -BeExactly '#AABBCC'
            $actual.Region | Should -BeExactly Content
            $actual.Alignment | Should -BeExactly Left
            $actual.VerticalAlignment | Should -BeExactly Bottom
            $actual.ForegroundColor | Should -BeExactly '#ABCDEF'
            $actual.BackgroundColor | Should -BeExactly '#A1B2C3'
            $actual.BorderStyle | Should -BeExactly double
            $actual.OverflowBehavior | Should -BeExactly Wrap
        }

        $nullableColors = & (Get-Module TerminalSlides) {
            $deck = New-TerminalPresentation -Title NullableColors
            $deck | Add-TerminalSlide -Title Content -Content { Add-SlideText value } | Out-Null
            $wire = ConvertTo-PresentationData $deck
            $wire.Presentation.Slides[0].Background = $null
            $wire.Presentation.Slides[0].Elements[0].ForegroundColor = $null
            $wire.Presentation.Slides[0].Elements[0].BackgroundColor = $null
            ConvertFrom-TerminalCurrentData $wire
        }
        $nullableColors.Slides[0].Background | Should -BeNullOrEmpty
        $nullableColors.Slides[0].Elements[0].ForegroundColor | Should -BeNullOrEmpty
        $nullableColors.Slides[0].Elements[0].BackgroundColor | Should -BeNullOrEmpty
    }

    It 'parses PSD1 from the immutable strict-decoded snapshot when the source is replaced' {
        $sourcePath = Join-Path $TestDrive 'source-swap.psd1'
        [IO.File]::WriteAllText($sourcePath, "@{ Title = 'Validated'; Slides = @() }", [Text.UTF8Encoding]::new($false))
        $replacement = [Text.Encoding]::UTF8.GetBytes("@{ Title = 'InvalidUtf8'; Slides = @() }")
        $replacement[[Array]::IndexOf($replacement, [byte][char]'I')] = 0xff

        InModuleScope TerminalSlides -Parameters @{ SourcePath = $sourcePath; Replacement = $replacement } {
            $script:Cycle19SnapshotPath = $null
            Mock Import-PowerShellDataFile {
                $script:Cycle19SnapshotPath = $LiteralPath
                [IO.File]::ReadAllText($LiteralPath) | Should -BeExactly "@{ Title = 'Validated'; Slides = @() }"
                [IO.File]::WriteAllBytes($SourcePath, $Replacement)
                return @{ Title = 'Validated'; Slides = @() }
            }

            $imported = Import-TerminalPresentation $SourcePath

            $imported.Title | Should -BeExactly Validated
            $script:Cycle19SnapshotPath | Should -Not -BeExactly $SourcePath
            Test-Path -LiteralPath $script:Cycle19SnapshotPath | Should -BeFalse
            Should -Invoke Import-PowerShellDataFile -Exactly 1
        }

        { Import-TerminalPresentation $sourcePath } | Should -Throw '*valid UTF-8*'
    }

    It 'emits canonical LF Markdown and accepts only line-ending changes to visible content' {
        $deck = New-TerminalPresentation -Title CanonicalMarkdown
        $deck | Add-TerminalSlide -Title Content -Content {
            Add-SlideText "first`rsecond"
            Add-SlideCode -Code "Get-Date`r`nGet-Process" -Language powershell
        } | Out-Null
        $path = Join-Path $TestDrive 'canonical.md'
        Export-TerminalPresentation -Presentation $deck -Path $path -Format Markdown -Force | Out-Null

        $content = [IO.File]::ReadAllText($path)
        $content.Contains("`r") | Should -BeFalse
        (Import-TerminalPresentation $path).Title | Should -BeExactly CanonicalMarkdown

        $match = [regex]::Match($content, '<!--\s*terminalslides:envelope\s+(?<data>[A-Za-z0-9+/=]+)\s*-->\s*\z')
        $match.Success | Should -BeTrue
        $transferred = $content.Remove($match.Index).Replace("`n", "`r`n") + $content.Substring($match.Index)
        [IO.File]::WriteAllText($path, $transferred, [Text.UTF8Encoding]::new($false))
        (Import-TerminalPresentation $path).Title | Should -BeExactly CanonicalMarkdown

        $edited = $transferred.Replace('# Content', '# Edited')
        [IO.File]::WriteAllText($path, $edited, [Text.UTF8Encoding]::new($false))
        { Import-TerminalPresentation $path } | Should -Throw '*visible Markdown was edited*'
    }
}
