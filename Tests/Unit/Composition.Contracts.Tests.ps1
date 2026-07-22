Describe 'Composition contracts' {
    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '..' '..' 'TerminalSlides.psd1') -Force
    }

    It 'enforces diagram and note builder context boundaries' {
        { Add-SlideDiagramNode -Id outside -Label Outside } | Should -Throw '*inside Add-SlideDiagram*'
        { Add-SlideDiagramEdge -From a -To b } | Should -Throw '*inside Add-SlideDiagram*'
        $note = Add-SlideNotes 'speaker note'
        $note.__TerminalSlidesNote | Should -BeTrue
        $note.Text | Should -Be 'speaker note'
    }

    It 'captures queued builders and compatible returned content values' {
        InModuleScope TerminalSlides {
            $deck = New-TerminalPresentation -Title 'Capture'
            $deck | Add-TerminalSlide -Title 'Queued' -Content {
                Add-SlideText 'queued' -RevealStep 2
                New-InternalSlideElement -Kind Text -Payload ([TerminalSlides.Schema.V1.TextPayload]::new('returned')) -RevealStep 3
                Add-SlideNotes 'returned note'
            } | Out-Null

            $deck.Slides[0].Elements.Payload.Text | Should -Contain 'queued'
            $deck.Slides[0].Elements.Payload.Text | Should -Contain 'returned'
            $deck.Slides[0].Notes | Should -Be 'returned note'
            $deck.Slides[0].MaxRevealStep | Should -Be 3
            $ids = @($deck.Slides[0].Elements.Id)
            $ids | Should -HaveCount 2
            @($ids | Sort-Object -Unique) | Should -HaveCount 2
            $ids | ForEach-Object { $_ | Should -Not -BeNullOrEmpty }
        }
    }

    It 'loads sparse theme definitions and validates the data assembly contract' {
        InModuleScope TerminalSlides {
            $theme = New-ThemeDefinitionFromHashtable -Definition @{ Name = 'Sparse'; Background = '#000000'; Foreground = '#FFFFFF'; Primary = '#123456'; Unknown = 'kept' }
            $theme.CodeTheme | Should -Be 'Default'
            $theme.BulletSymbol | Should -Be '•'
            $theme.ChartPalette.Count | Should -Be 3
            $theme.Metadata.Unknown | Should -Be 'kept'

            $script:Themes = @{}
            (Get-ResolvedTheme).Name | Should -Be 'Midnight'
            [TerminalSlides.Schema.V1.TerminalPresentation].Assembly.GetName().Version | Should -Be ([version]'1.0.0.0')
            { New-PresentationFromData -Data @{ Width = 10; Height = 10 } } | Should -Throw '*at least 20x10*'
        }
    }

    It 'supports custom chart palettes and capability probe fallbacks' {
        InModuleScope TerminalSlides {
            $script:Themes = $null
            $theme = New-TerminalPresentationTheme -Name 'Palette' -Background '#000000' -Foreground '#FFFFFF' -Primary '#111111' -ChartPalette '#222222', '#333333'
            $theme.ChartPalette | Should -Be @('#222222', '#333333')
            $script:Themes.ContainsKey('Palette') | Should -BeTrue
            (Invoke-TerminalCapabilityProbe -Operation { throw 'probe failed' } -Fallback 77) | Should -Be 77
            (Get-TerminalPresentationCapability).PSVersion | Should -Not -BeNullOrEmpty
            Initialize-TerminalSlidesThemes
        }
    }

}
