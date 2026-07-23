function ConvertTo-TerminalTableRowLine {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Values,
        [Parameter(Mandatory)][AllowEmptyCollection()][int[]]$Widths,
        [ValidateRange(0, [int]::MaxValue)][int]$StartColumn = 0
    )

    $cells = [System.Collections.Generic.List[string]]::new()
    $cellStartColumn = $StartColumn + 2
    for ($columnIndex = 0; $columnIndex -lt $Values.Count; $columnIndex++) {
        $cells.Add((Pad-TerminalText -Text $Values[$columnIndex] -Width $Widths[$columnIndex] -StartColumn $cellStartColumn))
        $cellStartColumn += $Widths[$columnIndex] + 3
    }
    return '| ' + ($cells -join ' | ') + ' |'
}

function ConvertTo-TerminalTableCellLines {
    param(
        [AllowNull()][string]$Text,
        [ValidateRange(0, [int]::MaxValue)][int]$StartColumn = 0
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($logicalLine in (Split-TerminalLogicalRows -Text $Text)) {
        $lines.Add((Expand-TerminalTabs -Text $logicalLine -StartColumn $StartColumn))
    }
    return ,$lines.ToArray()
}

function ConvertTo-TerminalTablePhysicalLines {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[][]]$Cells,
        [Parameter(Mandatory)][AllowEmptyCollection()][int[]]$Widths,
        [ValidateRange(0, [int]::MaxValue)][int]$StartColumn = 0
    )

    $lineCount = 1
    foreach ($cell in $Cells) { $lineCount = [Math]::Max($lineCount, $cell.Count) }
    $lines = [System.Collections.Generic.List[string]]::new()
    for ($lineIndex = 0; $lineIndex -lt $lineCount; $lineIndex++) {
        $values = [string[]]::new($Cells.Count)
        for ($columnIndex = 0; $columnIndex -lt $Cells.Count; $columnIndex++) {
            $values[$columnIndex] = if ($lineIndex -lt $Cells[$columnIndex].Count) {
                $Cells[$columnIndex][$lineIndex]
            }
            else { '' }
        }
        $lines.Add((ConvertTo-TerminalTableRowLine -Values $values -Widths $Widths -StartColumn $StartColumn))
    }
    return ,$lines.ToArray()
}

function ConvertTo-TableLines {
    param(
        [object]$Content,
        [ValidateRange(0, [int]::MaxValue)][int]$StartColumn = 0
    )
    $rows = @()
    if ($Content -is [System.Collections.IDictionary]) {
        $rows = [object[]]@($Content)
    }
    elseif ($Content -is [System.Collections.IEnumerable] -and $Content -isnot [string]) {
        $rows = @($Content)
    }
    else {
        return ,@([string]$Content)
    }
    if (-not $rows.Count) { return ,@('') }
    $shape = Get-TerminalExportTableShape -Data $rows
    $headers = [string[]]@($shape.Columns)
    $widths = [int[]]::new($headers.Count)
    $normalizedHeaders = [string[][]]::new($headers.Count)
    $normalizedRows = [System.Collections.Generic.List[string[][]]]::new()
    foreach ($row in $rows) { $normalizedRows.Add([string[][]]::new($headers.Count)) }

    $cellStartColumn = $StartColumn + 2
    for ($columnIndex = 0; $columnIndex -lt $headers.Count; $columnIndex++) {
        $header = $headers[$columnIndex]
        $normalizedHeaders[$columnIndex] = ConvertTo-TerminalTableCellLines -Text $header -StartColumn $cellStartColumn
        $widths[$columnIndex] = 3
        foreach ($headerLine in $normalizedHeaders[$columnIndex]) {
            $widths[$columnIndex] = [Math]::Max(
                $widths[$columnIndex],
                (Measure-TextWidth -Text $headerLine -StartColumn $cellStartColumn)
            )
        }
        for ($rowIndex = 0; $rowIndex -lt $rows.Count; $rowIndex++) {
            $row = $rows[$rowIndex]
            $value = [string](Get-TerminalSemanticProperty -InputObject $row -Name $header)
            $normalizedRows[$rowIndex][$columnIndex] = ConvertTo-TerminalTableCellLines -Text $value -StartColumn $cellStartColumn
            foreach ($valueLine in $normalizedRows[$rowIndex][$columnIndex]) {
                $widths[$columnIndex] = [Math]::Max(
                    $widths[$columnIndex],
                    (Measure-TextWidth -Text $valueLine -StartColumn $cellStartColumn)
                )
            }
        }
        $cellStartColumn += $widths[$columnIndex] + 3
    }

    $output = [System.Collections.Generic.List[string]]::new()
    foreach ($headerLine in (ConvertTo-TerminalTablePhysicalLines -Cells $normalizedHeaders -Widths $widths -StartColumn $StartColumn)) {
        $output.Add($headerLine)
    }
    $output.Add('|-' + (($widths | ForEach-Object { ''.PadLeft($_, '-') }) -join '-|-') + '-|')
    foreach ($normalizedRow in $normalizedRows) {
        foreach ($rowLine in (ConvertTo-TerminalTablePhysicalLines -Cells $normalizedRow -Widths $widths -StartColumn $StartColumn)) {
            $output.Add($rowLine)
        }
    }
    return ,$output.ToArray()
}

function ConvertTo-ChartLines {
    param([object]$Content, [hashtable]$Properties, [TerminalSlides.Schema.V1.ThemeDefinition]$Theme, [int]$Width)
    $items = @($Content)
    if (-not $items.Count) { return ,@('No chart data') }
    $chartType = ($Properties.ChartType ?? 'HorizontalBar')
    $palette = @($Theme.ChartPalette)
    if (-not $palette.Count) { $palette = @($Theme.Primary, $Theme.Accent, $Theme.Foreground) }
    $output = [System.Collections.Generic.List[object]]::new()
    if ($Properties.Title) {
        $output.Add((New-TerminalStyledLine -Text ([string]$Properties.Title) -Foreground $Theme.Heading -Bold))
    }
    switch ($chartType) {
        'Gauge' {
            $value = [double]($items[0].Value)
            $filled = [Math]::Round(($Width - 10) * ($value / 100))
            $filled = [Math]::Max(0, [Math]::Min($Width - 10, $filled))
            $output.Add((New-TerminalStyledLine -Text "[$(('█' * $filled) + ('░' * ([Math]::Max(0, ($Width - 10 - $filled)))))] $value%" -Foreground $palette[0]))
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
            $output.Add((New-TerminalStyledLine -Text $spark -Foreground $palette[0]))
        }
        'Bar' {
            $max = [double](($items | ForEach-Object { $_.Value } | Measure-Object -Maximum).Maximum)
            if ($max -le 0) { $max = 1 }
            for ($index = 0; $index -lt $items.Count; $index++) {
                $item = $items[$index]
                $count = [Math]::Max(0, [Math]::Round((([double]$item.Value) / $max) * ([Math]::Max(1, $Width - 12))))
                $label = Pad-TerminalText -Text ([string]$item.Label) -Width 10
                $color = $palette[$index % $palette.Count]
                $output.Add((New-TerminalStyledLine -Text "$label $('█' * $count)" -Foreground $color))
            }
        }
        'Line' {
            $values = @($items | ForEach-Object { [double]$_.Value })
            $sparkline = ConvertTo-ChartLines -Content $Content -Properties @{ ChartType='Sparkline' } -Theme $Theme -Width $Width
            foreach ($line in $sparkline) { $output.Add($line) }
            $output.Add(($items | ForEach-Object { "{0}: {1}" -f $_.Label, $_.Value }) -join '  ')
        }
        default {
            $max = [double](($items | ForEach-Object { $_.Value } | Measure-Object -Maximum).Maximum)
            if ($max -le 0) { $max = 1 }
            for ($index = 0; $index -lt $items.Count; $index++) {
                $item = $items[$index]
                $label = [string]$item.Label
                $count = [Math]::Max(0, [Math]::Round((([double]$item.Value) / $max) * ([Math]::Max(1, $Width - 20))))
                $label = Pad-TerminalText -Text $label -Width 12
                $color = $palette[$index % $palette.Count]
                $output.Add((New-TerminalStyledLine -Text "$label $('█' * $count) $($item.Value)" -Foreground $color))
            }
        }
    }
    return ,$output.ToArray()
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
    param(
        [TerminalSlides.Schema.V1.SlideElement]$Element,
        [TerminalSlides.Schema.V1.ThemeDefinition]$Theme,
        [int]$Width,
        [int]$Height = 0,
        [TerminalSlides.Schema.V1.TerminalCapability]$Capability,
        [ValidateRange(0, [int]::MaxValue)][int]$StartColumn = 0
    )
    $payload = Get-TerminalElementPayload -Element $Element
    switch ($payload.Kind) {
        'Title' {
            $title = if ($Theme.HeadingStyle -eq 'banner') { $payload.Text.ToUpperInvariant() } else { $payload.Text }
            return ,(Format-WordWrap -Text $title -Width $Width -StartColumn $StartColumn)
        }
        'Subtitle' { return ,(Format-WordWrap -Text $payload.Text -Width $Width -StartColumn $StartColumn) }
        'Text' { return ,(Format-WordWrap -Text $payload.Text -Width $Width -OverflowBehavior $Element.OverflowBehavior -StartColumn $StartColumn) }
        'Bullet' {
            $prefix = "$($Theme.BulletSymbol) "
            $prefixWidth = Measure-TextWidth -Text $prefix
            $wrapped = Format-WordWrap -Text $payload.Text -Width ([Math]::Max(1, $Width - $prefixWidth)) -StartColumn ($StartColumn + $prefixWidth)
            $result = [System.Collections.Generic.List[string]]::new()
            for ($i = 0; $i -lt $wrapped.Count; $i++) {
                if ($i -eq 0) { $result.Add($prefix + $wrapped[$i]) }
                else { $result.Add((' ' * $prefixWidth) + $wrapped[$i]) }
            }
            return ,$result.ToArray()
        }
        'Code' {
            $lines = [System.Collections.Generic.List[TerminalStyledLine]]::new()
            foreach ($highlightedLine in (Get-SyntaxHighlight -Code $payload.Code -Language $payload.Language -Theme $Theme)) {
                foreach ($wrappedLine in (Split-TerminalStyledLineByCellWidth -Line $highlightedLine -Width $Width -StartColumn $StartColumn)) {
                    $lines.Add($wrappedLine)
                }
            }
            return ,$lines.ToArray()
        }
        'Table' { return ,(ConvertTo-TableLines -Content $payload.Rows -StartColumn $StartColumn) }
        'Chart' {
            $properties = @{ ChartType = $payload.ChartType; Title = $payload.Title }
            return ,(ConvertTo-ChartLines -Content $payload.Rows -Properties $properties -Theme $Theme -Width $Width)
        }
        'Diagram' { return ,(ConvertTo-DiagramLines -Content @{ Nodes=$payload.Nodes; Edges=$payload.Edges }) }
        'Image' {
            $imageLines = ConvertTo-TerminalImageLines -Path $payload.Path -Width $Width -Height $Height -SourceDirectory $payload.SourceDirectory -Capability $Capability
            if ($null -ne $imageLines -and $imageLines.Count -gt 0) {
                return ,$imageLines
            }
            return ,@("Image: $($payload.Path)", $payload.AltText)
        }
        'Quote' {
            $lines = [System.Collections.Generic.List[string]]::new()
            foreach ($line in (Format-WordWrap -Text ('“' + $payload.Text + '”') -Width $Width -StartColumn $StartColumn)) { $lines.Add($line) }
            if ($payload.Attribution) { $lines.Add("— $($payload.Attribution)") }
            return ,$lines.ToArray()
        }
        'Box' {
            $boxChars = Get-BoxCharacters -Style $Theme.BoxDrawingStyle
            $innerStartColumn = $StartColumn + 2
            $inner = Format-WordWrap -Text $payload.Text -Width ([Math]::Max(1, $Width - 4)) -StartColumn $innerStartColumn
            $border = $boxChars.Tl + ($boxChars.H * ([Math]::Max(1, $Width - 2))) + $boxChars.Tr
            $bottom = $boxChars.Bl + ($boxChars.H * ([Math]::Max(1, $Width - 2))) + $boxChars.Br
            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add($border)
            foreach ($line in $inner) { $lines.Add($boxChars.V + ' ' + (Pad-TerminalText -Text $line -Width ([Math]::Max(1, $Width - 4)) -StartColumn $innerStartColumn) + ' ' + $boxChars.V) }
            $lines.Add($bottom)
            return ,$lines.ToArray()
        }
    }
}

function Write-LinesToFrame {
    param(
        [FrameBuffer]$FrameBuffer,
        [object[]]$Lines,
        [hashtable]$Region,
        [TerminalSlides.Schema.V1.ThemeDefinition]$Theme,
        [TerminalSlides.Schema.V1.SlideElement]$Element,
        [int]$StartY
    )
    $elementKind = (Get-TerminalElementPayload -Element $Element).Kind
    $fg = if ($Element.ForegroundColor) { $Element.ForegroundColor }
          elseif ($elementKind -eq 'Code' -and $Theme.CodeForeground) { $Theme.CodeForeground }
          else { $Theme.Foreground }
    $bg = if ($Element.BackgroundColor) { $Element.BackgroundColor }
          elseif ($elementKind -eq 'Code' -and $Theme.CodeBackground) { $Theme.CodeBackground }
          else { $null }
    $y = $StartY
    $usableWidth = [Math]::Max(1, $Region.Width - ($Element.Padding * 2))
    $contentStartColumn = $Region.X + $Element.Padding
    $preparedLines = ConvertTo-TerminalPreparedLines -Lines $Lines -StartColumn $contentStartColumn -MaxWidth $usableWidth -Alignment $Element.Alignment
    foreach ($preparedLine in $preparedLines) {
        if ($y -ge ($Region.Y + $Region.Height)) { break }
        $x = $preparedLine.StartColumn
        $baseBold = ($elementKind -eq 'Title' -and $Theme.HeadingStyle -ne 'plain')
        $baseItalic = ($elementKind -eq 'Subtitle')
        $col = $x
        foreach ($run in $preparedLine.Runs) {
            $runForeground = if ($run.Foreground) { $run.Foreground } else { $fg }
            $runBackground = if ($run.Background) { $run.Background } else { $bg }
            Set-FrameText -FrameBuffer $FrameBuffer -X $col -Y $y -Text $run.Text -Foreground $runForeground -Background $runBackground -Bold:($baseBold -or $run.Bold) -Italic:($baseItalic -or $run.Italic) -Underline:$run.Underline
            $col += $run.Width
        }
        $y++
    }
    return $y
}

function Get-SlideRenderDimensions {
    param([TerminalSlides.Schema.V1.TerminalPresentation]$Presentation, [TerminalSlides.Schema.V1.TerminalCapability]$Capability)
    $width = if ($Presentation.Width -gt 0) { $Presentation.Width } elseif ($Capability.Width -gt 0) { $Capability.Width } else { 80 }
    $height = if ($Presentation.Height -gt 0) { $Presentation.Height } elseif ($Capability.Height -gt 0) { $Capability.Height } else { 24 }
    return Resolve-TerminalViewport -Width $width -Height $height
}

function Get-RenderedSlideFrame {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][TerminalSlides.Schema.V1.TerminalPresentation]$Presentation,
        [Parameter(Mandatory)][int]$SlideIndex,
        [int]$RevealStep = 0,
        [switch]$ShowNotes,
        [ValidateSet('Slide','Overview','Help','Blank')][string]$DisplayMode = 'Slide',
        [timespan]$Elapsed = [timespan]::Zero,
        [switch]$ShowTimer,
        [TerminalSlides.Schema.V1.TerminalCapability]$Capability = $script:Capabilities,
        [object]$LayoutPlan
    )

    $theme = Resolve-TerminalPresentationTheme -Presentation $Presentation
    $dims = Get-SlideRenderDimensions -Presentation $Presentation -Capability $Capability
    $frame = [FrameBuffer]::new($dims.Width, $dims.Height)
    Fill-FrameRegion -FrameBuffer $frame -Background $theme.Background -Foreground $theme.Foreground
    if ($DisplayMode -eq 'Blank') { return $frame }

    if ($DisplayMode -eq 'Help') {
        $help = @(
            'TerminalSlides Help',
            '',
            'Right / Space / N           Next reveal or slide',
            'PageDown                   Next slide',
            'Left / Backspace / P       Previous reveal or slide',
            'PageUp                     Previous slide',
            'Home / End                 First / last slide',
            'S                          Toggle notes',
            'O                          Toggle overview',
            'B                          Blank screen',
            'T                          Toggle timer',
            'H / ?                      Toggle help',
            'Q / Esc                    Quit'
        )
        $region = @{ X = 2; Y = 2; Width = $dims.Width - 4; Height = $dims.Height - 4 }
        Draw-FrameBox -FrameBuffer $frame -X $region.X -Y $region.Y -Width $region.Width -Height $region.Height -Foreground $theme.Border -Background $theme.Background -Style $theme.BoxDrawingStyle
        Write-LinesToFrame -FrameBuffer $frame -Lines $help -Region @{ X = 4; Y = 3; Width = $dims.Width - 8; Height = $dims.Height - 6 } -Theme $theme -Element (New-InternalSlideElement -Kind Text -Payload ([TerminalSlides.Schema.V1.TextPayload]::new('')) -ForegroundColor $theme.Foreground) -StartY 3 | Out-Null
        return $frame
    }

    if ($DisplayMode -eq 'Overview') {
        Set-FrameText -FrameBuffer $frame -X 2 -Y 1 -Text $Presentation.Title -Foreground $theme.Heading -Background $theme.Background -Bold
        $y = 3
        for ($i = 0; $i -lt $Presentation.Slides.Count -and $y -lt $dims.Height - 2; $i++) {
            $prefix = if ($i -eq $SlideIndex) { '>' } else { ' ' }
            Set-FrameText -FrameBuffer $frame -X 2 -Y $y -Text ("$prefix [{0}] {1}" -f ($i + 1), $Presentation.Slides[$i].Title) -Foreground $theme.Foreground -Background $theme.Background
            $y++
        }
        return $frame
    }

    $plan = if ($LayoutPlan) {
        $LayoutPlan
    }
    else {
        Get-TerminalSlideLayoutPlan -Presentation $Presentation -SlideIndex $SlideIndex `
            -RevealStep $RevealStep -Capability $Capability
    }
    $slide = $plan.Slide
    if ($slide.Background) {
        Fill-FrameRegion -FrameBuffer $frame -Background $slide.Background -Foreground $theme.Foreground
    }

    foreach ($placement in $plan.Placements) {
        if ($placement.Border) {
            $border = $placement.BorderRegion
            $borderFg = if ($placement.Element.ForegroundColor) { $placement.Element.ForegroundColor } else { $theme.Border }
            $borderBg = if ($placement.Element.BackgroundColor) { $placement.Element.BackgroundColor } else { $theme.Background }
            Draw-FrameBox -FrameBuffer $frame -X $border.X -Y $border.Y -Width $border.Width -Height $border.Height -Foreground $borderFg -Background $borderBg -Style $placement.Element.BorderStyle
        }
        Write-LinesToFrame -FrameBuffer $frame -Lines $placement.Lines -Region $placement.Region -Theme $theme -Element $placement.Element -StartY $placement.StartY | Out-Null
    }
    $progressWidth = [Math]::Max(10, $dims.Width - 24)
    $ratio = ($SlideIndex + 1) / $Presentation.Slides.Count
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
        Write-LinesToFrame -FrameBuffer $frame -Lines $notes -Region @{ X = 2; Y = $notesY + 1; Width = $dims.Width - 4; Height = $notesHeight - 2 } -Theme $theme -Element (New-InternalSlideElement -Kind Text -Payload ([TerminalSlides.Schema.V1.TextPayload]::new('')) -ForegroundColor $theme.Foreground) -StartY ($notesY + 1) | Out-Null
    }
    return $frame
}

function Render-TerminalPresentationToString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][TerminalSlides.Schema.V1.TerminalPresentation]$Presentation,
        [int]$SlideIndex = 0,
        [int]$RevealStep = 0,
        [switch]$PlainText,
        [switch]$ShowNotes,
        [ValidateSet('Slide','Overview','Help','Blank')][string]$DisplayMode = 'Slide',
        [timespan]$Elapsed = [timespan]::Zero,
        [switch]$ShowTimer,
        [TerminalSlides.Schema.V1.TerminalCapability]$Capability = $script:Capabilities,
        [object]$LayoutPlan
    )
    $frame = Get-RenderedSlideFrame -Presentation $Presentation -SlideIndex $SlideIndex `
        -RevealStep $RevealStep -ShowNotes:$ShowNotes -DisplayMode $DisplayMode `
        -Elapsed $Elapsed -ShowTimer:$ShowTimer -Capability $Capability -LayoutPlan $LayoutPlan
    if ($PlainText) {
        $rows = [System.Collections.Generic.List[string]]::new()
        for ($r = 0; $r -lt $frame.Height; $r++) {
            $text = $frame.GetRowText($r)
            $rows.Add($text.TrimEnd())
        }
        return ($rows -join [Environment]::NewLine)
    }
    return $frame.Render($Capability.TrueColorSupport, $Capability.Color256Support)
}
