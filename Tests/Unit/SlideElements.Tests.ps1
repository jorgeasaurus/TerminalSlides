Describe 'Slide element builders' {
    BeforeAll { Import-Module (Join-Path $PSScriptRoot '..' '..' 'TerminalSlides.psd1') -Force }

    It 'creates title elements' {
        $deck = New-TerminalPresentation -Title 'Elements'
        $deck | Add-TerminalSlide -Title 'Slide' -Content { Add-SlideTitle 'Header' } | Out-Null
        $element = $deck.Slides[0].Elements[0]
        $element.Type | Should -Be 'Title'
        $element.Content | Should -Be 'Header'
    }

    It 'creates bullet elements with reveal step' {
        $deck = New-TerminalPresentation -Title 'Elements'
        $deck | Add-TerminalSlide -Title 'Slide' -Content { Add-SlideBullet 'Item' -RevealStep 2 } | Out-Null
        $deck.Slides[0].Elements[0].RevealStep | Should -Be 2
        $deck.Slides[0].MaxRevealStep | Should -Be 2
    }

    It 'runs diagram DSL without forcing SafeMode' {
        $deck = New-TerminalPresentation -Title 'D'
        $deck | Add-TerminalSlide -Title 'S' -Content {
            Add-SlideDiagram -Content {
                $id = 'a'
                Node -Id $id -Label 'A'
                Edge -From 'a' -To 'b'
            }
        } | Out-Null
        $diagram = $deck.Slides[0].Elements | Where-Object { $_.Type -eq 'Diagram' }
        $diagram | Should -Not -BeNullOrEmpty
        $diagram.Content.Nodes.Count | Should -Be 1
    }

    It 'creates code elements' {
        $deck = New-TerminalPresentation -Title 'Elements'
        $deck | Add-TerminalSlide -Title 'Slide' -Content { Add-SlideCode -Code 'Write-Host 1' -Language powershell } | Out-Null
        $element = $deck.Slides[0].Elements[0]
        $element.Type | Should -Be 'Code'
        $element.Properties.Language | Should -Be 'powershell'
    }
}
