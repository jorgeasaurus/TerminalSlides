BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '../../TerminalSlides.psd1'
    Import-Module $modulePath -Force

    function Write-Cycle23WireFile {
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
                    $visible = ''
                    $marker = [ordered]@{
                        MarkerVersion = 2
                        ProjectionHash = Get-TerminalMarkdownProjectionHash $visible $WireData
                        Presentation = $WireData
                    }
                    $visible + '<!-- terminalslides:envelope ' + (ConvertTo-TerminalDataMarker $marker) + ' -->'
                }
            }
        } $Data $Format
        [IO.File]::WriteAllText($Path, $content)
    }
}

Describe 'Cycle 20 single-pass persistence boundaries' {
    It 'roundtrips a self-contained custom theme after registry removal in every portable format' {
        InModuleScope TerminalSlides -Parameters @{ Root = $TestDrive } {
            New-TerminalPresentationTheme -Name PortableTheme -Background '#010203' -Foreground '#F0F1F2' `
                -Primary '#123456' -ChartPalette '#123456', '#654321' | Out-Null
            $deck = New-TerminalPresentation -Title Portable -Theme PortableTheme
            $deck | Add-TerminalSlide -Title One -Content { Add-SlideText 'themed' } | Out-Null
            foreach ($format in 'Json','Psd1','Markdown') {
                $path = Join-Path $Root "portable.$($format.ToLowerInvariant())"
                Export-TerminalPresentation $deck $path -Format $format | Out-Null
                [void]$script:Themes.Remove('PortableTheme')
                $roundtrip = Import-TerminalPresentation $path
                $roundtrip.Theme | Should -BeExactly PortableTheme
                (Resolve-TerminalPresentationTheme $roundtrip).Primary | Should -BeExactly '#123456'
                { Render-TerminalPresentationToString $roundtrip -PlainText } | Should -Not -Throw
            }
        }
    }

    It 'binds Markdown v2 to normalized visible and typed content without invoking the renderer on import' {
        $path = Join-Path $TestDrive projection.md
        $otherPath = Join-Path $TestDrive other.md
        $deck = New-TerminalPresentation -Title Bound
        $deck | Add-TerminalSlide -Title One -Content { Add-SlideText 'visible' } | Out-Null
        $other = New-TerminalPresentation -Title Other
        Export-TerminalPresentation $deck $path -Format Markdown | Out-Null
        Export-TerminalPresentation $other $otherPath -Format Markdown | Out-Null

        InModuleScope TerminalSlides -Parameters @{ Path = $path } {
            Mock ConvertTo-TerminalMarkdownDocument { throw 'renderer must not run during v2 import' }
            (Import-TerminalPresentation $Path).Title | Should -BeExactly Bound
            Should -Invoke ConvertTo-TerminalMarkdownDocument -Times 0
        }

        $first = [IO.File]::ReadAllText($path)
        $second = [IO.File]::ReadAllText($otherPath)
        $secondMarker = [regex]::Match($second, '<!--\s*terminalslides:envelope\s+.+?-->\s*\z').Value
        [IO.File]::WriteAllText($path, $first.Replace('visible', 'changed'))
        { Import-TerminalPresentation $path } | Should -Throw '*visible Markdown was edited*'
        $visible = [regex]::Replace($first, '<!--\s*terminalslides:envelope\s+.+?-->\s*\z', '')
        [IO.File]::WriteAllText($path, $visible + $secondMarker)
        { Import-TerminalPresentation $path } | Should -Throw '*visible Markdown was edited*'
    }

    It 'accepts both frozen v1 projection profiles while preserving later table columns' {
        $path = Join-Path $TestDrive legacy-v1.md
        InModuleScope TerminalSlides -Parameters @{ Path = $path } {
            $deck = New-TerminalPresentation -Title Legacy -Theme Midnight
            $rows = @([ordered]@{ Name = 'Ada' }, [ordered]@{ Name = 'Grace'; Role = 'Engineer' })
            $deck | Add-TerminalSlide -Title People -Content { Add-SlideTable -Data $rows } | Out-Null
            $wire = ConvertTo-PresentationData $deck
            $wire['$schema'] = $script:TerminalSlidesLegacyWireSchema
            $wire.SchemaVersion = $script:TerminalSlidesLegacyWireVersion
            $wire.Presentation.Theme = 'midnight'
            [void]$wire.Presentation.Remove('ThemeDefinition')
            $presentation = ConvertFrom-TerminalCurrentData $wire
            $visible = ConvertTo-TerminalMarkdownV1Document $presentation 'midnight'
            $marker = ConvertTo-TerminalDataMarker ([ordered]@{ MarkerVersion = 1; Presentation = $wire })
            [IO.File]::WriteAllText($Path, $visible + '<!-- terminalslides:envelope ' + $marker + ' -->')
            $roundtrip = Import-TerminalPresentation $Path
            $roundtrip.Theme | Should -BeExactly Midnight
            (ConvertFrom-TerminalDataRows $roundtrip.Slides[0].Elements[0].Payload.Rows)[1].Role |
                Should -BeExactly Engineer
            (Test-TerminalMarkdownV1Projection (ConvertTo-TerminalMarkdownDocument $presentation) $presentation Midnight) |
                Should -BeTrue
            [IO.File]::WriteAllText($Path, ([IO.File]::ReadAllText($Path)).Replace('Ada', 'Edited'))
            { Import-TerminalPresentation $Path } | Should -Throw '*visible Markdown was edited*'
        }
    }

    It 'rejects nonconstructable payloads, non-map roots, noncanonical scalars, and Int32 overflows' {
        InModuleScope TerminalSlides {
            $deck = New-TerminalPresentation -Title Boundary
            $deck | Add-TerminalSlide -Title One -Content { Add-SlideImage -Path image.png } | Out-Null
            $source = ConvertTo-PresentationData $deck
            $copy = { ConvertFrom-TerminalWireJson (ConvertTo-TerminalWireJson $source) }

            $negativeWidth = & $copy; $negativeWidth.Presentation.Width = -1
            { ConvertFrom-TerminalCurrentData $negativeWidth } | Should -Throw '*automatic*20x10*'
            $overflow = & $copy; $overflow.Presentation.Width = [int64]::MaxValue
            { ConvertFrom-TerminalCurrentData $overflow } | Should -Throw '*between -2147483648 and 2147483647*'
            $blankImage = & $copy; $blankImage.Presentation.Slides[0].Elements[0].Payload.Path = ' '
            { ConvertFrom-TerminalCurrentData $blankImage } | Should -Throw '*Image payload Path must be nonblank*'
            $arrayConfiguration = & $copy
            $arrayConfiguration.Presentation.Configuration = [ordered]@{ Type = 'ArrayList'; Items = @() }
            { ConvertFrom-TerminalCurrentData $arrayConfiguration } | Should -Throw '*Configuration must decode to a map*'
            $noncanonical = & $copy
            $noncanonical.Presentation.Metadata.Custom = [ordered]@{
                Type = 'Map'; Entries = @([ordered]@{ Name = 'Count'; Value = [ordered]@{ Type = 'Int32'; Value = '042' } })
            }
            { ConvertFrom-TerminalCurrentData $noncanonical } | Should -Throw '*canonical text*'
        }
    }

    It 'rejects case-confusable columns across separate rows before persistence' {
        $rows = @([ordered]@{ Name = 'Ada' }, [ordered]@{ name = 'Grace' })
        { New-TerminalPresentation -Title Table | Add-TerminalSlide -Title One -Content { Add-SlideTable -Data $rows } } |
            Should -Throw '*unique ignoring case*'
    }

    It 'covers the frozen v1 table and rich-element projection surface' {
        InModuleScope TerminalSlides {
            (ConvertTo-TerminalMarkdownV1Cell $null) | Should -BeExactly ''
            (ConvertTo-TerminalMarkdownV1Table -Data @()) | Should -Be @('_No data_')
            (ConvertTo-TerminalMarkdownV1Table -Data ([pscustomobject]@{})) | Should -Be @('_No data_')
            (ConvertTo-TerminalMarkdownV1Table -Data ([ordered]@{ Name = 'Ada' }))[0] | Should -Match 'Name'

            $deck = New-TerminalPresentation -Title V1 -Author Ada
            $deck | Add-TerminalSlide -Title Rich -Content {
                Add-SlideText text
                Add-SlideTitle title
                Add-SlideSubtitle subtitle
                Add-SlideBullet bullet
                Add-SlideCode -Code 'Get-Date' -Language powershell
                Add-SlideDiagram -Diagram @{
                    Nodes = @(@{ Id='A'; Label='Alpha' }, @{ Id='B'; Label='Beta' })
                    Edges = @(@{ From='A'; To='B'; Label='flows' }, @{ From='B'; To='A' })
                }
                Add-SlideImage -Path 'photo name.png' -AltText 'Photo ]'
                Add-SlideQuote -Text "first`nsecond" -Attribution Grace
                Add-SlideBox box
                Add-SlideChart -Data @(@{ Label = 'A'; Value = 1 }) -Title Totals
                Add-SlideNotes note
            } | Out-Null
            $document = ConvertTo-TerminalMarkdownV1Document $deck Midnight
            $document | Should -Match 'author:'
            $document | Should -Match '\*\*Totals\*\*'
            $document | Should -Match 'Diagram'
            $document | Should -Match 'photo%20name\.png'
            $document | Should -Match 'Notes: note'
        }
    }

    It 'covers empty and optional HTML projections without type leakage' {
        InModuleScope TerminalSlides {
            (ConvertTo-TerminalHtmlTable @()) | Should -Match 'No data'
            $chart = New-InternalSlideElement -Kind Chart -Payload (
                [TerminalSlides.Schema.V1.ChartPayload]::new(
                    [TerminalSlides.Schema.V1.ChartPoint[]]@(), [TerminalSlides.Schema.V1.ChartKind]::Bar, $null
                )
            )
            (ConvertTo-TerminalHtmlElement $chart) | Should -Not -Match 'figcaption'
            $diagram = New-InternalSlideElement -Kind Diagram -Payload (
                [TerminalSlides.Schema.V1.DiagramPayload]::new(
                    [TerminalSlides.Schema.V1.DiagramNode[]]@([TerminalSlides.Schema.V1.DiagramNode]::new('A','Alpha')),
                    [TerminalSlides.Schema.V1.DiagramEdge[]]@([TerminalSlides.Schema.V1.DiagramEdge]::new('A','A',$null))
                )
            )
            (ConvertTo-TerminalHtmlElement $diagram) | Should -Not -Match '\(\)'
            $quote = New-InternalSlideElement -Kind Quote -Payload ([TerminalSlides.Schema.V1.QuotePayload]::new('text',$null))
            (ConvertTo-TerminalHtmlElement $quote) | Should -Not -Match 'footer'
        }
    }

    It 'exercises every canonical scalar parser and rejected lexical form' {
        InModuleScope TerminalSlides {
            $values = [ordered]@{
                SByte = '-1'; Byte = '1'; Int16 = '-2'; UInt16 = '2'; Int32 = '-3'; UInt32 = '3'
                Int64 = '-4'; UInt64 = '4'; Single = '1.25'; Double = '2.5'; Decimal = '3.75'
                DateTime = '2024-01-02T03:04:05.0000000Z'
                DateTimeOffset = '2024-01-02T03:04:05.0000000+02:00'
                TimeSpan = '01:02:03'; Guid = '01234567-89ab-cdef-0123-456789abcdef'
                Uri = '../relative'; Version = '1.2.3.4'
            }
            foreach ($entry in $values.GetEnumerator()) {
                { Assert-TerminalCanonicalTaggedScalarText $entry.Key $entry.Value } | Should -Not -Throw
            }
            { Assert-TerminalCanonicalTaggedScalarText DateTime '2024-01-02T03:04:05Z' } | Should -Throw '*round-trip*'
            { Assert-TerminalCanonicalTaggedScalarText DateTime '2024-01-02T03:04:05.0000000-00:00' } |
                Should -Throw '*negative-zero*'
            foreach ($offset in '+00:00','+14:00','-14:00') {
                { Assert-TerminalCanonicalTaggedScalarText DateTime "2024-01-02T03:04:05.0000000$offset" } |
                    Should -Not -Throw
            }
            $negativeZero = '2024-01-02T03:04:05.0000000-00:00'
            { ConvertFrom-TerminalTaggedValue ([ordered]@{ Type='DateTime'; Value=$negativeZero }) -RequireCanonical } |
                Should -Throw '*negative-zero*'
            { Read-TerminalCurrentScalarValue ([ordered]@{ Name='When'; Kind='DateTime'; Value=$negativeZero }) -RequireCanonical } |
                Should -Throw '*negative-zero*'
            { Assert-TerminalCanonicalTaggedScalarText Guid 'not-a-guid' } | Should -Throw '*invalid canonical text*'
        }
    }

    It 'covers rejected parser constructability and envelope branches' {
        InModuleScope TerminalSlides {
            { Read-TerminalWireInt32 ([uint64]::MaxValue) Value } | Should -Throw '*32-bit*'
            { Read-TerminalCurrentScalarValue ([ordered]@{ Name='Count'; Kind='Int32'; Value='042' }) -RequireCanonical } |
                Should -Throw '*not canonical*'
            { Read-TerminalCurrentPayload Chart ([ordered]@{ ChartKind='Bar'; Title=$null; Points=@(@{Label='A';Value='nope'}) }) -RequireCanonical } |
                Should -Throw '*not a valid Decimal*'
            { Read-TerminalCurrentPayload Chart ([ordered]@{ ChartKind='Bar'; Title=$null; Points=@(@{Label='A';Value='01'}) }) -RequireCanonical } |
                Should -Throw '*not canonical*'
            { Read-TerminalCurrentPayload Diagram ([ordered]@{ Nodes=@(@{Id=' ';Label='A'}); Edges=@() }) } |
                Should -Throw '*Id must be nonblank*'
            { Read-TerminalCurrentPayload Diagram ([ordered]@{ Nodes=@(); Edges=@(@{From=' ';To='B';Label=$null}) }) } |
                Should -Throw '*endpoints must be nonblank*'

            $wire = ConvertTo-PresentationData (New-TerminalPresentation -Title Theme)
            $blankTheme = ConvertFrom-TerminalWireJson (ConvertTo-TerminalWireJson $wire)
            $blankTheme.Presentation.ThemeDefinition.BulletSymbol = ' '
            { ConvertFrom-TerminalCurrentData $blankTheme } | Should -Throw '*BulletSymbol must be nonblank*'
            $emptyPalette = ConvertFrom-TerminalWireJson (ConvertTo-TerminalWireJson $wire)
            $emptyPalette.Presentation.ThemeDefinition.ChartPalette = @()
            { ConvertFrom-TerminalCurrentData $emptyPalette } | Should -Throw '*ChartPalette must not be empty*'
            $legacy = ConvertFrom-TerminalWireJson (ConvertTo-TerminalWireJson $wire)
            $legacy['$schema'] = $script:TerminalSlidesLegacyWireSchema
            $legacy.SchemaVersion = 1
            $legacy.Presentation.Remove('ThemeDefinition')
            $legacy.Presentation.Theme = 'MissingTheme'
            { ConvertFrom-TerminalCurrentData $legacy } | Should -Throw '*unsupported value*'

            { Assert-TerminalCurrentTaggedNode 'not-an-object' } | Should -Throw '*must be an object*'
            { Assert-TerminalCurrentTaggedNode ([ordered]@{
                Type='Map'; Entries=@([ordered]@{ Name='Value'; Value=[ordered]@{ Type='String'; Value='ok' } })
            }) } | Should -Not -Throw
            { Assert-TerminalMarkdownEnvelope ([ordered]@{ MarkerVersion=2; ProjectionHash=('A' * 64); Presentation=@{} }) } |
                Should -Throw '*ProjectionHash is malformed*'
            { Assert-TerminalMarkdownEnvelope ([ordered]@{ MarkerVersion=3; Presentation=@{} }) } |
                Should -Throw '*unsupported*'
        }
    }

    It 'keeps embedded themes presentation-owned across failed and colliding imports' {
        InModuleScope TerminalSlides {
            New-TerminalPresentationTheme -Name Isolated -Background '#000000' -Foreground '#FFFFFF' -Primary '#111111' | Out-Null
            $original = New-TerminalPresentation -Title Original -Theme Isolated
            $wire = ConvertTo-PresentationData $original
            $wire.Presentation.ThemeDefinition.Primary = '#FF0000'
            $invalid = ConvertFrom-TerminalWireJson (ConvertTo-TerminalWireJson $wire)
            $invalid.Presentation.Slides = 'not-an-array'
            { ConvertFrom-TerminalCurrentData $invalid } | Should -Throw '*must be an array*'
            (Get-ResolvedTheme Isolated).Primary | Should -BeExactly '#111111'

            $imported = ConvertFrom-TerminalCurrentData $wire
            (Resolve-TerminalPresentationTheme $original).Primary | Should -BeExactly '#111111'
            (Resolve-TerminalPresentationTheme $imported).Primary | Should -BeExactly '#FF0000'
            (Get-ResolvedTheme Isolated).Primary | Should -BeExactly '#111111'

            $original.Theme = 'HighContrast'
            (Resolve-TerminalPresentationTheme $original).Name | Should -BeExactly HighContrast
            (ConvertTo-PresentationData $original).Presentation.Theme | Should -BeExactly HighContrast
        }
    }

    It 'verifies v1 profiles without invoking evolving current Markdown renderers' {
        InModuleScope TerminalSlides {
            $deck = New-TerminalPresentation -Title Frozen
            $deck | Add-TerminalSlide -Title One -Content { Add-SlideQuote -Text "first`nsecond" -Attribution Ada } | Out-Null
            $visible = ConvertTo-TerminalMarkdownV1Document $deck Midnight -CompleteColumns
            Mock ConvertTo-TerminalMarkdownDocument { throw 'current document renderer must not run' }
            Mock ConvertTo-TerminalMarkdownElement { throw 'current element renderer must not run' }
            Mock ConvertTo-TerminalMarkdownCell { throw 'current cell renderer must not run' }
            (Test-TerminalMarkdownV1Projection $visible $deck Midnight) | Should -BeTrue
            Should -Invoke ConvertTo-TerminalMarkdownDocument -Times 0
            Should -Invoke ConvertTo-TerminalMarkdownElement -Times 0
            Should -Invoke ConvertTo-TerminalMarkdownCell -Times 0
        }
    }

    It 'rejects parser-only geometry and diagram identities at authoring or export first' {
        InModuleScope TerminalSlides -Parameters @{ Root = $TestDrive } {
            $positioned = New-TerminalPresentation -Title Position
            $positioned | Add-TerminalSlide -Title One -Content { Add-SlideText text } | Out-Null
            $positioned.Slides[0].Elements[0].X = -1
            $path = Join-Path $Root invalid.json
            { Export-TerminalPresentation $positioned $path -Format Json } | Should -Throw '*X*-1*non-negative*'
            $path | Should -Not -Exist

            $dimensions = New-TerminalPresentation -Title Dimensions
            $dimensions.Width = 19
            { ConvertTo-PresentationData $dimensions } | Should -Throw '*automatic*20x10*'
            $dimensions.Width = -1
            { ConvertTo-PresentationData $dimensions } | Should -Throw '*automatic*20x10*'

            $indexed = New-TerminalPresentation -Title Index
            $indexed | Add-TerminalSlide -Title One | Out-Null
            $indexed.Slides[0].Index = -1
            { ConvertTo-PresentationData $indexed } | Should -Throw '*Index*-1*non-negative*'

            $region = New-TerminalPresentation -Title Region
            $region | Add-TerminalSlide -Title One -Layout Blank -Content { Add-SlideText text -Region Left } | Out-Null
            { Export-TerminalPresentation $region (Join-Path $Root region.json) -Format Json } |
                Should -Throw "*Region 'Left' is not available*"

            $elementColor = New-TerminalPresentation -Title ElementColor
            $elementColor | Add-TerminalSlide -Title One -Content { Add-SlideText text } | Out-Null
            $elementColor.Slides[0].Elements[0].ForegroundColor = 'not-a-color'
            { Export-TerminalPresentation $elementColor (Join-Path $Root element-color.json) -Format Json } |
                Should -Throw '*ForegroundColor*six-digit*'

            $slideColor = New-TerminalPresentation -Title SlideColor
            $slideColor | Add-TerminalSlide -Title One -Content { Add-SlideText text } | Out-Null
            $slideColor.Slides[0].Background = 'not-a-color'
            { Export-TerminalPresentation $slideColor (Join-Path $Root slide-color.json) -Format Json } |
                Should -Throw '*Slide Background*six-digit*'

            $themeModel = New-TerminalPresentation -Title ThemeModel
            $themeModel.EmbeddedTheme.CodeTheme = ' '
            { ConvertTo-PresentationData $themeModel } | Should -Throw '*CodeTheme must be nonblank*'
            $themeModel.EmbeddedTheme.CodeTheme = 'Default'
            $themeModel.EmbeddedTheme.ChartPalette = @()
            { ConvertTo-PresentationData $themeModel } | Should -Throw '*ChartPalette must not be empty*'

            $diagram = New-TerminalPresentation -Title Diagram
            {
                $diagram | Add-TerminalSlide -Title One -Content {
                    Add-SlideDiagram -Diagram @{ Nodes=@(@{Id='A';Label='One'},@{Id='a';Label='Two'}); Edges=@() }
                }
            } | Should -Throw '*node IDs must be unique ignoring case*'
            $diagram.Slides.Count | Should -Be 0

            $scalar = [TerminalSlides.Schema.V1.ScalarValue]::new('String', 'one')
            $duplicateCells = [TerminalSlides.Schema.V1.DataCell[]]@(
                [TerminalSlides.Schema.V1.DataCell]::new('Name', $scalar)
                [TerminalSlides.Schema.V1.DataCell]::new('Name', $scalar)
            )
            $duplicateRow = [TerminalSlides.Schema.V1.DataRow]::new($duplicateCells)
            $tableElement = [TerminalSlides.Schema.V1.SlideElement]::new(
                'Table', [TerminalSlides.Schema.V1.TablePayload]::new([TerminalSlides.Schema.V1.DataRow[]]@($duplicateRow))
            )
            $tableDeck = New-TerminalPresentation -Title Table
            $tableDeck | Add-TerminalSlide -Title One | Out-Null
            $tableDeck.Slides[0].Elements.Add($tableElement)
            { ConvertTo-PresentationData $tableDeck } | Should -Throw '*Duplicate table column*Name*'

            $nullMap = New-TerminalPresentation -Title NullMap
            $nullMap.Configuration = $null
            { ConvertTo-PresentationData $nullMap } | Should -Throw '*Configuration map must not be null*'

            foreach ($kindAndValue in @(
                [pscustomobject]@{ Kind = 'Null'; Value = 'not-null' }
                [pscustomobject]@{ Kind = 'Int32'; Value = 'not-an-integer' }
                [pscustomobject]@{ Kind = 'Int32'; Value = '042' }
                [pscustomobject]@{ Kind = 'DateTime'; Value = '2024-01-02' }
            )) {
                $cell = [TerminalSlides.Schema.V1.DataCell]::new(
                    'Value', [TerminalSlides.Schema.V1.ScalarValue]::new($kindAndValue.Kind, $kindAndValue.Value)
                )
                $row = [TerminalSlides.Schema.V1.DataRow]::new([TerminalSlides.Schema.V1.DataCell[]]@($cell))
                $element = [TerminalSlides.Schema.V1.SlideElement]::new(
                    'Table', [TerminalSlides.Schema.V1.TablePayload]::new([TerminalSlides.Schema.V1.DataRow[]]@($row))
                )
                $invalidTable = New-TerminalPresentation -Title InvalidTable
                $invalidTable | Add-TerminalSlide -Title One | Out-Null
                $invalidTable.Slides[0].Elements.Add($element)
                { ConvertTo-PresentationData $invalidTable } | Should -Throw
            }

            $sparseTheme = [TerminalSlides.Schema.V1.ThemeDefinition]::new()
            $sparseTheme.ChartPalette = @()
            $sparseTheme.Metadata = $null
            (Copy-TerminalThemeDefinition $sparseTheme).Metadata.Count | Should -Be 0
        }
    }

    It 'finalizes legacy migrations through owned themes and shared wire-ready semantics' {
        InModuleScope TerminalSlides {
            { New-PresentationFromData ([ordered]@{ Title='Negative'; Width=-1; Slides=@() }) } |
                Should -Throw '*dimensions must be automatic*'
            { New-PresentationFromData ([ordered]@{ Title='Layout'; DefaultLayout='Unknown'; Slides=@() }) } |
                Should -Throw '*DefaultLayout*unsupported value*'
            {
                New-PresentationFromData ([ordered]@{
                    Title='Geometry'
                    Slides=@([ordered]@{
                        Title='One'; Layout='TitleAndContent'
                        Elements=@([ordered]@{ Type='Text'; Content='invalid'; X=-1 })
                    })
                })
            } | Should -Throw '*X*-1*non-negative*'
            {
                New-PresentationFromData ([ordered]@{
                    Title='Region'
                    Slides=@([ordered]@{
                        Title='One'; Layout='Blank'
                        Elements=@([ordered]@{ Type='Text'; Content='invalid'; Region='Left' })
                    })
                })
            } | Should -Throw "*Region 'Left' is not available*"

            $legacy = New-PresentationFromData ([ordered]@{
                Title='Legacy'; Theme='midnight'
                Metadata=[ordered]@{ Custom=[ordered]@{ Audience='engineers' } }
                Slides=@([ordered]@{
                    Title='One'; Layout='TitleAndContent'
                    Elements=@([ordered]@{ Type='Code'; Content=[ordered]@{ Code='Get-Date'; Language='powershell' } })
                })
            })
            $legacy.EmbeddedTheme.Name | Should -BeExactly Midnight
            $legacy.Metadata.Custom.Audience | Should -BeExactly engineers
            $legacy.Slides[0].Elements[0].Payload.Language | Should -BeExactly powershell
            $ownedPrimary = $legacy.EmbeddedTheme.Primary
            $registeredPrimary = $script:Themes['Midnight'].Primary
            try {
                $script:Themes['Midnight'].Primary = '#010203'
                (Resolve-TerminalPresentationTheme $legacy).Primary | Should -BeExactly $ownedPrimary
            }
            finally { $script:Themes['Midnight'].Primary = $registeredPrimary }
        }
    }

    It 'rejects undefined typed chart kinds before every structured export' {
        InModuleScope TerminalSlides -Parameters @{ Root = $TestDrive } {
            $invalidKind = [Enum]::ToObject([TerminalSlides.Schema.V1.ChartKind], 999)
            $chart = [TerminalSlides.Schema.V1.SlideElement]::new(
                'Chart',
                [TerminalSlides.Schema.V1.ChartPayload]::new(
                    [TerminalSlides.Schema.V1.ChartPoint[]]@(), $invalidKind, 'Invalid'
                )
            )
            $deck = New-TerminalPresentation -Title InvalidChart
            $deck | Add-TerminalSlide -Title One | Out-Null
            $deck.Slides[0].Elements.Add($chart)

            foreach ($format in 'Json','Psd1','Markdown') {
                $path = Join-Path $Root "invalid-chart.$($format.ToLowerInvariant())"
                { Export-TerminalPresentation $deck $path -Format $format } |
                    Should -Throw "*ChartKind '999' is unsupported*"
                $path | Should -Not -Exist
            }
        }
    }

    It 'requires canonical v2 presentation dates while preserving legacy date parsing' {
        $wire = & (Get-Module TerminalSlides) {
            ConvertTo-PresentationData (New-TerminalPresentation -Title Dates)
        }
        $invalidDates = @(
            [pscustomobject]@{ Text='2024-01-02'; Message='*round-trip format*' }
            [pscustomobject]@{ Text='01/02/2024'; Message='*round-trip format*' }
            [pscustomobject]@{ Text='2024-01-02T03:04:05Z'; Message='*round-trip format*' }
            [pscustomobject]@{ Text='2024-01-02T03:04:05.000Z'; Message='*round-trip format*' }
            [pscustomobject]@{ Text='2024-01-02T03:04:05.1234567-00:00'; Message='*negative-zero*' }
        )
        foreach ($field in 'CreatedDate','ModifiedDate') {
            foreach ($invalidDate in $invalidDates) {
                foreach ($format in 'Json','Psd1','Markdown') {
                    $copy = & (Get-Module TerminalSlides) {
                        param($Value) ConvertFrom-TerminalWireJson (ConvertTo-TerminalWireJson $Value)
                    } $wire
                    $copy.Presentation[$field] = $invalidDate.Text
                    $path = Join-Path $TestDrive "invalid-$field-$([array]::IndexOf($invalidDates, $invalidDate)).$($format.ToLowerInvariant())"
                    Write-Cycle23WireFile -Data $copy -Format $format -Path $path
                    { Import-TerminalPresentation $path } | Should -Throw $invalidDate.Message
                }
            }
        }

        foreach ($case in @(
            [pscustomobject]@{ Name='Utc'; Text='2024-01-02T03:04:05.1234567Z'; Kind=[DateTimeKind]::Utc; UtcTicks=([datetimeoffset]'2024-01-02T03:04:05.1234567Z').UtcTicks }
            [pscustomobject]@{ Name='PositiveZero'; Text='2024-01-02T03:04:05.1234567+00:00'; Kind=[DateTimeKind]::Local; UtcTicks=([datetimeoffset]'2024-01-02T03:04:05.1234567+00:00').UtcTicks }
            [pscustomobject]@{ Name='East14'; Text='2024-01-02T03:04:05.1234567+14:00'; Kind=[DateTimeKind]::Local; UtcTicks=([datetimeoffset]'2024-01-02T03:04:05.1234567+14:00').UtcTicks }
            [pscustomobject]@{ Name='West14'; Text='2024-01-02T03:04:05.1234567-14:00'; Kind=[DateTimeKind]::Local; UtcTicks=([datetimeoffset]'2024-01-02T03:04:05.1234567-14:00').UtcTicks }
            [pscustomobject]@{ Name='Unspecified'; Text='2024-01-02T03:04:05.1234567'; Kind=[DateTimeKind]::Unspecified; UtcTicks=$null }
        )) {
            foreach ($format in 'Json','Psd1','Markdown') {
                $copy = & (Get-Module TerminalSlides) {
                    param($Value) ConvertFrom-TerminalWireJson (ConvertTo-TerminalWireJson $Value)
                } $wire
                $copy.Presentation.CreatedDate = $case.Text
                $copy.Presentation.ModifiedDate = $case.Text
                $path = Join-Path $TestDrive "valid-$($case.Name).$($format.ToLowerInvariant())"
                Write-Cycle23WireFile -Data $copy -Format $format -Path $path
                $roundtrip = Import-TerminalPresentation $path
                $roundtrip.CreatedDate.Kind | Should -Be $case.Kind
                $roundtrip.ModifiedDate.Kind | Should -Be $case.Kind
                if ($null -ne $case.UtcTicks) {
                    $roundtrip.CreatedDate.ToUniversalTime().Ticks | Should -Be $case.UtcTicks
                    $roundtrip.ModifiedDate.ToUniversalTime().Ticks | Should -Be $case.UtcTicks
                }
            }
        }

        InModuleScope TerminalSlides -Parameters @{ Wire = $wire } {
            $v1 = ConvertFrom-TerminalWireJson (ConvertTo-TerminalWireJson $Wire)
            $v1['$schema'] = $script:TerminalSlidesLegacyWireSchema
            $v1.SchemaVersion = $script:TerminalSlidesLegacyWireVersion
            $v1.Presentation.Remove('ThemeDefinition')
            $v1.Presentation.CreatedDate = '2024-01-02'
            (ConvertFrom-TerminalCurrentData $v1).CreatedDate.Kind | Should -Be ([DateTimeKind]::Unspecified)
            foreach ($field in 'CreatedDate','ModifiedDate') {
                $malformed = ConvertFrom-TerminalWireJson (ConvertTo-TerminalWireJson $v1)
                $malformed.Presentation[$field] = 'not-a-date'
                { ConvertFrom-TerminalCurrentData $malformed } | Should -Throw "*$field is invalid*"
            }
            (New-PresentationFromData ([ordered]@{ Title='Legacy'; CreatedDate='2024-01-02'; Slides=@() })).CreatedDate.Kind |
                Should -Be ([DateTimeKind]::Unspecified)
        }
    }

    It 'requires explicit canonical Regex timeouts in v2 while preserving the v1 shape' {
        $wire = & (Get-Module TerminalSlides) {
            $expression = [regex]::new(
                'deck-[0-9]+',
                [Text.RegularExpressions.RegexOptions]::CultureInvariant,
                [timespan]::FromMilliseconds(250)
            )
            ConvertTo-PresentationData (New-TerminalPresentation -Title Regex -Metadata @{ Expression=$expression })
        }
        $invalidCases = @(
            [pscustomobject]@{ Name='Missing'; Value=$null; Remove=$true; Message='*MatchTimeoutTicks*required*' }
            [pscustomobject]@{ Name='LeadingZeros'; Value='0002500000'; Remove=$false; Message='*canonical text*' }
            [pscustomobject]@{ Name='PlusSign'; Value='+2500000'; Remove=$false; Message='*canonical text*' }
            [pscustomobject]@{ Name='Malformed'; Value='not-ticks'; Remove=$false; Message='*match timeout is invalid*' }
            [pscustomobject]@{ Name='Overflow'; Value='9223372036854775808'; Remove=$false; Message='*match timeout is invalid*' }
            [pscustomobject]@{ Name='Zero'; Value='0'; Remove=$false; Message='*match timeout is invalid*' }
            [pscustomobject]@{ Name='Negative'; Value='-1'; Remove=$false; Message='*match timeout is invalid*' }
        )
        foreach ($case in $invalidCases) {
            foreach ($format in 'Json','Psd1','Markdown') {
                $copy = & (Get-Module TerminalSlides) {
                    param($Value) ConvertFrom-TerminalWireJson (ConvertTo-TerminalWireJson $Value)
                } $wire
                $regexValue = $copy.Presentation.Metadata.Custom.Entries[0].Value.Value
                if ($case.Remove) { $regexValue.Remove('MatchTimeoutTicks') }
                else { $regexValue.MatchTimeoutTicks = $case.Value }
                $path = Join-Path $TestDrive "invalid-regex-$($case.Name).$($format.ToLowerInvariant())"
                Write-Cycle23WireFile -Data $copy -Format $format -Path $path
                { Import-TerminalPresentation $path } | Should -Throw $case.Message
            }
        }

        foreach ($ticks in '2500000','-10000') {
            foreach ($format in 'Json','Psd1','Markdown') {
                $copy = & (Get-Module TerminalSlides) {
                    param($Value) ConvertFrom-TerminalWireJson (ConvertTo-TerminalWireJson $Value)
                } $wire
                $copy.Presentation.Metadata.Custom.Entries[0].Value.Value.MatchTimeoutTicks = $ticks
                $path = Join-Path $TestDrive "valid-regex-$ticks.$($format.ToLowerInvariant())"
                Write-Cycle23WireFile -Data $copy -Format $format -Path $path
                (Import-TerminalPresentation $path).Metadata.Custom.Expression.MatchTimeout.Ticks | Should -Be ([int64]$ticks)
            }
        }

        InModuleScope TerminalSlides -Parameters @{ Wire = $wire } {
            {
                ConvertFrom-TerminalTaggedValue ([ordered]@{
                    Type='Regex'
                    Value=[ordered]@{ Pattern=[object[]]@('invalid'); Options=512; MatchTimeoutTicks='2500000' }
                }) -RequireCanonical
            } | Should -Throw '*Pattern*must be a string*'
            {
                ConvertFrom-TerminalTaggedValue ([ordered]@{
                    Type='Regex'
                    Value=[ordered]@{ Pattern='('; Options=512; MatchTimeoutTicks='2500000' }
                }) -RequireCanonical
            } | Should -Throw '*regular-expression value is malformed*'

            $v1 = ConvertFrom-TerminalWireJson (ConvertTo-TerminalWireJson $Wire)
            $v1['$schema'] = $script:TerminalSlidesLegacyWireSchema
            $v1.SchemaVersion = $script:TerminalSlidesLegacyWireVersion
            $v1.Presentation.Remove('ThemeDefinition')
            $v1.Presentation.Metadata.Custom.Entries[0].Value.Value.Remove('MatchTimeoutTicks')
            $expected = ([regex]::new('legacy')).MatchTimeout
            (ConvertFrom-TerminalCurrentData $v1).Metadata.Custom.Expression.MatchTimeout | Should -Be $expected
        }
    }
}
