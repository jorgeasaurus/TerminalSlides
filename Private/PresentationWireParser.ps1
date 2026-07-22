function Read-TerminalWireTaggedHashtable {
    param(
        [Parameter(Mandatory)][AllowNull()][object]$Node,
        [Parameter(Mandatory)][string]$Subject,
        [switch]$RequireCanonical
    )
    if ($Node -isnot [Collections.IDictionary]) { throw "$Subject must be a tagged object in the current wire format." }
    $value = ConvertFrom-TerminalTaggedValue -Node $Node -RequireCanonical:$RequireCanonical
    return ConvertTo-TerminalHashtableRoot -Value $value -Subject $Subject
}

function Read-TerminalCurrentScalarValue {
    param(
        [Parameter(Mandatory)][Collections.IDictionary]$Data,
        [switch]$RequireCanonical
    )
    Assert-TerminalWireObject $Data @('Name','Kind','Value') 'Current wire table cell'
    if ($Data['Name'] -isnot [string] -or [string]::IsNullOrWhiteSpace($Data['Name'])) {
        throw 'Table column names must be non-empty strings in the current wire format.'
    }
    $kind = Read-TerminalWireEnum $Data['Kind'] ([TerminalSlides.Schema.V1.ScalarKind]) 'Current wire table cell Kind'
    if ($kind -eq [TerminalSlides.Schema.V1.ScalarKind]::Null) {
        if ($null -ne $Data['Value']) { throw 'Current wire Null table cell Value must be null.' }
        $text = [Management.Automation.Language.NullString]::Value
    }
    else {
        Assert-TerminalWireString $Data['Value'] 'Current wire table cell Value'
        $text = ConvertFrom-TerminalPersistedScalarText -Kind $kind.ToString() -Value $Data['Value']
    }
    $scalar = [TerminalSlides.Schema.V1.ScalarValue]::new($kind, $text)
    try { $decoded = ConvertFrom-TerminalScalarValue $scalar }
    catch { throw "Current wire table cell Value is invalid for kind '$kind': $($_.Exception.Message)" }
    if ($RequireCanonical -and $kind -ne [TerminalSlides.Schema.V1.ScalarKind]::Null) {
        if ($kind -eq [TerminalSlides.Schema.V1.ScalarKind]::DateTime) {
            Assert-TerminalCanonicalTaggedScalarText -Type DateTime -Value $Data['Value']
        }
        else {
            $canonical = ConvertTo-TerminalScalarValue $decoded
            if ($canonical.Value -cne $Data['Value']) {
                throw "Current wire table cell Value for kind '$kind' is not canonical."
            }
        }
    }
    return [TerminalSlides.Schema.V1.DataCell]::new([string]$Data['Name'], $scalar)
}

function Read-TerminalCurrentPayload {
    param(
        [Parameter(Mandatory)][TerminalSlides.Schema.V1.ElementKind]$Kind,
        [AllowNull()][object]$Data,
        [switch]$RequireCanonical
    )
    $fields = switch ($Kind.ToString()) {
        { $_ -in 'Title','Subtitle','Text','Bullet','Box' } { @('Text') }
        'Code' { @('Code','Language') }
        'Image' { @('Path','AltText') }
        'Quote' { @('Text','Attribution') }
        'Chart' { @('ChartKind','Title','Points') }
        'Diagram' { @('Nodes','Edges') }
        'Table' { @('Rows') }
    }
    Assert-TerminalWireObject $Data $fields "Current wire $Kind payload"
    switch ($Kind.ToString()) {
        { $_ -in 'Title','Subtitle','Text','Bullet','Box' } {
            Assert-TerminalWireString $Data['Text'] "Current wire $Kind payload Text"
            return [TerminalSlides.Schema.V1.TextPayload]::new([string]$Data['Text'])
        }
        'Code' {
            Assert-TerminalWireString $Data['Code'] 'Current wire Code payload Code'
            Assert-TerminalWireString $Data['Language'] 'Current wire Code payload Language'
            if ([string]::IsNullOrWhiteSpace($Data['Language'])) { throw 'Current wire Code payload Language must be nonblank.' }
            return [TerminalSlides.Schema.V1.CodePayload]::new([string]$Data['Code'], [string]$Data['Language'])
        }
        'Image' {
            Assert-TerminalWireString $Data['Path'] 'Current wire Image payload Path'
            Assert-TerminalWireString $Data['AltText'] 'Current wire Image payload AltText' -AllowNull
            if ([string]::IsNullOrWhiteSpace($Data['Path'])) { throw 'Current wire Image payload Path must be nonblank.' }
            return [TerminalSlides.Schema.V1.ImagePayload]::new([string]$Data['Path'], [string]$Data['AltText'])
        }
        'Quote' {
            Assert-TerminalWireString $Data['Text'] 'Current wire Quote payload Text'
            Assert-TerminalWireString $Data['Attribution'] 'Current wire Quote payload Attribution' -AllowNull
            return [TerminalSlides.Schema.V1.QuotePayload]::new([string]$Data['Text'], [string]$Data['Attribution'])
        }
        'Chart' {
            $chartKind = Read-TerminalWireEnum $Data['ChartKind'] ([TerminalSlides.Schema.V1.ChartKind]) 'Current wire ChartKind'
            Assert-TerminalWireString $Data['Title'] 'Current wire Chart payload Title' -AllowNull
            Assert-TerminalWireArray $Data['Points'] 'Current wire Chart payload Points'
            $points = foreach ($point in $Data['Points']) {
                Assert-TerminalWireObject $point @('Label','Value') 'Current wire chart point'
                Assert-TerminalWireString $point['Label'] 'Current wire chart point Label'
                Assert-TerminalWireString $point['Value'] 'Current wire chart point Value'
                try { $number = [decimal]::Parse($point['Value'], [Globalization.CultureInfo]::InvariantCulture) }
                catch { throw "Current wire chart point Value '$($point['Value'])' is not a valid Decimal." }
                if ($RequireCanonical -and $number.ToString([Globalization.CultureInfo]::InvariantCulture) -cne $point['Value']) {
                    throw "Current wire chart point Value '$($point['Value'])' is not canonical."
                }
                [TerminalSlides.Schema.V1.ChartPoint]::new([string]$point['Label'], $number)
            }
            return [TerminalSlides.Schema.V1.ChartPayload]::new([TerminalSlides.Schema.V1.ChartPoint[]]@($points), $chartKind, [string]$Data['Title'])
        }
        'Diagram' {
            Assert-TerminalWireArray $Data['Nodes'] 'Current wire Diagram payload Nodes'
            Assert-TerminalWireArray $Data['Edges'] 'Current wire Diagram payload Edges'
            $nodes = foreach ($node in $Data['Nodes']) {
                Assert-TerminalWireObject $node @('Id','Label') 'Current wire diagram node'
                Assert-TerminalWireString $node['Id'] 'Current wire diagram node Id'
                Assert-TerminalWireString $node['Label'] 'Current wire diagram node Label'
                if ([string]::IsNullOrWhiteSpace($node['Id'])) { throw 'Current wire diagram node Id must be nonblank.' }
                [TerminalSlides.Schema.V1.DiagramNode]::new([string]$node['Id'], [string]$node['Label'])
            }
            $edges = foreach ($edge in $Data['Edges']) {
                Assert-TerminalWireObject $edge @('From','To','Label') 'Current wire diagram edge'
                Assert-TerminalWireString $edge['From'] 'Current wire diagram edge From'
                Assert-TerminalWireString $edge['To'] 'Current wire diagram edge To'
                Assert-TerminalWireString $edge['Label'] 'Current wire diagram edge Label' -AllowNull
                if ([string]::IsNullOrWhiteSpace($edge['From']) -or [string]::IsNullOrWhiteSpace($edge['To'])) {
                    throw 'Current wire diagram edge endpoints must be nonblank.'
                }
                [TerminalSlides.Schema.V1.DiagramEdge]::new([string]$edge['From'], [string]$edge['To'], [string]$edge['Label'])
            }
            return [TerminalSlides.Schema.V1.DiagramPayload]::new(
                [TerminalSlides.Schema.V1.DiagramNode[]]@($nodes), [TerminalSlides.Schema.V1.DiagramEdge[]]@($edges)
            )
        }
        'Table' {
            Assert-TerminalWireArray $Data['Rows'] 'Current wire table Rows'
            $rows = foreach ($row in $Data['Rows']) {
                Assert-TerminalWireObject $row @('Cells') 'Current wire table row'
                Assert-TerminalWireArray $row['Cells'] 'Current wire table row Cells'
                $cells = foreach ($cell in $row['Cells']) {
                    Read-TerminalCurrentScalarValue -Data $cell -RequireCanonical:$RequireCanonical
                }
                [TerminalSlides.Schema.V1.DataRow]::new([TerminalSlides.Schema.V1.DataCell[]]@($cells))
            }
            $typedRows = [TerminalSlides.Schema.V1.DataRow[]]@($rows)
            Assert-TerminalTableColumnIdentity -Rows $typedRows
            return [TerminalSlides.Schema.V1.TablePayload]::new($typedRows)
        }
    }
}

function Read-TerminalCurrentElement {
    param([AllowNull()][object]$Data, [switch]$RequireCanonical)
    $fields = @('Id','Kind','Payload','Region','X','Y','Width','Height','Alignment','VerticalAlignment','Padding',
        'ForegroundColor','BackgroundColor','Border','BorderStyle','RevealStep','OverflowBehavior')
    Assert-TerminalWireObject $Data $fields 'Current wire slide element'
    Assert-TerminalWireString $Data['Id'] 'Current wire element Id' -AllowNull
    $kind = Read-TerminalWireEnum $Data['Kind'] ([TerminalSlides.Schema.V1.ElementKind]) 'Current wire element Kind'
    $payload = Read-TerminalCurrentPayload -Kind $kind -Data $Data['Payload'] -RequireCanonical:$RequireCanonical
    $element = [TerminalSlides.Schema.V1.SlideElement]::new($kind, $payload)
    $element.Id = [string]$Data['Id']
    $element.Region = Read-TerminalWireDomainName $Data['Region'] $script:TerminalElementRegionOrder 'Current wire element Region'
    $element.Alignment = Read-TerminalWireDomainName $Data['Alignment'] @('Left','Center','Right') 'Current wire element Alignment'
    $element.VerticalAlignment = Read-TerminalWireDomainName $Data['VerticalAlignment'] @('Top','Middle','Bottom') 'Current wire element VerticalAlignment'
    $element.ForegroundColor = Read-TerminalWireHexColor $Data['ForegroundColor'] 'Current wire element ForegroundColor' -AllowDefault
    $element.BackgroundColor = Read-TerminalWireHexColor $Data['BackgroundColor'] 'Current wire element BackgroundColor' -AllowDefault
    $element.BorderStyle = Read-TerminalWireDomainName $Data['BorderStyle'] @('unicode','ascii','double','rounded','single') 'Current wire element BorderStyle'
    $element.OverflowBehavior = Read-TerminalWireDomainName $Data['OverflowBehavior'] @('Wrap','Truncate','Scroll') 'Current wire element OverflowBehavior'
    foreach ($field in 'X','Y','Width','Height','Padding') { $element.$field = Read-TerminalWireInt32 $Data[$field] "Current wire element $field" }
    $element.RevealStep = Read-TerminalWireInt32 $Data['RevealStep'] 'Current wire element RevealStep'
    Assert-TerminalWireBoolean $Data['Border'] 'Current wire element Border'
    $element.Border = [bool]$Data['Border']
    return $element
}

function Read-TerminalCurrentSlide {
    param([AllowNull()][object]$Data, [switch]$RequireCanonical)
    $fields = @('Id','Index','Title','Layout','Notes','Background','Transition','Hidden','MaxRevealStep','Metadata','Elements')
    Assert-TerminalWireObject $Data $fields 'Current wire slide'
    $slide = [TerminalSlides.Schema.V1.Slide]::new()
    foreach ($field in 'Id','Title','Notes','Transition') { Assert-TerminalWireString $Data[$field] "Current wire slide $field" -AllowNull; $slide.$field = $Data[$field] }
    $slide.Index = Read-TerminalWireInt32 $Data['Index'] 'Current wire slide Index' 0
    $slide.Layout = Read-TerminalWireDomainName $Data['Layout'] $script:TerminalSlideLayouts 'Current wire slide Layout'
    $slide.Background = Read-TerminalWireHexColor $Data['Background'] 'Current wire slide Background' -AllowDefault
    Assert-TerminalWireBoolean $Data['Hidden'] 'Current wire slide Hidden'; $slide.Hidden = [bool]$Data['Hidden']
    [void](Read-TerminalWireInt32 $Data['MaxRevealStep'] 'Current wire slide MaxRevealStep')
    Assert-TerminalWireObject $Data['Metadata'] @('Author','Custom') 'Current wire slide Metadata'
    Assert-TerminalWireString $Data.Metadata['Author'] 'Current wire slide metadata Author' -AllowNull
    $slide.Metadata.Author = $Data.Metadata['Author']
    $slide.Metadata.Custom = Read-TerminalWireTaggedHashtable $Data.Metadata['Custom'] 'Current wire slide Metadata Custom' -RequireCanonical:$RequireCanonical
    Assert-TerminalWireArray $Data['Elements'] 'Current wire slide Elements'
    foreach ($elementData in $Data['Elements']) { $slide.Elements.Add((Read-TerminalCurrentElement $elementData -RequireCanonical:$RequireCanonical)) }
    $slide.MaxRevealStep = Get-TerminalSlideMaximumRevealStep -Slide $slide
    return $slide
}

function Read-TerminalCurrentThemeDefinition {
    param([AllowNull()][object]$Data, [switch]$RequireCanonical)
    $fields = @('Name','Background','Foreground','Primary','Accent','Muted','Heading','Border','CodeTheme','CodeBackground',
        'CodeForeground','BulletSymbol','BoxDrawingStyle','HeadingStyle','ChartPalette','ErrorColor','WarningColor','SuccessColor','Metadata')
    Assert-TerminalWireObject $Data $fields 'Current wire ThemeDefinition'
    $theme = [TerminalSlides.Schema.V1.ThemeDefinition]::new()
    foreach ($field in 'Name','CodeTheme','BulletSymbol') {
        Assert-TerminalWireString $Data[$field] "Current wire ThemeDefinition $field"
        if ([string]::IsNullOrWhiteSpace($Data[$field])) { throw "Current wire ThemeDefinition $field must be nonblank." }
        $theme.$field = $Data[$field]
    }
    foreach ($field in 'Background','Foreground','Primary','Accent','Muted','Heading','Border','ErrorColor','WarningColor','SuccessColor') {
        $theme.$field = Read-TerminalWireHexColor $Data[$field] "Current wire ThemeDefinition $field"
    }
    foreach ($field in 'CodeBackground','CodeForeground') { $theme.$field = Read-TerminalWireHexColor $Data[$field] "Current wire ThemeDefinition $field" -AllowDefault }
    $theme.BoxDrawingStyle = Read-TerminalWireDomainName $Data['BoxDrawingStyle'] @('unicode','ascii','double','rounded','single') 'Current wire ThemeDefinition BoxDrawingStyle'
    $theme.HeadingStyle = Read-TerminalWireDomainName $Data['HeadingStyle'] @('plain','bold','banner') 'Current wire ThemeDefinition HeadingStyle'
    Assert-TerminalWireArray $Data['ChartPalette'] 'Current wire ThemeDefinition ChartPalette'
    if ($Data['ChartPalette'].Count -eq 0) { throw 'Current wire ThemeDefinition ChartPalette must not be empty.' }
    $theme.ChartPalette = [string[]]@($Data['ChartPalette'] | ForEach-Object { Read-TerminalWireHexColor $_ 'Current wire ThemeDefinition ChartPalette' })
    $theme.Metadata = Read-TerminalWireTaggedHashtable $Data['Metadata'] 'Current wire ThemeDefinition Metadata' -RequireCanonical:$RequireCanonical
    return $theme
}

function Read-TerminalCurrentPresentation {
    param([AllowNull()][object]$Data, [switch]$RequireThemeDefinition)
    $fields = @('Title','Subtitle','Author','Description','Theme','Width','Height','DefaultTransition','DefaultLayout',
        'CreatedDate','ModifiedDate','Metadata','Configuration','Slides')
    if ($RequireThemeDefinition) { $fields = @($fields[0..4] + 'ThemeDefinition' + $fields[5..($fields.Count - 1)]) }
    Assert-TerminalWireObject $Data $fields 'Current wire Presentation'
    $presentation = [TerminalSlides.Schema.V1.TerminalPresentation]::new()
    foreach ($field in 'Title','Subtitle','Author','Description','DefaultTransition') {
        Assert-TerminalWireString $Data[$field] "Current wire Presentation $field" -AllowNull
        $presentation.$field = $Data[$field]
    }
    if ($RequireThemeDefinition) {
        Assert-TerminalWireString $Data['Theme'] 'Current wire Presentation Theme'
        $theme = Read-TerminalCurrentThemeDefinition $Data['ThemeDefinition'] -RequireCanonical
        if ($Data['Theme'] -cne $theme.Name) { throw 'Current wire Presentation Theme must exactly match ThemeDefinition Name.' }
        $presentation.Theme = $theme.Name
        $presentation.EmbeddedTheme = $theme
    }
    else {
        Assert-TerminalWireString $Data['Theme'] 'Current wire Presentation Theme'
        try {
            $resolvedTheme = Get-ResolvedTheme -Name $Data['Theme']
            $presentation.Theme = $resolvedTheme.Name
            $presentation.EmbeddedTheme = Copy-TerminalThemeDefinition $resolvedTheme
        }
        catch { throw "Current wire Presentation Theme has unsupported value '$($Data['Theme'])'." }
    }
    $presentation.Width = Read-TerminalWireInt32 $Data['Width'] 'Current wire Presentation Width'
    $presentation.Height = Read-TerminalWireInt32 $Data['Height'] 'Current wire Presentation Height'
    $presentation.DefaultLayout = Read-TerminalWireDomainName $Data['DefaultLayout'] $script:TerminalSlideLayouts 'Current wire Presentation DefaultLayout'
    foreach ($field in 'CreatedDate','ModifiedDate') {
        Assert-TerminalWireString $Data[$field] "Current wire Presentation $field"
        if ($RequireThemeDefinition) {
            try { Assert-TerminalCanonicalTaggedScalarText -Type DateTime -Value $Data[$field] }
            catch { throw "Current wire Presentation $field is invalid: $($_.Exception.Message)" }
        }
    }
    try { $presentation.CreatedDate = ConvertFrom-TerminalDateTimeText $Data['CreatedDate'] }
    catch { throw "Current wire Presentation CreatedDate is invalid: $($_.Exception.Message)" }
    try { $modified = ConvertFrom-TerminalDateTimeText $Data['ModifiedDate'] }
    catch { throw "Current wire Presentation ModifiedDate is invalid: $($_.Exception.Message)" }
    Assert-TerminalWireObject $Data['Metadata'] @('Title','Subtitle','Author','Description','Version','Custom') 'Current wire Presentation Metadata'
    foreach ($field in 'Title','Subtitle','Author','Description','Version') {
        Assert-TerminalWireString $Data.Metadata[$field] "Current wire presentation metadata $field" -AllowNull
        $presentation.Metadata.$field = $Data.Metadata[$field]
    }
    $presentation.Metadata.Custom = Read-TerminalWireTaggedHashtable $Data.Metadata['Custom'] 'Current wire Presentation Metadata Custom' -RequireCanonical:$RequireThemeDefinition
    $presentation.Configuration = Read-TerminalWireTaggedHashtable $Data['Configuration'] 'Current wire Presentation Configuration' -RequireCanonical:$RequireThemeDefinition
    Assert-TerminalWireArray $Data['Slides'] 'Current wire Presentation Slides'
    foreach ($slideData in $Data['Slides']) { $presentation.Slides.Add((Read-TerminalCurrentSlide $slideData -RequireCanonical:$RequireThemeDefinition)) }
    Update-SlideIndices $presentation
    $presentation.ModifiedDate = $modified
    try { Assert-TerminalWireReadyPresentationModel -Presentation $presentation }
    catch { throw "Current wire Presentation is semantically invalid: $($_.Exception.Message)" }
    return $presentation
}

function ConvertFrom-TerminalCurrentData {
    param([Parameter(Mandatory)][Collections.IDictionary]$Envelope)
    Assert-TerminalExactObjectFields $Envelope @('$schema','SchemaVersion','Presentation') 'Current wire envelope'
    Assert-TerminalWireString $Envelope['$schema'] 'Current wire envelope $schema'
    $version = Read-TerminalWireInt32 $Envelope['SchemaVersion'] 'Current wire envelope SchemaVersion' 1
    $isCurrent = $Envelope['$schema'] -ceq $script:TerminalSlidesWireSchema -and $version -eq $script:TerminalSlidesWireVersion
    $isLegacy = $Envelope['$schema'] -ceq $script:TerminalSlidesLegacyWireSchema -and $version -eq $script:TerminalSlidesLegacyWireVersion
    if (-not $isCurrent -and -not $isLegacy) { throw "Unsupported TerminalSlides schema '$($Envelope['$schema'])' version '$version'." }
    return Read-TerminalCurrentPresentation $Envelope['Presentation'] -RequireThemeDefinition:$isCurrent
}
