Describe 'Terminal slide management' {
    BeforeEach {
        Import-Module (Join-Path $PSScriptRoot '..' '..' 'TerminalSlides.psd1') -Force
        $script:deck = New-TerminalPresentation -Title 'Management'
        foreach ($title in 'One', 'Two', 'Three') {
            $script:deck | Add-TerminalSlide -Title $title -Content { Add-SlideText 'Content' } | Out-Null
        }
    }

    It 'retrieves slides by index, title, and collection' {
        (Get-TerminalSlide -Presentation $deck -Index 2).Title | Should -Be 'Two'
        @(Get-TerminalSlide -Presentation $deck -Title 'Three').Title | Should -Be @('Three')
        @(Get-TerminalSlide -Presentation $deck).Count | Should -Be 3
        { Get-TerminalSlide -Presentation $deck -Index 4 } | Should -Throw 'Slide index out of range.'
    }

    It 'updates every editable slide property' {
        $updated = Set-TerminalSlide -Presentation $deck -Index 2 -Title 'Updated' -Layout Title -Notes 'Speaker note' -Background '#000000' -Hidden

        $updated.Slides[1].Title | Should -Be 'Updated'
        $updated.Slides[1].Layout | Should -Be 'Title'
        $updated.Slides[1].Notes | Should -Be 'Speaker note'
        $updated.Slides[1].Background | Should -Be '#000000'
        $updated.Slides[1].Hidden | Should -BeTrue
        { Set-TerminalSlide -Presentation $deck -Index 4 -Title 'Invalid' } | Should -Throw 'Slide index out of range.'
    }

    It 'copies slides at the end or at a requested destination' {
        $copyAtEnd = Copy-TerminalSlide -Presentation $deck -Index 1
        $copyAtEnd.Slides.Count | Should -Be 4
        $copyAtEnd.Slides[3].Title | Should -Be 'One'
        $copyAtEnd.Slides[3].Id | Should -Not -Be $copyAtEnd.Slides[0].Id

        $copyAtPosition = Copy-TerminalSlide -Presentation $deck -Index 1 -DestinationIndex 2
        $copyAtPosition.Slides[1].Title | Should -Be 'One'
        { Copy-TerminalSlide -Presentation $deck -Index 0 } | Should -Throw 'Slide index out of range.'
    }

    It 'moves and removes slides while preserving contiguous indices' {
        $moved = Move-TerminalSlide -Presentation $deck -Index 1 -DestinationIndex 3
        @($moved.Slides.Title) | Should -Be @('Two', 'Three', 'One')
        @($moved.Slides.Index) | Should -Be @(1, 2, 3)

        $removed = Remove-TerminalSlide -Presentation $deck -Index 2
        @($removed.Slides.Title) | Should -Be @('Two', 'One')
        { Move-TerminalSlide -Presentation $deck -Index 3 -DestinationIndex 1 } | Should -Throw 'Slide index out of range.'
        { Move-TerminalSlide -Presentation $deck -Index 1 -DestinationIndex 3 } | Should -Throw 'Destination index out of range.'
        { Remove-TerminalSlide -Presentation $deck -Index 3 } | Should -Throw 'Slide index out of range.'
    }
}
