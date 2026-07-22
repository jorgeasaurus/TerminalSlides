$script:TerminalSlidesLegacyWireSchema = 'https://terminalslides.dev/schema/presentation/v1'
$script:TerminalSlidesLegacyWireVersion = 1
$script:TerminalSlidesWireSchema = 'https://terminalslides.dev/schema/presentation/v2'
$script:TerminalSlidesWireVersion = 2
$script:TerminalSlidesDateTimePrefix = 'terminalslides:datetime:'
$script:TerminalSlidesDateTimeOffsetPrefix = 'terminalslides:datetimeoffset:'
$script:TerminalSlidesWireDepthPerSemanticLevel = 3
$script:TerminalSlidesWireEnvelopeDepth = 8
$script:TerminalSlidesMaximumWireDepth = $script:TerminalSlidesWireEnvelopeDepth +
    (($script:TerminalSlidesMaximumValueDepth + 1) * $script:TerminalSlidesWireDepthPerSemanticLevel)
$script:TerminalSlidesPersistedArrayElementTypes = @{
    'System.Object'=[object]; 'System.String'=[string]; 'System.Char'=[char]; 'System.Boolean'=[bool]; 'System.Byte'=[byte]
    'System.SByte'=[sbyte]; 'System.Int16'=[int16]; 'System.UInt16'=[uint16]; 'System.Int32'=[int]
    'System.UInt32'=[uint32]; 'System.Int64'=[int64]; 'System.UInt64'=[uint64]; 'System.Single'=[single]
    'System.Double'=[double]; 'System.Decimal'=[decimal]; 'System.DateTime'=[datetime]
    'System.DateTimeOffset'=[datetimeoffset]; 'System.TimeSpan'=[timespan]; 'System.Guid'=[guid]
    'System.Uri'=[uri]; 'System.Version'=[version]; 'System.Text.RegularExpressions.Regex'=[regex]
}
$script:TerminalSlidesTaggedValueFields = [Collections.Generic.Dictionary[string,string[]]]::new(
    [StringComparer]::Ordinal
)
foreach ($type in 'String','Char','Boolean','SByte','Byte','Int16','UInt16','Int32','UInt32','Int64',
    'UInt64','Single','Double','Decimal','DateTime','DateTimeOffset','TimeSpan','Guid','Uri','Version','Regex') {
    $script:TerminalSlidesTaggedValueFields.Add($type, [string[]]@('Type','Value'))
}
$script:TerminalSlidesTaggedValueFields.Add('Null', [string[]]@('Type'))
$script:TerminalSlidesTaggedValueFields.Add('Map', [string[]]@('Type','Entries'))
$script:TerminalSlidesTaggedValueFields.Add('OrderedMap', [string[]]@('Type','Entries'))
$script:TerminalSlidesTaggedValueFields.Add('Object', [string[]]@('Type','Properties'))
$script:TerminalSlidesTaggedValueFields.Add('Array', [string[]]@('Type','ElementType','Items'))
$script:TerminalSlidesTaggedValueFields.Add('ArrayList', [string[]]@('Type','Items'))
$script:TerminalSlidesCanonicalStringValueTypes = [Collections.Generic.HashSet[string]]::new(
    [string[]]@(
        'String','Char','SByte','Byte','Int16','UInt16','Int32','UInt32','Int64','UInt64','Single','Double',
        'Decimal','DateTime','DateTimeOffset','TimeSpan','Guid','Uri','Version'
    ),
    [StringComparer]::Ordinal
)

function ConvertFrom-TerminalUtf8Bytes {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes,
        [switch]$RemoveByteOrderMark
    )

    $offset = if ($RemoveByteOrderMark -and $Bytes.Length -ge 3 -and
        $Bytes[0] -eq 0xef -and $Bytes[1] -eq 0xbb -and $Bytes[2] -eq 0xbf) { 3 }
        else { 0 }
    try {
        return $script:TerminalSlidesStrictUtf8.GetString($Bytes, $offset, $Bytes.Length - $offset)
    }
    catch [Text.DecoderFallbackException] {
        throw 'TerminalSlides structured input requires valid UTF-8 text.'
    }
}

function Assert-TerminalCanonicalTaggedScalarValue {
    param(
        [Parameter(Mandatory)][string]$Type,
        [AllowNull()][object]$Value
    )

    $valid = if ($Type -ceq 'Boolean') {
        $Value -is [bool]
    }
    elseif ($script:TerminalSlidesCanonicalStringValueTypes.Contains($Type)) {
        $Value -is [string] -and ($Type -cne 'Char' -or $Value.Length -eq 1)
    }
    else { $true }
    if (-not $valid) {
        throw "Persisted tagged type '$Type' requires a canonical Value representation."
    }
}

function Assert-TerminalExactObjectFields {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Value,
        [Parameter(Mandatory)][string[]]$Fields,
        [Parameter(Mandatory)][string]$Subject
    )

    $expected = [Collections.Generic.HashSet[string]]::new($Fields, [StringComparer]::Ordinal)
    $present = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($field in $Value.Keys) {
        if ($field -isnot [string] -or -not $expected.Contains($field)) {
            throw "$Subject is malformed: field '$field' is not supported."
        }
        [void]$present.Add($field)
    }
    foreach ($field in $Fields) {
        if (-not $present.Contains($field)) {
            throw "$Subject is malformed: field '$field' is required."
        }
    }
}

function Get-TerminalTaggedNodeArray {
    param([AllowNull()][object]$Value)

    return ,([object[]]$Value)
}

function Get-TerminalTaggedMembers {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Node,
        [Parameter(Mandatory)][string]$Field
    )

    return Get-TerminalTaggedNodeArray -Value $Node[$Field]
}

function Get-TerminalPersistedArrayElementType {
    param([Parameter(Mandatory)][string]$TypeName)

    $elementType = $script:TerminalSlidesPersistedArrayElementTypes[$TypeName]
    if (-not $elementType) { throw "Array element type '$TypeName' is not supported." }
    return $elementType
}

function ConvertFrom-TerminalPersistedScalarText {
    param(
        [Parameter(Mandatory)][string]$Kind,
        [AllowNull()][object]$Value
    )

    if ($null -eq $Value) { return $null }
    $culture = [Globalization.CultureInfo]::InvariantCulture
    if ($Kind -eq 'DateTime' -and $Value -is [datetime]) {
        return ([datetime]$Value).ToString('o', $culture)
    }
    if ($Kind -eq 'DateTimeOffset') {
        if ($Value -is [datetimeoffset]) { return ([datetimeoffset]$Value).ToString('o', $culture) }
        if ($Value -is [datetime]) { return ([datetimeoffset][datetime]$Value).ToString('o', $culture) }
    }

    $text = [string]$Value
    if ($Kind -eq 'DateTime' -and $text.StartsWith($script:TerminalSlidesDateTimePrefix, [StringComparison]::Ordinal)) {
        return $text.Substring($script:TerminalSlidesDateTimePrefix.Length)
    }
    if ($Kind -eq 'DateTimeOffset' -and $text.StartsWith($script:TerminalSlidesDateTimeOffsetPrefix, [StringComparison]::Ordinal)) {
        return $text.Substring($script:TerminalSlidesDateTimeOffsetPrefix.Length)
    }
    return $text
}

function Assert-TerminalPersistableRegexOptions {
    param([Parameter(Mandatory)][Text.RegularExpressions.RegexOptions]$Options)

    $cultureInvariant = [int]([Text.RegularExpressions.RegexOptions]::CultureInvariant)
    if (([int]$Options -band $cultureInvariant) -eq 0) {
        throw 'Regular-expression persistence requires RegexOptions.CultureInvariant.'
    }
}

function ConvertFrom-TerminalPersistedRegex {
    param(
        [Parameter(Mandatory)][AllowNull()][object]$Value,
        [switch]$RequireCanonical
    )

    $hasMatchTimeout = $false
    foreach ($field in $Value.Keys) {
        if ($field -is [string] -and $field -ceq 'MatchTimeoutTicks') { $hasMatchTimeout = $true }
    }
    $pattern = [string]$Value['Pattern']
    try {
        $optionValue = [int]::Parse([string]$Value['Options'], [Globalization.CultureInfo]::InvariantCulture)
        $options = [Text.RegularExpressions.RegexOptions]$optionValue
        $validated = [regex]::new($pattern, $options)
    }
    catch { throw "Persisted regular-expression value is malformed: $($_.Exception.Message)" }
    if (-not $hasMatchTimeout) { return $validated }
    Assert-TerminalPersistableRegexOptions -Options $options

    try {
        $ticks = [int64]::Parse([string]$Value['MatchTimeoutTicks'], [Globalization.CultureInfo]::InvariantCulture)
        if ($RequireCanonical -and
            $ticks.ToString([Globalization.CultureInfo]::InvariantCulture) -cne $Value['MatchTimeoutTicks']) {
            throw 'MatchTimeoutTicks does not use its canonical text representation.'
        }
        return [regex]::new($pattern, $options, [timespan]::FromTicks($ticks))
    }
    catch { throw "Persisted regular-expression match timeout is invalid: $($_.Exception.Message)" }
}

function ConvertTo-TerminalTaggedValue {
    param(
        [AllowNull()][object]$Value,
        [int]$Depth = 0,
        [AllowNull()][psobject]$TraversalContext
    )

    if ($null -eq $TraversalContext) { $TraversalContext = New-TerminalSemanticTraversalContext }
    Assert-TerminalSemanticTraversalDepth -Depth $Depth -MaximumDepth $TraversalContext.MaximumDepth
    if ($null -eq $Value) { return [ordered]@{ Type = 'Null' } }

    $typeName = switch ($Value.GetType().FullName) {
        'System.String' { 'String' }
        'System.Char' { 'Char' }
        'System.Boolean' { 'Boolean' }
        'System.SByte' { 'SByte' }
        'System.Byte' { 'Byte' }
        'System.Int16' { 'Int16' }
        'System.UInt16' { 'UInt16' }
        'System.Int32' { 'Int32' }
        'System.UInt32' { 'UInt32' }
        'System.Int64' { 'Int64' }
        'System.UInt64' { 'UInt64' }
        'System.Single' { 'Single' }
        'System.Double' { 'Double' }
        'System.Decimal' { 'Decimal' }
        'System.DateTime' { 'DateTime' }
        'System.DateTimeOffset' { 'DateTimeOffset' }
        'System.TimeSpan' { 'TimeSpan' }
        'System.Guid' { 'Guid' }
        'System.Uri' { 'Uri' }
        'System.Version' { 'Version' }
        'System.Text.RegularExpressions.Regex' { 'Regex' }
        default { $null }
    }
    if ($typeName) {
        $serialized = switch ($typeName) {
            'Boolean' { [bool]$Value }
            { $_ -in 'SByte','Byte','Int16','UInt16','Int32','UInt32','Int64','UInt64' } { $Value.ToString([Globalization.CultureInfo]::InvariantCulture) }
            'Single' { ([single]$Value).ToString('R', [Globalization.CultureInfo]::InvariantCulture) }
            'Double' { ([double]$Value).ToString('R', [Globalization.CultureInfo]::InvariantCulture) }
            'Decimal' { ([decimal]$Value).ToString([Globalization.CultureInfo]::InvariantCulture) }
            'DateTime' { ([datetime]$Value).ToString('o', [Globalization.CultureInfo]::InvariantCulture) }
            'DateTimeOffset' { ([datetimeoffset]$Value).ToString('o', [Globalization.CultureInfo]::InvariantCulture) }
            'TimeSpan' { ([timespan]$Value).ToString('c', [Globalization.CultureInfo]::InvariantCulture) }
            'Guid' { ([guid]$Value).ToString('D') }
            'Uri' { ([uri]$Value).OriginalString }
            'Regex' {
                Assert-TerminalPersistableRegexOptions -Options $Value.Options
                [ordered]@{
                    Pattern = $Value.ToString()
                    Options = [int]$Value.Options
                    MatchTimeoutTicks = $Value.MatchTimeout.Ticks.ToString([Globalization.CultureInfo]::InvariantCulture)
                }
            }
            default { [string]$Value }
        }
        return [ordered]@{ Type = $typeName; Value = $serialized }
    }

    Enter-TerminalSemanticReference -Value $Value -TraversalContext $TraversalContext
    try {
        if ($Value -is [System.Collections.IDictionary]) {
            Assert-TerminalUnambiguousDictionaryKeys -Dictionary $Value
            $entries = foreach ($key in (Get-TerminalCanonicalDictionaryKeys -Dictionary $Value)) {
                $item = ConvertTo-TerminalTaggedValue -Value $Value[$key] -Depth ($Depth + 1) -TraversalContext $TraversalContext
                [ordered]@{ Name = $key; Value = $item }
            }
            $kind = if ($Value -is [System.Collections.Specialized.OrderedDictionary]) { 'OrderedMap' } else { 'Map' }
            return [ordered]@{ Type = $kind; Entries = @($entries) }
        }
        if ($Value.GetType().IsArray) {
            Assert-TerminalSupportedArrayShape -ArrayType $Value.GetType()
            $elementTypeName = $Value.GetType().GetElementType().FullName
            $null = Get-TerminalPersistedArrayElementType -TypeName $elementTypeName
            $items = [Collections.Generic.List[object]]::new()
            foreach ($item in $Value) {
                $items.Add((ConvertTo-TerminalTaggedValue -Value $item -Depth ($Depth + 1) -TraversalContext $TraversalContext))
            }
            return [ordered]@{ Type = 'Array'; ElementType = $elementTypeName; Items = $items.ToArray() }
        }
        if ($Value -is [System.Collections.ArrayList]) {
            $items = foreach ($item in $Value) {
                ConvertTo-TerminalTaggedValue -Value $item -Depth ($Depth + 1) -TraversalContext $TraversalContext
            }
            return [ordered]@{ Type = 'ArrayList'; Items = @($items) }
        }
        if ($Value -is [System.Management.Automation.PSCustomObject]) {
            $properties = foreach ($property in $Value.PSObject.Properties) {
                $item = ConvertTo-TerminalTaggedValue -Value $property.Value -Depth ($Depth + 1) -TraversalContext $TraversalContext
                [ordered]@{ Name = $property.Name; Value = $item }
            }
            return [ordered]@{ Type = 'Object'; Properties = @($properties) }
        }

        throw "Value type '$($Value.GetType().FullName)' cannot be persisted safely."
    }
    finally {
        Exit-TerminalSemanticReference -Value $Value -TraversalContext $TraversalContext
    }
}

function Assert-TerminalCanonicalTaggedScalarText {
    param(
        [Parameter(Mandatory)][string]$Type,
        [AllowNull()][object]$Value
    )

    if ($Type -in 'Null','String','Char','Boolean','Map','OrderedMap','Object','Array','ArrayList','Regex') { return }
    $culture = [Globalization.CultureInfo]::InvariantCulture
    try {
        $canonical = switch ($Type) {
            'SByte' { [sbyte]::Parse($Value, $culture).ToString($culture) }
            'Byte' { [byte]::Parse($Value, $culture).ToString($culture) }
            'Int16' { [int16]::Parse($Value, $culture).ToString($culture) }
            'UInt16' { [uint16]::Parse($Value, $culture).ToString($culture) }
            'Int32' { [int32]::Parse($Value, $culture).ToString($culture) }
            'UInt32' { [uint32]::Parse($Value, $culture).ToString($culture) }
            'Int64' { [int64]::Parse($Value, $culture).ToString($culture) }
            'UInt64' { [uint64]::Parse($Value, $culture).ToString($culture) }
            'Single' { [single]::Parse($Value, $culture).ToString('R', $culture) }
            'Double' { [double]::Parse($Value, $culture).ToString('R', $culture) }
            'Decimal' { [decimal]::Parse($Value, $culture).ToString($culture) }
            'DateTime' {
                [void](ConvertFrom-TerminalDateTimeText -Text $Value)
                if ($Value -cnotmatch '\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{7}(?:Z|[+-]\d{2}:\d{2})?\z') {
                    throw 'DateTime text must use the round-trip format.'
                }
                if ($Value -cmatch '-00:00\z') {
                    throw 'DateTime text must not use a negative-zero offset.'
                }
                [string]$Value
            }
            'DateTimeOffset' {
                [datetimeoffset]::ParseExact($Value, 'o', $culture, [Globalization.DateTimeStyles]::RoundtripKind).ToString('o', $culture)
            }
            'TimeSpan' { [timespan]::ParseExact($Value, 'c', $culture).ToString('c', $culture) }
            'Guid' { [guid]::ParseExact($Value, 'D').ToString('D') }
            'Uri' { [uri]::new($Value, [UriKind]::RelativeOrAbsolute).OriginalString }
            'Version' { [version]::new($Value).ToString() }
        }
    }
    catch { throw "Persisted tagged type '$Type' has invalid canonical text: $($_.Exception.Message)" }
    if ([string]$Value -cne $canonical) {
        throw "Persisted tagged type '$Type' does not use its canonical text representation."
    }
}

function ConvertFrom-TerminalTaggedValue {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Node,
        [int]$Depth = 0,
        [switch]$RequireCanonical
    )

    Assert-TerminalCurrentTaggedNode -Node $Node -Depth $Depth -Recurse $false -RequireCanonical:$RequireCanonical
    $culture = [Globalization.CultureInfo]::InvariantCulture
    $type = [string]$Node['Type']
    if ($RequireCanonical) { Assert-TerminalCanonicalTaggedScalarText -Type $type -Value $Node['Value'] }

    switch ($type) {
        'Null' { return $null }
        'String' { return [string]$Node.Value }
        'Char' { return [char][string]$Node.Value }
        'Boolean' { return [bool]::Parse([string]$Node.Value) }
        'SByte' { return [sbyte]::Parse([string]$Node.Value, $culture) }
        'Byte' { return [byte]::Parse([string]$Node.Value, $culture) }
        'Int16' { return [int16]::Parse([string]$Node.Value, $culture) }
        'UInt16' { return [uint16]::Parse([string]$Node.Value, $culture) }
        'Int32' { return [int32]::Parse([string]$Node.Value, $culture) }
        'UInt32' { return [uint32]::Parse([string]$Node.Value, $culture) }
        'Int64' { return [int64]::Parse([string]$Node.Value, $culture) }
        'UInt64' { return [uint64]::Parse([string]$Node.Value, $culture) }
        'Single' { return [single]::Parse([string]$Node.Value, $culture) }
        'Double' { return [double]::Parse([string]$Node.Value, $culture) }
        'Decimal' { return [decimal]::Parse([string]$Node.Value, $culture) }
        'DateTime' {
            $text = ConvertFrom-TerminalPersistedScalarText -Kind DateTime -Value $Node.Value
            return ConvertFrom-TerminalDateTimeText -Text $text
        }
        'DateTimeOffset' {
            $text = ConvertFrom-TerminalPersistedScalarText -Kind DateTimeOffset -Value $Node.Value
            return [datetimeoffset]::ParseExact($text, 'o', $culture, [Globalization.DateTimeStyles]::RoundtripKind)
        }
        'TimeSpan' { return [timespan]::ParseExact([string]$Node.Value, 'c', $culture) }
        'Guid' { return [guid]::ParseExact([string]$Node.Value, 'D') }
        'Uri' { return [uri]::new([string]$Node.Value, [UriKind]::RelativeOrAbsolute) }
        'Version' { return [version]::new([string]$Node.Value) }
        'Regex' { return ConvertFrom-TerminalPersistedRegex -Value $Node.Value -RequireCanonical:$RequireCanonical }
        { $_ -in 'Map','OrderedMap' } {
            $map = if ($Node.Type -eq 'OrderedMap') { [ordered]@{} } else { @{} }
            $entries = Get-TerminalTaggedMembers -Node $Node -Field Entries
            Assert-TerminalUnambiguousNames -Names @($entries | ForEach-Object { $_['Name'] }) -Subject 'Metadata dictionary keys' -Item 'metadata key'
            foreach ($entry in $entries) {
                $map[[string]$entry['Name']] = ConvertFrom-TerminalTaggedValue $entry['Value'] ($Depth + 1) -RequireCanonical:$RequireCanonical
            }
            return $map
        }
        'Object' {
            $properties = [ordered]@{}
            $members = Get-TerminalTaggedMembers -Node $Node -Field Properties
            Assert-TerminalUnambiguousNames -Names @($members | ForEach-Object { $_['Name'] }) -Subject 'Metadata object properties' -Item 'metadata property'
            foreach ($property in $members) {
                $properties[[string]$property['Name']] = ConvertFrom-TerminalTaggedValue $property['Value'] ($Depth + 1) -RequireCanonical:$RequireCanonical
            }
            return [pscustomobject]$properties
        }
        { $_ -in 'Array','ArrayList' } {
            $elementType = if ($Node.Type -eq 'Array') {
                Get-TerminalPersistedArrayElementType -TypeName ([string]$Node.ElementType)
            }
            else { $null }
            $itemNodes = Get-TerminalTaggedNodeArray -Value $Node['Items']
            $items = @($itemNodes | ForEach-Object {
                ConvertFrom-TerminalTaggedValue $_ ($Depth + 1) -RequireCanonical:$RequireCanonical
            })
            if ($Node.Type -eq 'ArrayList') { return ,([Collections.ArrayList]::new($items)) }
            $array = [Array]::CreateInstance($elementType, $items.Count)
            for ($index = 0; $index -lt $items.Count; $index++) {
                $item = $items[$index]
                if ($null -eq $item) {
                    if ($elementType.IsValueType) {
                        throw "Persisted array element type '$($elementType.FullName)' does not allow null items."
                    }
                    $array.SetValue($null, $index)
                    continue
                }
                if (-not $elementType.IsInstanceOfType($item)) {
                    throw "Persisted array item type '$($item.GetType().FullName)' is not assignable to '$($elementType.FullName)'."
                }
                $array.SetValue($item, $index)
            }
            return ,$array
        }
    }
}

function ConvertTo-TerminalPayloadData {
    param([Parameter(Mandatory)][TerminalSlides.Schema.V1.ElementPayload]$Payload)

    switch ($Payload.GetType().Name) {
        'TextPayload' { return [ordered]@{ Text = $Payload.Text } }
        'CodePayload' { return [ordered]@{ Code = $Payload.Code; Language = $Payload.Language } }
        'ImagePayload' { return [ordered]@{ Path = $Payload.Path; AltText = $Payload.AltText } }
        'QuotePayload' { return [ordered]@{ Text = $Payload.Text; Attribution = $Payload.Attribution } }
        'ChartPayload' {
            return [ordered]@{
                ChartKind = $Payload.ChartKind.ToString(); Title = $Payload.Title
                Points = @($Payload.Points | ForEach-Object { [ordered]@{ Label = $_.Label; Value = $_.Value.ToString([Globalization.CultureInfo]::InvariantCulture) } })
            }
        }
        'DiagramPayload' {
            return [ordered]@{
                Nodes = @($Payload.Nodes | ForEach-Object { [ordered]@{ Id = $_.Id; Label = $_.Label } })
                Edges = @($Payload.Edges | ForEach-Object { [ordered]@{ From = $_.From; To = $_.To; Label = $_.Label } })
            }
        }
        'TablePayload' {
            return [ordered]@{ Rows = @($Payload.Rows | ForEach-Object {
                [ordered]@{ Cells = @($_.Cells | ForEach-Object {
                    [ordered]@{
                        Name = $_.Name
                        Kind = $_.Value.Kind.ToString()
                        Value = $_.Value.Value
                    }
                }) }
            }) }
        }
    }
}

function ConvertTo-TerminalThemeData {
    param([Parameter(Mandatory)][TerminalSlides.Schema.V1.ThemeDefinition]$Theme)

    return [ordered]@{
        Name = $Theme.Name
        Background = $Theme.Background
        Foreground = $Theme.Foreground
        Primary = $Theme.Primary
        Accent = $Theme.Accent
        Muted = $Theme.Muted
        Heading = $Theme.Heading
        Border = $Theme.Border
        CodeTheme = $Theme.CodeTheme
        CodeBackground = $Theme.CodeBackground
        CodeForeground = $Theme.CodeForeground
        BulletSymbol = $Theme.BulletSymbol
        BoxDrawingStyle = $Theme.BoxDrawingStyle
        HeadingStyle = $Theme.HeadingStyle
        ChartPalette = @($Theme.ChartPalette)
        ErrorColor = $Theme.ErrorColor
        WarningColor = $Theme.WarningColor
        SuccessColor = $Theme.SuccessColor
        Metadata = ConvertTo-TerminalTaggedValue $Theme.Metadata
    }
}

function ConvertTo-TerminalHashtableRoot {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory)][string]$Subject
    )

    if ($Value -isnot [System.Collections.IDictionary]) { throw "$Subject must decode to a map." }
    $result = @{}
    foreach ($key in $Value.Keys) { $result[[string]$key] = $Value[$key] }
    return $result
}

function ConvertTo-PresentationData {
    param([Parameter(Mandatory)][TerminalSlides.Schema.V1.TerminalPresentation]$Presentation)

    Assert-TerminalWireReadyPresentationModel -Presentation $Presentation
    $theme = Resolve-TerminalPresentationTheme -Presentation $Presentation
    $slides = foreach ($slide in $Presentation.Slides) {
        $maximumRevealStep = Get-TerminalSlideMaximumRevealStep -Slide $slide
        [ordered]@{
            Id=$slide.Id; Index=$slide.Index; Title=$slide.Title; Layout=$slide.Layout; Notes=$slide.Notes
            Background=$slide.Background; Transition=$slide.Transition; Hidden=$slide.Hidden; MaxRevealStep=$maximumRevealStep
            Metadata=[ordered]@{ Author=$slide.Metadata.Author; Custom=(ConvertTo-TerminalTaggedValue $slide.Metadata.Custom) }
            Elements=@($slide.Elements | ForEach-Object {
                [ordered]@{
                    Id=$_.Id; Kind=$_.Kind.ToString(); Payload=(ConvertTo-TerminalPayloadData $_.Payload); Region=$_.Region
                    X=$_.X; Y=$_.Y; Width=$_.Width; Height=$_.Height; Alignment=$_.Alignment
                    VerticalAlignment=$_.VerticalAlignment; Padding=$_.Padding; ForegroundColor=$_.ForegroundColor
                    BackgroundColor=$_.BackgroundColor; Border=$_.Border; BorderStyle=$_.BorderStyle
                    RevealStep=$_.RevealStep; OverflowBehavior=$_.OverflowBehavior
                }
            })
        }
    }
    return [ordered]@{
        '$schema'=$script:TerminalSlidesWireSchema
        SchemaVersion=$script:TerminalSlidesWireVersion
        Presentation=[ordered]@{
            Title=$Presentation.Title; Subtitle=$Presentation.Subtitle; Author=$Presentation.Author
            Description=$Presentation.Description; Theme=$theme.Name; ThemeDefinition=(ConvertTo-TerminalThemeData $theme)
            Width=$Presentation.Width; Height=$Presentation.Height
            DefaultTransition=$Presentation.DefaultTransition; DefaultLayout=$Presentation.DefaultLayout
            CreatedDate=$Presentation.CreatedDate.ToString('o'); ModifiedDate=$Presentation.ModifiedDate.ToString('o')
            Metadata=[ordered]@{
                Title=$Presentation.Metadata.Title; Subtitle=$Presentation.Metadata.Subtitle; Author=$Presentation.Metadata.Author
                Description=$Presentation.Metadata.Description; Version=$Presentation.Metadata.Version
                Custom=(ConvertTo-TerminalTaggedValue $Presentation.Metadata.Custom)
            }
            Configuration=(ConvertTo-TerminalTaggedValue $Presentation.Configuration)
            Slides=@($slides)
        }
    }
}

function ConvertFrom-TerminalLegacyData {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Data)

    $presentation = [TerminalSlides.Schema.V1.TerminalPresentation]::new()
    foreach ($property in 'Title','Subtitle','Author','Description','Theme','Width','Height','DefaultTransition','DefaultLayout','Configuration') {
        if ($Data.Contains($property)) { $presentation.$property = Copy-TerminalSemanticValue $Data[$property] }
    }
    if (($presentation.Width -gt 0 -and $presentation.Width -lt 20) -or ($presentation.Height -gt 0 -and $presentation.Height -lt 10)) { throw 'Presentation dimensions must be automatic (0) or at least 20x10.' }
    if ($Data.CreatedDate) { $presentation.CreatedDate = ConvertFrom-TerminalDateTimeText -Text ([string]$Data.CreatedDate) }
    $modified = if ($Data.ModifiedDate) { ConvertFrom-TerminalDateTimeText -Text ([string]$Data.ModifiedDate) } else { $presentation.ModifiedDate }
    if ($Data.Metadata) {
        foreach ($property in 'Title','Subtitle','Author','Description','Version') { if ($Data.Metadata.Contains($property)) { $presentation.Metadata.$property = $Data.Metadata[$property] } }
        if ($Data.Metadata.Contains('Custom')) { $presentation.Metadata.Custom = Copy-TerminalSemanticValue $Data.Metadata.Custom }
    }
    foreach ($slideData in @($Data.Slides ?? @())) {
        $slide = [TerminalSlides.Schema.V1.Slide]::new()
        foreach ($property in 'Id','Index','Title','Layout','Notes','Background','Transition','Hidden') { if ($slideData.Contains($property)) { $slide.$property = $slideData[$property] } }
        if ($slideData.Metadata) {
            $slide.Metadata.Author = $slideData.Metadata.Author
            if ($slideData.Metadata.Contains('Custom')) { $slide.Metadata.Custom = Copy-TerminalSemanticValue $slideData.Metadata.Custom }
        }
        foreach ($legacy in @($slideData.Elements ?? @())) {
            if (-not $legacy.Type) { throw 'Legacy slide elements require a Type.' }
            $kind = [TerminalSlides.Schema.V1.ElementKind]([string]$legacy.Type)
            $payload = switch ($kind.ToString()) {
                { $_ -in 'Title','Subtitle','Text','Bullet','Box' } { [TerminalSlides.Schema.V1.TextPayload]::new([string]$legacy.Content) }
                'Code' {
                    $code = (Get-TerminalSemanticProperty $legacy.Content Code) ?? [string]$legacy.Content
                    $language = (Get-TerminalSemanticProperty $legacy.Content Language) ?? (Get-TerminalSemanticProperty $legacy.Properties Language) ?? 'text'
                    [TerminalSlides.Schema.V1.CodePayload]::new([string]$code, [string]$language)
                }
                'Table' { [TerminalSlides.Schema.V1.TablePayload]::new((ConvertTo-TerminalDataRows $legacy.Content)) }
                'Chart' {
                    $points = @($legacy.Content | ForEach-Object { [TerminalSlides.Schema.V1.ChartPoint]::new([string](Get-TerminalSemanticProperty $_ Label), [decimal](Get-TerminalSemanticProperty $_ Value)) })
                    $chartKind = (Get-TerminalSemanticProperty $legacy.Properties ChartType) ?? 'HorizontalBar'
                    [TerminalSlides.Schema.V1.ChartPayload]::new([TerminalSlides.Schema.V1.ChartPoint[]]$points, [TerminalSlides.Schema.V1.ChartKind]([string]$chartKind), [string](Get-TerminalSemanticProperty $legacy.Properties Title))
                }
                'Diagram' {
                    $nodes = @((Get-TerminalSemanticProperty $legacy.Content Nodes) | ForEach-Object { [TerminalSlides.Schema.V1.DiagramNode]::new([string](Get-TerminalSemanticProperty $_ Id), [string](Get-TerminalSemanticProperty $_ Label)) })
                    $edges = @((Get-TerminalSemanticProperty $legacy.Content Edges) | ForEach-Object { [TerminalSlides.Schema.V1.DiagramEdge]::new([string](Get-TerminalSemanticProperty $_ From), [string](Get-TerminalSemanticProperty $_ To), [string](Get-TerminalSemanticProperty $_ Label)) })
                    [TerminalSlides.Schema.V1.DiagramPayload]::new([TerminalSlides.Schema.V1.DiagramNode[]]$nodes, [TerminalSlides.Schema.V1.DiagramEdge[]]$edges)
                }
                'Image' { [TerminalSlides.Schema.V1.ImagePayload]::new([string](Get-TerminalSemanticProperty $legacy.Content Path), [string](Get-TerminalSemanticProperty $legacy.Content AltText)) }
                'Quote' { [TerminalSlides.Schema.V1.QuotePayload]::new([string](Get-TerminalSemanticProperty $legacy.Content Text), [string](Get-TerminalSemanticProperty $legacy.Content Attribution)) }
            }
            $element = [TerminalSlides.Schema.V1.SlideElement]::new($kind, $payload)
            foreach ($property in 'Id','Region','X','Y','Width','Height','Alignment','VerticalAlignment','Padding','ForegroundColor','BackgroundColor','Border','BorderStyle','RevealStep','OverflowBehavior') {
                if ($legacy.Contains($property)) { $element.$property = $legacy[$property] }
            }
            $slide.Elements.Add($element)
        }
        $slide.MaxRevealStep = Get-TerminalSlideMaximumRevealStep -Slide $slide
        $presentation.Slides.Add($slide)
    }
    Update-SlideIndices $presentation
    $presentation.ModifiedDate = $modified
    $presentation.EmbeddedTheme = Copy-TerminalThemeDefinition (Resolve-TerminalPresentationTheme $presentation)
    Assert-TerminalWireReadyPresentationModel -Presentation $presentation
    return $presentation
}

function New-PresentationFromData {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Data)
    if ($Data.Contains('SchemaVersion') -or $Data.Contains('$schema')) { return ConvertFrom-TerminalCurrentData $Data }
    return ConvertFrom-TerminalLegacyData $Data
}

function ConvertTo-TerminalWireJson {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Data)

    $stream = [IO.MemoryStream]::new()
    $options = [System.Text.Json.JsonWriterOptions]::new()
    $options.Indented = $false
    $options.SkipValidation = $false
    $options.MaxDepth = $script:TerminalSlidesMaximumWireDepth
    $writer = [System.Text.Json.Utf8JsonWriter]::new($stream, $options)
    try {
        Write-TerminalJsonValue -Writer $writer -Value $Data
        $writer.Flush()
        $json = $script:TerminalSlidesStrictUtf8.GetString($stream.ToArray())
        [void]$script:TerminalSlidesStrictUtf8.GetByteCount($json)
        return $json
    }
    finally {
        $writer.Dispose()
        $stream.Dispose()
    }
}

function Write-TerminalJsonValue {
    param(
        [Parameter(Mandatory)][System.Text.Json.Utf8JsonWriter]$Writer,
        [AllowNull()][object]$Value
    )

    if ($null -eq $Value) {
        $Writer.WriteNullValue()
        return
    }
    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($key in $Value.Keys) {
            if ($key -isnot [string]) {
                throw 'TerminalSlides JSON object keys must be strings.'
            }
        }
        $Writer.WriteStartObject()
        foreach ($key in (Get-TerminalCanonicalDictionaryKeys -Dictionary $Value)) {
            Assert-TerminalValidUtf16 -Value $key
            $Writer.WritePropertyName($key)
            Write-TerminalJsonValue -Writer $Writer -Value $Value[$key]
        }
        $Writer.WriteEndObject()
        return
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $Writer.WriteStartArray()
        foreach ($item in $Value) {
            Write-TerminalJsonValue -Writer $Writer -Value $item
        }
        $Writer.WriteEndArray()
        return
    }

    switch ($Value.GetType().FullName) {
        'System.String' {
            Assert-TerminalValidUtf16 -Value $Value
            $Writer.WriteStringValue([string]$Value)
        }
        'System.Boolean' { $Writer.WriteBooleanValue([bool]$Value) }
        'System.SByte' { $Writer.WriteNumberValue([int]$Value) }
        'System.Byte' { $Writer.WriteNumberValue([int]$Value) }
        'System.Int16' { $Writer.WriteNumberValue([int]$Value) }
        'System.UInt16' { $Writer.WriteNumberValue([int]$Value) }
        'System.Int32' { $Writer.WriteNumberValue([int]$Value) }
        'System.UInt32' { $Writer.WriteNumberValue([uint32]$Value) }
        'System.Int64' { $Writer.WriteNumberValue([int64]$Value) }
        'System.UInt64' { $Writer.WriteNumberValue([uint64]$Value) }
        'System.Single' { $Writer.WriteNumberValue([single]$Value) }
        'System.Double' { $Writer.WriteNumberValue([double]$Value) }
        'System.Decimal' { $Writer.WriteNumberValue([decimal]$Value) }
        default { throw "TerminalSlides JSON cannot encode value type '$($Value.GetType().FullName)'." }
    }
}

function ConvertFrom-TerminalJsonElement {
    param([Parameter(Mandatory)][System.Text.Json.JsonElement]$Element)

    switch ($Element.ValueKind) {
        'Object' {
            $result = [Collections.Specialized.OrderedDictionary]::new([StringComparer]::Ordinal)
            foreach ($property in $Element.EnumerateObject()) {
                if ($result.Contains($property.Name)) { throw "JSON contains duplicate property '$($property.Name)'." }
                $value = ConvertFrom-TerminalJsonElement -Element $property.Value
                $result.Add($property.Name, $value)
            }
            return $result
        }
        'Array' {
            $items = [Collections.Generic.List[object]]::new()
            foreach ($item in $Element.EnumerateArray()) {
                $items.Add((ConvertFrom-TerminalJsonElement -Element $item))
            }
            return ,([object[]]$items.ToArray())
        }
        'String' { return $Element.GetString() }
        'Number' {
            [int64]$signed = 0
            if ($Element.TryGetInt64([ref]$signed)) { return $signed }
            [uint64]$unsigned = 0
            if ($Element.TryGetUInt64([ref]$unsigned)) { return $unsigned }
            $raw = $Element.GetRawText()
            if ($raw -notmatch '[.eE]') {
                return [Numerics.BigInteger]::Parse($raw, [Globalization.CultureInfo]::InvariantCulture)
            }
            return $Element.GetDouble()
        }
        'True' { return $true }
        'False' { return $false }
        'Null' { return $null }
        default { throw "Unsupported JSON token '$($Element.ValueKind)'." }
    }
}

function ConvertFrom-TerminalJsonValue {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Json)

    $options = [System.Text.Json.JsonDocumentOptions]::new()
    $options.AllowTrailingCommas = $false
    $options.CommentHandling = [System.Text.Json.JsonCommentHandling]::Disallow
    $options.MaxDepth = $script:TerminalSlidesMaximumWireDepth
    $document = [System.Text.Json.JsonDocument]::Parse($Json, $options)
    try {
        return ,(ConvertFrom-TerminalJsonElement -Element $document.RootElement)
    }
    finally { $document.Dispose() }
}

function ConvertFrom-TerminalWireJson {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Json)

    $data = ConvertFrom-TerminalJsonValue -Json $Json
    if ($data -isnot [System.Collections.IDictionary]) {
        throw 'The TerminalSlides JSON root must be an object.'
    }
    return $data
}

function ConvertTo-TerminalDataMarker {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Data)
    return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((ConvertTo-TerminalWireJson $Data)))
}

function ConvertFrom-TerminalDataMarker {
    param([Parameter(Mandatory)][string]$Marker)
    try {
        $json = ConvertFrom-TerminalUtf8Bytes -Bytes ([Convert]::FromBase64String($Marker))
        return ConvertFrom-TerminalWireJson -Json $json
    }
    catch { throw "The TerminalSlides data marker is invalid: $($_.Exception.Message)" }
}
