Describe 'Canonical export, import, and media model' {
    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '..' '..' 'TerminalSlides.psd1') -Force
        $script:Pixel = [Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=')
    }

    It 'roundtrips every rich element through the canonical Markdown dialect' {
        $imagePath = Join-Path $TestDrive 'photo.png'
        [IO.File]::WriteAllBytes($imagePath, $script:Pixel)
        $deck = New-TerminalPresentation -Title 'Quoted: "deck"' -Author 'Ada' -Theme Midnight -Width 80 -Height 24
        $deck | Add-TerminalSlide -Title 'Rich' -Content {
            Add-SlideTitle 'Heading'
            Add-SlideSubtitle 'Subheading'
            Add-SlideText 'Body'
            Add-SlideBullet 'Point'
            Add-SlideCode -Language powershell -Code 'Get-Process'
            Add-SlideTable -Data @([ordered]@{ Name = 'Ada'; Score = 10 })
            Add-SlideChart -Title 'Trend' -ChartType Line -Data @([pscustomobject]@{ Label = 'A'; Value = 2 })
            Add-SlideDiagram -Diagram @{ Nodes = @([pscustomobject]@{ Id = 'a'; Label = 'A' }); Edges = @([pscustomobject]@{ From = 'a'; To = 'a'; Label = 'loop' }) }
            Add-SlideImage -Path $imagePath -AltText 'Photo'
            Add-SlideQuote -Text 'Quote' -Attribution 'Grace'
            Add-SlideBox -Text 'Key point'
            Add-SlideNotes 'Speaker note'
        } | Out-Null
        $path = Join-Path $TestDrive 'rich.md'

        Export-TerminalPresentation -Presentation $deck -Path $path -Format Markdown | Out-Null
        $roundtrip = Import-TerminalPresentation -Path $path

        $roundtrip.Title | Should -BeExactly $deck.Title
        $roundtrip.Author | Should -BeExactly $deck.Author
        $roundtrip.Slides[0].Notes | Should -BeExactly 'Speaker note'
        @($roundtrip.Slides[0].Elements | ForEach-Object { $_.Kind.ToString() }) | Should -Be @('Title','Subtitle','Text','Bullet','Code','Table','Chart','Diagram','Image','Quote','Box')
        $roundtrip.Slides[0].Elements[4].Payload.Code | Should -BeExactly 'Get-Process'
        $roundtrip.Slides[0].Elements[6].Payload.ChartKind | Should -Be ([TerminalSlides.Schema.V1.ChartKind]::Line)
        $roundtrip.Slides[0].Elements[7].Payload.Edges[0].Label | Should -BeExactly 'loop'
        $roundtrip.Slides[0].Elements[8].Payload.AltText | Should -BeExactly 'Photo'
        $roundtrip.Slides[0].Elements[9].Payload.Attribution | Should -BeExactly 'Grace'
    }

    It 'excludes hidden slides from every export format and reindexes visible progress' {
        $deck = New-TerminalPresentation -Title 'Visibility' -Width 60 -Height 16
        $deck | Add-TerminalSlide -Title 'First' -Content { Add-SlideText 'PUBLIC-FIRST' } | Out-Null
        $deck | Add-TerminalSlide -Title 'Secret' -Hidden -Content { Add-SlideText 'TOP-SECRET' } | Out-Null
        $deck | Add-TerminalSlide -Title 'Last' -Content { Add-SlideText 'PUBLIC-LAST' } | Out-Null

        foreach ($format in 'Ansi','PlainText','Markdown','Html','Psd1','Json') {
            $path = Join-Path $TestDrive ("visibility.$($format.ToLowerInvariant())")
            Export-TerminalPresentation -Presentation $deck -Path $path -Format $format | Out-Null
            (Get-Content -LiteralPath $path -Raw) | Should -Not -Match 'TOP-SECRET'
            if ($format -in 'Psd1','Json') {
                $imported = Import-TerminalPresentation -Path $path
                $imported.Slides.Count | Should -Be 2
                @($imported.Slides.Index) | Should -Be @(1, 2)
            }
        }
        $plain = Get-Content -LiteralPath (Join-Path $TestDrive 'visibility.plaintext') -Raw
        $plain | Should -Match 'Slide 1 of 2'
        $plain | Should -Match 'Slide 2 of 2'
        $plain | Should -Not -Match 'Slide 3 of 3'
    }

    It 'deep-copies slide data without JSON type coercion or shared containers' {
        $deck = New-TerminalPresentation -Title 'Typed copy'
        $deck | Add-TerminalSlide -Title 'Source' -Content { Add-SlideText 'Body' } | Out-Null
        $source = $deck.Slides[0]
        $source.Metadata.Custom.When = [datetime]'2024-02-03T04:05:06Z'
        $source.Metadata.Custom.Identifier = [guid]'62ae7708-a44f-4b87-af96-d7affc799073'
        $source.Metadata.Custom.Pattern = [regex]'body'
        $source.Metadata.Custom.Nested = [ordered]@{ Items = @('one', 'two') }

        Copy-TerminalSlide -Presentation $deck -Index 1 | Out-Null
        $copy = $deck.Slides[1]

        $copy.Metadata.Custom.When | Should -BeOfType datetime
        $copy.Metadata.Custom.Identifier | Should -BeOfType guid
        $copy.Metadata.Custom.Pattern | Should -BeOfType regex
        $copy.Metadata.Custom.Nested.Items[0] = 'changed'
        $source.Metadata.Custom.Nested.Items[0] | Should -BeExactly 'one'
        $deck.Slides[1].Elements[0].Id | Should -Not -BeExactly $deck.Slides[0].Elements[0].Id
    }

    It 'resolves relative media only from its captured source origin' {
        $source = Join-Path $TestDrive 'source'
        $collision = Join-Path $TestDrive 'collision'
        New-Item -ItemType Directory -Path $source, $collision | Out-Null
        [IO.File]::WriteAllBytes((Join-Path $source 'photo.png'), $script:Pixel)
        Set-Content -LiteralPath (Join-Path $collision 'photo.png') -Value 'not an image'
        Push-Location $source
        try {
            $deck = New-TerminalPresentation -Title 'Media' -Width 40 -Height 12
            $deck | Add-TerminalSlide -Title 'Image' -Content { Add-SlideImage -Path 'photo.png' -AltText 'Origin image' } | Out-Null
        }
        finally { Pop-Location }

        $element = $deck.Slides[0].Elements[0]
        $element.Payload.Path | Should -BeExactly 'photo.png'
        Push-Location $collision
        try {
            InModuleScope TerminalSlides -Parameters @{ Element = $element } {
                $lines = ConvertTo-TerminalImageLines -Path $Element.Payload.Path -SourceDirectory (Get-TerminalMediaOrigin $Element) -Width 20 -Height 5
                $lines | Should -Not -BeNullOrEmpty
            }
        }
        finally { Pop-Location }

        $jsonPath = Join-Path $TestDrive 'media.json'
        Export-TerminalPresentation -Presentation $deck -Path $jsonPath -Format Json | Out-Null
        $json = Get-Content -LiteralPath $jsonPath -Raw
        $json | Should -Not -Match ([regex]::Escape($source))
        $json | Should -Not -Match 'BasePath|SourceDirectory'
    }

    It 'ignores a persisted legacy BasePath and uses the importing document origin' {
        $path = Join-Path $TestDrive 'legacy.json'
        @{ Title = 'Legacy'; Slides = @(@{ Title = 'Image'; Elements = @(@{ Type = 'Image'; Content = @{ Path = 'photo.png'; AltText = 'Photo'; BasePath = '/wrong/machine' } }) }) } |
            ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path

        $deck = Import-TerminalPresentation -Path $path
        $image = $deck.Slides[0].Elements[0]

        $image.Payload.Path | Should -BeExactly 'photo.png'
        InModuleScope TerminalSlides -Parameters @{ Element = $image; Expected = $TestDrive } {
            Get-TerminalMediaOrigin $Element | Should -BeExactly $Expected
        }
    }

    It 'renders Spectre content through typed styled lines without a console transcript' {
        InModuleScope TerminalSlides {
            $renderable = [Spectre.Console.Markup]::new('[red bold]Alert[/]')
            $styled = ConvertTo-SpectreStyledLines -Renderable $renderable -Width 20
            $lines = ConvertTo-SpectreRenderableLines -Renderable $renderable -Width 20

            $styled.Count | Should -Be 1
            $styled[0].Runs[0].Text | Should -BeExactly 'Alert'
            $styled[0].Runs[0].Foreground | Should -BeExactly '#FF0000'
            $lines[0].GetText() | Should -BeExactly 'Alert'
        }
    }

    It 'encodes PSD1 payloads without executable here-string boundaries' {
        $deck = New-TerminalPresentation -Title 'Safe PSD1'
        $deck | Add-TerminalSlide -Title 'Content' -Content { Add-SlideText "before`n'@`nafter" } | Out-Null
        $path = Join-Path $TestDrive 'safe.psd1'

        Export-TerminalPresentation -Presentation $deck -Path $path -Format Psd1 | Out-Null
        $raw = Get-Content -LiteralPath $path -Raw
        $roundtrip = Import-TerminalPresentation -Path $path

        $raw | Should -Match '^@\{ TerminalSlidesEnvelope = ''[A-Za-z0-9+/=]+'' \}'
        $roundtrip.Slides[0].Elements[0].Payload.Text | Should -BeExactly "before`n'@`nafter"
    }

    It 'keeps backward compatibility with the preview JSON-in-PSD1 envelope' {
        $path = Join-Path $TestDrive 'legacy.psd1'
        "@{ Json = '{`"Title`":`"Legacy envelope`",`"Slides`":[]}' }" | Set-Content -LiteralPath $path

        (Import-TerminalPresentation -Path $path).Title | Should -BeExactly 'Legacy envelope'
    }

    It 'imports the legacy base64 PSD1 envelope key' {
        $deck = New-TerminalPresentation -Title 'Legacy marker'
        $deck | Add-TerminalSlide -Title 'One' -Content { Add-SlideText 'Preserved' } | Out-Null
        $currentPath = Join-Path $TestDrive 'current-envelope.psd1'
        $legacyPath = Join-Path $TestDrive 'legacy-envelope.psd1'
        Export-TerminalPresentation -Presentation $deck -Path $currentPath -Format Psd1 | Out-Null
        (Get-Content -LiteralPath $currentPath -Raw).Replace('TerminalSlidesEnvelope', 'TerminalSlidesData') |
            Set-Content -LiteralPath $legacyPath -NoNewline

        $imported = Import-TerminalPresentation -Path $legacyPath

        $imported.Title | Should -BeExactly 'Legacy marker'
        $imported.Slides[0].Elements[0].Payload.Text | Should -BeExactly 'Preserved'
    }

    It 'rejects unsupported canonical Markdown envelopes' {
        $path = Join-Path $TestDrive 'unsupported-envelope.md'
        $cases = @(
            [ordered]@{ MarkerVersion = 2; Presentation = [ordered]@{} }
            [ordered]@{ MarkerVersion = 1 }
        )

        foreach ($data in $cases) {
            $json = $data | ConvertTo-Json -Depth 10 -Compress
            $marker = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
            Set-Content -LiteralPath $path -Value "<!-- terminalslides:envelope $marker -->" -NoNewline

            { Import-TerminalPresentation -Path $path } |
                Should -Throw '*Markdown TerminalSlides envelope is unsupported*'
        }
    }

    It 'rejects legacy Markdown data markers without an integrity binding' {
        $path = Join-Path $TestDrive 'legacy-marker.md'
        Set-Content -LiteralPath $path -Value '<!-- terminalslides:data ZGVjaw== -->' -NoNewline

        { Import-TerminalPresentation -Path $path } |
            Should -Throw '*Legacy Markdown data markers have no integrity binding*'
    }

    It 'validates direct Spectre rendering inputs' {
        InModuleScope TerminalSlides {
            { ConvertTo-SpectreStyledLines -Renderable 'plain text' -Width 10 } | Should -Throw '*IRenderable*'
        }
    }
}
