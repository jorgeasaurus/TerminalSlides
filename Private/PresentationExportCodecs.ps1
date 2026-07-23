function Get-TerminalExportTableShape {
    param([AllowNull()][object]$Data)
    $rows = @($Data)
    $columns = [Collections.Generic.List[string]]::new()
    foreach ($row in $rows) {
        $names = if ($row -is [Collections.IDictionary]) {
            @(Get-TerminalCanonicalDictionaryKeys -Dictionary $row)
        }
        else { @($row.PSObject.Properties.Name) }
        foreach ($name in $names) { if (-not $columns.Contains($name)) { $columns.Add($name) } }
    }
    [pscustomobject]@{ Columns = $columns.ToArray(); Rows = $rows }
}

function ConvertTo-TerminalMarkdownCell {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return '' }
    $rows = Split-TerminalLogicalRows -Text ([string]$Value)
    return ($rows | ForEach-Object { $_.Replace('|', '\|') }) -join '<br>'
}

function ConvertTo-TerminalMarkdownTable {
    param([AllowNull()][object]$Data)
    $shape = Get-TerminalExportTableShape -Data $Data
    if ($shape.Columns.Count -eq 0) { return @('_No data_') }
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add('| ' + (($shape.Columns | ForEach-Object { ConvertTo-TerminalMarkdownCell $_ }) -join ' | ') + ' |')
    $lines.Add('| ' + (($shape.Columns | ForEach-Object { '---' }) -join ' | ') + ' |')
    foreach ($row in $shape.Rows) {
        $values = foreach ($column in $shape.Columns) { ConvertTo-TerminalMarkdownCell (Get-TerminalSemanticProperty $row $column) }
        $lines.Add('| ' + ($values -join ' | ') + ' |')
    }
    return ,$lines.ToArray()
}

function ConvertTo-TerminalHtmlTable {
    param([AllowNull()][object]$Data)
    $encode = { param($Value) ConvertTo-TerminalHtmlEncodedText -Value $Value }
    $shape = Get-TerminalExportTableShape -Data $Data
    if ($shape.Columns.Count -eq 0) { return '<p><em>No data</em></p>' }
    $head = ($shape.Columns | ForEach-Object { '<th>' + (& $encode $_) + '</th>' }) -join ''
    $body = foreach ($row in $shape.Rows) {
        $cells = foreach ($column in $shape.Columns) { '<td>' + (& $encode (Get-TerminalSemanticProperty $row $column)) + '</td>' }
        '<tr>' + ($cells -join '') + '</tr>'
    }
    return '<table><thead><tr>' + $head + '</tr></thead><tbody>' + ($body -join '') + '</tbody></table>'
}

function ConvertTo-TerminalCssColor {
    param(
        [AllowNull()][string]$Value,
        [Parameter(Mandatory)][string]$Fallback
    )

    $color = if ([string]::IsNullOrWhiteSpace($Value)) { $Fallback } else { $Value }
    $rgb = Convert-HexToRgb -Hex $color
    return '#{0:X2}{1:X2}{2:X2}' -f $rgb[0], $rgb[1], $rgb[2]
}

function ConvertTo-TerminalHtmlStyle {
    param([Parameter(Mandatory)][TerminalSlides.Schema.V1.ThemeDefinition]$Theme)

    $background = ConvertTo-TerminalCssColor $Theme.Background '#000000'
    $foreground = ConvertTo-TerminalCssColor $Theme.Foreground '#FFFFFF'
    $primary = ConvertTo-TerminalCssColor $Theme.Primary $foreground
    $accent = ConvertTo-TerminalCssColor $Theme.Accent $primary
    $heading = ConvertTo-TerminalCssColor $Theme.Heading $primary
    $border = ConvertTo-TerminalCssColor $Theme.Border $primary
    $codeBackground = ConvertTo-TerminalCssColor $Theme.CodeBackground $background
    $codeForeground = ConvertTo-TerminalCssColor $Theme.CodeForeground $foreground

    return @"
:root { --ts-background: $background; --ts-foreground: $foreground; --ts-primary: $primary; --ts-accent: $accent; --ts-heading: $heading; --ts-border: $border; --ts-code-background: $codeBackground; --ts-code-foreground: $codeForeground; }
body { font-family: system-ui, sans-serif; background: var(--ts-background); color: var(--ts-foreground); margin: 0; padding: 2rem; }
.slide { background: var(--ts-code-background); border: 1px solid var(--ts-border); border-radius: 12px; padding: 2rem; margin-bottom: 2rem; }
h1, h2, h3, h4, figcaption { color: var(--ts-heading); }
pre { background: var(--ts-code-background); color: var(--ts-code-foreground); padding: 1rem; overflow-x: auto; }
blockquote { border-left: 4px solid var(--ts-accent); margin: 1rem 0; padding-left: 1rem; }
table { border-collapse: collapse; margin: 1rem 0; } th, td { border: 1px solid var(--ts-border); padding: .5rem; text-align: left; }
img { display: block; height: auto; max-width: 100%; }
.box { border: 1px solid var(--ts-primary); border-radius: .5rem; padding: 1rem; }
.slide h2, .slide h3, .slide h4, .slide p, .slide li, .slide th, .slide td, .slide figcaption, .slide footer, .slide .box { white-space: pre-wrap; }
"@
}

function ConvertTo-TerminalMarkdownElement {
    param([Parameter(Mandatory)][TerminalSlides.Schema.V1.SlideElement]$Element)
    $payload = Get-TerminalElementPayload -Element $Element
    switch ($payload.Kind) {
        'Title' { "## $($payload.Raw)" }
        'Subtitle' { "### $($payload.Raw)" }
        'Text' { [string]$payload.Raw }
        'Bullet' { "- $($payload.Raw)" }
        'Code' {
            '```' + $payload.Language + "`n" + $payload.Code + "`n" + '```'
        }
        'Table' { (ConvertTo-TerminalMarkdownTable $payload.Raw) -join "`n" }
        'Chart' {
            $parts = [Collections.Generic.List[string]]::new()
            if ($payload.Title) { $parts.Add("**$($payload.Title)**") }
            if ($payload.ChartType) { $parts.Add("_Chart: $($payload.ChartType)_") }
            $parts.Add((ConvertTo-TerminalMarkdownTable $payload.Raw) -join "`n")
            $parts -join "`n`n"
        }
        'Diagram' {
            $lines = [Collections.Generic.List[string]]::new(); $lines.Add('**Diagram**')
            foreach ($node in $payload.Nodes) { $lines.Add("- [$([string](Get-TerminalSemanticProperty $node Id))] $([string](Get-TerminalSemanticProperty $node Label))") }
            foreach ($edge in $payload.Edges) {
                $label = Get-TerminalSemanticProperty $edge Label; $suffix = if ($label) { " ($label)" } else { '' }
                $lines.Add("- $([string](Get-TerminalSemanticProperty $edge From)) -> $([string](Get-TerminalSemanticProperty $edge To))$suffix")
            }
            $lines -join "`n"
        }
        'Image' {
            $alt = ConvertTo-TerminalMarkdownImageAlt $payload.AltText
            $destination = ConvertTo-TerminalMarkdownImageDestination $payload.Path
            "![$alt]($destination)"
        }
        'Quote' {
            $quoteRows = [string[]](Split-TerminalLogicalRows -Text $payload.Text)
            $lines = @($quoteRows | ForEach-Object { "> $_" })
            if ($payload.Attribution) {
                $attributionRows = [string[]](Split-TerminalLogicalRows -Text $payload.Attribution)
                $lines += "> — $($attributionRows[0])"
                if ($attributionRows.Count -gt 1) {
                    $lines += @($attributionRows[1..($attributionRows.Count - 1)] | ForEach-Object { "> $_" })
                }
            }
            $lines -join "`n"
        }
        'Box' { "> **Key point:** $($payload.Raw)" }
    }
}

function ConvertTo-TerminalHtmlElement {
    param([Parameter(Mandatory)][TerminalSlides.Schema.V1.SlideElement]$Element)
    $encode = { param($Value) ConvertTo-TerminalHtmlEncodedText -Value $Value }
    $payload = Get-TerminalElementPayload -Element $Element
    switch ($payload.Kind) {
        'Title' { '<h3>' + (& $encode $payload.Raw) + '</h3>' }
        'Subtitle' { '<h4>' + (& $encode $payload.Raw) + '</h4>' }
        'Text' { '<p>' + (& $encode $payload.Raw) + '</p>' }
        'Bullet' { '<ul><li>' + (& $encode $payload.Raw) + '</li></ul>' }
        'Code' { '<pre><code class="language-' + (& $encode $payload.Language) + '">' + (& $encode $payload.Code) + '</code></pre>' }
        'Table' { ConvertTo-TerminalHtmlTable $payload.Raw }
        'Chart' {
            $caption = if ($payload.Title) { '<figcaption>' + (& $encode $payload.Title) + '</figcaption>' } else { '' }
            '<figure class="chart" data-chart-type="' + (& $encode $payload.ChartType) + '">' + $caption + (ConvertTo-TerminalHtmlTable $payload.Raw) + '</figure>'
        }
        'Diagram' {
            $nodes = foreach ($node in $payload.Nodes) { '<li><code>' + (& $encode (Get-TerminalSemanticProperty $node Id)) + '</code> ' + (& $encode (Get-TerminalSemanticProperty $node Label)) + '</li>' }
            $edges = foreach ($edge in $payload.Edges) {
                $label = Get-TerminalSemanticProperty $edge Label; $suffix = if ($label) { ' (' + (& $encode $label) + ')' } else { '' }
                '<li>' + (& $encode (Get-TerminalSemanticProperty $edge From)) + ' &rarr; ' + (& $encode (Get-TerminalSemanticProperty $edge To)) + $suffix + '</li>'
            }
            '<figure class="diagram"><figcaption>Diagram</figcaption><ul class="nodes">' + ($nodes -join '') + '</ul><ul class="edges">' + ($edges -join '') + '</ul></figure>'
        }
        'Image' { '<figure class="image"><img src="' + (& $encode $payload.Path) + '" alt="' + (& $encode $payload.AltText) + '" /></figure>' }
        'Quote' {
            $footer = if ($payload.Attribution) { '<footer>&mdash; ' + (& $encode $payload.Attribution) + '</footer>' } else { '' }
            '<blockquote><p>' + (& $encode $payload.Text) + '</p>' + $footer + '</blockquote>'
        }
        'Box' { '<aside class="box">' + (& $encode $payload.Raw) + '</aside>' }
    }
}

function ConvertTo-TerminalMarkdownDocument {
    param([Parameter(Mandatory)][TerminalSlides.Schema.V1.TerminalPresentation]$Presentation)

    $builder = [Text.StringBuilder]::new()
    $themeName = (Resolve-TerminalPresentationTheme -Presentation $Presentation).Name
    [void]$builder.Append("---`n")
    [void]$builder.Append('title: ' + ($Presentation.Title | ConvertTo-Json -Compress) + "`n")
    if ($Presentation.Author) { [void]$builder.Append('author: ' + ($Presentation.Author | ConvertTo-Json -Compress) + "`n") }
    [void]$builder.Append('theme: ' + ($themeName | ConvertTo-Json -Compress) + "`n")
    [void]$builder.Append("---`n`n")
    foreach ($slide in $Presentation.Slides) {
        [void]$builder.Append("# $($slide.Title)`n`n")
        foreach ($element in $slide.Elements) {
            [void]$builder.Append((ConvertTo-TerminalMarkdownElement $element))
            [void]$builder.Append("`n`n")
        }
        if ($slide.Notes) { [void]$builder.Append('<!-- Notes: ' + $slide.Notes + " -->`n`n") }
        [void]$builder.Append("---`n`n")
    }
    return ConvertTo-TerminalLfText -Value $builder.ToString()
}
