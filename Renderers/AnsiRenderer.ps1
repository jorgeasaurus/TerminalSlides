function ConvertTo-TableLines {
    param([object]$Content)
    $rows = @()
    if ($Content -is [System.Collections.IDictionary]) {
        $rows = @([pscustomobject]$Content)
    }
    elseif ($Content -is [System.Collections.IEnumerable] -and $Content -isnot [string]) {
        $rows = @($Content)
    }
    else {
        return ,@([string]$Content)
    }
    if (-not $rows.Count) { return ,@('') }
    $first = $rows[0]
    $headers = if ($first -is [System.Collections.IDictionary]) { @($first.Keys) } else { @($first.PSObject.Properties.Name) }
    $widths = @{}
    foreach ($header in $headers) { $widths[$header] = [Math]::Max($header.Length, 3) }
    foreach ($row in $rows) {
        foreach ($header in $headers) {
            $value = if ($row -is [System.Collections.IDictionary]) { [string]$row[$header] } else { [string]$row.$header }
            $widths[$header] = [Math]::Max($widths[$header], (Measure-TextWidth -Text $value))
        }
    }
    $headerLine = '| ' + (($headers | ForEach-Object { $_.PadRight($widths[$_]) }) -join ' | ') + ' |'
    $separator = '|-' + (($headers | ForEach-Object { ''.PadLeft($widths[$_], '-') }) -join '-|-') + '-|'
    $output = [System.Collections.Generic.List[string]]::new()
    $output.Add($headerLine)
    $output.Add($separator)
    foreach ($row in $rows) {
        $output.Add('| ' + (($headers | ForEach-Object {
            $value = if ($row -is [System.Collections.IDictionary]) { [string]$row[$_] } else { [string]$row.$_ }
            $value.PadRight($widths[$_])
        }) -join ' | ') + ' |')
    }
    return ,$output.ToArray()
}

function ConvertTo-ChartLines {
    param([object]$Content, [hashtable]$Properties, [ThemeDefinition]$Theme, [int]$Width)
    $items = @($Content)
    if (-not $items.Count) { return ,@('No chart data') }
    $chartType = ($Properties.ChartType ?? 'HorizontalBar')
    switch ($chartType) {
        'Gauge' {
            $value = [double]($items[0].Value)
            $filled = [Math]::Round(($Width - 10) * ($value / 100))
            $filled = [Math]::Max(0, [Math]::Min($Width - 10, $filled))
            return ,@("[$(('█' * $filled) + ('░' * ([Math]::Max(0, ($Width - 10 - $filled)))))] $value%")
        }
        'Sparkline' {
            $values = @($items | ForEach-Object { [double]$_.Value })
            $blocks = '▁▂▃▄▅▆▇█'.ToCharArray()
            $min = ($values | Measure-Object -Minimum).Minimum
            $max = ($values | Measure-Object -Maximum).Maximum
            if ($max -eq $min) { $max = $min + 1 }
            $spark = -join ($values | ForEach-Object {
                $idx = [int][Math]::Round((($_ - $min) / ($max - $min)) * ($blocks.Length - 1))
                $blocks[$idx]
            })
            return ,@($spark)
        }
        'Bar' {
            $max = [double](($items | ForEach-Object { $_.Value } | Measure-Object -Maximum).Maximum)
            if ($max -le 0) { $max = 1 }
            $rows = [System.Collections.Generic.List[string]]::new()
            foreach ($item in $items) {
                $count = [Math]::Max(1, [Math]::Round((([double]$item.Value) / $max) * ([Math]::Max(1, $Width - 12))))
                $rows.Add(('{0,-10} {1}' -f $item.Label, ('█' * $count)))
            }
            return ,$rows.ToArray()
        }
        'Line' {
            $values = @($items | ForEach-Object { [double]$_.Value })
            $rows = [System.Collections.Generic.List[string]]::new()
            $rows.Add((ConvertTo-ChartLines -Content $Content -Properties @{ ChartType='Sparkline' } -Theme $Theme -Width $Width)[0])
            $rows.Add(($items | ForEach-Object { "{0}: {1}" -f $_.Label, $_.Value }) -join '  ')
            return ,$rows.ToArray()
        }
        default {
            $max = [double](($items | ForEach-Object { $_.Value } | Measure-Object -Maximum).Maximum)
            if ($max -le 0) { $max = 1 }
            $rows = [System.Collections.Generic.List[string]]::new()
            foreach ($item in $items) {
                $label = [string]$item.Label
                $count = [Math]::Max(1, [Math]::Round((([double]$item.Value) / $max) * ([Math]::Max(1, $Width - 20))))
                $rows.Add(('{0,-12} {1} {2}' -f $label, ('█' * $count), $item.Value))
            }
            return ,$rows.ToArray()
        }
    }
}

function ConvertTo-DiagramLines {
    param([hashtable]$Content)
    $nodes = @($Content.Nodes)
    $edges = @($Content.Edges)
    if (-not $nodes.Count) { return ,@('Empty diagram') }
    $lines = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $nodes.Count; $i++) {
        $node = $nodes[$i]
        $box = "[$($node.Id)] $($node.Label)"
        $lines.Add($box)
        foreach ($edge in $edges | Where-Object { $_.From -eq $node.Id }) {
            $target = $nodes | Where-Object Id -eq $edge.To | Select-Object -First 1
            if ($target) {
                $label = if ($edge.Label) { " ($($edge.Label))" } else { '' }
                $lines.Add("  └─> [$($target.Id)] $($target.Label)$label")
            }
        }
    }
    return ,$lines.ToArray()
}

function ConvertTo-ElementLines {
    param([SlideElement]$Element, [ThemeDefinition]$Theme, [int]$Width)
    $contentText = if ($Element.Content -is [string]) { $Element.Content } else { $null }
    switch ($Element.Type) {
        'Title' { return ,(Format-WordWrap -Text $contentText -Width $Width) }
        'Subtitle' { return ,(Format-WordWrap -Text $contentText -Width $Width) }
        'Text' { return ,(Format-WordWrap -Text $contentText -Width $Width -OverflowBehavior $Element.OverflowBehavior) }
        'Bullet' {
            $prefix = "$($Theme.BulletSymbol) "
            $wrapped = Format-WordWrap -Text $contentText -Width ([Math]::Max(1, $Width - $prefix.Length))
            $result = [System.Collections.Generic.List[string]]::new()
            for ($i = 0; $i -lt $wrapped.Count; $i++) {
                if ($i -eq 0) { $result.Add($prefix + $wrapped[$i]) }
                else { $result.Add((' ' * $prefix.Length) + $wrapped[$i]) }
            }
            return ,$result.ToArray()
        }
        'Code' {
            $code = if ($Element.Content -is [string]) {
                $Element.Content
            }
            elseif ($Element.Content -is [System.Collections.IDictionary]) {
                [string]$Element.Content['Code']
            }
            else {
                [string]$Element.Content.Code
            }
            return ,(Format-WordWrap -Text ($code -replace "`r", '') -Width $Width -OverflowBehavior 'Scroll')
        }
        'Table' { return ,(ConvertTo-TableLines -Content $Element.Content) }
        'Chart' { return ,(ConvertTo-ChartLines -Content $Element.Content -Properties $Element.Properties -Theme $Theme -Width $Width) }
        'Diagram' { return ,(ConvertTo-DiagramLines -Content $Element.Content) }
        'Image' {
            $path = if ($Element.Content -is [hashtable]) { $Element.Content.Path } else { [string]$Element.Content }
            $alt = if ($Element.Content -is [hashtable]) { [string]($Element.Content.AltText ?? '') } else { '' }
            return ,@("Image: $path", $alt)
        }
        'Quote' {
            $lines = [System.Collections.Generic.List[string]]::new()
            foreach ($line in (Format-WordWrap -Text ('“' + $Element.Content.Text + '”') -Width $Width)) { $lines.Add($line) }
            if ($Element.Content.Attribution) { $lines.Add("— $($Element.Content.Attribution)") }
            return ,$lines.ToArray()
        }
        'Box' {
            $inner = Format-WordWrap -Text $contentText -Width ([Math]::Max(1, $Width - 4))
            $border = '+' + ('-' * ([Math]::Max(1, $Width - 2))) + '+'
            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add($border)
            foreach ($line in $inner) { $lines.Add('| ' + $line.PadRight([Math]::Max(1, $Width - 4)) + ' |') }
            $lines.Add($border)
            return ,$lines.ToArray()
        }
        default {
            if ($Element.Content -is [string]) { return ,(Format-WordWrap -Text $Element.Content -Width $Width) }
            return ,@([string]$Element.Content)
        }
    }
}

function Write-LinesToFrame {
    param(
        [FrameBuffer]$FrameBuffer,
        [string[]]$Lines,
        [hashtable]$Region,
        [ThemeDefinition]$Theme,
        [SlideElement]$Element,
        [int]$StartY
    )
    $fg = if ($Element.ForegroundColor) { $Element.ForegroundColor } else { $Theme.Foreground }
    $bg = if ($Element.BackgroundColor) { $Element.BackgroundColor } else { $null }
    $y = $StartY
    $usableWidth = [Math]::Max(1, $Region.Width - ($Element.Padding * 2))
    foreach ($line in $Lines) {
        if ($y -ge ($Region.Y + $Region.Height)) { break }
        $text = Strip-AnsiSequences -Text $line
        $display = if ((Measure-TextWidth -Text $text) -gt $usableWidth) { $text.Substring(0, $usableWidth) } else { $text }
        $x = $Region.X + $Element.Padding
        switch ($Element.Alignment) {
            'Center' { $x = $Region.X + [Math]::Max(0, [Math]::Floor(($Region.Width - (Measure-TextWidth -Text $display)) / 2)) }
            'Right' { $x = $Region.X + [Math]::Max(0, $Region.Width - (Measure-TextWidth -Text $display) - $Element.Padding) }
        }
        Set-FrameText -FrameBuffer $FrameBuffer -X $x -Y $y -Text $display -Foreground $fg -Background $bg -Bold:($Element.Type -eq 'Title') -Italic:($Element.Type -eq 'Subtitle')
        $y++
    }
    return $y
}

function Get-SlideRenderDimensions {
    param([TerminalPresentation]$Presentation, [TerminalCapability]$Capability)
    $width = if ($Presentation.Width -gt 0) { $Presentation.Width } elseif ($Capability.Width -gt 0) { $Capability.Width } else { 80 }
    $height = if ($Presentation.Height -gt 0) { $Presentation.Height } elseif ($Capability.Height -gt 0) { $Capability.Height } else { 24 }
    return @{ Width = $width; Height = $height }
}

function Get-RenderedSlideFrame {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][TerminalPresentation]$Presentation,
        [Parameter(Mandatory)][int]$SlideIndex,
        [int]$RevealStep = 0,
        [switch]$ShowNotes,
        [switch]$OverviewMode,
        [switch]$ShowHelp,
        [switch]$Blank,
        [timespan]$Elapsed = [timespan]::Zero,
        [switch]$ShowTimer,
        [TerminalCapability]$Capability = $script:Capabilities
    )

    $theme = Get-ResolvedTheme -Name $Presentation.Theme
    $dims = Get-SlideRenderDimensions -Presentation $Presentation -Capability $Capability
    $frame = [FrameBuffer]::new($dims.Width, $dims.Height)
    Fill-FrameRegion -FrameBuffer $frame -Background $theme.Background -Foreground $theme.Foreground
    if ($Blank) { return $frame }

    if ($ShowHelp) {
        $help = @(
            'TerminalSlides Help',
            '',
            'Right / Space / N / PgDn  Next reveal or slide',
            'Left / Backspace / P / PgUp Previous reveal or slide',
            'Home / End                 First / last slide',
            'S                          Toggle notes',
            'O                          Toggle overview',
            'B                          Blank screen',
            'T                          Toggle timer',
            'Q / Esc                    Quit'
        )
        $region = @{ X = 2; Y = 2; Width = $dims.Width - 4; Height = $dims.Height - 4 }
        Draw-FrameBox -FrameBuffer $frame -X $region.X -Y $region.Y -Width $region.Width -Height $region.Height -Foreground $theme.Border -Background $theme.Background -Style $theme.BoxDrawingStyle
        Write-LinesToFrame -FrameBuffer $frame -Lines $help -Region @{ X = 4; Y = 4; Width = $dims.Width - 8; Height = $dims.Height - 8 } -Theme $theme -Element (New-InternalSlideElement -Type Text -Content '' -ForegroundColor $theme.Foreground) -StartY 4 | Out-Null
        return $frame
    }

    if ($OverviewMode) {
        Set-FrameText -FrameBuffer $frame -X 2 -Y 1 -Text $Presentation.Title -Foreground $theme.Heading -Background $theme.Background -Bold
        $y = 3
        for ($i = 0; $i -lt $Presentation.Slides.Count -and $y -lt $dims.Height - 2; $i++) {
            $prefix = if ($i -eq $SlideIndex) { '>' } else { ' ' }
            Set-FrameText -FrameBuffer $frame -X 2 -Y $y -Text ("$prefix [{0}] {1}" -f ($i + 1), $Presentation.Slides[$i].Title) -Foreground $theme.Foreground -Background $theme.Background
            $y++
        }
        return $frame
    }

    $slide = $Presentation.Slides[$SlideIndex]
    $regions = Get-LayoutRegions -Layout $slide.Layout -Width $dims.Width -Height $dims.Height
    if ($slide.Background) {
        Fill-FrameRegion -FrameBuffer $frame -Background $slide.Background -Foreground $theme.Foreground
    }
    if ($regions.ContainsKey('Title') -and $slide.Title) {
        $titleElement = New-InternalSlideElement -Type Title -Content $slide.Title -ForegroundColor $theme.Heading
        $titleLines = Format-WordWrap -Text $slide.Title -Width $regions.Title.Width
        Write-LinesToFrame -FrameBuffer $frame -Lines $titleLines -Region $regions.Title -Theme $theme -Element $titleElement -StartY $regions.Title.Y | Out-Null
        if ($Presentation.Subtitle -and $slide.Layout -eq 'Title') {
            $subEl = New-InternalSlideElement -Type Subtitle -Content $Presentation.Subtitle -ForegroundColor $theme.Muted
            $subLines = Format-WordWrap -Text $Presentation.Subtitle -Width $regions.Title.Width
            Write-LinesToFrame -FrameBuffer $frame -Lines $subLines -Region @{ X=$regions.Title.X; Y=($regions.Title.Y+2); Width=$regions.Title.Width; Height=2 } -Theme $theme -Element $subEl -StartY ($regions.Title.Y+2) | Out-Null
        }
    }
    $contentRegions = @{}
    foreach ($entry in $regions.GetEnumerator()) { $contentRegions[$entry.Key] = $entry.Value }
    if (-not $contentRegions.ContainsKey('Content') -and $regions.ContainsKey('Body')) { $contentRegions['Content'] = $regions['Body'] }
    foreach ($regionName in @('Content','Left','Center','Right','Image','Code','Quote')) {
        if ($contentRegions.ContainsKey($regionName)) {
            $region = $contentRegions[$regionName]
            $y = $region.Y
            $elements = $slide.Elements | Where-Object {
                $_.RevealStep -le $RevealStep -and (($_.Region ?? 'Content') -eq $regionName -or ($regionName -eq 'Content' -and [string]::IsNullOrWhiteSpace($_.Region)))
            }
            foreach ($element in $elements) {
                if ($element.Border) {
                    $borderHeight = [Math]::Max(3, [Math]::Min($region.Height - ($y - $region.Y), [Math]::Max(3, ($element.Height + 2))))
                    $borderFg = if ($element.ForegroundColor) { $element.ForegroundColor } else { $theme.Border }
                    $borderBg = if ($element.BackgroundColor) { $element.BackgroundColor } else { $theme.Background }
                    Draw-FrameBox -FrameBuffer $frame -X $region.X -Y $y -Width $region.Width -Height $borderHeight -Foreground $borderFg -Background $borderBg -Style $element.BorderStyle
                }
                $lines = ConvertTo-ElementLines -Element $element -Theme $theme -Width ([Math]::Max(1, $region.Width - ($element.Padding * 2)))
                $y = Write-LinesToFrame -FrameBuffer $frame -Lines $lines -Region $region -Theme $theme -Element $element -StartY $y
                $y++
            }
        }
    }
    $progressWidth = [Math]::Max(10, $dims.Width - 24)
    $ratio = if ($Presentation.Slides.Count -gt 0) { ($SlideIndex + 1) / $Presentation.Slides.Count } else { 0 }
    $filled = [Math]::Round($progressWidth * $ratio)
    $progressBar = ('█' * $filled).PadRight($progressWidth, '░')
    $status = "Slide {0} of {1} {2}" -f ($SlideIndex + 1), $Presentation.Slides.Count, $progressBar
    $status = $status.Substring(0, [Math]::Min($status.Length, $dims.Width - 2))
    Set-FrameText -FrameBuffer $frame -X 1 -Y ($dims.Height - 2) -Text $status -Foreground $theme.Muted -Background $theme.Background
    if ($ShowTimer) {
        $timerText = $Elapsed.ToString('hh\:mm\:ss')
        Set-FrameText -FrameBuffer $frame -X ([Math]::Max(1, $dims.Width - $timerText.Length - 2)) -Y ($dims.Height - 1) -Text $timerText -Foreground $theme.Accent -Background $theme.Background
    }
    if ($ShowNotes -and $slide.Notes) {
        $notes = Format-WordWrap -Text ("Notes: $($slide.Notes)") -Width ([Math]::Max(10, $dims.Width - 4))
        $notesHeight = [Math]::Min(4, $notes.Count + 2)
        $notesY = [Math]::Max(0, $dims.Height - $notesHeight - 1)
        Draw-FrameBox -FrameBuffer $frame -X 1 -Y $notesY -Width ($dims.Width - 2) -Height $notesHeight -Foreground $theme.Border -Background $theme.Background -Style $theme.BoxDrawingStyle
        Write-LinesToFrame -FrameBuffer $frame -Lines $notes -Region @{ X = 2; Y = $notesY + 1; Width = $dims.Width - 4; Height = $notesHeight - 2 } -Theme $theme -Element (New-InternalSlideElement -Type Text -Content '' -ForegroundColor $theme.Foreground) -StartY ($notesY + 1) | Out-Null
    }
    return $frame
}

function Render-TerminalPresentationToString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][TerminalPresentation]$Presentation,
        [int]$SlideIndex = 0,
        [int]$RevealStep = 0,
        [switch]$PlainText,
        [switch]$ShowNotes,
        [switch]$OverviewMode,
        [switch]$ShowHelp,
        [switch]$Blank,
        [timespan]$Elapsed = [timespan]::Zero,
        [switch]$ShowTimer,
        [TerminalCapability]$Capability = $script:Capabilities
    )
    $frame = Get-RenderedSlideFrame -Presentation $Presentation -SlideIndex $SlideIndex -RevealStep $RevealStep -ShowNotes:$ShowNotes -OverviewMode:$OverviewMode -ShowHelp:$ShowHelp -Blank:$Blank -Elapsed $Elapsed -ShowTimer:$ShowTimer -Capability $Capability
    $rendered = $frame.Render($false)
    if ($PlainText) {
        $rows = [System.Collections.Generic.List[string]]::new()
        for ($r = 0; $r -lt $frame.Height; $r++) {
            $text = -join ($frame.Cells[$r] | ForEach-Object { $_.Char })
            $rows.Add($text.TrimEnd())
        }
        return ($rows -join [Environment]::NewLine)
    }
    return $rendered
}
