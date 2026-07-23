function Get-TerminalMarkdownProjectionHash {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$VisibleDocument,
        [Parameter(Mandatory)][System.Collections.IDictionary]$PresentationData
    )

    $binding = [ordered]@{
        Visible = ConvertTo-TerminalLfText -Value $VisibleDocument
        Presentation = $PresentationData
    }
    $bytes = $script:TerminalSlidesStrictUtf8.GetBytes((ConvertTo-TerminalWireJson $binding))
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}

function ConvertTo-TerminalMarkdownV1Cell {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return '' }
    return ([string]$Value).Replace('|', '\|') -replace '\r?\n', '<br>'
}

function ConvertTo-TerminalMarkdownV1Table {
    param(
        [AllowNull()][object]$Data,
        [switch]$CompleteColumns
    )

    $rows = @($Data)
    if ($rows.Count -eq 0) { return @('_No data_') }
    $columns = [Collections.Generic.List[string]]::new()
    $columnRows = if ($CompleteColumns) { $rows } else { @($rows[0]) }
    foreach ($row in $columnRows) {
        $names = if ($row -is [Collections.IDictionary]) {
            @(Get-TerminalCanonicalDictionaryKeys -Dictionary $row)
        }
        else { @($row.PSObject.Properties.Name) }
        foreach ($name in $names) { if (-not $columns.Contains($name)) { $columns.Add($name) } }
    }
    if ($columns.Count -eq 0) { return @('_No data_') }
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add('| ' + (($columns | ForEach-Object { ConvertTo-TerminalMarkdownV1Cell $_ }) -join ' | ') + ' |')
    $lines.Add('| ' + (($columns | ForEach-Object { '---' }) -join ' | ') + ' |')
    foreach ($row in $rows) {
        $values = foreach ($column in $columns) {
            ConvertTo-TerminalMarkdownV1Cell (Get-TerminalSemanticProperty $row $column)
        }
        $lines.Add('| ' + ($values -join ' | ') + ' |')
    }
    return ,$lines.ToArray()
}

function ConvertTo-TerminalMarkdownV1ImageAlt {
    param([AllowNull()][string]$Text)
    return ([string]$Text).Replace('\', '\\').Replace(']', '\]')
}

function ConvertTo-TerminalMarkdownV1ImageDestination {
    param([Parameter(Mandatory)][string]$Path)
    $normalized = $Path.Replace('\', '/')
    $encoded = ($normalized -split '/' | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/'
    return '<' + $encoded.Replace('>', '%3E').Replace('<', '%3C') + '>'
}

function ConvertTo-TerminalMarkdownV1Element {
    param(
        [Parameter(Mandatory)][TerminalSlides.Schema.V1.SlideElement]$Element,
        [switch]$CompleteColumns
    )

    $payload = Get-TerminalElementPayload -Element $Element
    switch ($payload.Kind) {
        'Title' { return "## $($payload.Raw)" }
        'Subtitle' { return "### $($payload.Raw)" }
        'Text' { return [string]$payload.Raw }
        'Bullet' { return "- $($payload.Raw)" }
        'Code' { return '```' + $payload.Language + "`n" + $payload.Code + "`n" + '```' }
        'Table' { return (ConvertTo-TerminalMarkdownV1Table $payload.Raw -CompleteColumns:$CompleteColumns) -join "`n" }
        'Chart' {
            $parts = [Collections.Generic.List[string]]::new()
            if ($payload.Title) { $parts.Add("**$($payload.Title)**") }
            if ($payload.ChartType) { $parts.Add("_Chart: $($payload.ChartType)_") }
            $parts.Add((ConvertTo-TerminalMarkdownV1Table $payload.Raw -CompleteColumns:$CompleteColumns) -join "`n")
            return $parts -join "`n`n"
        }
        'Diagram' {
            $lines = [Collections.Generic.List[string]]::new()
            $lines.Add('**Diagram**')
            foreach ($node in $payload.Nodes) {
                $lines.Add("- [$([string](Get-TerminalSemanticProperty $node Id))] $([string](Get-TerminalSemanticProperty $node Label))")
            }
            foreach ($edge in $payload.Edges) {
                $label = Get-TerminalSemanticProperty $edge Label
                $suffix = if ($label) { " ($label)" } else { '' }
                $lines.Add("- $([string](Get-TerminalSemanticProperty $edge From)) -> $([string](Get-TerminalSemanticProperty $edge To))$suffix")
            }
            return $lines -join "`n"
        }
        'Image' {
            $alt = ConvertTo-TerminalMarkdownV1ImageAlt $payload.AltText
            $destination = ConvertTo-TerminalMarkdownV1ImageDestination $payload.Path
            return "![$alt]($destination)"
        }
        'Quote' {
            $lines = @(([string]$payload.Text -split '\r?\n') | ForEach-Object { "> $_" })
            if ($payload.Attribution) { $lines += "> — $($payload.Attribution)" }
            return $lines -join "`n"
        }
        'Box' { return "> **Key point:** $($payload.Raw)" }
    }
}

function ConvertTo-TerminalMarkdownV1Document {
    param(
        [Parameter(Mandatory)][TerminalSlides.Schema.V1.TerminalPresentation]$Presentation,
        [AllowNull()][string]$SourceThemeName,
        [switch]$CompleteColumns
    )

    $builder = [Text.StringBuilder]::new()
    [void]$builder.Append("---`n")
    [void]$builder.Append('title: ' + ($Presentation.Title | ConvertTo-Json -Compress) + "`n")
    if ($Presentation.Author) { [void]$builder.Append('author: ' + ($Presentation.Author | ConvertTo-Json -Compress) + "`n") }
    if ($SourceThemeName) { [void]$builder.Append('theme: ' + ($SourceThemeName | ConvertTo-Json -Compress) + "`n") }
    [void]$builder.Append("---`n`n")
    foreach ($slide in $Presentation.Slides) {
        [void]$builder.Append("# $($slide.Title)`n`n")
        foreach ($element in $slide.Elements) {
            [void]$builder.Append((ConvertTo-TerminalMarkdownV1Element $element -CompleteColumns:$CompleteColumns))
            [void]$builder.Append("`n`n")
        }
        if ($slide.Notes) { [void]$builder.Append('<!-- Notes: ' + $slide.Notes + " -->`n`n") }
        [void]$builder.Append("---`n`n")
    }
    return ConvertTo-TerminalLfText -Value $builder.ToString()
}

function Test-TerminalMarkdownV1Projection {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$VisibleDocument,
        [Parameter(Mandatory)][TerminalSlides.Schema.V1.TerminalPresentation]$Presentation,
        [AllowNull()][string]$SourceThemeName
    )

    $actual = ConvertTo-TerminalLfText -Value $VisibleDocument
    $canonicalTheme = (Resolve-TerminalPresentationTheme -Presentation $Presentation).Name
    $cycle19 = ConvertTo-TerminalMarkdownV1Document $Presentation $canonicalTheme -CompleteColumns
    if ($actual -ceq (ConvertTo-TerminalLfText -Value $cycle19)) { return $true }
    $original = ConvertTo-TerminalMarkdownV1Document $Presentation $SourceThemeName
    return $actual -ceq (ConvertTo-TerminalLfText -Value $original)
}
