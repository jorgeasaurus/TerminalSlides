$script:TerminalSlidesWireIntegerTypes = [Collections.Generic.HashSet[string]]::new(
    [string[]]@(
        'System.SByte','System.Byte','System.Int16','System.UInt16','System.Int32','System.UInt32',
        'System.Int64','System.UInt64'
    ),
    [StringComparer]::Ordinal
)

function Assert-TerminalWireObject {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory)][string[]]$Fields,
        [Parameter(Mandatory)][string]$Subject
    )
    if ($Value -isnot [Collections.IDictionary]) { throw "$Subject must be an object in the current wire format." }
    Assert-TerminalExactObjectFields -Value $Value -Fields $Fields -Subject $Subject
}

function Assert-TerminalWireArray {
    param([AllowNull()][object]$Value, [Parameter(Mandatory)][string]$Subject)
    if ($Value -isnot [object[]]) { throw "$Subject must be an array in the current wire format." }
}

function Assert-TerminalWireString {
    param([AllowNull()][object]$Value, [Parameter(Mandatory)][string]$Subject, [switch]$AllowNull)
    if ($null -eq $Value -and $AllowNull) { return }
    if ($Value -isnot [string]) { throw "$Subject must be a string in the current wire format." }
}

function Assert-TerminalWireInteger {
    param([AllowNull()][object]$Value, [Parameter(Mandatory)][string]$Subject)
    if ($null -eq $Value -or -not $script:TerminalSlidesWireIntegerTypes.Contains($Value.GetType().FullName)) {
        throw "$Subject must be an integer in the current wire format."
    }
}

function Read-TerminalWireInt32 {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory)][string]$Subject,
        [int]$Minimum = [int]::MinValue,
        [int]$Maximum = [int]::MaxValue
    )
    Assert-TerminalWireInteger -Value $Value -Subject $Subject
    try { $number = [int64]$Value }
    catch { throw "$Subject must fit in a signed 32-bit integer in the current wire format." }
    if ($number -lt $Minimum -or $number -gt $Maximum) {
        throw "$Subject must be between $Minimum and $Maximum in the current wire format."
    }
    return [int]$number
}

function Assert-TerminalWireBoolean {
    param([AllowNull()][object]$Value, [Parameter(Mandatory)][string]$Subject)
    if ($Value -isnot [bool]) { throw "$Subject must be a Boolean in the current wire format." }
}

function Read-TerminalWireEnum {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory)][Type]$EnumType,
        [Parameter(Mandatory)][string]$Subject
    )
    Assert-TerminalWireString -Value $Value -Subject $Subject
    if ($EnumType.GetEnumNames() -cnotcontains $Value) {
        throw "$Subject has unsupported value '$Value' in the current wire format."
    }
    return [Enum]::Parse($EnumType, $Value, $false)
}

function Read-TerminalWireDomainName {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory)][string[]]$AllowedValues,
        [Parameter(Mandatory)][string]$Subject
    )
    Assert-TerminalWireString -Value $Value -Subject $Subject
    foreach ($allowedValue in $AllowedValues) {
        if ([string]::Equals($Value, $allowedValue, [StringComparison]::OrdinalIgnoreCase)) { return $allowedValue }
    }
    throw "$Subject has unsupported value '$Value' in the current wire format."
}

function Read-TerminalWireHexColor {
    param([AllowNull()][object]$Value, [Parameter(Mandatory)][string]$Subject, [switch]$AllowDefault)
    if ($AllowDefault -and $null -eq $Value) { return $null }
    Assert-TerminalWireString -Value $Value -Subject $Subject
    if ($AllowDefault -and [string]::IsNullOrWhiteSpace($Value)) { return $null }
    try { [void](Convert-HexToRgb -Hex $Value) }
    catch { throw "$Subject must be a six-digit hexadecimal color in the current wire format." }
    return '#' + $Value.Trim().TrimStart('#').ToUpperInvariant()
}

function Assert-TerminalCurrentRegexValue {
    param([AllowNull()][object]$Value, [switch]$RequireCanonical)
    if ($Value -isnot [Collections.IDictionary]) {
        throw 'Persisted regular-expression value is malformed: an object is required in the current wire format.'
    }
    $hasTimeout = $Value.Keys -ccontains 'MatchTimeoutTicks'
    $fields = if ($RequireCanonical -or $hasTimeout) { @('Pattern','Options','MatchTimeoutTicks') } else { @('Pattern','Options') }
    Assert-TerminalExactObjectFields -Value $Value -Fields $fields -Subject 'Persisted regular-expression value'
    if ($Value['Pattern'] -isnot [string]) {
        throw "Persisted regular-expression value is malformed: field 'Pattern' must be a string in the current wire format."
    }
    Assert-TerminalWireInteger -Value $Value['Options'] -Subject "Persisted regular-expression value is malformed: field 'Options'"
    if ($hasTimeout -and $Value['MatchTimeoutTicks'] -isnot [string]) {
        throw "Persisted regular-expression value is malformed: field 'MatchTimeoutTicks' must be a string in the current wire format."
    }
}

function Assert-TerminalCurrentTaggedNode {
    param(
        [AllowNull()][object]$Node,
        [int]$Depth = 0,
        [bool]$Recurse = $true,
        [switch]$RequireCanonical
    )
    Assert-TerminalSemanticTraversalDepth -Depth $Depth
    if ($Node -isnot [Collections.IDictionary]) { throw 'Persisted tagged value must be an object in the current wire format.' }
    $type = $Node['Type']
    if ($type -isnot [string] -or $type.Length -eq 0) {
        throw "Persisted tagged value is malformed: field 'Type' is required and must be a string in the current wire format."
    }
    if (-not $script:TerminalSlidesTaggedValueFields.ContainsKey($type)) { throw "Unsupported persisted value type '$type'." }
    Assert-TerminalExactObjectFields -Value $Node -Fields $script:TerminalSlidesTaggedValueFields[$type] -Subject 'Persisted tagged value'
    if ($type -ceq 'Regex') {
        Assert-TerminalCurrentRegexValue -Value $Node['Value'] -RequireCanonical:$RequireCanonical
        return
    }
    Assert-TerminalCanonicalTaggedScalarValue -Type $type -Value $Node['Value']
    if ($type -in 'Null','String','Char','Boolean','SByte','Byte','Int16','UInt16','Int32','UInt32',
        'Int64','UInt64','Single','Double','Decimal','DateTime','DateTimeOffset','TimeSpan','Guid','Uri','Version') { return }

    $collectionField = switch ($type) {
        { $_ -in 'Map','OrderedMap' } { 'Entries' }
        'Object' { 'Properties' }
        { $_ -in 'Array','ArrayList' } { 'Items' }
    }
    if ($type -ceq 'Array') { Assert-TerminalWireString -Value $Node['ElementType'] -Subject 'Persisted array ElementType' }
    Assert-TerminalWireArray -Value $Node[$collectionField] -Subject "Persisted tagged value is malformed: field '$collectionField'"
    foreach ($item in $Node[$collectionField]) {
        if ($type -in 'Map','OrderedMap','Object') {
            Assert-TerminalWireObject -Value $item -Fields @('Name','Value') -Subject "Persisted $type member"
            if ($item['Name'] -isnot [string] -or $item['Name'].Length -eq 0) {
                $subject = if ($type -in 'Map','OrderedMap') { 'Metadata dictionary keys' } else { 'Metadata object properties' }
                throw "$subject must be non-empty strings in the current wire format."
            }
            $child = $item['Value']
        }
        else { $child = $item }
        if ($child -isnot [Collections.IDictionary]) {
            throw "Persisted tagged value is malformed: $type child must be a tagged object in the current wire format."
        }
        if ($Recurse) {
            Assert-TerminalCurrentTaggedNode -Node $child -Depth ($Depth + 1) -RequireCanonical:$RequireCanonical
        }
    }
}

function Assert-TerminalMarkdownEnvelope {
    param([Parameter(Mandatory)][Collections.IDictionary]$Envelope)
    $markerVersion = $Envelope['MarkerVersion']
    if ($null -eq $markerVersion -or -not $script:TerminalSlidesWireIntegerTypes.Contains($markerVersion.GetType().FullName) -or
        $Envelope['Presentation'] -isnot [Collections.IDictionary]) {
        throw 'The Markdown TerminalSlides envelope is unsupported.'
    }
    switch ([uint64]$markerVersion) {
        1 { Assert-TerminalExactObjectFields $Envelope @('MarkerVersion','Presentation') 'Markdown TerminalSlides envelope' }
        2 {
            try { Assert-TerminalExactObjectFields $Envelope @('MarkerVersion','ProjectionHash','Presentation') 'Markdown TerminalSlides envelope' }
            catch { throw 'The Markdown TerminalSlides envelope is unsupported.' }
            if ($Envelope['ProjectionHash'] -isnot [string] -or $Envelope['ProjectionHash'] -cnotmatch '\A[0-9a-f]{64}\z') {
                throw 'The Markdown TerminalSlides envelope is unsupported because ProjectionHash is malformed.'
            }
        }
        default { throw 'The Markdown TerminalSlides envelope is unsupported.' }
    }
}
