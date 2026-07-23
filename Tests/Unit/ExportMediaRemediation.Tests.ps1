Describe 'Export and media behavior' {
    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '..' '..' 'TerminalSlides.psd1') -Force
        $script:PresentationPhoto = Join-Path $PSScriptRoot '..' '..' 'Assets/presentation-team-photo.jpg'
    }

    It 'serializes every slide element meaningfully to Markdown and HTML' {
        $deck = New-TerminalPresentation -Title 'Rich <Deck>' -Author 'Presenter'
        $deck | Add-TerminalSlide -Title 'Everything & More' -Content {
            Add-SlideTitle 'Element title'
            Add-SlideSubtitle 'Element subtitle'
            Add-SlideText 'Plain <text>'
            Add-SlideBullet 'First bullet'
            Add-SlideCode -Code 'Write-Output "hello"' -Language powershell
            Add-SlideTable -Data @(
                [pscustomobject]@{ Name = 'Ada'; Role = 'Engineer' }
                [pscustomobject]@{ Name = 'Grace'; Role = 'Admiral' }
                [pscustomobject]@{ Name = 'Linus' }
            )
            Add-SlideChart -Title 'Adoption' -ChartType Bar -Data @(
                [pscustomobject]@{ Label = 'Terminal'; Value = 42 }
            )
            Add-SlideDiagram -Diagram @{
                Nodes = @(
                    [pscustomobject]@{ Id = 'cli'; Label = 'Terminal CLI' }
                    [pscustomobject]@{ Id = 'api'; Label = 'Service API' }
                )
                Edges = @([pscustomobject]@{ From = 'cli'; To = 'api'; Label = 'calls' })
            }
            Add-SlideImage -Path $script:PresentationPhoto -AltText 'Team presenting'
            Add-SlideQuote -Text 'Make it useful.' -Attribution 'Grace Hopper'
            Add-SlideBox -Text 'Key takeaway'
            Add-SlideNotes 'Speaker guidance'
        } | Out-Null

        $markdownPath = Join-Path $TestDrive 'rich.md'
        $htmlPath = Join-Path $TestDrive 'rich.html'
        Export-TerminalPresentation -Presentation $deck -Path $markdownPath -Format Markdown | Out-Null
        Export-TerminalPresentation -Presentation $deck -Path $htmlPath -Format Html | Out-Null
        $markdown = Get-Content -LiteralPath $markdownPath -Raw
        $html = Get-Content -LiteralPath $htmlPath -Raw

        foreach ($expected in 'Element title', 'Element subtitle', 'Plain <text>', 'First bullet', 'Write-Output', 'Ada', 'Engineer', 'Adoption', 'Terminal', '42', 'Terminal CLI', 'Service API', 'calls', 'Team presenting', 'Make it useful.', 'Grace Hopper', 'Key takeaway') {
            $markdown | Should -Match ([regex]::Escape($expected))
        }
        foreach ($expected in 'Element title', 'Element subtitle', 'Plain &lt;text&gt;', 'First bullet', 'Write-Output', 'Ada', 'Engineer', 'Adoption', 'Terminal', '42', 'Terminal CLI', 'Service API', 'calls', 'Team presenting', 'Make it useful.', 'Grace Hopper', 'Key takeaway') {
            $html | Should -Match ([regex]::Escape($expected))
        }
        $markdown | Should -Not -Match 'System\.(Collections|Object)'
        $html | Should -Not -Match 'System\.(Collections|Object)'
        $markdown | Should -Match '!\[Team presenting\]\(<rich\.md\.assets/[a-f0-9]{64}\.jpg>\)'
        (Get-ChildItem (Join-Path $TestDrive 'rich.md.assets') -Filter '*.jpg').Count | Should -Be 1
        $html | Should -Match '<img[^>]+alt="Team presenting"'
    }

    It 'requires Force to replace a file and honors WhatIf without partial files' {
        $deck = New-TerminalPresentation -Title 'Safe export'
        $deck | Add-TerminalSlide -Title 'Only slide' -Content { Add-SlideText 'replacement' } | Out-Null
        $path = Join-Path $TestDrive 'safe.txt'
        Set-Content -LiteralPath $path -Value 'original' -NoNewline

        { Export-TerminalPresentation -Presentation $deck -Path $path -Format PlainText } |
            Should -Throw '*Use -Force to overwrite it*'
        (Get-Content -LiteralPath $path -Raw) | Should -BeExactly 'original'

        $whatIfPath = Join-Path $TestDrive 'what-if' 'deck.txt'
        Export-TerminalPresentation -Presentation $deck -Path $whatIfPath -Format PlainText -WhatIf | Should -BeNullOrEmpty
        $whatIfPath | Should -Not -Exist

        Export-TerminalPresentation -Presentation $deck -Path $path -Format PlainText -Force | Out-Null
        (Get-Content -LiteralPath $path -Raw) | Should -Match 'replacement'
        @(Get-ChildItem -LiteralPath $TestDrive -Filter '.safe.txt.*.tmp').Count | Should -Be 0
    }

    It 'never claims a sibling asset directory when a portable export has no images' {
        $deck = New-TerminalPresentation -Title 'No media'
        $deck | Add-TerminalSlide -Title 'Text' -Content { Add-SlideText 'body' } | Out-Null
        $path = Join-Path $TestDrive 'no-media.html'
        $assetDirectory = $path + '.assets'
        New-Item -ItemType Directory -Path $assetDirectory | Out-Null
        $sentinel = Join-Path $assetDirectory 'keep.txt'
        [IO.File]::WriteAllText($sentinel, 'keep')

        Export-TerminalPresentation -Presentation $deck -Path $path -Format Html | Out-Null
        [IO.File]::ReadAllText($sentinel) | Should -BeExactly 'keep'

        [IO.File]::WriteAllText($path, 'old document')
        Export-TerminalPresentation -Presentation $deck -Path $path -Format Html -Force | Out-Null
        [IO.File]::ReadAllText($sentinel) | Should -BeExactly 'keep'
        @(Get-ChildItem -LiteralPath $TestDrive -Force | Where-Object Name -Like '.no-media.html.assets.*').Count |
            Should -Be 0

        $directoryTarget = Join-Path $TestDrive 'no-media-directory-collision'
        $directorySidecar = $directoryTarget + '.assets'
        New-Item -ItemType Directory -Path $directoryTarget, $directorySidecar | Out-Null
        $directorySentinel = Join-Path $directorySidecar 'keep.txt'
        [IO.File]::WriteAllText($directorySentinel, 'keep')

        { Export-TerminalPresentation -Presentation $deck -Path $directoryTarget -Format Html -Force } | Should -Throw
        [IO.File]::ReadAllText($directorySentinel) | Should -BeExactly 'keep'
    }

    It 'requires Force before replacing a sibling asset directory for an image export' {
        $deck = New-TerminalPresentation -Title 'Media collision'
        $deck | Add-TerminalSlide -Title 'Photo' -Content {
            Add-SlideImage -Path $script:PresentationPhoto -AltText 'Presentation team'
        } | Out-Null
        $path = Join-Path $TestDrive 'media-collision.html'
        $assetDirectory = $path + '.assets'
        New-Item -ItemType Directory -Path $assetDirectory | Out-Null
        $sentinel = Join-Path $assetDirectory 'keep.txt'
        [IO.File]::WriteAllText($sentinel, 'keep')

        Export-TerminalPresentation -Presentation $deck -Path $path -Format Html -WhatIf | Should -BeNullOrEmpty
        $path | Should -Not -Exist
        [IO.File]::ReadAllText($sentinel) | Should -BeExactly 'keep'

        { Export-TerminalPresentation -Presentation $deck -Path $path -Format Html } |
            Should -Throw '*Asset path*already exists*Use -Force*'
        $path | Should -Not -Exist
        [IO.File]::ReadAllText($sentinel) | Should -BeExactly 'keep'

        Export-TerminalPresentation -Presentation $deck -Path $path -Format Html -Force | Out-Null
        $sentinel | Should -Not -Exist
        @(Get-ChildItem -LiteralPath $assetDirectory -File -Filter '*.jpg').Count | Should -Be 1

        [IO.File]::WriteAllText($sentinel, 'second sentinel')
        { Export-TerminalPresentation -Presentation $deck -Path $path -Format Html } |
            Should -Throw '*Use -Force to overwrite it*'
        [IO.File]::ReadAllText($sentinel) | Should -BeExactly 'second sentinel'

        Export-TerminalPresentation -Presentation $deck -Path $path -Format Html -Force | Out-Null
        $sentinel | Should -Not -Exist
        @(Get-ChildItem -LiteralPath $TestDrive -Force | Where-Object Name -Like 'media-collision.html.assets.*.backup').Count |
            Should -Be 0
    }

    It 'enforces sidecar authorization again at commit when paths appear after preflight' {
        $deck = New-TerminalPresentation -Title 'Media race'
        $deck | Add-TerminalSlide -Title 'Photo' -Content {
            Add-SlideImage -Path $script:PresentationPhoto -AltText 'Presentation team'
        } | Out-Null

        InModuleScope TerminalSlides -Parameters @{ Deck = $deck; Root = $TestDrive } {
            $unforcedTarget = Join-Path $Root 'unforced-race.html'
            $unforced = New-TerminalPortableExport `
                -Presentation (New-TerminalPresentationView $Deck) `
                -TargetPath $unforcedTarget `
                -Overwrite $false
            $unforcedSidecar = $unforcedTarget + '.assets'
            [void][IO.Directory]::CreateDirectory($unforcedSidecar)
            $unforcedSentinel = Join-Path $unforcedSidecar 'external.txt'
            [IO.File]::WriteAllText($unforcedSentinel, 'external')

            {
                Write-TerminalExportFile -Path $unforcedTarget -Content 'document' -Overwrite $false `
                    -MediaTransaction $unforced.Transaction
            } | Should -Throw '*Asset path*already exists*Use -Force*'
            $unforcedTarget | Should -Not -Exist
            [IO.File]::ReadAllText($unforcedSentinel) | Should -BeExactly 'external'
            $unforced.Transaction.StagingDirectory | Should -Not -Exist

            $forcedTarget = Join-Path $Root 'forced-race.html'
            $forced = New-TerminalPortableExport `
                -Presentation (New-TerminalPresentationView $Deck) `
                -TargetPath $forcedTarget `
                -Overwrite $true
            $forcedSidecar = $forcedTarget + '.assets'
            [void][IO.Directory]::CreateDirectory($forcedSidecar)
            $forcedSentinel = Join-Path $forcedSidecar 'external.txt'
            [IO.File]::WriteAllText($forcedSentinel, 'external')

            Write-TerminalExportFile -Path $forcedTarget -Content 'document' -Overwrite $true `
                -MediaTransaction $forced.Transaction
            [IO.File]::ReadAllText($forcedTarget) | Should -BeExactly 'document'
            $forcedSentinel | Should -Not -Exist
            @(Get-ChildItem -LiteralPath $forcedSidecar -File).Count | Should -Be 1

            $targetRace = Join-Path $Root 'target-race.html'
            $targetTransaction = New-TerminalPortableExport `
                -Presentation (New-TerminalPresentationView $Deck) `
                -TargetPath $targetRace `
                -Overwrite $false
            [IO.File]::WriteAllText($targetRace, 'external document')

            {
                Write-TerminalExportFile -Path $targetRace -Content 'replacement' -Overwrite $false `
                    -MediaTransaction $targetTransaction.Transaction
            } | Should -Throw
            [IO.File]::ReadAllText($targetRace) | Should -BeExactly 'external document'
            ($targetRace + '.assets') | Should -Not -Exist
            $targetTransaction.Transaction.StagingDirectory | Should -Not -Exist
        }
    }

    It 'preserves an authorized existing sidecar when image export serialization fails' {
        $deck = New-TerminalPresentation -Title 'Invalid media export'
        $deck | Add-TerminalSlide -Title 'Photo' -Content {
            Add-SlideImage -Path $script:PresentationPhoto -AltText 'Presentation team'
            Add-SlideText ([string][char]0xD800)
        } | Out-Null
        $path = Join-Path $TestDrive 'media-rollback.html'
        $assetDirectory = $path + '.assets'
        New-Item -ItemType Directory -Path $assetDirectory | Out-Null
        $sentinel = Join-Path $assetDirectory 'keep.txt'
        [IO.File]::WriteAllText($path, 'old document')
        [IO.File]::WriteAllText($sentinel, 'keep')

        { Export-TerminalPresentation -Presentation $deck -Path $path -Format Html -Force } |
            Should -Throw '*valid UTF-16*'

        [IO.File]::ReadAllText($path) | Should -BeExactly 'old document'
        [IO.File]::ReadAllText($sentinel) | Should -BeExactly 'keep'
        @(Get-ChildItem -LiteralPath $TestDrive -Force | Where-Object Name -Like '.media-rollback.html.assets.*').Count |
            Should -Be 0
    }

    It 'preserves logical rows and HTML encoding through the exported CSS contract' {
        $deck = New-TerminalPresentation -Title 'HTML rows'
        $deck | Add-TerminalSlide -Title 'Rows' -Content {
            Add-SlideText "one<&`rtwo"
            Add-SlideQuote -Text "three`nfour" -Attribution "Ada<&`rGrace`nLinus`r`nEnd"
            Add-SlideTable @([ordered]@{ Value = "five`r`nsix" })
        } | Out-Null
        $path = Join-Path $TestDrive 'logical-rows.html'
        $markdownPath = Join-Path $TestDrive 'logical-rows.md'

        Export-TerminalPresentation -Presentation $deck -Path $path -Format Html | Out-Null
        Export-TerminalPresentation -Presentation $deck -Path $markdownPath -Format Markdown | Out-Null
        $html = [IO.File]::ReadAllText($path)
        $markdown = [IO.File]::ReadAllText($markdownPath)
        $visibleMarkdown = $markdown.Substring(0, $markdown.IndexOf('<!-- terminalslides:envelope'))

        $html | Should -Match 'white-space: pre-wrap'
        $html | Should -Match '\.slide footer'
        $html.Contains("one&lt;&amp;`rtwo") | Should -BeTrue
        $html.Contains("three`nfour") | Should -BeTrue
        $html.Contains("&mdash; Ada&lt;&amp;`rGrace`nLinus`r`nEnd") | Should -BeTrue
        $html.Contains("five`r`nsix") | Should -BeTrue
        $html | Should -Not -Match 'one<&'
        $html | Should -Not -Match 'Ada<&'
        $visibleMarkdown.Contains("> — Ada<&`n> Grace`n> Linus`n> End") | Should -BeTrue
    }

    It 'renders isolated same-name imported themes into HTML CSS' {
        New-TerminalPresentationTheme -Name 'SharedHtmlTheme' -Background '#101112' -Foreground '#F1F2F3' -Primary '#A1A2A3' | Out-Null
        $first = New-TerminalPresentation -Title 'First theme' -Theme 'SharedHtmlTheme'
        $first | Add-TerminalSlide -Title 'First' -Content { Add-SlideText 'first' } | Out-Null
        $firstJson = Join-Path $TestDrive 'first-theme.json'
        Export-TerminalPresentation $first $firstJson -Format Json | Out-Null

        New-TerminalPresentationTheme -Name 'SharedHtmlTheme' -Background '#202122' -Foreground '#E1E2E3' -Primary '#B1B2B3' | Out-Null
        $second = New-TerminalPresentation -Title 'Second theme' -Theme 'SharedHtmlTheme'
        $second | Add-TerminalSlide -Title 'Second' -Content { Add-SlideText 'second' } | Out-Null
        $secondJson = Join-Path $TestDrive 'second-theme.json'
        Export-TerminalPresentation $second $secondJson -Format Json | Out-Null

        $firstImported = Import-TerminalPresentation $firstJson
        $secondImported = Import-TerminalPresentation $secondJson
        $firstHtml = Join-Path $TestDrive 'first-theme.html'
        $secondHtml = Join-Path $TestDrive 'second-theme.html'
        Export-TerminalPresentation $firstImported $firstHtml -Format Html | Out-Null
        Export-TerminalPresentation $secondImported $secondHtml -Format Html | Out-Null

        [IO.File]::ReadAllText($firstHtml) | Should -Match '--ts-background: #101112;.*--ts-primary: #A1A2A3;'
        [IO.File]::ReadAllText($secondHtml) | Should -Match '--ts-background: #202122;.*--ts-primary: #B1B2B3;'
        (Get-TerminalPresentationTheme -Name 'SharedHtmlTheme').Primary | Should -BeExactly '#B1B2B3'
    }

    It 'rejects invalid UTF-16 at the shared export sink before HTML can replace text' {
        $deck = New-TerminalPresentation -Title 'Invalid HTML'
        $deck | Add-TerminalSlide -Title 'Slide' -Content {
            Add-SlideText ([string][char]0xD800)
        } | Out-Null
        $path = Join-Path $TestDrive 'invalid.html'

        { Export-TerminalPresentation -Presentation $deck -Path $path -Format Html } |
            Should -Throw '*valid UTF-16*'
        $path | Should -Not -Exist
        @(Get-ChildItem -LiteralPath $TestDrive -Filter '.invalid.html.*.tmp').Count | Should -Be 0

        [IO.File]::WriteAllText($path, 'original')
        { Export-TerminalPresentation -Presentation $deck -Path $path -Format Html -Force } |
            Should -Throw '*valid UTF-16*'
        [IO.File]::ReadAllText($path) | Should -BeExactly 'original'

        $directDirectory = Join-Path $TestDrive 'invalid-sink'
        $directPath = Join-Path $directDirectory 'deck.txt'
        InModuleScope TerminalSlides -Parameters @{ Path = $directPath } {
            { Write-TerminalExportFile -Path $Path -Content ([string][char]0xD800) -Overwrite $false } |
                Should -Throw '*valid UTF-16*'
        }
        $directDirectory | Should -Not -Exist
    }

    It 'rolls back only a portable export parent created by the failed operation' {
        $deck = New-TerminalPresentation -Title 'Invalid portable export'
        $deck | Add-TerminalSlide -Title 'Slide' -Content {
            Add-SlideText ([string][char]0xD800)
        } | Out-Null

        $newParent = Join-Path $TestDrive 'new-portable-parent'
        { Export-TerminalPresentation -Presentation $deck -Path (Join-Path $newParent 'deck.html') -Format Html } |
            Should -Throw '*valid UTF-16*'
        $newParent | Should -Not -Exist

        $existingParent = Join-Path $TestDrive 'existing-portable-parent'
        New-Item -Path $existingParent -ItemType Directory | Out-Null
        $sentinel = Join-Path $existingParent 'keep.txt'
        [IO.File]::WriteAllText($sentinel, 'keep')

        { Export-TerminalPresentation -Presentation $deck -Path (Join-Path $existingParent 'deck.html') -Format Html } |
            Should -Throw '*valid UTF-16*'
        $existingParent | Should -Exist
        [IO.File]::ReadAllText($sentinel) | Should -BeExactly 'keep'
    }

    It 'assigns new IDs to every element in a copied slide' {
        $deck = New-TerminalPresentation -Title 'Copy IDs'
        $deck | Add-TerminalSlide -Title 'Source' -Content {
            Add-SlideTitle 'Heading'
            Add-SlideText 'Body'
            Add-SlideBullet 'Point'
        } | Out-Null
        $sourceIds = @($deck.Slides[0].Elements.Id)

        Copy-TerminalSlide -Presentation $deck -Index 1 | Out-Null
        $copyIds = @($deck.Slides[1].Elements.Id)

        $copyIds.Count | Should -Be $sourceIds.Count
        @($copyIds | Select-Object -Unique).Count | Should -Be $copyIds.Count
        @($copyIds | Where-Object { $_ -in $sourceIds }).Count | Should -Be 0
    }

    It 'preserves a relative image path and renders it from its authored base directory' {
        $imagePath = Join-Path $TestDrive 'pixel.png'
        $pixel = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='
        [System.IO.File]::WriteAllBytes($imagePath, [Convert]::FromBase64String($pixel))
        Push-Location $TestDrive
        try {
            $deck = New-TerminalPresentation -Title 'Portable image' -Width 60 -Height 20
            $deck | Add-TerminalSlide -Title 'Photo' -Layout ImageFocus -Content {
                Add-SlideImage -Path 'pixel.png' -AltText 'One pixel' -Region Image
            } | Out-Null
        }
        finally { Pop-Location }

        $image = $deck.Slides[0].Elements | Where-Object Kind -eq Image | Select-Object -First 1
        $image.Payload.Path | Should -BeExactly 'pixel.png'
        InModuleScope TerminalSlides -Parameters @{ Element = $image; Expected = $TestDrive } {
            Get-TerminalMediaOrigin $Element | Should -BeExactly $Expected
        }
        $path = Join-Path $TestDrive 'portable.txt'
        Export-TerminalPresentation -Presentation $deck -Path $path -Format PlainText | Out-Null
        (Get-Content -LiteralPath $path -Raw) | Should -Not -Match 'Image: pixel\.png'
    }

    It 'warns on image decode failure and keeps the accessible fallback' {
        $imagePath = Join-Path $TestDrive 'broken.png'
        Set-Content -LiteralPath $imagePath -Value 'not an image'
        $deck = New-TerminalPresentation -Title 'Broken image' -Width 60 -Height 20
        $deck | Add-TerminalSlide -Title 'Photo' -Layout ImageFocus -Content {
            Add-SlideImage -Path $imagePath -AltText 'Broken but described' -Region Image
        } | Out-Null
        $path = Join-Path $TestDrive 'broken.txt'
        $warnings = @()

        Export-TerminalPresentation -Presentation $deck -Path $path -Format PlainText -WarningVariable warnings | Out-Null

        $warnings.Message -join "`n" | Should -Match 'could not be decoded'
        $output = Get-Content -LiteralPath $path -Raw
        $output | Should -Match 'Image:'
        $output | Should -Match 'Broken but described'
    }

    It 'resolves imported relative images from the presentation file directory' {
        $imageDirectory = Join-Path $TestDrive 'images'
        New-Item -Path $imageDirectory -ItemType Directory | Out-Null
        $imagePath = Join-Path $imageDirectory 'pixel.png'
        $pixel = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='
        [System.IO.File]::WriteAllBytes($imagePath, [Convert]::FromBase64String($pixel))
        $sourcePath = Join-Path $TestDrive 'imported.json'
        @{
            Title = 'Imported image'
            Slides = @(@{
                Title = 'Photo'
                Layout = 'ImageFocus'
                Elements = @(@{
                    Type = 'Image'
                    Content = @{ Path = 'images/pixel.png'; BasePath = '/stale/location'; AltText = 'Imported pixel' }
                    Region = 'Image'
                })
            })
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $sourcePath

        $deck = Import-TerminalPresentation -Path $sourcePath

        $deck.Slides[0].Elements[0].Payload.Path | Should -BeExactly 'images/pixel.png'
        InModuleScope TerminalSlides -Parameters @{ Element = $deck.Slides[0].Elements[0]; Expected = $TestDrive } {
            Get-TerminalMediaOrigin $Element | Should -BeExactly $Expected
        }
        $outputPath = Join-Path $TestDrive 'imported.txt'
        Export-TerminalPresentation -Presentation $deck -Path $outputPath -Format PlainText | Out-Null
        (Get-Content -LiteralPath $outputPath -Raw) | Should -Not -Match 'Image: images/pixel\.png'
    }

    It 'handles omitted optional rich-element data without leaking type names' {
        $sourcePath = Join-Path $TestDrive 'optional-elements.json'
        @{
            Title = 'Optional data'
            Slides = @(@{
                Title = 'Elements'
                Elements = @(
                    @{ Type = 'Code'; Content = @{ Code = 'plain code' }; Properties = @{} }
                    @{ Type = 'Table'; Content = $null }
                    @{ Type = 'Chart'; Content = @(@{ Label = 'Only'; Value = 1 }); Properties = @{ ChartType = 'Gauge' } }
                    @{ Type = 'Chart'; Content = @(@{ Label = 'No metadata'; Value = 2 }); Properties = $null }
                    @{ Type = 'Diagram'; Content = @{ Nodes = @(@{ Id = 'a'; Label = 'A' }); Edges = @(@{ From = 'a'; To = 'a' }) } }
                    @{ Type = 'Quote'; Content = @{ Text = 'Anonymous' } }
                )
            })
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $sourcePath
        $deck = Import-TerminalPresentation -Path $sourcePath
        $markdownPath = Join-Path $TestDrive 'optional.md'
        $htmlPath = Join-Path $TestDrive 'optional.html'

        Export-TerminalPresentation -Presentation $deck -Path $markdownPath -Format Markdown | Out-Null
        Export-TerminalPresentation -Presentation $deck -Path $htmlPath -Format Html | Out-Null
        $markdown = Get-Content -LiteralPath $markdownPath -Raw
        $html = Get-Content -LiteralPath $htmlPath -Raw

        $markdown | Should -Match '_No data_'
        $html | Should -Match '<em>No data</em>'
        $markdown | Should -Match '```text'
        $markdown | Should -Match 'a -> a'
        $markdown | Should -Match 'Anonymous'
    }

    It 'creates destination directories and removes temporary files after a failed atomic move' {
        $deck = New-TerminalPresentation -Title 'Atomic'
        $deck | Add-TerminalSlide -Title 'Slide' -Content { Add-SlideText 'Body' } | Out-Null
        $nestedPath = Join-Path $TestDrive 'nested' 'deck.txt'
        Export-TerminalPresentation -Presentation $deck -Path $nestedPath -Format PlainText | Out-Null
        $nestedPath | Should -Exist

        $directoryCollision = Join-Path $TestDrive 'destination-is-a-directory'
        New-Item -Path $directoryCollision -ItemType Directory | Out-Null
        { Export-TerminalPresentation -Presentation $deck -Path $directoryCollision -Format PlainText } | Should -Throw
        @(Get-ChildItem -LiteralPath $TestDrive -Filter '.destination-is-a-directory.*.tmp').Count | Should -Be 0
    }

    It 'rejects missing portable media and removes its staging directory' {
        $missingPath = Join-Path $TestDrive 'missing-photo.png'
        $deck = New-TerminalPresentation -Title 'Missing media'
        $deck | Add-TerminalSlide -Title 'Photo' -Content {
            Add-SlideImage -Path $missingPath -AltText 'Missing photo'
        } | Out-Null
        $targetDirectory = Join-Path $TestDrive 'missing-export-parent'
        $targetPath = Join-Path $targetDirectory 'missing.md'

        { Export-TerminalPresentation -Presentation $deck -Path $targetPath -Format Markdown } |
            Should -Throw "*Image '$missingPath' was not found*"

        $targetPath | Should -Not -Exist
        $targetDirectory | Should -Not -Exist
    }

    It 'requires image elements and a captured origin for relative media paths' {
        InModuleScope TerminalSlides -Parameters @{ Root = $TestDrive } {
            $textElement = [TerminalSlides.Schema.V1.SlideElement]::new(
                [TerminalSlides.Schema.V1.ElementKind]::Text,
                [TerminalSlides.Schema.V1.TextPayload]::new('not media')
            )
            { Resolve-TerminalImagePath -Element $textElement } |
                Should -Throw '*Only image elements have media paths*'

            $imageElement = [TerminalSlides.Schema.V1.SlideElement]::new(
                [TerminalSlides.Schema.V1.ElementKind]::Image,
                [TerminalSlides.Schema.V1.ImagePayload]::new('relative.png', 'Relative image')
            )
            { Resolve-TerminalImagePath -Element $imageElement } |
                Should -Throw "*Relative image 'relative.png' has no source origin*"

            Set-TerminalMediaOrigin -Element $imageElement -Directory $Root
            Resolve-TerminalImagePath -Element $imageElement |
                Should -BeExactly ([IO.Path]::GetFullPath((Join-Path $Root 'relative.png')))
        }
    }

    It 'restores prior media when a sidecar swap fails' {
        $targetPath = Join-Path $TestDrive 'swap.json'
        $stagingPath = Join-Path $TestDrive '.swap.json.assets.staging.tmp'
        $finalPath = Join-Path $TestDrive 'swap.json.assets'
        New-Item -Path $stagingPath, $finalPath -ItemType Directory | Out-Null
        Set-Content -LiteralPath (Join-Path $stagingPath 'new.txt') -Value 'new'
        Set-Content -LiteralPath (Join-Path $finalPath 'old.txt') -Value 'old'
        $transaction = [pscustomobject]@{
            StagingDirectory = $stagingPath
            FinalDirectory = $finalPath
            HasAssets = $true
            ReplaceExistingAssets = $true
        }

        InModuleScope TerminalSlides -Parameters @{ Target = $targetPath; Transaction = $transaction } {
            Mock Move-TerminalDirectoryAtomically {
                param($Source, $Destination)
                [void][IO.Directory]::CreateDirectory($Destination)
                [IO.File]::WriteAllText((Join-Path $Destination 'partial.txt'), $Source)
                throw 'INTENTIONAL-MEDIA-SWAP-FAILURE'
            }

            { Write-TerminalExportFile -Path $Target -Content 'replacement' -Overwrite $false -MediaTransaction $Transaction } |
                Should -Throw '*INTENTIONAL-MEDIA-SWAP-FAILURE*'
        }

        Join-Path $finalPath 'old.txt' | Should -Exist
        Join-Path $finalPath 'new.txt' | Should -Not -Exist
        $stagingPath | Should -Not -Exist
        $targetPath | Should -Not -Exist
        @(Get-ChildItem -LiteralPath $TestDrive -Force | Where-Object Name -Like 'swap.json.assets.*.backup').Count |
            Should -Be 0
    }

    It 'restores a media backup from the finalizer when primary restoration fails' {
        $targetPath = Join-Path $TestDrive 'finalizer.json'
        $finalPath = Join-Path $TestDrive 'finalizer.json.assets'
        $stagingPath = Join-Path $TestDrive '.finalizer.json.assets.staging.tmp'
        New-Item -Path $stagingPath, $finalPath -ItemType Directory | Out-Null
        [IO.File]::WriteAllText($targetPath, 'external document')
        [IO.File]::WriteAllText((Join-Path $stagingPath 'new.txt'), 'new')
        Set-Content -LiteralPath (Join-Path $finalPath 'old.txt') -Value 'old'
        $transaction = [pscustomobject]@{
            StagingDirectory = $stagingPath
            FinalDirectory = $finalPath
            HasAssets = $true
            ReplaceExistingAssets = $true
        }

        InModuleScope TerminalSlides -Parameters @{ Target = $targetPath; Transaction = $transaction } {
            Mock Move-Item {
                throw 'INTENTIONAL-FIRST-RESTORE-FAILURE'
            } -ParameterFilter {
                $LiteralPath -like '*.backup' -and
                    $ErrorAction -ne [System.Management.Automation.ActionPreference]::SilentlyContinue
            }

            { Write-TerminalExportFile -Path $Target -Content 'replacement' -Overwrite $false -MediaTransaction $Transaction } |
                Should -Throw '*INTENTIONAL-FIRST-RESTORE-FAILURE*'
        }

        Join-Path $finalPath 'old.txt' | Should -Exist
        Join-Path $finalPath 'new.txt' | Should -Not -Exist
        [IO.File]::ReadAllText($targetPath) | Should -BeExactly 'external document'
        $stagingPath | Should -Not -Exist
        @(Get-ChildItem -LiteralPath $TestDrive -Force | Where-Object Name -Like 'finalizer.json.assets.*.backup').Count |
            Should -Be 0
    }

    It 'removes portable media staging when document serialization cannot commit' {
        $imagePath = Join-Path $TestDrive 'outer-cleanup.png'
        $pixel = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='
        [System.IO.File]::WriteAllBytes($imagePath, [Convert]::FromBase64String($pixel))
        $deck = New-TerminalPresentation -Title 'Outer cleanup'
        $deck | Add-TerminalSlide -Title 'Photo' -Content {
            Add-SlideImage -Path $imagePath -AltText 'Photo'
        } | Out-Null
        $targetDirectory = Join-Path $TestDrive 'outer-cleanup-parent'
        $targetPath = Join-Path $targetDirectory 'outer-cleanup.md'

        InModuleScope TerminalSlides -Parameters @{ Deck = $deck; Target = $targetPath } {
            Mock Write-TerminalExportFile { throw 'INTENTIONAL-DOCUMENT-WRITE-FAILURE' }

            { Export-TerminalPresentation -Presentation $Deck -Path $Target -Format Markdown } |
                Should -Throw '*INTENTIONAL-DOCUMENT-WRITE-FAILURE*'
        }

        $targetPath | Should -Not -Exist
        $targetDirectory | Should -Not -Exist
    }

    It 'resolves an authored relative image from the current directory' {
        $imagePath = Join-Path $TestDrive 'current.png'
        $pixel = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='
        [System.IO.File]::WriteAllBytes($imagePath, [Convert]::FromBase64String($pixel))
        Push-Location $TestDrive
        try {
            $deck = New-TerminalPresentation -Title 'Current image' -Width 60 -Height 20
            $deck | Add-TerminalSlide -Title 'Photo' -Layout ImageFocus -Content {
                Add-SlideImage -Path 'current.png' -AltText 'Current pixel' -Region Image
            } | Out-Null
            Export-TerminalPresentation -Presentation $deck -Path (Join-Path $TestDrive 'current.txt') -Format PlainText | Out-Null
        }
        finally { Pop-Location }

        (Get-Content -LiteralPath (Join-Path $TestDrive 'current.txt') -Raw) | Should -Not -Match 'Image: current\.png'
    }

    It 'crops Spectre renderables to the requested image height' {
        InModuleScope TerminalSlides {
            $renderable = [Spectre.Console.Markup]::new("one`ntwo`nthree")
            $lines = ConvertTo-SpectreRenderableLines -Renderable $renderable -Width 20 -Height 1
            $lines.Count | Should -Be 1
            $lines[0] | Should -Match 'one'
        }
    }

    It 'imports direct PSD1 data and separates Markdown slides' {
        $psd1Path = Join-Path $TestDrive 'direct.psd1'
        "@{ Title = 'Direct data'; Slides = @() }" | Set-Content -LiteralPath $psd1Path
        Push-Location $TestDrive
        try { $directDeck = Import-TerminalPresentation -Path './direct.psd1' }
        finally { Pop-Location }
        $directDeck.Title | Should -BeExactly 'Direct data'

        $markdownPath = Join-Path $TestDrive 'separated.md'
        @'
first slide without a heading
---
# Two
## Heading
### Subheading
> Quoted
<!-- Notes: remember this -->
```
plain code
```
'@ | Set-Content -LiteralPath $markdownPath
        $deck = Import-TerminalPresentation -Path $markdownPath
        @($deck.Slides.Title) | Should -Be @('Slide', 'Two')
        $deck.Slides[1].Notes | Should -BeExactly 'remember this'
        ($deck.Slides[1].Elements | Where-Object Kind -eq Code).Payload.Language | Should -BeExactly 'text'

        $unsupportedPath = Join-Path $TestDrive 'unsupported.txt'
        Set-Content -LiteralPath $unsupportedPath -Value 'content'
        { Import-TerminalPresentation -Path $unsupportedPath } | Should -Throw '*Unsupported presentation format*'
    }
}
