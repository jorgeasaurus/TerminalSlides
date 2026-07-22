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
}
