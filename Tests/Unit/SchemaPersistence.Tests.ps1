Describe 'Typed schema and persistence boundary' {
    BeforeAll {
        $script:ModulePath = Join-Path $PSScriptRoot '..' '..' 'TerminalSlides.psd1'
        Import-Module $script:ModulePath -Force
        $script:Pixel = [Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=')
    }

    It 'loads an immutable schema identity from the packaged assembly' {
        $type = [TerminalSlides.Schema.V1.TerminalPresentation]
        $type.Assembly.GetName().Version | Should -Be ([version]'1.0.0.0')
        [IO.Path]::GetFileName($type.Assembly.Location) | Should -BeExactly 'TerminalSlides.Schema.dll'
        $before = $type

        Import-Module $script:ModulePath -Force

        [object]::ReferenceEquals($before, [TerminalSlides.Schema.V1.TerminalPresentation]) | Should -BeTrue
    }

    It 'normalizes every public element into a typed payload' {
        $deck = New-TerminalPresentation -Title Typed
        $deck | Add-TerminalSlide -Title Elements -Content {
            Add-SlideTitle title
            Add-SlideSubtitle subtitle
            Add-SlideText text
            Add-SlideBullet bullet
            Add-SlideCode -Code code -Language powershell
            Add-SlideTable -Data @([pscustomobject]@{ Name = 'Ada'; Score = 10 })
            Add-SlideChart -Data @([pscustomobject]@{ Label = 'A'; Value = 2 }) -ChartType Line
            Add-SlideDiagram -Content { Add-SlideDiagramNode -Id a -Label A; Add-SlideDiagramEdge -From a -To a }
            Add-SlideImage -Path ./photo.png -AltText Photo
            Add-SlideQuote -Text quote -Attribution author
            Add-SlideBox box
        } | Out-Null

        @($deck.Slides[0].Elements | ForEach-Object { $_.Kind.ToString() }) | Should -Be @('Title','Subtitle','Text','Bullet','Code','Table','Chart','Diagram','Image','Quote','Box')
        @($deck.Slides[0].Elements | ForEach-Object { $_.Payload.GetType().Name }) | Should -Be @(
            'TextPayload','TextPayload','TextPayload','TextPayload','CodePayload','TablePayload',
            'ChartPayload','DiagramPayload','ImagePayload','QuotePayload','TextPayload'
        )
        # Read-only legacy projections bridge the old renderer until the next stacked PR.
        $deck.Slides[0].Elements[0].PSObject.Properties.Name | Should -Contain Type
        $deck.Slides[0].Elements[0].PSObject.Properties.Name | Should -Contain Content
        $deck.Slides[0].Elements[0].PSObject.Properties.Name | Should -Contain Properties
    }

    It 'enforces payload-kind invariants and immutable payload collections' {
        {
            [TerminalSlides.Schema.V1.SlideElement]::new(
                [TerminalSlides.Schema.V1.ElementKind]::Code,
                [TerminalSlides.Schema.V1.TextPayload]::new('wrong')
            )
        } | Should -Throw "*not valid for element kind 'Code'*"

        $source = [Collections.Generic.List[TerminalSlides.Schema.V1.ChartPoint]]::new()
        $source.Add([TerminalSlides.Schema.V1.ChartPoint]::new('Before', 1))
        $payload = [TerminalSlides.Schema.V1.ChartPayload]::new(
            $source,
            [TerminalSlides.Schema.V1.ChartKind]::Bar,
            'Snapshot'
        )
        $source[0] = [TerminalSlides.Schema.V1.ChartPoint]::new('After', 2)

        $payload.Points[0].Label | Should -BeExactly Before
        { $payload.Points[0] = [TerminalSlides.Schema.V1.ChartPoint]::new('Mutation', 3) } | Should -Throw
    }

    It 'preserves typed metadata arrays through copy and every structured format' {
        $deck = New-TerminalPresentation -Title Arrays
        $deck.Metadata.Custom.Bytes = [byte[]](1, 2, 3)
        $deck.Metadata.Custom.Ints = [int[]](4, 5, 6)
        $deck.Metadata.Custom.Chars = [char[]]('a', 'b')
        $deck.Metadata.Custom.Number = [int32]42
        $deck | Add-TerminalSlide -Title One -Metadata @{ Values = [int[]](7, 8) } -Content { Add-SlideText body } | Out-Null
        Copy-TerminalSlide $deck 1 | Out-Null
        $deck.Slides[1].Metadata.Custom.Values[0] = 99
        $deck.Slides[0].Metadata.Custom.Values[0] | Should -Be 7
        $deck.Slides[1].Metadata.Custom.Values.GetType().FullName | Should -BeExactly 'System.Int32[]'

        foreach ($format in 'Json','Psd1','Markdown') {
            $extension = @{ Json='json'; Psd1='psd1'; Markdown='md' }[$format]
            $path = Join-Path $TestDrive "arrays.$extension"
            Export-TerminalPresentation $deck $path -Format $format | Out-Null
            $roundtrip = Import-TerminalPresentation $path
            $roundtrip.Metadata.Custom.Bytes.GetType().FullName | Should -BeExactly 'System.Byte[]'
            $roundtrip.Metadata.Custom.Ints.GetType().FullName | Should -BeExactly 'System.Int32[]'
            $roundtrip.Metadata.Custom.Chars.GetType().FullName | Should -BeExactly 'System.Char[]'
            $roundtrip.Metadata.Custom.Number.GetType().FullName | Should -BeExactly 'System.Int32'
        }
    }

    It 'rejects unsupported mutable values instead of aliasing them' {
        $deck = New-TerminalPresentation -Title Mutable
        $deck | Add-TerminalSlide -Title One -Metadata @{ Builder = [Text.StringBuilder]::new('before') } -Content { Add-SlideText body } | Out-Null

        { Copy-TerminalSlide $deck 1 } | Should -Throw '*Unsupported mutable value type*StringBuilder*'
        $deck.Slides.Count | Should -Be 1
    }

    It 'roundtrips every supported tagged scalar without type or culture drift' {
        InModuleScope TerminalSlides {
            $cases = @(
                @{ Value = 'text'; Type = [string] }
                @{ Value = [char]'Z'; Type = [char] }
                @{ Value = $false; Type = [bool] }
                @{ Value = [sbyte]-2; Type = [sbyte] }
                @{ Value = [byte]2; Type = [byte] }
                @{ Value = [int16]-3; Type = [int16] }
                @{ Value = [uint16]3; Type = [uint16] }
                @{ Value = [int32]-4; Type = [int32] }
                @{ Value = [uint32]4; Type = [uint32] }
                @{ Value = [int64]-5; Type = [int64] }
                @{ Value = [uint64]5; Type = [uint64] }
                @{ Value = [single]1.25; Type = [single] }
                @{ Value = [double]2.5; Type = [double] }
                @{ Value = [decimal]3.75; Type = [decimal] }
                @{ Value = [datetime]'2024-01-02T03:04:05.0000000Z'; Type = [datetime] }
                @{ Value = [datetimeoffset]'2024-02-03T04:05:06.0000000+02:00'; Type = [datetimeoffset] }
                @{ Value = [timespan]'01:02:03'; Type = [timespan] }
                @{ Value = [guid]'62ae7708-a44f-4b87-af96-d7affc799073'; Type = [guid] }
                @{ Value = [uri]'https://example.test/path'; Type = [uri] }
                @{ Value = [version]'1.2.3.4'; Type = [version] }
            )

            foreach ($case in $cases) {
                $actual = ConvertFrom-TerminalTaggedValue (ConvertTo-TerminalTaggedValue $case.Value)
                $actual.GetType() | Should -Be $case.Type
                $actual | Should -Be $case.Value
            }

            $expression = [regex]::new(
                'deck-[0-9]+',
                ([Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [Text.RegularExpressions.RegexOptions]::CultureInvariant)
            )
            $regexRoundtrip = ConvertFrom-TerminalTaggedValue (ConvertTo-TerminalTaggedValue $expression)
            $regexRoundtrip.GetType() | Should -Be ([regex])
            $regexRoundtrip.ToString() | Should -BeExactly $expression.ToString()
            $regexRoundtrip.Options | Should -Be $expression.Options
            (ConvertFrom-TerminalTaggedValue ([ordered]@{ Type = 'Boolean'; Value = $false })) | Should -BeFalse
            (ConvertFrom-TerminalTaggedValue ([ordered]@{ Type = 'Null' })) | Should -BeNullOrEmpty
        }
    }

    It 'preserves date identity in metadata and tables through every structured format' {
        $utc = [datetime]::SpecifyKind([datetime]'2024-01-02T03:04:05.1234567', [DateTimeKind]::Utc)
        $unspecified = [datetime]::SpecifyKind([datetime]'2025-02-03T04:05:06.7654321', [DateTimeKind]::Unspecified)
        $offset = [datetimeoffset]'2024-02-03T04:05:06.1234567+02:30'
        $dateVector = [datetime[]]@($utc, $unspecified)
        $offsetVector = [datetimeoffset[]]@($offset)
        $deck = New-TerminalPresentation -Title Dates -Metadata @{
            Utc = $utc
            Offset = $offset
            DateVector = $dateVector
            OffsetVector = $offsetVector
        }
        $tableData = @([ordered]@{ Utc = $utc; Offset = $offset })
        $content = { Add-SlideTable -Data $tableData }.GetNewClosure()
        $deck | Add-TerminalSlide -Title Dates -Content $content | Out-Null
        $deck.CreatedDate = $utc
        $deck.ModifiedDate = $unspecified

        InModuleScope TerminalSlides -Parameters @{ Presentation = $deck } {
            $wire = ConvertTo-PresentationData -Presentation $Presentation
            ($wire.Presentation.Metadata.Custom.Entries | Where-Object Name -EQ Utc).Value.Value |
                Should -BeExactly '2024-01-02T03:04:05.1234567Z'
            $wire.Presentation.Slides[0].Elements[0].Payload.Rows[0].Cells[0].Value |
                Should -BeExactly '2024-01-02T03:04:05.1234567Z'
            $wire.Presentation.Slides[0].Elements[0].Payload.Rows[0].Cells[1].Value |
                Should -BeExactly '2024-02-03T04:05:06.1234567+02:30'
        }

        foreach ($format in 'Json', 'Psd1', 'Markdown') {
            $path = Join-Path $TestDrive "dates.$($format.ToLowerInvariant())"
            Export-TerminalPresentation $deck $path -Format $format | Out-Null
            $roundtrip = Import-TerminalPresentation $path

            $roundtrip.Metadata.Custom.Utc.ToString('o') | Should -BeExactly $utc.ToString('o')
            $roundtrip.Metadata.Custom.Utc.Kind | Should -Be ([DateTimeKind]::Utc)
            $roundtrip.Metadata.Custom.Offset.ToString('o') | Should -BeExactly $offset.ToString('o')
            $roundtrip.Metadata.Custom.Offset.Offset | Should -Be $offset.Offset
            $roundtrip.Metadata.Custom.DateVector.GetType().FullName | Should -BeExactly 'System.DateTime[]'
            $roundtrip.Metadata.Custom.DateVector[0].ToString('o') | Should -BeExactly $utc.ToString('o')
            $roundtrip.Metadata.Custom.DateVector[0].Kind | Should -Be ([DateTimeKind]::Utc)
            $roundtrip.Metadata.Custom.DateVector[1].ToString('o') | Should -BeExactly $unspecified.ToString('o')
            $roundtrip.Metadata.Custom.DateVector[1].Kind | Should -Be ([DateTimeKind]::Unspecified)
            $roundtrip.Metadata.Custom.OffsetVector.GetType().FullName | Should -BeExactly 'System.DateTimeOffset[]'
            $roundtrip.Metadata.Custom.OffsetVector[0].ToString('o') | Should -BeExactly $offset.ToString('o')
            $roundtrip.Metadata.Custom.OffsetVector[0].Offset | Should -Be $offset.Offset
            $roundtrip.CreatedDate.ToString('o') | Should -BeExactly $utc.ToString('o')
            $roundtrip.CreatedDate.Kind | Should -Be ([DateTimeKind]::Utc)
            $roundtrip.ModifiedDate.ToString('o') | Should -BeExactly $unspecified.ToString('o')
            $roundtrip.ModifiedDate.Kind | Should -Be ([DateTimeKind]::Unspecified)

            InModuleScope TerminalSlides -Parameters @{
                Presentation = $roundtrip
                ExpectedUtc = $utc
                ExpectedOffset = $offset
            } {
                $payload = $Presentation.Slides[0].Elements[0].Payload
                $tableUtc = ConvertFrom-TerminalScalarValue $payload.Rows[0].Cells[0].Value
                $tableOffset = ConvertFrom-TerminalScalarValue $payload.Rows[0].Cells[1].Value
                $tableUtc.ToString('o') | Should -BeExactly $ExpectedUtc.ToString('o')
                $tableUtc.Kind | Should -Be ([DateTimeKind]::Utc)
                $tableOffset.ToString('o') | Should -BeExactly $ExpectedOffset.ToString('o')
                $tableOffset.Offset | Should -Be $ExpectedOffset.Offset
                { Render-TerminalPresentationToString -Presentation $Presentation -PlainText } | Should -Not -Throw
            }
        }
    }

    It 'decodes ISO DateTime kinds while preserving serialized local instants' {
        InModuleScope TerminalSlides {
            $utc = ConvertFrom-TerminalDateTimeText -Text '2024-01-02T03:04:05.1234567Z'
            $unspecified = ConvertFrom-TerminalDateTimeText -Text '2024-01-02T03:04:05.1234567'
            $local = ConvertFrom-TerminalDateTimeText -Text '2024-01-02T03:04:05.1234567-08:00'

            $utc.Kind | Should -Be ([DateTimeKind]::Utc)
            $utc.Ticks | Should -Be ([datetime]'2024-01-02T03:04:05.1234567').Ticks
            $unspecified.Kind | Should -Be ([DateTimeKind]::Unspecified)
            $unspecified.Ticks | Should -Be ([datetime]'2024-01-02T03:04:05.1234567').Ticks
            $local.Kind | Should -Be ([DateTimeKind]::Local)
            $local.Ticks | Should -Be ([datetimeoffset]'2024-01-02T03:04:05.1234567-08:00').LocalDateTime.Ticks
        }
    }

    It 'preserves local DateTime instants across timezone changes and every structured format' {
        $previousTimeZone = $env:TZ
        try {
            $env:TZ = 'America/Los_Angeles'
            [TimeZoneInfo]::ClearCachedData()
            $local = [datetime]::SpecifyKind([datetime]'2024-01-02T03:04:05.1234567', [DateTimeKind]::Local)
            $expectedUtc = $local.ToUniversalTime()
            $sourceOffset = [TimeZoneInfo]::Local.GetUtcOffset($local)
            $deck = New-TerminalPresentation -Title 'Local DateTime' -Metadata @{ Local = $local }
            $tableData = @([ordered]@{ Local = $local })
            $content = { Add-SlideTable -Data $tableData }.GetNewClosure()
            $deck | Add-TerminalSlide -Title Dates -Content $content | Out-Null
            $deck.CreatedDate = $local
            $deck.ModifiedDate = $local

            $paths = @{}
            foreach ($format in 'Json', 'Psd1', 'Markdown') {
                $path = Join-Path $TestDrive "local-datetime.$($format.ToLowerInvariant())"
                Export-TerminalPresentation $deck $path -Format $format | Out-Null
                $paths[$format] = $path
            }

            $env:TZ = 'UTC'
            [TimeZoneInfo]::ClearCachedData()
            if ([TimeZoneInfo]::Local.GetUtcOffset($local) -eq $sourceOffset) {
                Set-ItResult -Skipped -Because 'This platform does not honor runtime TZ changes.'
                return
            }

            foreach ($format in 'Json', 'Psd1', 'Markdown') {
                $roundtrip = Import-TerminalPresentation $paths[$format]
                $roundtrip.Metadata.Custom.Local.Kind | Should -Be ([DateTimeKind]::Local)
                $roundtrip.Metadata.Custom.Local.ToUniversalTime().Ticks | Should -Be $expectedUtc.Ticks
                $roundtrip.CreatedDate.Kind | Should -Be ([DateTimeKind]::Local)
                $roundtrip.CreatedDate.ToUniversalTime().Ticks | Should -Be $expectedUtc.Ticks
                $roundtrip.ModifiedDate.Kind | Should -Be ([DateTimeKind]::Local)
                $roundtrip.ModifiedDate.ToUniversalTime().Ticks | Should -Be $expectedUtc.Ticks
                InModuleScope TerminalSlides -Parameters @{ Presentation = $roundtrip; ExpectedUtc = $expectedUtc } {
                    $scalar = $Presentation.Slides[0].Elements[0].Payload.Rows[0].Cells[0].Value
                    $tableLocal = ConvertFrom-TerminalScalarValue $scalar
                    $tableLocal.Kind | Should -Be ([DateTimeKind]::Local)
                    $tableLocal.ToUniversalTime().Ticks | Should -Be $ExpectedUtc.Ticks
                    { Render-TerminalPresentationToString -Presentation $Presentation -PlainText } | Should -Not -Throw
                }
            }
        }
        finally {
            $env:TZ = $previousTimeZone
            [TimeZoneInfo]::ClearCachedData()
        }
    }

    It 'decodes legacy ISO and prefixed dates while rejecting coerced tagged values' {
        InModuleScope TerminalSlides {
            $legacyUtcText = '2024-01-02T03:04:05.1234567Z'
            $legacyOffsetText = '2024-02-03T04:05:06.1234567+02:30'
            $legacyUtc = ConvertFrom-TerminalTaggedValue ([ordered]@{ Type = 'DateTime'; Value = $legacyUtcText })
            $legacyOffset = ConvertFrom-TerminalTaggedValue ([ordered]@{ Type = 'DateTimeOffset'; Value = $legacyOffsetText })
            $legacyUtc.ToString('o') | Should -BeExactly $legacyUtcText
            $legacyUtc.Kind | Should -Be ([DateTimeKind]::Utc)
            $legacyOffset.ToString('o') | Should -BeExactly $legacyOffsetText
            $legacyOffset.Offset | Should -Be ([timespan]'02:30:00')
            (ConvertFrom-TerminalTaggedValue ([ordered]@{
                Type = 'DateTime'
                Value = "terminalslides:datetime:$legacyUtcText"
            })).ToString('o') | Should -BeExactly $legacyUtcText
            (ConvertFrom-TerminalTaggedValue ([ordered]@{
                Type = 'DateTimeOffset'
                Value = "terminalslides:datetimeoffset:$legacyOffsetText"
            })).ToString('o') | Should -BeExactly $legacyOffsetText

            ConvertFrom-TerminalPersistedScalarText -Kind String -Value $null | Should -BeNullOrEmpty
            ConvertFrom-TerminalPersistedScalarText -Kind DateTimeOffset -Value $legacyOffset |
                Should -BeExactly $legacyOffsetText
            [datetimeoffset](ConvertFrom-TerminalPersistedScalarText -Kind DateTimeOffset -Value $legacyUtc) |
                Should -Be ([datetimeoffset]$legacyUtc)

            $markerData = [ordered]@{ Type = 'DateTime'; Value = $legacyUtcText }
            $markerNode = ConvertFrom-TerminalDataMarker (ConvertTo-TerminalDataMarker $markerData)
            $markerNode.Value | Should -BeOfType string
            $markerNode.Value | Should -BeExactly $legacyUtcText
            $coercedNode = [ordered]@{ Type = 'DateTime'; Value = [datetime]$legacyUtcText }
            { ConvertFrom-TerminalTaggedValue $coercedNode } | Should -Throw '*canonical*Value*'

            $table = Read-TerminalCurrentPayload -Kind Table -Data ([ordered]@{
                Rows = @([ordered]@{
                    Cells = @(
                        [ordered]@{ Name = 'Utc'; Kind = 'DateTime'; Value = $legacyUtcText }
                        [ordered]@{ Name = 'Offset'; Kind = 'DateTimeOffset'; Value = $legacyOffsetText }
                    )
                })
            })
            (ConvertFrom-TerminalScalarValue $table.Rows[0].Cells[0].Value).ToString('o') |
                Should -BeExactly $legacyUtcText
            (ConvertFrom-TerminalScalarValue $table.Rows[0].Cells[1].Value).ToString('o') |
                Should -BeExactly $legacyOffsetText
        }
    }

    It 'preserves ISO-looking ordinary strings through every structured format' {
        $iso = '2024-01-02T03:04:05.1234567Z'
        $deck = New-TerminalPresentation -Title $iso -Metadata @{
            Scalar = $iso
            Nested = [pscustomobject]@{ Value = $iso }
            Vector = [string[]]@($iso)
        }
        $tableData = @([ordered]@{ Value = $iso })
        $content = {
            Add-SlideText $iso
            Add-SlideTable -Data $tableData
        }.GetNewClosure()
        $deck | Add-TerminalSlide -Title $iso -Metadata @{ Scalar = $iso } -Content $content | Out-Null

        foreach ($format in 'Json', 'Psd1', 'Markdown') {
            $path = Join-Path $TestDrive "iso-string.$($format.ToLowerInvariant())"
            Export-TerminalPresentation $deck $path -Format $format | Out-Null
            $roundtrip = Import-TerminalPresentation $path

            $roundtrip.Title | Should -BeExactly $iso
            $roundtrip.Metadata.Custom.Scalar | Should -BeExactly $iso
            $roundtrip.Metadata.Custom.Nested.Value | Should -BeExactly $iso
            $roundtrip.Metadata.Custom.Vector.GetType().FullName | Should -BeExactly 'System.String[]'
            $roundtrip.Metadata.Custom.Vector[0] | Should -BeExactly $iso
            $roundtrip.Slides[0].Title | Should -BeExactly $iso
            $roundtrip.Slides[0].Metadata.Custom.Scalar | Should -BeExactly $iso
            $roundtrip.Slides[0].Elements[0].Payload.Text | Should -BeExactly $iso
            InModuleScope TerminalSlides -Parameters @{ Presentation = $roundtrip; Expected = $iso } {
                $table = Get-TerminalElementPayload -Element $Presentation.Slides[0].Elements[1]
                $table.Rows[0].Value | Should -BeExactly $Expected
                { Render-TerminalPresentationToString -Presentation $Presentation -PlainText } | Should -Not -Throw
            }
        }
    }

    It 'decodes strict JSON deterministically without array or numeric shape loss' {
        InModuleScope TerminalSlides {
            $json = @'
{"text":"2024-01-02T03:04:05.1234567Z","empty":[],"nulls":[null],"nested":[[]],"signed":-1,"unsigned":18446744073709551615,"big":18446744073709551616,"fraction":1.25,"name":1,"Name":2}
'@
            $value = ConvertFrom-TerminalJsonValue -Json $json
            $value.GetType().FullName | Should -BeExactly 'System.Collections.Specialized.OrderedDictionary'
            $value.text | Should -BeExactly '2024-01-02T03:04:05.1234567Z'
            $value.empty.GetType().FullName | Should -BeExactly 'System.Object[]'
            $value.empty.Count | Should -Be 0
            $value.nulls.GetType().FullName | Should -BeExactly 'System.Object[]'
            $value.nulls.Count | Should -Be 1
            $value.nulls[0] | Should -BeNullOrEmpty
            $value.nested.GetType().FullName | Should -BeExactly 'System.Object[]'
            $value.nested[0].GetType().FullName | Should -BeExactly 'System.Object[]'
            $value.nested[0].Count | Should -Be 0
            $value.signed.GetType() | Should -Be ([int64])
            $value.unsigned.GetType() | Should -Be ([uint64])
            $value.big.GetType() | Should -Be ([Numerics.BigInteger])
            $value.fraction.GetType() | Should -Be ([double])
            @($value.Keys) | Should -Contain name
            @($value.Keys) | Should -Contain Name

            { ConvertFrom-TerminalJsonValue -Json '{"same":1,"same":2}' } | Should -Throw '*duplicate property*same*'
            { ConvertFrom-TerminalJsonValue -Json '{"value":1,}' } | Should -Throw
            { ConvertFrom-TerminalJsonValue -Json '{/*comment*/"value":1}' } | Should -Throw
            { ConvertFrom-TerminalJsonElement -Element ([System.Text.Json.JsonElement]::new()) } |
                Should -Throw '*Unsupported JSON token*Undefined*'
            { ConvertFrom-TerminalWireJson -Json '[]' } | Should -Throw '*root must be an object*'
        }
    }

    It 'roundtrips nested maps, objects, typed arrays, and ArrayList metadata' {
        InModuleScope TerminalSlides {
            $list = [Collections.ArrayList]::new()
            [void]$list.Add('first')
            [void]$list.Add([int32]2)
            $source = [ordered]@{
                Map = @{ Enabled = $true }
                Object = [pscustomobject]@{ Name = 'Ada'; Count = [int16]3 }
                Bytes = [byte[]](1, 2, 3)
                Objects = [object[]]@('mixed', [int32]4)
                Uris = [uri[]]@([uri]'https://one.test', [uri]'https://two.test')
                Versions = [version[]]@([version]'1.0', [version]'2.0')
                Patterns = [regex[]]@(
                    [regex]::new('one', [Text.RegularExpressions.RegexOptions]::CultureInvariant)
                    [regex]::new('two', [Text.RegularExpressions.RegexOptions]::CultureInvariant)
                )
                List = $list
            }

            $actual = ConvertFrom-TerminalTaggedValue (ConvertTo-TerminalTaggedValue $source)

            $actual.GetType().FullName | Should -BeExactly 'System.Collections.Specialized.OrderedDictionary'
            $actual.Map.GetType() | Should -Be ([hashtable])
            $actual.Object.GetType().FullName | Should -BeExactly 'System.Management.Automation.PSCustomObject'
            $actual.Bytes.GetType().FullName | Should -BeExactly 'System.Byte[]'
            $actual.Objects.GetType().FullName | Should -BeExactly 'System.Object[]'
            $actual.Uris.GetType().FullName | Should -BeExactly 'System.Uri[]'
            $actual.Versions.GetType().FullName | Should -BeExactly 'System.Version[]'
            $actual.Patterns.GetType().FullName | Should -BeExactly 'System.Text.RegularExpressions.Regex[]'
            $actual.List.GetType() | Should -Be ([Collections.ArrayList])
            $actual.List | Should -Be @('first', 2)
        }
    }

    It 'preserves relative Uri scalar, vector, and nested metadata through every structured format' {
        $relative = [uri]'../assets/team photo.png?size=large#speaker'
        $absolute = [uri]'https://example.test/assets/team%20photo.png'
        $deck = New-TerminalPresentation -Title Uris -Metadata @{
            Relative = $relative
            Vector = [uri[]]@($relative, $absolute)
            Nested = [ordered]@{ Relative = $relative }
        }

        InModuleScope TerminalSlides -Parameters @{ Relative = $relative; Absolute = $absolute } {
            $relativeNode = [ordered]@{ Type = 'Uri'; Value = $Relative.OriginalString }
            $absoluteNode = [ordered]@{ Type = 'Uri'; Value = $Absolute.OriginalString }
            $relativeLegacy = ConvertFrom-TerminalTaggedValue $relativeNode
            $absoluteLegacy = ConvertFrom-TerminalTaggedValue $absoluteNode
            $relativeLegacy.IsAbsoluteUri | Should -BeFalse
            $relativeLegacy.OriginalString | Should -BeExactly $Relative.OriginalString
            $absoluteLegacy.IsAbsoluteUri | Should -BeTrue
            $absoluteLegacy.AbsoluteUri | Should -BeExactly $Absolute.AbsoluteUri
        }

        foreach ($format in 'Json', 'Psd1', 'Markdown') {
            $path = Join-Path $TestDrive "relative-uri.$($format.ToLowerInvariant())"
            Export-TerminalPresentation $deck $path -Format $format | Out-Null
            $roundtrip = Import-TerminalPresentation $path

            $roundtrip.Metadata.Custom.Relative.GetType() | Should -Be ([uri])
            $roundtrip.Metadata.Custom.Relative.IsAbsoluteUri | Should -BeFalse
            $roundtrip.Metadata.Custom.Relative.OriginalString | Should -BeExactly $relative.OriginalString
            $roundtrip.Metadata.Custom.Vector.GetType().FullName | Should -BeExactly 'System.Uri[]'
            $roundtrip.Metadata.Custom.Vector[0].OriginalString | Should -BeExactly $relative.OriginalString
            $roundtrip.Metadata.Custom.Vector[1].IsAbsoluteUri | Should -BeTrue
            $roundtrip.Metadata.Custom.Vector[1].AbsoluteUri | Should -BeExactly $absolute.AbsoluteUri
            $roundtrip.Metadata.Custom.Nested.Relative.OriginalString | Should -BeExactly $relative.OriginalString
        }
    }

    It 'preserves finite and infinite Regex match timeouts through every structured format' {
        $finite = [regex]::new(
            '^(a+)+$',
            ([Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [Text.RegularExpressions.RegexOptions]::CultureInvariant),
            [timespan]::FromMilliseconds(250)
        )
        $infinite = [regex]::new(
            'deck-[0-9]+',
            [Text.RegularExpressions.RegexOptions]::CultureInvariant,
            [Text.RegularExpressions.Regex]::InfiniteMatchTimeout
        )
        $deck = New-TerminalPresentation -Title Regex -Metadata @{
            Finite = $finite
            Vector = [regex[]]@($finite, $infinite)
            Nested = [ordered]@{ Expression = $finite }
        }

        InModuleScope TerminalSlides -Parameters @{ Finite = $finite } {
            $copy = Copy-TerminalSemanticValue $Finite
            $copy.MatchTimeout | Should -Be $Finite.MatchTimeout
            $node = ConvertTo-TerminalTaggedValue $Finite
            $node.Value.MatchTimeoutTicks | Should -BeExactly ([string]$Finite.MatchTimeout.Ticks)
            (ConvertFrom-TerminalTaggedValue $node).MatchTimeout | Should -Be $Finite.MatchTimeout

            $legacyNode = [ordered]@{
                Type = 'Regex'
                Value = [ordered]@{ Pattern = 'legacy'; Options = 0 }
            }
            (ConvertFrom-TerminalTaggedValue $legacyNode).MatchTimeout |
                Should -Be ([regex]::new('legacy', [Text.RegularExpressions.RegexOptions]::None)).MatchTimeout
            {
                ConvertFrom-TerminalTaggedValue ([ordered]@{
                    Type = 'Regex'
                    Value = [ordered]@{ Pattern = 'invalid'; Options = 512; MatchTimeoutTicks = 'not-ticks' }
                })
            } | Should -Throw '*regular-expression match timeout is invalid*'
            {
                ConvertFrom-TerminalTaggedValue ([ordered]@{
                    Type = 'Regex'
                    Value = [ordered]@{ Pattern = 'invalid'; Options = 512; MatchTimeoutTicks = '0' }
                })
            } | Should -Throw '*regular-expression match timeout is invalid*'
        }

        foreach ($format in 'Json', 'Psd1', 'Markdown') {
            $path = Join-Path $TestDrive "regex-timeout.$($format.ToLowerInvariant())"
            Export-TerminalPresentation $deck $path -Format $format | Out-Null
            $roundtrip = Import-TerminalPresentation $path

            $roundtrip.Metadata.Custom.Finite.ToString() | Should -BeExactly $finite.ToString()
            $roundtrip.Metadata.Custom.Finite.Options | Should -Be $finite.Options
            $roundtrip.Metadata.Custom.Finite.MatchTimeout | Should -Be $finite.MatchTimeout
            $roundtrip.Metadata.Custom.Vector.GetType().FullName |
                Should -BeExactly 'System.Text.RegularExpressions.Regex[]'
            $roundtrip.Metadata.Custom.Vector[0].MatchTimeout | Should -Be $finite.MatchTimeout
            $roundtrip.Metadata.Custom.Vector[1].MatchTimeout |
                Should -Be ([Text.RegularExpressions.Regex]::InfiniteMatchTimeout)
            $roundtrip.Metadata.Custom.Nested.Expression.MatchTimeout | Should -Be $finite.MatchTimeout
        }
    }

    It 'rejects case-distinct metadata keys before copy or structured export can collapse them' {
        $ambiguous = [Collections.Specialized.OrderedDictionary]::new([StringComparer]::Ordinal)
        $ambiguous.Add('name', 1)
        $ambiguous.Add('Name', 2)

        InModuleScope TerminalSlides -Parameters @{ Ambiguous = $ambiguous } {
            { Copy-TerminalSemanticValue $Ambiguous } | Should -Throw '*unique ignoring case*Name*'
            { ConvertTo-TerminalTaggedValue $Ambiguous } | Should -Throw '*unique ignoring case*Name*'
            {
                ConvertFrom-TerminalTaggedValue ([ordered]@{
                    Type = 'OrderedMap'
                    Entries = @(
                        [ordered]@{ Name = 'name'; Value = [ordered]@{ Type = 'Int32'; Value = '1' } }
                        [ordered]@{ Name = 'Name'; Value = [ordered]@{ Type = 'Int32'; Value = '2' } }
                    )
                })
            } | Should -Throw '*unique ignoring case*Name*'
        }

        $deck = New-TerminalPresentation -Title Ambiguous -Metadata @{ Nested = $ambiguous }
        foreach ($format in 'Json', 'Psd1', 'Markdown') {
            $path = Join-Path $TestDrive "ambiguous-map.$($format.ToLowerInvariant())"
            { Export-TerminalPresentation $deck $path -Format $format } |
                Should -Throw '*unique ignoring case*Name*'
            $path | Should -Not -Exist
        }
    }

    It 'rejects non-vector metadata arrays before copy or persistence' {
        $matrix = [int[,]]::new(2, 2)
        $matrix[0, 0] = 1
        $jagged = [int[][]]@([int[]](1, 2), [int[]](3, 4))
        $nonZeroLowerBound = [Array]::CreateInstance([int], [int[]]@(2), [int[]]@(1))
        $nonZeroLowerBound.SetValue(7, 1)

        InModuleScope TerminalSlides -Parameters @{
            Matrix = $matrix
            Jagged = $jagged
            NonZeroLowerBound = $nonZeroLowerBound
        } {
            { Copy-TerminalSemanticValue $Matrix } | Should -Throw '*zero-based, one-dimensional, and non-jagged*'
            { Copy-TerminalSemanticValue $Jagged } | Should -Throw '*zero-based, one-dimensional, and non-jagged*'
            { Copy-TerminalSemanticValue $NonZeroLowerBound } | Should -Throw '*zero-based, one-dimensional, and non-jagged*'
            { ConvertTo-TerminalTaggedValue $Matrix } | Should -Throw '*zero-based, one-dimensional, and non-jagged*'
            { ConvertTo-TerminalTaggedValue $Jagged } | Should -Throw '*zero-based, one-dimensional, and non-jagged*'
            { ConvertTo-TerminalTaggedValue $NonZeroLowerBound } | Should -Throw '*zero-based, one-dimensional, and non-jagged*'
        }

        $copyDeck = New-TerminalPresentation -Title Copy
        $copyDeck | Add-TerminalSlide -Title One -Metadata @{ Unsupported = $nonZeroLowerBound } | Out-Null
        { Copy-TerminalSlide $copyDeck 1 } | Should -Throw '*zero-based, one-dimensional, and non-jagged*'
        $copyDeck.Slides.Count | Should -Be 1

        $exportDeck = New-TerminalPresentation -Title Export -Metadata @{ Unsupported = $nonZeroLowerBound }
        foreach ($format in 'Json', 'Psd1', 'Markdown') {
            $path = Join-Path $TestDrive "unsupported-array.$($format.ToLowerInvariant())"
            { Export-TerminalPresentation $exportDeck $path -Format $format } |
                Should -Throw '*zero-based, one-dimensional, and non-jagged*'
            $path | Should -Not -Exist
        }
    }

    It 'rejects unsupported typed container vectors while object vectors preserve nested values' {
        $typedMaps = [hashtable[]]@(@{ Name = 'Ada' })
        $mixed = [object[]]::new(3)
        $mixed[0] = @{ Enabled = $true }
        $mixed[1] = [int[]](1, 2)
        $mixed[2] = [pscustomobject]@{ Name = 'Grace' }

        InModuleScope TerminalSlides -Parameters @{ TypedMaps = $typedMaps; Mixed = $mixed } {
            $copy = Copy-TerminalSemanticValue $TypedMaps
            $copy.GetType().FullName | Should -BeExactly 'System.Collections.Hashtable[]'
            $copy[0].Name = 'Changed'
            $TypedMaps[0].Name | Should -BeExactly Ada

            { ConvertTo-TerminalTaggedValue $TypedMaps } |
                Should -Throw "*Array element type 'System.Collections.Hashtable' is not supported*"

            $roundtrip = ConvertFrom-TerminalTaggedValue (ConvertTo-TerminalTaggedValue $Mixed)
            $roundtrip.GetType().FullName | Should -BeExactly 'System.Object[]'
            $roundtrip[0].GetType() | Should -Be ([hashtable])
            $roundtrip[1].GetType().FullName | Should -BeExactly 'System.Int32[]'
            $roundtrip[2].GetType().FullName | Should -BeExactly 'System.Management.Automation.PSCustomObject'
        }

        $unsupportedDeck = New-TerminalPresentation -Title Unsupported -Metadata @{ People = $typedMaps }
        foreach ($format in 'Json', 'Psd1', 'Markdown') {
            $path = Join-Path $TestDrive "unsupported-container.$($format.ToLowerInvariant())"
            { Export-TerminalPresentation $unsupportedDeck $path -Format $format } |
                Should -Throw "*Array element type 'System.Collections.Hashtable' is not supported*"
            $path | Should -Not -Exist
        }

        $supportedDeck = New-TerminalPresentation -Title Supported -Metadata @{ Mixed = $mixed }
        foreach ($format in 'Json', 'Psd1', 'Markdown') {
            $path = Join-Path $TestDrive "object-vector.$($format.ToLowerInvariant())"
            Export-TerminalPresentation $supportedDeck $path -Format $format | Out-Null
            $roundtrip = Import-TerminalPresentation $path
            $roundtrip.Metadata.Custom.Mixed.GetType().FullName | Should -BeExactly 'System.Object[]'
            $roundtrip.Metadata.Custom.Mixed[1].GetType().FullName | Should -BeExactly 'System.Int32[]'
        }
    }

    It 'preserves empty and null-bearing vectors through copy and every structured format' {
        $emptyInts = [int[]]@()
        $emptyObjects = [object[]]@()
        $nullObject = [object[]]::new(1)
        $nullObject[0] = $null
        $mixed = [object[]]::new(4)
        $mixed[0] = $null
        $mixed[1] = 'value'
        $mixed[2] = $null
        $mixed[3] = [int[]](1, 2)

        InModuleScope TerminalSlides -Parameters @{
            EmptyInts = $emptyInts
            EmptyObjects = $emptyObjects
            NullObject = $nullObject
            Mixed = $mixed
        } {
            $emptyIntCopy = Copy-TerminalSemanticValue -Value $EmptyInts
            $emptyObjectCopy = Copy-TerminalSemanticValue -Value $EmptyObjects
            $nullCopy = Copy-TerminalSemanticValue -Value $NullObject
            $mixedCopy = Copy-TerminalSemanticValue -Value $Mixed
            $emptyIntCopy.GetType().FullName | Should -BeExactly 'System.Int32[]'
            $emptyIntCopy.Count | Should -Be 0
            $emptyObjectCopy.GetType().FullName | Should -BeExactly 'System.Object[]'
            $emptyObjectCopy.Count | Should -Be 0
            $nullCopy.Count | Should -Be 1
            $nullCopy[0] | Should -BeNullOrEmpty
            $mixedCopy.Count | Should -Be 4
            $mixedCopy[0] | Should -BeNullOrEmpty
            $mixedCopy[2] | Should -BeNullOrEmpty

            $emptyIntRoundtrip = ConvertFrom-TerminalTaggedValue (ConvertTo-TerminalTaggedValue -Value $EmptyInts)
            $emptyObjectRoundtrip = ConvertFrom-TerminalTaggedValue (ConvertTo-TerminalTaggedValue -Value $EmptyObjects)
            $nullRoundtrip = ConvertFrom-TerminalTaggedValue (ConvertTo-TerminalTaggedValue -Value $NullObject)
            $mixedRoundtrip = ConvertFrom-TerminalTaggedValue (ConvertTo-TerminalTaggedValue -Value $Mixed)
            $emptyIntRoundtrip.GetType().FullName | Should -BeExactly 'System.Int32[]'
            $emptyIntRoundtrip.Count | Should -Be 0
            $emptyObjectRoundtrip.GetType().FullName | Should -BeExactly 'System.Object[]'
            $emptyObjectRoundtrip.Count | Should -Be 0
            $nullRoundtrip.GetType().FullName | Should -BeExactly 'System.Object[]'
            $nullRoundtrip.Count | Should -Be 1
            $nullRoundtrip[0] | Should -BeNullOrEmpty
            $mixedRoundtrip.Count | Should -Be 4
            $mixedRoundtrip[0] | Should -BeNullOrEmpty
            $mixedRoundtrip[2] | Should -BeNullOrEmpty
            $mixedRoundtrip[3].GetType().FullName | Should -BeExactly 'System.Int32[]'
        }

        $deck = New-TerminalPresentation -Title Vectors -Metadata @{
            EmptyInts = $emptyInts
            EmptyObjects = $emptyObjects
            NullObject = $nullObject
            Mixed = $mixed
        }
        foreach ($format in 'Json', 'Psd1', 'Markdown') {
            $path = Join-Path $TestDrive "edge-vectors.$($format.ToLowerInvariant())"
            Export-TerminalPresentation $deck $path -Format $format | Out-Null
            $roundtrip = Import-TerminalPresentation $path
            $roundtrip.Metadata.Custom.EmptyInts.GetType().FullName | Should -BeExactly 'System.Int32[]'
            $roundtrip.Metadata.Custom.EmptyInts.Count | Should -Be 0
            $roundtrip.Metadata.Custom.EmptyObjects.GetType().FullName | Should -BeExactly 'System.Object[]'
            $roundtrip.Metadata.Custom.EmptyObjects.Count | Should -Be 0
            $roundtrip.Metadata.Custom.NullObject.Count | Should -Be 1
            $roundtrip.Metadata.Custom.NullObject[0] | Should -BeNullOrEmpty
            $roundtrip.Metadata.Custom.Mixed.Count | Should -Be 4
            $roundtrip.Metadata.Custom.Mixed[0] | Should -BeNullOrEmpty
            $roundtrip.Metadata.Custom.Mixed[2] | Should -BeNullOrEmpty
            $roundtrip.Metadata.Custom.Mixed[3].GetType().FullName | Should -BeExactly 'System.Int32[]'
        }
    }

    It 'deep-copies every supported metadata container and rejects opaque mutable values' {
        InModuleScope TerminalSlides {
            $list = [Collections.ArrayList]::new()
            [void]$list.Add([pscustomobject]@{ Name = 'before' })
            $source = [ordered]@{
                Nested = @{ Values = [int[]](1, 2) }
                List = $list
                Immutable = [uri]'https://example.test'
            }

            $copy = Copy-TerminalSemanticValue $source
            $copy.Nested.Values[0] = 99
            $copy.List[0].Name = 'after'

            $source.Nested.Values[0] | Should -Be 1
            $source.List[0].Name | Should -BeExactly before
            $copy.GetType().FullName | Should -BeExactly 'System.Collections.Specialized.OrderedDictionary'
            $copy.Nested.GetType() | Should -Be ([hashtable])
            $copy.List.GetType() | Should -Be ([Collections.ArrayList])
            { Copy-TerminalSemanticValue ([Collections.Queue]::new()) } | Should -Throw '*Unsupported mutable value type*Queue*'
        }
    }

    It 'preserves all table scalar kinds and treats DateTimeOffset and TimeSpan as scalar rows' {
        InModuleScope TerminalSlides {
            $values = @(
                $null, 'text', [char]'Q', $false, [sbyte]-1, [byte]1, [int16]-2, [uint16]2,
                [int32]-3, [uint32]3, [int64]-4, [uint64]4, [single]1.5, [double]2.5,
                [decimal]3.5, [datetime]'2024-01-02T03:04:05Z',
                [datetimeoffset]'2024-02-03T04:05:06+02:00', [timespan]'01:02:03',
                [guid]'62ae7708-a44f-4b87-af96-d7affc799073'
            )
            foreach ($value in $values) {
                $scalar = ConvertTo-TerminalScalarValue $value
                $actual = ConvertFrom-TerminalScalarValue $scalar
                if ($null -eq $value) { $actual | Should -BeNullOrEmpty }
                else {
                    $actual.GetType() | Should -Be $value.GetType()
                    $actual | Should -Be $value
                }
            }

            $rowValues = [object[]]::new(3)
            $rowValues[0] = $null
            $rowValues[1] = [datetimeoffset]'2024-02-03T04:05:06+02:00'
            $rowValues[2] = [timespan]'01:02:03'
            $rows = ConvertTo-TerminalDataRows $rowValues
            @($rows | ForEach-Object { $_.Cells.Count }) | Should -Be @(1, 1, 1)
            @($rows | ForEach-Object { $_.Cells[0].Value.Kind.ToString() }) | Should -Be @('Null', 'DateTimeOffset', 'TimeSpan')
            (ConvertTo-TerminalDataRows 'single row')[0].Cells[0].Value.Kind.ToString() | Should -BeExactly String
            (ConvertTo-TerminalDataRows ([datetimeoffset]'2024-03-04T05:06:07Z'))[0].Cells[0].Value.Kind.ToString() | Should -BeExactly DateTimeOffset
            (ConvertTo-TerminalDataRows ([ordered]@{ Name = 'Ada'; Score = 10 }))[0].Cells.Count | Should -Be 2
            (ConvertTo-TerminalDataRows $null).Count | Should -Be 0
            { ConvertTo-TerminalScalarValue ([Text.StringBuilder]::new()) } | Should -Throw '*Table values must be scalar*'
        }
    }

    It 'rejects malformed, ambiguous, and over-deep tagged metadata' {
        InModuleScope TerminalSlides {
            (ConvertTo-TerminalTaggedValue $null).Type | Should -BeExactly Null
            {
                $invalidKind = [Enum]::ToObject([TerminalSlides.Schema.V1.ScalarKind], 999)
                ConvertFrom-TerminalScalarValue ([TerminalSlides.Schema.V1.ScalarValue]::new($invalidKind, 'invalid'))
            } | Should -Throw '*Unsupported scalar kind*'
            { ConvertTo-TerminalTaggedValue ([hashtable]@{ 1 = 'numeric key' }) } | Should -Throw '*must be non-empty strings*'
            { ConvertTo-TerminalTaggedValue ([Text.StringBuilder]::new('opaque')) } | Should -Throw '*cannot be persisted safely*'
            { ConvertTo-TerminalTaggedValue 'deep' 33 } | Should -Throw '*supported depth of 32*'
            { ConvertFrom-TerminalTaggedValue ([ordered]@{ Type = 'Null' }) 33 } | Should -Throw '*supported depth of 32*'
            {
                ConvertFrom-TerminalTaggedValue ([ordered]@{
                    Type = 'Map'
                    Entries = @(
                        [ordered]@{ Name = 'same'; Value = [ordered]@{ Type = 'String'; Value = 'one' } }
                        [ordered]@{ Name = 'same'; Value = [ordered]@{ Type = 'String'; Value = 'two' } }
                    )
                })
            } | Should -Throw '*Duplicate metadata key*same*'
            {
                ConvertFrom-TerminalTaggedValue ([ordered]@{ Type = 'Array'; ElementType = 'System.Text.StringBuilder'; Items = @() })
            } | Should -Throw '*Array element type*not supported*'
            { ConvertFrom-TerminalTaggedValue ([ordered]@{ Type = 'Mystery' }) } | Should -Throw '*Unsupported persisted value type*'
            { ConvertFrom-TerminalDataMarker 'not-base64!' } | Should -Throw '*data marker is invalid*'
        }
    }

    It 'binds the visible Markdown projection to its typed envelope' {
        $first = New-TerminalPresentation -Title First
        $first | Add-TerminalSlide -Title One -Content { Add-SlideText ORIGINAL } | Out-Null
        $second = New-TerminalPresentation -Title Second
        $second | Add-TerminalSlide -Title Two -Content { Add-SlideText SWAPPED } | Out-Null
        $firstPath = Join-Path $TestDrive first.md
        $secondPath = Join-Path $TestDrive second.md
        Export-TerminalPresentation $first $firstPath -Format Markdown | Out-Null
        Export-TerminalPresentation $second $secondPath -Format Markdown | Out-Null

        $firstText = [IO.File]::ReadAllText($firstPath)
        $markerPattern = '<!--\s*terminalslides:envelope\s+[A-Za-z0-9+/=]+\s*-->'
        $match = [regex]::Match($firstText, $markerPattern)
        $edited = $firstText.Substring(0, $match.Index).Replace('ORIGINAL', 'EDITED') + $match.Value
        [IO.File]::WriteAllText($firstPath, $edited)
        { Import-TerminalPresentation $firstPath } | Should -Throw '*visible Markdown was edited*'

        $secondMarker = [regex]::Match([IO.File]::ReadAllText($secondPath), $markerPattern).Value
        $swapped = $firstText.Substring(0, $match.Index) + $secondMarker
        [IO.File]::WriteAllText($firstPath, $swapped)
        { Import-TerminalPresentation $firstPath } | Should -Throw '*visible Markdown was edited*'
    }

    It 'uses only the trailing Markdown envelope and rejects malformed or duplicate trailing envelopes' {
        $deck = New-TerminalPresentation -Title Markers
        $markerText = '<!-- terminalslides:envelope AAAA -->'
        $deck | Add-TerminalSlide -Title One -Content { Add-SlideText $markerText } | Out-Null
        $path = Join-Path $TestDrive markers.md
        Export-TerminalPresentation $deck $path -Format Markdown | Out-Null

        $roundtrip = Import-TerminalPresentation $path
        $roundtrip.Slides[0].Elements[0].Payload.Text | Should -BeExactly $markerText

        $raw = [IO.File]::ReadAllText($path)
        $trailingPattern = '<!--\s*terminalslides:envelope\s+[A-Za-z0-9+/=]+\s*-->\s*\z'
        $trailingMarker = [regex]::Match($raw, $trailingPattern).Value
        [IO.File]::WriteAllText($path, $raw + $trailingMarker)
        { Import-TerminalPresentation $path } | Should -Throw '*visible Markdown was edited*'

        $malformedPath = Join-Path $TestDrive malformed-marker.md
        $malformed = [regex]::Replace($raw, $trailingPattern, '<!-- terminalslides:envelope not*base64 -->')
        [IO.File]::WriteAllText($malformedPath, $malformed)
        { Import-TerminalPresentation $malformedPath } | Should -Throw '*envelope is malformed*'
    }

    It 'exports relative media as a deterministic portable sidecar across module reloads' {
        $source = Join-Path $TestDrive source
        $destination = Join-Path $TestDrive destination
        New-Item -ItemType Directory -Path $source, $destination | Out-Null
        [IO.File]::WriteAllBytes((Join-Path $source 'team photo.png'), $script:Pixel)
        Push-Location $source
        try {
            $deck = New-TerminalPresentation -Title Media
            $deck | Add-TerminalSlide -Title Photo -Content { Add-SlideImage -Path 'team photo.png' -AltText 'Team ] photo' } | Out-Null
        }
        finally { Pop-Location }

        Import-Module $script:ModulePath -Force
        $path = Join-Path $destination deck.md
        Export-TerminalPresentation $deck $path -Format Markdown | Out-Null
        $roundtrip = Import-TerminalPresentation $path
        $image = $roundtrip.Slides[0].Elements[0]
        $resolved = Join-Path $destination $image.Payload.Path

        $resolved | Should -Exist
        (Get-FileHash $resolved).Hash | Should -Be (Get-FileHash (Join-Path $source 'team photo.png')).Hash
        [IO.File]::ReadAllText($path) | Should -Match '!\[Team \\] photo\]\(<deck\.md\.assets/[a-f0-9]{64}\.png>\)'
    }

    It 'commits media and document as one recoverable replacement' {
        $imagePath = Join-Path $TestDrive photo.png
        [IO.File]::WriteAllBytes($imagePath, $script:Pixel)
        $deck = New-TerminalPresentation -Title Media
        $deck | Add-TerminalSlide -Title Photo -Content { Add-SlideImage -Path $imagePath -AltText Photo } | Out-Null
        $path = Join-Path $TestDrive deck.json
        Export-TerminalPresentation $deck $path -Format Json | Out-Null
        Join-Path $TestDrive deck.json.assets | Should -Exist

        $withoutMedia = New-TerminalPresentation -Title Clean
        $withoutMedia | Add-TerminalSlide -Title Text -Content { Add-SlideText clean } | Out-Null
        Export-TerminalPresentation $withoutMedia $path -Format Json -Force | Out-Null
        Join-Path $TestDrive deck.json.assets | Should -Exist
        @(Get-ChildItem (Join-Path $TestDrive deck.json.assets) -File).Count | Should -Be 1

        $collision = Join-Path $TestDrive collision
        $oldAssets = Join-Path $TestDrive collision.assets
        New-Item -ItemType Directory -Path $collision, $oldAssets | Out-Null
        Set-Content -LiteralPath (Join-Path $oldAssets old.txt) -Value old
        { Export-TerminalPresentation $deck $collision -Format Json -Force } | Should -Throw
        Join-Path $oldAssets old.txt | Should -Exist
        @(Get-ChildItem $TestDrive -Force | Where-Object Name -Match '^\.collision\.assets\..*\.tmp$|\.backup$').Count | Should -Be 0
    }

    It 'versions the wire contract and explicitly migrates legacy data' {
        $jsonPath = Join-Path $TestDrive current.json
        $deck = New-TerminalPresentation -Title Current
        Export-TerminalPresentation $deck $jsonPath -Format Json | Out-Null
        $wire = Get-Content $jsonPath -Raw | ConvertFrom-Json -AsHashtable
        $wire.SchemaVersion | Should -Be 2
        $wire.'$schema' | Should -BeExactly 'https://terminalslides.dev/schema/presentation/v2'
        $wire.SchemaVersion = 3
        $wire | ConvertTo-Json -Depth 100 | Set-Content $jsonPath
        { Import-TerminalPresentation $jsonPath } | Should -Throw '*Unsupported TerminalSlides schema*'

        $legacyPath = Join-Path $TestDrive legacy.json
        @{ Title='Legacy'; Slides=@(@{ Title='One'; Elements=@(@{ Type='Code'; Content=@{ Code='Get-Date'; Language='powershell' } }) }) } |
            ConvertTo-Json -Depth 10 | Set-Content $legacyPath
        $legacy = Import-TerminalPresentation $legacyPath
        $legacy.Slides[0].Elements[0].Payload | Should -BeOfType TerminalSlides.Schema.V1.CodePayload
        $legacy.Slides[0].Elements[0].Payload.Language | Should -BeExactly powershell
    }

    It 'migrates every legacy payload shape and copies legacy metadata' {
        InModuleScope TerminalSlides {
            $legacy = [ordered]@{
                Title = 'Legacy'
                Subtitle = 'Compatibility'
                Width = 80
                Height = 24
                CreatedDate = '2024-01-02T03:04:05Z'
                ModifiedDate = '2024-02-03T04:05:06Z'
                Configuration = @{ Nested = [ordered]@{ Enabled = $true } }
                Metadata = [ordered]@{
                    Title = 'Metadata title'
                    Subtitle = 'Metadata subtitle'
                    Author = 'Ada'
                    Description = 'Legacy metadata'
                    Version = '0.9'
                    Custom = @{ Audience = 'engineers' }
                }
                Slides = @([ordered]@{
                    Title = 'All elements'
                    Metadata = [ordered]@{ Author = 'Grace'; Custom = @{ Track = 'compatibility' } }
                    Elements = @(
                        [ordered]@{ Type = 'Title'; Content = 'Title'; X = 2; Border = $true }
                        [ordered]@{ Type = 'Subtitle'; Content = 'Subtitle' }
                        [ordered]@{ Type = 'Text'; Content = 'Text' }
                        [ordered]@{ Type = 'Bullet'; Content = 'Bullet' }
                        [ordered]@{ Type = 'Box'; Content = 'Box' }
                        [ordered]@{ Type = 'Code'; Content = 'Get-Date'; Properties = @{ Language = 'powershell' } }
                        [ordered]@{ Type = 'Table'; Content = @([ordered]@{ Name = 'Ada'; Score = 10 }) }
                        [ordered]@{
                            Type = 'Chart'
                            Content = @([ordered]@{ Label = 'A'; Value = 2 })
                            Properties = @{ ChartType = 'Line'; Title = 'Trend' }
                        }
                        [ordered]@{
                            Type = 'Diagram'
                            Content = [ordered]@{
                                Nodes = @([ordered]@{ Id = 'a'; Label = 'A' })
                                Edges = @([ordered]@{ From = 'a'; To = 'a'; Label = 'loop' })
                            }
                        }
                        [ordered]@{ Type = 'Image'; Content = [ordered]@{ Path = 'photo.png'; AltText = 'Photo' } }
                        [ordered]@{ Type = 'Quote'; Content = [ordered]@{ Text = 'Quote'; Attribution = 'Author' } }
                    )
                })
            }

            $presentation = New-PresentationFromData $legacy

            @($presentation.Slides[0].Elements | ForEach-Object { $_.Kind.ToString() }) | Should -Be @(
                'Title', 'Subtitle', 'Text', 'Bullet', 'Box', 'Code', 'Table', 'Chart', 'Diagram', 'Image', 'Quote'
            )
            $presentation.Slides[0].Elements[0].X | Should -Be 2
            $presentation.Slides[0].Elements[0].Border | Should -BeTrue
            $presentation.Slides[0].Elements[5].Payload.Language | Should -BeExactly powershell
            $presentation.Slides[0].Elements[6].Payload.Rows[0].Cells[1].Value.Kind.ToString() | Should -BeExactly Int32
            $presentation.Slides[0].Elements[7].Payload.ChartKind.ToString() | Should -BeExactly Line
            $presentation.Slides[0].Elements[8].Payload.Edges[0].Label | Should -BeExactly loop
            $presentation.Slides[0].Elements[9].Payload.AltText | Should -BeExactly Photo
            $presentation.Slides[0].Elements[10].Payload.Attribution | Should -BeExactly Author
            $presentation.Metadata.Custom.Audience | Should -BeExactly engineers
            $presentation.Slides[0].Metadata.Custom.Track | Should -BeExactly compatibility

            $presentation.Configuration.Nested.Enabled = $false
            $presentation.Metadata.Custom.Audience = 'changed'
            $legacy.Configuration.Nested.Enabled | Should -BeTrue
            $legacy.Metadata.Custom.Audience | Should -BeExactly engineers
        }
    }

    It 'rejects malformed current and legacy migration boundaries' {
        InModuleScope TerminalSlides {
            {
                New-PresentationFromData ([ordered]@{
                    '$schema' = 'https://terminalslides.dev/schema/presentation/v1'
                    SchemaVersion = 1
                    Presentation = [ordered]@{ Title = 'Minimal'; Slides = @() }
                })
            } | Should -Throw "*field 'Subtitle' is required*"
            $current = ConvertTo-PresentationData (New-TerminalPresentation -Title Current)
            $invalidPresentation = ConvertFrom-TerminalWireJson (ConvertTo-TerminalWireJson $current)
            $invalidPresentation.Presentation = 'not an object'
            { New-PresentationFromData $invalidPresentation } | Should -Throw '*Presentation must be an object*'
            $invalidDimensions = ConvertFrom-TerminalWireJson (ConvertTo-TerminalWireJson $current)
            $invalidDimensions.Presentation.Width = 19
            $invalidDimensions.Presentation.Height = 10
            { New-PresentationFromData $invalidDimensions } | Should -Throw '*dimensions must be automatic*'
            {
                New-PresentationFromData ([ordered]@{ Width = 20; Height = 9; Slides = @() })
            } | Should -Throw '*dimensions must be automatic*'
            {
                New-PresentationFromData ([ordered]@{ Slides = @([ordered]@{ Elements = @([ordered]@{ Content = 'missing type' }) }) })
            } | Should -Throw '*require a Type*'
        }
    }
}
