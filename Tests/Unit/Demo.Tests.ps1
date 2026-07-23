Describe 'TerminalSlides feature demo' {
    BeforeAll { Import-Module (Join-Path $PSScriptRoot '..' '..' 'TerminalSlides.psd1') -Force }

    It 'builds a playable walkthrough of every slide element type' {
        $demo = Start-TerminalSlidesDemo -PassThru

        $demo | Should -BeOfType TerminalSlides.Schema.V1.TerminalPresentation
        $demo.Title | Should -Be 'TerminalSlides Feature Tour'
        $demo.Slides.Count | Should -BeGreaterOrEqual 7

        $elementTypes = @($demo.Slides | ForEach-Object { $_.Elements | ForEach-Object { $_.Kind.ToString() } })
        foreach ($type in 'Title', 'Subtitle', 'Text', 'Bullet', 'Code', 'Table', 'Chart', 'Diagram', 'Image', 'Quote', 'Box') {
            $elementTypes | Should -Contain $type
        }

        ($demo.Slides | Where-Object { $_.MaxRevealStep -gt 0 }).Count | Should -BeGreaterThan 0
        ($demo.Slides | Where-Object { $_.Notes }).Count | Should -BeGreaterThan 0
    }

    It 'renders every demo slide at its final reveal state' {
        $demo = Start-TerminalSlidesDemo -PassThru

        InModuleScope TerminalSlides -Parameters @{ Demo = $demo } {
            foreach ($slide in $Demo.Slides) {
                $output = Render-TerminalPresentationToString -Presentation $Demo -SlideIndex ($slide.Index - 1) -RevealStep $slide.MaxRevealStep -PlainText
                $output | Should -Match ([regex]::Escape($slide.Title))
            }
        }
    }

    It 'includes a packaged presentation photo that renders in its own image slide' {
        $demo = Start-TerminalSlidesDemo -PassThru
        $imageSlide = $demo.Slides | Where-Object Layout -eq ImageFocus | Select-Object -First 1
        $image = $imageSlide.Elements | Where-Object Kind -eq Image | Select-Object -First 1

        $imageSlide | Should -Not -BeNullOrEmpty
        $image | Should -Not -BeNullOrEmpty
        [System.IO.Path]::GetFileName($image.Payload.Path) | Should -Be 'presentation-team-photo.jpg'
        (Split-Path (Split-Path $image.Payload.Path -Parent) -Leaf) | Should -Be 'Assets'
        $image.Payload.Path | Should -Exist

        InModuleScope TerminalSlides -Parameters @{ Demo = $demo; Slide = $imageSlide } {
            $output = Render-TerminalPresentationToString -Presentation $Demo -SlideIndex ($Slide.Index - 1)
            $output | Should -Match '[▀▄]'
            $output | Should -Not -Match 'Image:'
        }
    }

    It 'builds a playable Intune Hydration Kit showcase from the same launcher' {
        $demo = Start-TerminalSlidesDemo -Name IntuneHydrationKit -PassThru

        $demo | Should -BeOfType TerminalSlides.Schema.V1.TerminalPresentation
        $demo.Title | Should -Be 'Intune Hydration Kit'
        $demo.Theme | Should -Be 'PowerShell'
        @($demo.Slides.Title) | Should -Be @(
            'Intune Hydration Kit'
            'One command. 1,000+ building blocks.'
            'Install, then hydrate'
            'Guided TUI, deliberate choices'
            'Choose only what you need'
            'Preview before Graph writes'
            'Windows apps, ready for Intune'
            'Repeatable automation'
            'Guardrails, not guesswork'
            'Evidence at the finish line'
        )

        $elementTypes = @($demo.Slides | ForEach-Object {
            $_.Elements | ForEach-Object { $_.Kind.ToString() }
        })
        foreach ($type in 'Title', 'Subtitle', 'Text', 'Bullet', 'Code', 'Table', 'Chart', 'Diagram', 'Image', 'Box') {
            $elementTypes | Should -Contain $type
        }

        $previewCode = $demo.Slides |
            Where-Object Title -eq 'Preview before Graph writes' |
            ForEach-Object Elements |
            Where-Object Kind -eq Code |
            Select-Object -ExpandProperty Payload |
            Select-Object -ExpandProperty Code
        $previewCode | Should -Match 'Invoke-IntuneHydration'
        $previewCode | Should -Match '-WhatIf'
    }

    It 'renders every Intune Hydration Kit slide at its final reveal state' {
        $demo = Start-TerminalSlidesDemo -Name IntuneHydrationKit -PassThru

        InModuleScope TerminalSlides -Parameters @{ Demo = $demo } {
            foreach ($slide in $Demo.Slides) {
                $output = Render-TerminalPresentationToString -Presentation $Demo -SlideIndex ($slide.Index - 1) -RevealStep $slide.MaxRevealStep -PlainText
                $output | Should -Match ([regex]::Escape($slide.Title))
            }
        }
    }

    It 'fits the Intune Hydration Kit showcase at compact and presentation viewports' {
        $demo = Start-TerminalSlidesDemo -Name IntuneHydrationKit -PassThru
        $results = Test-TerminalPresentation `
            -Presentation $demo `
            -Viewport '80x24', '100x30', '128x32'

        @($results | Where-Object { -not $_.Fits }) | Should -BeNullOrEmpty
    }

    It 'packages and renders the Intune Hydration Kit TUI in its own image slide' {
        $demo = Start-TerminalSlidesDemo -Name IntuneHydrationKit -PassThru
        $imageSlide = $demo.Slides | Where-Object Title -eq 'Guided TUI, deliberate choices'
        $image = $imageSlide.Elements | Where-Object Kind -eq Image | Select-Object -First 1

        $imageSlide.Layout | Should -Be 'ImageFocus'
        [System.IO.Path]::GetFileName($image.Payload.Path) | Should -Be 'intune-hydration-kit-tui.png'
        $image.Payload.Path | Should -Exist

        InModuleScope TerminalSlides -Parameters @{ Demo = $demo; Slide = $imageSlide } {
            $output = Render-TerminalPresentationToString -Presentation $Demo -SlideIndex ($Slide.Index - 1)
            $output | Should -Match '[▀▄]'
            $output | Should -Not -Match 'Image:'
        }
    }
}
