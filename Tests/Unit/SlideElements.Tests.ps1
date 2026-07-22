Describe 'Slide element builders' {
    BeforeAll { Import-Module (Join-Path $PSScriptRoot '..' '..' 'TerminalSlides.psd1') -Force }

    It 'creates title elements' {
        $deck = New-TerminalPresentation -Title 'Elements'
        $deck | Add-TerminalSlide -Title 'Slide' -Content { Add-SlideTitle 'Header' } | Out-Null
        $element = $deck.Slides[0].Elements[0]
        $element.Kind | Should -Be ([TerminalSlides.Schema.V1.ElementKind]::Title)
        $element.Payload.Text | Should -Be 'Header'
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
                Add-SlideDiagramNode -Id $id -Label 'A'
                Add-SlideDiagramEdge -From 'a' -To 'b'
            }
        } | Out-Null
        $diagram = $deck.Slides[0].Elements | Where-Object { $_.Kind -eq 'Diagram' }
        $diagram | Should -Not -BeNullOrEmpty
        $diagram.Payload.Nodes.Count | Should -Be 1
    }

    It 'creates code elements' {
        $deck = New-TerminalPresentation -Title 'Elements'
        $deck | Add-TerminalSlide -Title 'Slide' -Content { Add-SlideCode -Code 'Write-Host 1' -Language powershell } | Out-Null
        $element = $deck.Slides[0].Elements[0]
        $element.Kind | Should -Be ([TerminalSlides.Schema.V1.ElementKind]::Code)
        $element.Payload.Language | Should -Be 'powershell'
    }

    It 'rejects chart values that are not invariant numeric values' {
        $deck = New-TerminalPresentation -Title 'Charts'

        {
            $deck | Add-TerminalSlide -Title 'Invalid chart' -Content {
                Add-SlideChart -Data @([pscustomobject]@{ Label = 'Broken'; Value = 'not-a-number' })
            }
        } | Should -Throw "*Chart value 'not-a-number' is not numeric*"

        {
            $deck | Add-TerminalSlide -Title 'Missing label' -Content {
                Add-SlideChart -Data @([pscustomobject]@{ Value = 1 })
            }
        } | Should -Throw '*Chart rows require Label and Value properties*'
    }
}
