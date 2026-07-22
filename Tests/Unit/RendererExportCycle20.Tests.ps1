Describe 'Cycle 20 renderer and export transactions' {
    BeforeAll {
        $script:ModulePath = Join-Path $PSScriptRoot '..' '..' 'TerminalSlides.psd1'
        Import-Module $script:ModulePath -Force

        function New-Cycle20ExportDeck {
            param(
                [Parameter(Mandatory)][string]$Title,
                [string]$ImagePath
            )

            $deck = New-TerminalPresentation -Title $Title
            $deck | Add-TerminalSlide -Title Slide -Content {
                if ($ImagePath) { Add-SlideImage -Path $ImagePath -AltText Photo }
                else { Add-SlideText Body }
            } | Out-Null
            return $deck
        }

        function Assert-Cycle20CreatedChainRemoved {
            param(
                [Parameter(Mandatory)][string]$ExistingRoot,
                [Parameter(Mandatory)][string]$TargetPath
            )

            $TargetPath | Should -Not -Exist
            Split-Path -Parent $TargetPath | Should -Not -Exist
            Split-Path -Parent (Split-Path -Parent $TargetPath) | Should -Not -Exist
            $ExistingRoot | Should -Exist
            Join-Path $ExistingRoot sentinel.txt | Should -Exist
        }
    }

    It 'removes every nested directory created before a missing-media failure' {
        $existingRoot = Join-Path $TestDrive missing-media-root
        New-Item -Path $existingRoot -ItemType Directory | Out-Null
        Set-Content -LiteralPath (Join-Path $existingRoot sentinel.txt) -Value keep
        $missingPath = Join-Path $TestDrive missing.png
        $deck = New-Cycle20ExportDeck -Title Missing -ImagePath $missingPath
        $target = Join-Path $existingRoot first second deck.md

        { Export-TerminalPresentation -Presentation $deck -Path $target -Format Markdown } |
            Should -Throw '*was not found*'

        Assert-Cycle20CreatedChainRemoved -ExistingRoot $existingRoot -TargetPath $target
    }

    It 'removes every nested directory created before serialization fails' {
        $existingRoot = Join-Path $TestDrive serialization-root
        New-Item -Path $existingRoot -ItemType Directory | Out-Null
        Set-Content -LiteralPath (Join-Path $existingRoot sentinel.txt) -Value keep
        $deck = New-Cycle20ExportDeck -Title ([string][char]0xd800)
        $target = Join-Path $existingRoot first second deck.md

        { Export-TerminalPresentation -Presentation $deck -Path $target -Format Markdown } |
            Should -Throw '*valid UTF-16*'

        Assert-Cycle20CreatedChainRemoved -ExistingRoot $existingRoot -TargetPath $target
    }

    It 'removes every nested directory created before the document writer fails' {
        $existingRoot = Join-Path $TestDrive writer-root
        New-Item -Path $existingRoot -ItemType Directory | Out-Null
        Set-Content -LiteralPath (Join-Path $existingRoot sentinel.txt) -Value keep
        $deck = New-Cycle20ExportDeck -Title Writer
        $target = Join-Path $existingRoot first second deck.md

        InModuleScope TerminalSlides -Parameters @{ Deck = $deck; Target = $target } {
            Mock Write-TerminalExportFile { throw 'INTENTIONAL-CYCLE20-WRITER-FAILURE' }
            { Export-TerminalPresentation -Presentation $Deck -Path $Target -Format Markdown } |
                Should -Throw '*INTENTIONAL-CYCLE20-WRITER-FAILURE*'
        }

        Assert-Cycle20CreatedChainRemoved -ExistingRoot $existingRoot -TargetPath $target
    }

    It 'preserves canonical Markdown boundaries and semantic roundtrips for every newline form' {
        $cases = [ordered]@{ CR = "`r"; LF = "`n"; CRLF = "`r`n" }
        foreach ($case in $cases.GetEnumerator()) {
            $header = "Head$($case.Value)Tail"
            $cell = "one$($case.Value)two"
            $quote = "left$($case.Value)right"
            $rows = @([pscustomobject][ordered]@{ $header = $cell })
            $deck = New-TerminalPresentation -Title "Markdown $($case.Key)"
            $deck | Add-TerminalSlide -Title Slide -Layout Blank -Content {
                Add-SlideTable -Data $rows
                Add-SlideQuote -Text $quote -Attribution author
            } | Out-Null
            $path = Join-Path $TestDrive "logical-$($case.Key).md"

            Export-TerminalPresentation -Presentation $deck -Path $path -Format Markdown | Out-Null

            $document = [IO.File]::ReadAllText($path)
            $visible = [regex]::Replace(
                $document,
                '<!--\s*terminalslides:envelope\s+[A-Za-z0-9+/=]+\s*-->\s*\z',
                ''
            )
            $visible | Should -Match ([regex]::Escape('Head<br>Tail'))
            $visible | Should -Match ([regex]::Escape('one<br>two'))
            $visible | Should -Match ([regex]::Escape("> left`n> right"))
            $visible.Contains("`r") | Should -BeFalse

            $imported = Import-TerminalPresentation $path
            $table = $imported.Slides[0].Elements[0].Payload
            $imported.Slides[0].Elements[1].Payload.Text | Should -BeExactly $quote
            $table.Rows[0].Cells[0].Name | Should -BeExactly $header
            $table.Rows[0].Cells[0].Value.Value | Should -BeExactly $cell
        }
    }
}
