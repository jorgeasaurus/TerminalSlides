$script:TerminalSlidesMaximumValueDepth = 32

function Get-TerminalSlideMaximumRevealStep {
    param([Parameter(Mandatory)][TerminalSlides.Schema.V1.Slide]$Slide)

    $maximum = 0
    foreach ($element in $Slide.Elements) {
        if ($element.RevealStep -lt 0) {
            throw "Slide element reveal step '$($element.RevealStep)' must be non-negative."
        }
        if ($element.RevealStep -gt $maximum) { $maximum = $element.RevealStep }
    }
    return $maximum
}

function New-TerminalSemanticTraversalContext {
    return [pscustomobject]@{
        MaximumDepth = $script:TerminalSlidesMaximumValueDepth
        ActiveReferences = [Collections.Generic.HashSet[object]]::new(
            [Collections.Generic.ReferenceEqualityComparer]::Instance
        )
    }
}

function Assert-TerminalSemanticTraversalDepth {
    param(
        [int]$Depth,
        [int]$MaximumDepth = $script:TerminalSlidesMaximumValueDepth
    )

    if ($Depth -gt $MaximumDepth) {
        throw "Metadata exceeds the supported depth of $MaximumDepth."
    }
}

function Enter-TerminalSemanticReference {
    param(
        [Parameter(Mandatory)][object]$Value,
        [Parameter(Mandatory)][psobject]$TraversalContext
    )

    if (-not $TraversalContext.ActiveReferences.Add($Value)) {
        throw "Metadata contains a reference cycle at type '$($Value.GetType().FullName)'."
    }
}

function Exit-TerminalSemanticReference {
    param(
        [Parameter(Mandatory)][object]$Value,
        [Parameter(Mandatory)][psobject]$TraversalContext
    )

    [void]$TraversalContext.ActiveReferences.Remove($Value)
}

function Set-TerminalMediaOrigin {
    param(
        [Parameter(Mandatory)][TerminalSlides.Schema.V1.SlideElement]$Element,
        [Parameter(Mandatory)][string]$Directory
    )

    [TerminalSlides.Schema.V1.MediaOriginRegistry]::Set($Element, [IO.Path]::GetFullPath($Directory))
}

function Get-TerminalMediaOrigin {
    param([Parameter(Mandatory)][TerminalSlides.Schema.V1.SlideElement]$Element)

    return [TerminalSlides.Schema.V1.MediaOriginRegistry]::Get($Element)
}

function Get-TerminalSemanticProperty {
    param(
        [AllowNull()][object]$InputObject,
        [Parameter(Mandatory)][string]$Name
    )

    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [System.Collections.IDictionary]) { return $InputObject[$Name] }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $null
}

function Assert-TerminalSupportedArrayShape {
    param([Parameter(Mandatory)][Type]$ArrayType)

    if (-not $ArrayType.IsSZArray -or $ArrayType.GetElementType().IsArray) {
        throw "Metadata arrays must be zero-based, one-dimensional, and non-jagged. Type '$($ArrayType.FullName)' is not supported."
    }
}

function ConvertFrom-TerminalDateTimeText {
    param([Parameter(Mandatory)][string]$Text)

    $culture = [Globalization.CultureInfo]::InvariantCulture
    if ($Text -match '[+-][0-9]{2}:[0-9]{2}\z') {
        $offsetValue = [datetimeoffset]::Parse($Text, $culture, [Globalization.DateTimeStyles]::RoundtripKind)
        return $offsetValue.LocalDateTime
    }
    return [datetime]::Parse($Text, $culture, [Globalization.DateTimeStyles]::RoundtripKind)
}

function Assert-TerminalUnambiguousDictionaryKeys {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Dictionary)

    Assert-TerminalUnambiguousNames -Names @($Dictionary.Keys) -Subject 'Metadata dictionary keys' -Item 'metadata key'
}

function Get-TerminalCanonicalDictionaryKeys {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Dictionary)

    $keys = [string[]]@($Dictionary.Keys)
    if ($Dictionary -isnot [System.Collections.Specialized.OrderedDictionary]) {
        [Array]::Sort($keys, [StringComparer]::Ordinal)
    }
    return $keys
}

function Assert-TerminalUnambiguousNames {
    param(
        [AllowEmptyCollection()][object[]]$Names,
        [Parameter(Mandatory)][string]$Subject,
        [Parameter(Mandatory)][string]$Item
    )

    $keys = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($name in $Names) {
        if ($null -eq $name -or $name -isnot [string] -or $name.Length -eq 0) {
            throw "$Subject must be non-empty strings."
        }
        if (-not $keys.Add($name)) {
            throw "$Subject must be unique ignoring case. Duplicate $Item '$name'."
        }
    }
}

function Copy-TerminalSemanticValue {
    param(
        [AllowNull()][object]$Value,
        [int]$Depth = 0,
        [AllowNull()][psobject]$TraversalContext
    )

    if ($null -eq $TraversalContext) { $TraversalContext = New-TerminalSemanticTraversalContext }
    Assert-TerminalSemanticTraversalDepth -Depth $Depth -MaximumDepth $TraversalContext.MaximumDepth

    if ($null -eq $Value -or $Value -is [string] -or $Value.GetType().IsValueType -or
        $Value -is [uri] -or $Value -is [version] -or $Value -is [regex] -or
        $Value -is [scriptblock]) {
        return $Value
    }

    Enter-TerminalSemanticReference -Value $Value -TraversalContext $TraversalContext
    try {
        if ($Value -is [System.Collections.Specialized.OrderedDictionary]) {
            Assert-TerminalUnambiguousDictionaryKeys -Dictionary $Value
            $copy = [ordered]@{}
            foreach ($key in $Value.Keys) {
                $copy[$key] = Copy-TerminalSemanticValue -Value $Value[$key] -Depth ($Depth + 1) -TraversalContext $TraversalContext
            }
            return $copy
        }
        if ($Value -is [hashtable]) {
            Assert-TerminalUnambiguousDictionaryKeys -Dictionary $Value
            $copy = @{}
            foreach ($key in $Value.Keys) {
                $copy[$key] = Copy-TerminalSemanticValue -Value $Value[$key] -Depth ($Depth + 1) -TraversalContext $TraversalContext
            }
            return $copy
        }
        if ($Value.GetType().IsArray) {
            Assert-TerminalSupportedArrayShape -ArrayType $Value.GetType()
            $elementType = $Value.GetType().GetElementType()
            $copy = [Array]::CreateInstance($elementType, $Value.Length)
            for ($index = 0; $index -lt $Value.Length; $index++) {
                $item = Copy-TerminalSemanticValue -Value $Value.GetValue($index) -Depth ($Depth + 1) -TraversalContext $TraversalContext
                $copy.SetValue($item, $index)
            }
            return ,$copy
        }
        if ($Value -is [System.Collections.ArrayList]) {
            $copy = [System.Collections.ArrayList]::new($Value.Count)
            foreach ($item in $Value) {
                [void]$copy.Add((Copy-TerminalSemanticValue -Value $item -Depth ($Depth + 1) -TraversalContext $TraversalContext))
            }
            return ,$copy
        }
        if ($Value -is [System.Management.Automation.PSCustomObject]) {
            $copy = [ordered]@{}
            foreach ($property in $Value.PSObject.Properties) {
                $copy[$property.Name] = Copy-TerminalSemanticValue -Value $property.Value -Depth ($Depth + 1) -TraversalContext $TraversalContext
            }
            return [pscustomobject]$copy
        }

        throw "Unsupported mutable value type '$($Value.GetType().FullName)'. Use primitives, arrays, hashtables, ordered dictionaries, or PSCustomObject values."
    }
    finally {
        Exit-TerminalSemanticReference -Value $Value -TraversalContext $TraversalContext
    }
}

function ConvertTo-TerminalScalarValue {
    param([AllowNull()][object]$Value)

    $culture = [Globalization.CultureInfo]::InvariantCulture
    if ($null -eq $Value) {
        return [TerminalSlides.Schema.V1.ScalarValue]::new('Null', [Management.Automation.Language.NullString]::Value)
    }
    if ($Value -is [string]) { return [TerminalSlides.Schema.V1.ScalarValue]::new('String', [string]$Value) }
    if ($Value -is [char]) { return [TerminalSlides.Schema.V1.ScalarValue]::new('Char', [string]$Value) }
    if ($Value -is [bool]) { return [TerminalSlides.Schema.V1.ScalarValue]::new('Boolean', $Value.ToString($culture)) }
    if ($Value -is [sbyte]) { return [TerminalSlides.Schema.V1.ScalarValue]::new('SByte', $Value.ToString($culture)) }
    if ($Value -is [byte]) { return [TerminalSlides.Schema.V1.ScalarValue]::new('Byte', $Value.ToString($culture)) }
    if ($Value -is [int16]) { return [TerminalSlides.Schema.V1.ScalarValue]::new('Int16', $Value.ToString($culture)) }
    if ($Value -is [uint16]) { return [TerminalSlides.Schema.V1.ScalarValue]::new('UInt16', $Value.ToString($culture)) }
    if ($Value -is [int32]) { return [TerminalSlides.Schema.V1.ScalarValue]::new('Int32', $Value.ToString($culture)) }
    if ($Value -is [uint32]) { return [TerminalSlides.Schema.V1.ScalarValue]::new('UInt32', $Value.ToString($culture)) }
    if ($Value -is [int64]) { return [TerminalSlides.Schema.V1.ScalarValue]::new('Int64', $Value.ToString($culture)) }
    if ($Value -is [uint64]) { return [TerminalSlides.Schema.V1.ScalarValue]::new('UInt64', $Value.ToString($culture)) }
    if ($Value -is [single]) { return [TerminalSlides.Schema.V1.ScalarValue]::new('Single', $Value.ToString('R', $culture)) }
    if ($Value -is [double]) { return [TerminalSlides.Schema.V1.ScalarValue]::new('Double', $Value.ToString('R', $culture)) }
    if ($Value -is [decimal]) { return [TerminalSlides.Schema.V1.ScalarValue]::new('Decimal', $Value.ToString($culture)) }
    if ($Value -is [datetime]) { return [TerminalSlides.Schema.V1.ScalarValue]::new('DateTime', $Value.ToString('o', $culture)) }
    if ($Value -is [datetimeoffset]) { return [TerminalSlides.Schema.V1.ScalarValue]::new('DateTimeOffset', $Value.ToString('o', $culture)) }
    if ($Value -is [timespan]) { return [TerminalSlides.Schema.V1.ScalarValue]::new('TimeSpan', $Value.ToString('c', $culture)) }
    if ($Value -is [guid]) { return [TerminalSlides.Schema.V1.ScalarValue]::new('Guid', $Value.ToString('D')) }

    throw "Table values must be scalar. '$($Value.GetType().FullName)' is not supported."
}

function ConvertFrom-TerminalScalarValue {
    param([Parameter(Mandatory)][TerminalSlides.Schema.V1.ScalarValue]$Value)

    $culture = [Globalization.CultureInfo]::InvariantCulture
    switch ($Value.Kind.ToString()) {
        'Null' { return $null }
        'String' { return $Value.Value }
        'Char' { return [char]$Value.Value }
        'Boolean' { return [bool]::Parse($Value.Value) }
        'SByte' { return [sbyte]::Parse($Value.Value, $culture) }
        'Byte' { return [byte]::Parse($Value.Value, $culture) }
        'Int16' { return [int16]::Parse($Value.Value, $culture) }
        'UInt16' { return [uint16]::Parse($Value.Value, $culture) }
        'Int32' { return [int32]::Parse($Value.Value, $culture) }
        'UInt32' { return [uint32]::Parse($Value.Value, $culture) }
        'Int64' { return [int64]::Parse($Value.Value, $culture) }
        'UInt64' { return [uint64]::Parse($Value.Value, $culture) }
        'Single' { return [single]::Parse($Value.Value, $culture) }
        'Double' { return [double]::Parse($Value.Value, $culture) }
        'Decimal' { return [decimal]::Parse($Value.Value, $culture) }
        'DateTime' { return ConvertFrom-TerminalDateTimeText -Text $Value.Value }
        'DateTimeOffset' { return [datetimeoffset]::ParseExact($Value.Value, 'o', $culture, [Globalization.DateTimeStyles]::RoundtripKind) }
        'TimeSpan' { return [timespan]::ParseExact($Value.Value, 'c', $culture) }
        'Guid' { return [guid]::ParseExact($Value.Value, 'D') }
        default { throw "Unsupported scalar kind '$($Value.Kind)'." }
    }
}

function Assert-TerminalTableColumnIdentity {
    param([Parameter(Mandatory)][AllowEmptyCollection()][TerminalSlides.Schema.V1.DataRow[]]$Rows)

    $names = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($row in $Rows) {
        Assert-TerminalRequiredModelValue -Value $row -Subject 'Table row'
        $rowNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($cell in $row.Cells) {
            Assert-TerminalRequiredModelValue -Value $cell -Subject 'Table cell'
            if (-not $rowNames.Add($cell.Name)) {
                throw "Table column names must be unique ignoring case. Duplicate table column '$($cell.Name)'."
            }
            if ($names.ContainsKey($cell.Name) -and $names[$cell.Name] -cne $cell.Name) {
                throw 'Table column names must be unique ignoring case.'
            }
            if (-not $names.ContainsKey($cell.Name)) { $names.Add($cell.Name, $cell.Name) }
        }
    }
}

function Assert-TerminalDiagramNodeIdentity {
    param([Parameter(Mandatory)][TerminalSlides.Schema.V1.DiagramNode[]]$Nodes)

    $identifiers = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($node in $Nodes) {
        Assert-TerminalRequiredModelValue -Value $node -Subject 'Diagram node'
        if (-not $identifiers.Add($node.Id)) {
            throw "Diagram node IDs must be unique ignoring case. Duplicate node ID '$($node.Id)'."
        }
    }
}

function Assert-TerminalRequiredModelValue {
    param(
        [Parameter(Mandatory)][AllowNull()][object]$Value,
        [Parameter(Mandatory)][string]$Subject
    )

    if ($null -eq $Value) { throw "$Subject must not be null." }
}

function Assert-TerminalWireReadyPresentationModel {
    param([Parameter(Mandatory)][TerminalSlides.Schema.V1.TerminalPresentation]$Presentation)

    if ($Presentation.Width -lt 0 -or $Presentation.Height -lt 0 -or
        ($Presentation.Width -gt 0 -and $Presentation.Width -lt 20) -or
        ($Presentation.Height -gt 0 -and $Presentation.Height -lt 10)) {
        throw 'Presentation dimensions must be automatic (0) or at least 20x10.'
    }
    Assert-TerminalRequiredModelValue -Value $Presentation.Metadata -Subject 'Presentation Metadata'
    Assert-TerminalRequiredModelValue -Value $Presentation.Metadata.Custom -Subject 'Presentation Metadata Custom map'
    Assert-TerminalRequiredModelValue -Value $Presentation.Configuration -Subject 'Presentation Configuration map'
    Assert-TerminalRequiredModelValue -Value $Presentation.Slides -Subject 'Presentation Slides collection'
    $theme = Resolve-TerminalPresentationTheme -Presentation $Presentation
    Assert-TerminalRequiredModelValue -Value $theme.Metadata -Subject 'Presentation theme Metadata map'
    foreach ($field in 'Name','CodeTheme','BulletSymbol') {
        if ([string]::IsNullOrWhiteSpace($theme.$field)) { throw "Presentation theme $field must be nonblank." }
    }
    foreach ($field in 'Background','Foreground','Primary','Accent','Muted','Heading','Border','ErrorColor','WarningColor','SuccessColor') {
        [void](Read-TerminalWireHexColor $theme.$field "Presentation theme $field")
    }
    foreach ($field in 'CodeBackground','CodeForeground') {
        [void](Read-TerminalWireHexColor $theme.$field "Presentation theme $field" -AllowDefault)
    }
    [void](Read-TerminalWireDomainName $theme.BoxDrawingStyle @('unicode','ascii','double','rounded','single') 'Presentation theme BoxDrawingStyle')
    [void](Read-TerminalWireDomainName $theme.HeadingStyle @('plain','bold','banner') 'Presentation theme HeadingStyle')
    if (-not $theme.ChartPalette -or $theme.ChartPalette.Count -eq 0) { throw 'Presentation theme ChartPalette must not be empty.' }
    foreach ($color in $theme.ChartPalette) { [void](Read-TerminalWireHexColor $color 'Presentation theme ChartPalette') }

    [void](Read-TerminalWireDomainName $Presentation.DefaultLayout $script:TerminalSlideLayouts 'Presentation DefaultLayout')
    foreach ($slide in $Presentation.Slides) {
        Assert-TerminalRequiredModelValue -Value $slide -Subject 'Presentation slide'
        if ($slide.Index -lt 0) { throw "Slide Index '$($slide.Index)' must be non-negative." }
        Assert-TerminalRequiredModelValue -Value $slide.Metadata -Subject 'Slide Metadata'
        Assert-TerminalRequiredModelValue -Value $slide.Metadata.Custom -Subject 'Slide Metadata Custom map'
        Assert-TerminalRequiredModelValue -Value $slide.Elements -Subject 'Slide Elements collection'
        [void](Get-TerminalSlideMaximumRevealStep -Slide $slide)
        $layout = Read-TerminalWireDomainName $slide.Layout $script:TerminalSlideLayouts 'Slide Layout'
        [void](Read-TerminalWireHexColor $slide.Background 'Slide Background' -AllowDefault)
        $regions = Get-LayoutRegions -Layout $layout -Width 20 -Height 10
        $supportedRegions = @(Get-TerminalElementRegionNames -Regions $regions)
        $usedRegions = [Collections.Generic.List[string]]::new()
        foreach ($element in $slide.Elements) {
            Assert-TerminalRequiredModelValue -Value $element -Subject 'Slide element'
            foreach ($field in 'X','Y','Width','Height','Padding') {
                if ($element.$field -lt 0) { throw "Slide element $field '$($element.$field)' must be non-negative." }
            }
            if ($element.Kind -eq [TerminalSlides.Schema.V1.ElementKind]::Diagram) {
                Assert-TerminalDiagramNodeIdentity -Nodes ([TerminalSlides.Schema.V1.DiagramNode[]]@($element.Payload.Nodes))
                foreach ($edge in $element.Payload.Edges) { Assert-TerminalRequiredModelValue -Value $edge -Subject 'Diagram edge' }
            }
            if ($element.Kind -eq [TerminalSlides.Schema.V1.ElementKind]::Table) {
                Assert-TerminalTableColumnIdentity -Rows ([TerminalSlides.Schema.V1.DataRow[]]@($element.Payload.Rows))
                foreach ($row in $element.Payload.Rows) {
                    foreach ($cell in $row.Cells) {
                        Assert-TerminalRequiredModelValue -Value $cell.Value -Subject 'Table cell value'
                        if ($cell.Value.Kind -eq [TerminalSlides.Schema.V1.ScalarKind]::Null) {
                            if ($null -ne $cell.Value.Value) { throw 'Null table cell values must contain null text.' }
                            continue
                        }
                        try { $decoded = ConvertFrom-TerminalScalarValue $cell.Value }
                        catch { throw "Table cell '$($cell.Name)' contains an invalid $($cell.Value.Kind) value: $($_.Exception.Message)" }
                        if ($cell.Value.Kind -eq [TerminalSlides.Schema.V1.ScalarKind]::DateTime) {
                            Assert-TerminalCanonicalTaggedScalarText -Type DateTime -Value $cell.Value.Value
                        }
                        else {
                            $canonical = ConvertTo-TerminalScalarValue $decoded
                            if ($canonical.Kind -ne $cell.Value.Kind -or $canonical.Value -cne $cell.Value.Value) {
                                throw "Table cell '$($cell.Name)' contains a noncanonical $($cell.Value.Kind) value."
                            }
                        }
                    }
                }
            }
            if ($element.Kind -eq [TerminalSlides.Schema.V1.ElementKind]::Chart) {
                if (-not [Enum]::IsDefined([TerminalSlides.Schema.V1.ChartKind], $element.Payload.ChartKind)) {
                    throw "Chart payload ChartKind '$($element.Payload.ChartKind)' is unsupported."
                }
                foreach ($point in $element.Payload.Points) { Assert-TerminalRequiredModelValue -Value $point -Subject 'Chart point' }
            }
            $region = Read-TerminalWireDomainName $element.Region $script:TerminalElementRegionOrder 'Slide element Region'
            if ($region -notin $supportedRegions) { throw "Region '$region' is not available in layout '$layout'." }
            $usedRegions.Add($region)
            [void](Read-TerminalWireDomainName $element.Alignment @('Left','Center','Right') 'Slide element Alignment')
            [void](Read-TerminalWireDomainName $element.VerticalAlignment @('Top','Middle','Bottom') 'Slide element VerticalAlignment')
            [void](Read-TerminalWireDomainName $element.BorderStyle @('unicode','ascii','double','rounded','single') 'Slide element BorderStyle')
            [void](Read-TerminalWireDomainName $element.OverflowBehavior @('Wrap','Truncate','Scroll') 'Slide element OverflowBehavior')
            [void](Read-TerminalWireHexColor $element.ForegroundColor 'Slide element ForegroundColor' -AllowDefault)
            [void](Read-TerminalWireHexColor $element.BackgroundColor 'Slide element BackgroundColor' -AllowDefault)
        }
        Assert-TerminalElementRegionCombination -Layout $layout -Regions $regions -RegionNames $usedRegions.ToArray()
    }
}

function ConvertTo-TerminalDataRows {
    param([AllowNull()][object]$Data)

    if ($null -eq $Data) { return ,([TerminalSlides.Schema.V1.DataRow[]]@()) }
    $rows = if ($Data -is [System.Collections.IDictionary] -or $Data -is [string]) { @($Data) }
        elseif ($Data -is [System.Collections.IEnumerable]) { @($Data) }
        else { @($Data) }

    $typedRows = foreach ($row in $rows) {
        $cells = [Collections.Generic.List[TerminalSlides.Schema.V1.DataCell]]::new()
        if ($row -is [System.Collections.IDictionary]) {
            Assert-TerminalUnambiguousNames -Names @($row.Keys) -Subject 'Table column names' -Item 'table column'
            foreach ($name in (Get-TerminalCanonicalDictionaryKeys -Dictionary $row)) {
                $cells.Add([TerminalSlides.Schema.V1.DataCell]::new([string]$name, (ConvertTo-TerminalScalarValue $row[$name])))
            }
        }
        elseif ($null -eq $row -or $row -is [string] -or $row.GetType().IsPrimitive -or
            $row -is [decimal] -or $row -is [datetime] -or $row -is [datetimeoffset] -or
            $row -is [timespan] -or $row -is [guid]) {
            $cells.Add([TerminalSlides.Schema.V1.DataCell]::new('Value', (ConvertTo-TerminalScalarValue $row)))
        }
        else {
            $properties = @($row.PSObject.Properties | Where-Object MemberType -in NoteProperty, Property)
            Assert-TerminalUnambiguousNames -Names @($properties.Name) -Subject 'Table column names' -Item 'table column'
            foreach ($property in $properties) {
                $cells.Add([TerminalSlides.Schema.V1.DataCell]::new($property.Name, (ConvertTo-TerminalScalarValue $property.Value)))
            }
        }
        [TerminalSlides.Schema.V1.DataRow]::new($cells.ToArray())
    }
    $result = [TerminalSlides.Schema.V1.DataRow[]]@($typedRows)
    Assert-TerminalTableColumnIdentity -Rows $result
    return ,$result
}

function ConvertFrom-TerminalDataRows {
    param([Parameter(Mandatory)][Collections.Generic.IReadOnlyList[TerminalSlides.Schema.V1.DataRow]]$Rows)

    return @(
        foreach ($row in $Rows) {
            $record = [ordered]@{}
            foreach ($cell in $row.Cells) { $record[$cell.Name] = ConvertFrom-TerminalScalarValue $cell.Value }
            [pscustomobject]$record
        }
    )
}

function Copy-TerminalElementPayload {
    param([Parameter(Mandatory)][TerminalSlides.Schema.V1.ElementPayload]$Payload)

    switch ($Payload.GetType().Name) {
        'TextPayload' { return [TerminalSlides.Schema.V1.TextPayload]::new($Payload.Text) }
        'CodePayload' { return [TerminalSlides.Schema.V1.CodePayload]::new($Payload.Code, $Payload.Language) }
        'ImagePayload' { return [TerminalSlides.Schema.V1.ImagePayload]::new($Payload.Path, $Payload.AltText) }
        'QuotePayload' { return [TerminalSlides.Schema.V1.QuotePayload]::new($Payload.Text, $Payload.Attribution) }
        'ChartPayload' {
            $points = @($Payload.Points | ForEach-Object { [TerminalSlides.Schema.V1.ChartPoint]::new($_.Label, $_.Value) })
            return [TerminalSlides.Schema.V1.ChartPayload]::new([TerminalSlides.Schema.V1.ChartPoint[]]$points, $Payload.ChartKind, $Payload.Title)
        }
        'DiagramPayload' {
            $nodes = @($Payload.Nodes | ForEach-Object { [TerminalSlides.Schema.V1.DiagramNode]::new($_.Id, $_.Label) })
            $edges = @($Payload.Edges | ForEach-Object { [TerminalSlides.Schema.V1.DiagramEdge]::new($_.From, $_.To, $_.Label) })
            return [TerminalSlides.Schema.V1.DiagramPayload]::new([TerminalSlides.Schema.V1.DiagramNode[]]$nodes, [TerminalSlides.Schema.V1.DiagramEdge[]]$edges)
        }
        'TablePayload' {
            $rows = foreach ($row in $Payload.Rows) {
                $cells = @($row.Cells | ForEach-Object {
                    $scalarText = if ($null -eq $_.Value.Value) {
                        [Management.Automation.Language.NullString]::Value
                    }
                    else { $_.Value.Value }
                    [TerminalSlides.Schema.V1.DataCell]::new(
                        $_.Name,
                        [TerminalSlides.Schema.V1.ScalarValue]::new($_.Value.Kind, $scalarText)
                    )
                })
                [TerminalSlides.Schema.V1.DataRow]::new([TerminalSlides.Schema.V1.DataCell[]]$cells)
            }
            return [TerminalSlides.Schema.V1.TablePayload]::new([TerminalSlides.Schema.V1.DataRow[]]@($rows))
        }
    }
}

function Copy-TerminalSlideElement {
    param([Parameter(Mandatory)][TerminalSlides.Schema.V1.SlideElement]$Element)

    $copy = [TerminalSlides.Schema.V1.SlideElement]::new($Element.Kind, (Copy-TerminalElementPayload $Element.Payload))
    foreach ($property in 'Id','Region','X','Y','Width','Height','Alignment','VerticalAlignment','Padding','ForegroundColor','BackgroundColor','Border','BorderStyle','RevealStep','OverflowBehavior') {
        $copy.$property = $Element.$property
    }
    $origin = Get-TerminalMediaOrigin $Element
    if ($origin) { Set-TerminalMediaOrigin -Element $copy -Directory $origin }
    return $copy
}

function Copy-TerminalSlideModel {
    param([Parameter(Mandatory)][TerminalSlides.Schema.V1.Slide]$Slide)

    $copy = [TerminalSlides.Schema.V1.Slide]::new()
    foreach ($property in 'Id','Index','Title','Layout','Notes','Background','Transition','Hidden') { $copy.$property = $Slide.$property }
    $copy.Metadata.Author = $Slide.Metadata.Author
    $copy.Metadata.Custom = Copy-TerminalSemanticValue $Slide.Metadata.Custom
    foreach ($element in $Slide.Elements) { $copy.Elements.Add((Copy-TerminalSlideElement $element)) }
    $copy.MaxRevealStep = Get-TerminalSlideMaximumRevealStep -Slide $copy
    return $copy
}

function Copy-TerminalThemeDefinition {
    param([Parameter(Mandatory)][TerminalSlides.Schema.V1.ThemeDefinition]$Theme)

    $copy = [TerminalSlides.Schema.V1.ThemeDefinition]::new()
    foreach ($property in 'Name','Background','Foreground','Primary','Accent','Muted','Heading','Border','CodeTheme',
        'CodeBackground','CodeForeground','BulletSymbol','BoxDrawingStyle','HeadingStyle','ErrorColor','WarningColor','SuccessColor') {
        $copy.$property = $Theme.$property
    }
    $copy.ChartPalette = [string[]]@($Theme.ChartPalette)
    $copy.Metadata = if ($Theme.Metadata) { Copy-TerminalSemanticValue $Theme.Metadata } else { @{} }
    return $copy
}

function Resolve-TerminalPresentationTheme {
    param([Parameter(Mandatory)][TerminalSlides.Schema.V1.TerminalPresentation]$Presentation)

    if ($Presentation.EmbeddedTheme -and [string]::Equals(
        $Presentation.Theme, $Presentation.EmbeddedTheme.Name, [StringComparison]::OrdinalIgnoreCase
    )) { return $Presentation.EmbeddedTheme }
    return Get-ResolvedTheme -Name $Presentation.Theme
}

function New-TerminalPresentationView {
    param([Parameter(Mandatory)][TerminalSlides.Schema.V1.TerminalPresentation]$Presentation)

    $view = [TerminalSlides.Schema.V1.TerminalPresentation]::new()
    foreach ($property in 'Title','Subtitle','Author','Description','Theme','Width','Height','DefaultTransition','DefaultLayout','CreatedDate','ModifiedDate') { $view.$property = $Presentation.$property }
    if ($Presentation.EmbeddedTheme) { $view.EmbeddedTheme = Copy-TerminalThemeDefinition $Presentation.EmbeddedTheme }
    foreach ($property in 'Title','Subtitle','Author','Description','Version') { $view.Metadata.$property = $Presentation.Metadata.$property }
    $view.Metadata.Custom = Copy-TerminalSemanticValue $Presentation.Metadata.Custom
    $view.Configuration = Copy-TerminalSemanticValue $Presentation.Configuration
    foreach ($slide in $Presentation.Slides) {
        if ($slide.Hidden) { continue }
        $copy = Copy-TerminalSlideModel $slide
        $copy.Hidden = $false
        $copy.Index = $view.Slides.Count + 1
        $view.Slides.Add($copy)
    }
    return $view
}

function Get-TerminalElementPayload {
    param([Parameter(Mandatory)][TerminalSlides.Schema.V1.SlideElement]$Element)

    $payload = $Element.Payload
    $result = [ordered]@{
        Kind = $Element.Kind.ToString(); Text = ''; Code = ''; Language = ''; Rows = @(); Title = ''
        ChartType = ''; Nodes = @(); Edges = @(); Path = ''; AltText = ''; Attribution = ''
        SourceDirectory = (Get-TerminalMediaOrigin $Element); Raw = $null
    }
    switch ($Element.Kind.ToString()) {
        { $_ -in 'Title','Subtitle','Text','Bullet','Box' } { $result.Text = $payload.Text; $result.Raw = $payload.Text }
        'Code' { $result.Code = $payload.Code; $result.Language = $payload.Language; $result.Raw = $payload.Code }
        'Table' { $result.Rows = @(ConvertFrom-TerminalDataRows $payload.Rows); $result.Raw = $result.Rows }
        'Chart' {
            $result.Rows = @($payload.Points | ForEach-Object { [pscustomobject]@{ Label = $_.Label; Value = $_.Value } })
            $result.ChartType = $payload.ChartKind.ToString(); $result.Title = $payload.Title; $result.Raw = $result.Rows
        }
        'Diagram' { $result.Nodes = @($payload.Nodes); $result.Edges = @($payload.Edges); $result.Raw = $payload }
        'Image' { $result.Path = $payload.Path; $result.AltText = $payload.AltText; $result.Raw = $payload.Path }
        'Quote' { $result.Text = $payload.Text; $result.Attribution = $payload.Attribution; $result.Raw = $payload.Text }
    }
    return [pscustomobject]$result
}
