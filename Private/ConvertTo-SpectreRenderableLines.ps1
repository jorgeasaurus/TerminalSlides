function New-TerminalStyledLine {
    param(
        [AllowEmptyString()][string]$Text = '',
        [string]$Foreground,
        [string]$Background,
        [switch]$Bold,
        [switch]$Italic,
        [switch]$Underline
    )

    $line = [TerminalStyledLine]::new()
    if ($Text.Length -gt 0) {
        $line.Runs.Add([TerminalStyledRun]::new($Text, $Foreground, $Background, $Bold.IsPresent, $Italic.IsPresent, $Underline.IsPresent))
    }
    return $line
}

function Add-TerminalStyledRun {
    param(
        [Parameter(Mandatory)][TerminalStyledLine]$Line,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [string]$Foreground,
        [string]$Background,
        [switch]$Bold,
        [switch]$Italic,
        [switch]$Underline
    )

    if ($Text.Length -gt 0) {
        $Line.Runs.Add([TerminalStyledRun]::new($Text, $Foreground, $Background, $Bold.IsPresent, $Italic.IsPresent, $Underline.IsPresent))
    }
}

function Get-TerminalStyledLineText {
    param([Parameter(Mandatory)][object]$Line)

    if ($Line -is [TerminalPreparedLine]) { return $Line.GetText() }
    if ($Line -is [TerminalStyledLine]) { return $Line.GetText() }
    return [string]$Line
}

function Get-TerminalStyledGraphemes {
    param([Parameter(Mandatory)][TerminalStyledLine]$Line)

    $text = [System.Text.StringBuilder]::new()
    $segments = [System.Collections.Generic.List[object]]::new()
    foreach ($run in $Line.Runs) {
        $plainRunText = Strip-AnsiSequences -Text $run.Text
        if ($plainRunText.Length -eq 0) { continue }
        $start = $text.Length
        [void]$text.Append($plainRunText)
        $segments.Add([pscustomobject]@{ Start = $start; End = $text.Length; Style = $run })
    }
    if ($text.Length -eq 0) { return ,([TerminalStyledGrapheme[]]@()) }

    Assert-TerminalValidUtf16 -Value $text.ToString()
    $graphemes = [System.Collections.Generic.List[TerminalStyledGrapheme]]::new()
    $enumerator = [System.Globalization.StringInfo]::GetTextElementEnumerator($text.ToString())
    $segmentIndex = 0
    while ($enumerator.MoveNext()) {
        while ($segmentIndex -lt $segments.Count - 1 -and $enumerator.ElementIndex -ge $segments[$segmentIndex].End) {
            $segmentIndex++
        }
        $graphemes.Add([TerminalStyledGrapheme]::new($enumerator.GetTextElement(), $segments[$segmentIndex].Style))
    }
    return ,$graphemes.ToArray()
}

function Get-TerminalStyledTextElements {
    param(
        [Parameter(Mandatory)][TerminalStyledLine]$Line,
        [ValidateRange(0, [int]::MaxValue)][int]$StartColumn
    )

    $elements = [System.Collections.Generic.List[TerminalStyledTextElement]]::new()
    $column = $StartColumn
    foreach ($grapheme in (Get-TerminalStyledGraphemes -Line $Line)) {
        $measured = @(Get-TerminalTextElements -Text $grapheme.Text -StartColumn $column -PreserveTabs)
        $width = 0
        foreach ($part in $measured) { $width += $part.Width }
        $elements.Add([TerminalStyledTextElement]::new($grapheme.Text, $width, $grapheme.Style))
        $column += $width
    }
    return ,$elements.ToArray()
}

function Add-TerminalStyledBuffer {
    param(
        [Parameter(Mandatory)][TerminalStyledLine]$Line,
        [Parameter(Mandatory)][System.Text.StringBuilder]$Buffer,
        [Parameter(Mandatory)][TerminalStyledRun]$Style
    )

    if ($Buffer.Length -eq 0) { return }
    $Line.Runs.Add([TerminalStyledRun]::new(
        $Buffer.ToString(), $Style.Foreground, $Style.Background,
        $Style.Bold, $Style.Italic, $Style.Underline
    ))
    [void]$Buffer.Clear()
}

function Split-TerminalStyledLine {
    param([Parameter(Mandatory)][object]$Line)

    $styledLine = if ($Line -is [TerminalStyledLine]) { $Line } else { New-TerminalStyledLine -Text ([string]$Line) }
    $rows = [System.Collections.Generic.List[TerminalStyledLine]]::new()
    $row = [TerminalStyledLine]::new()
    $buffer = [System.Text.StringBuilder]::new()
    $activeStyle = $null

    foreach ($grapheme in (Get-TerminalStyledGraphemes -Line $styledLine)) {
        if ($grapheme.Text.Contains("`r") -or $grapheme.Text.Contains("`n")) {
            if ($buffer.Length -gt 0) { Add-TerminalStyledBuffer -Line $row -Buffer $buffer -Style $activeStyle }
            $rows.Add($row)
            $row = [TerminalStyledLine]::new()
            $activeStyle = $null
            continue
        }
        if (-not [object]::ReferenceEquals($activeStyle, $grapheme.Style) -and $buffer.Length -gt 0) {
            Add-TerminalStyledBuffer -Line $row -Buffer $buffer -Style $activeStyle
        }
        $activeStyle = $grapheme.Style
        [void]$buffer.Append($grapheme.Text)
    }
    if ($buffer.Length -gt 0) { Add-TerminalStyledBuffer -Line $row -Buffer $buffer -Style $activeStyle }
    $rows.Add($row)
    return ,$rows.ToArray()
}

function Split-TerminalStyledLineByCellWidth {
    param(
        [Parameter(Mandatory)][TerminalStyledLine]$Line,
        [Parameter(Mandatory)][ValidateRange(1, [int]::MaxValue)][int]$Width,
        [ValidateRange(0, [int]::MaxValue)][int]$StartColumn = 0
    )

    $segments = [System.Collections.Generic.List[TerminalStyledLine]]::new()
    foreach ($logicalLine in (Split-TerminalStyledLine -Line $Line)) {
        $segment = [TerminalStyledLine]::new()
        $buffer = [System.Text.StringBuilder]::new()
        $activeStyle = $null
        $usedWidth = 0

        foreach ($grapheme in (Get-TerminalStyledGraphemes -Line $logicalLine)) {
            $graphemeWidth = 0
            foreach ($part in (Get-TerminalTextElements -Text $grapheme.Text -StartColumn ($StartColumn + $usedWidth) -PreserveTabs)) {
                $graphemeWidth += $part.Width
            }
            $hasContent = $segment.Runs.Count -gt 0 -or $buffer.Length -gt 0
            if ($hasContent -and $usedWidth + $graphemeWidth -gt $Width) {
                if ($buffer.Length -gt 0) {
                    Add-TerminalStyledBuffer -Line $segment -Buffer $buffer -Style $activeStyle
                }
                $segments.Add($segment)
                $segment = [TerminalStyledLine]::new()
                $activeStyle = $null
                $usedWidth = 0
                $graphemeWidth = 0
                foreach ($part in (Get-TerminalTextElements -Text $grapheme.Text -StartColumn $StartColumn -PreserveTabs)) {
                    $graphemeWidth += $part.Width
                }
            }
            if (-not [object]::ReferenceEquals($activeStyle, $grapheme.Style) -and $buffer.Length -gt 0) {
                Add-TerminalStyledBuffer -Line $segment -Buffer $buffer -Style $activeStyle
            }
            $activeStyle = $grapheme.Style
            [void]$buffer.Append($grapheme.Text)
            $usedWidth += $graphemeWidth
        }
        if ($buffer.Length -gt 0) {
            Add-TerminalStyledBuffer -Line $segment -Buffer $buffer -Style $activeStyle
        }
        $segments.Add($segment)
    }
    return ,$segments.ToArray()
}

function Measure-TerminalStyledLineWidth {
    param(
        [Parameter(Mandatory)][TerminalStyledLine]$Line,
        [ValidateRange(0, [int]::MaxValue)][int]$StartColumn
    )

    $width = 0
    foreach ($textElement in (Get-TerminalStyledTextElements -Line $Line -StartColumn $StartColumn)) {
        $width += $textElement.Width
    }
    return $width
}

function Resolve-TerminalPreparedLineOrigin {
    param(
        [Parameter(Mandatory)][TerminalStyledLine]$Line,
        [ValidateRange(0, [int]::MaxValue)][int]$StartColumn,
        [ValidateRange(1, [int]::MaxValue)][int]$MaxWidth,
        [ValidateSet('Left', 'Center', 'Right')][string]$Alignment
    )

    if ($Alignment -eq 'Left' -or $MaxWidth -eq [int]::MaxValue) { return $StartColumn }

    $rightBoundary = $StartColumn + $MaxWidth
    if (-not $Line.GetText().Contains("`t")) {
        $lineWidth = Measure-TerminalStyledLineWidth -Line $Line -StartColumn $StartColumn
        if ($lineWidth -gt $MaxWidth) { return $StartColumn }
        $freeWidth = $MaxWidth - $lineWidth
        if ($Alignment -eq 'Center') { return $StartColumn + [Math]::Floor($freeWidth / 2) }
        return $StartColumn + $freeWidth
    }

    $bestOrigin = -1
    $bestError = [int]::MaxValue
    for ($residue = 0; $residue -lt $script:TerminalTabStopWidth; $residue++) {
        $offset = ($residue - ($StartColumn % $script:TerminalTabStopWidth) + $script:TerminalTabStopWidth) % $script:TerminalTabStopWidth
        $firstOrigin = $StartColumn + $offset
        if ($firstOrigin -gt $rightBoundary) { continue }
        $lineWidth = Measure-TerminalStyledLineWidth -Line $Line -StartColumn $firstOrigin
        $lastFeasibleOrigin = $rightBoundary - $lineWidth
        if ($firstOrigin -gt $lastFeasibleOrigin) { continue }

        $maxStep = [Math]::Floor(($lastFeasibleOrigin - $firstOrigin) / $script:TerminalTabStopWidth)
        $steps = if ($Alignment -eq 'Right') {
            @($maxStep)
        }
        else {
            $idealOrigin = ($StartColumn + $rightBoundary - $lineWidth) / 2.0
            $idealStep = [Math]::Floor(($idealOrigin - $firstOrigin) / $script:TerminalTabStopWidth)
            @([Math]::Max(0, [Math]::Min($maxStep, $idealStep)), [Math]::Max(0, [Math]::Min($maxStep, $idealStep + 1))) | Select-Object -Unique
        }
        foreach ($step in $steps) {
            $candidate = $firstOrigin + ($step * $script:TerminalTabStopWidth)
            $rightMargin = $rightBoundary - ($candidate + $lineWidth)
            $leftMargin = $candidate - $StartColumn
            $error = if ($Alignment -eq 'Center') { [Math]::Abs($leftMargin - $rightMargin) } else { $rightMargin }
            $tieWins = $error -eq $bestError -and (
                ($Alignment -eq 'Center' -and $candidate -lt $bestOrigin) -or
                ($Alignment -eq 'Right' -and $candidate -gt $bestOrigin)
            )
            if ($error -lt $bestError -or $tieWins) {
                $bestOrigin = $candidate
                $bestError = $error
            }
        }
    }

    if ($bestOrigin -ge 0) { return $bestOrigin }
    return $StartColumn
}

function ConvertTo-TerminalPreparedLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Line,
        [ValidateRange(0, [int]::MaxValue)][int]$StartColumn = 0,
        [ValidateRange(1, [int]::MaxValue)][int]$MaxWidth = [int]::MaxValue,
        [ValidateSet('Left', 'Center', 'Right')][string]$Alignment = 'Left'
    )

    $styledLine = if ($Line -is [TerminalStyledLine]) { $Line } else { New-TerminalStyledLine -Text ([string]$Line) }
    if ($styledLine.GetText().Contains("`r") -or $styledLine.GetText().Contains("`n")) {
        throw 'TerminalPreparedLine accepts exactly one logical row. Use ConvertTo-TerminalPreparedLines for multiline content.'
    }
    $renderStartColumn = Resolve-TerminalPreparedLineOrigin -Line $styledLine -StartColumn $StartColumn -MaxWidth $MaxWidth -Alignment $Alignment
    $availableWidth = if ($MaxWidth -eq [int]::MaxValue) {
        $MaxWidth
    }
    else {
        [Math]::Max(1, $MaxWidth - ($renderStartColumn - $StartColumn))
    }
    $prepared = [TerminalPreparedLine]::new($renderStartColumn, $availableWidth)
    $renderedWidth = 0
    $prefixFits = $true
    $activeStyle = $null
    $runText = [System.Text.StringBuilder]::new()
    $runWidth = 0
    foreach ($textElement in (Get-TerminalStyledTextElements -Line $styledLine -StartColumn $renderStartColumn)) {
        if (-not [object]::ReferenceEquals($activeStyle, $textElement.Style) -and $runText.Length -gt 0) {
            $prepared.Runs.Add([TerminalPreparedRun]::new(
                $runText.ToString(), $runWidth, $activeStyle.Foreground, $activeStyle.Background,
                $activeStyle.Bold, $activeStyle.Italic, $activeStyle.Underline
            ))
            [void]$runText.Clear()
            $runWidth = 0
        }
        $activeStyle = $textElement.Style
        $pieceCount = if ($textElement.Text -eq "`t") { $textElement.Width } else { 1 }
        for ($piece = 0; $piece -lt $pieceCount; $piece++) {
            $pieceWidth = if ($textElement.Text -eq "`t") { 1 } else { $textElement.Width }
            $prepared.Width += $pieceWidth
            if (-not $prefixFits) { continue }
            if ($renderedWidth + $pieceWidth -gt $availableWidth) {
                $prefixFits = $false
                continue
            }
            $renderedText = if ($textElement.Text -eq "`t") { ' ' } else { $textElement.Text }
            [void]$runText.Append($renderedText)
            $runWidth += $pieceWidth
            $renderedWidth += $pieceWidth
        }
    }
    if ($runText.Length -gt 0) {
        $prepared.Runs.Add([TerminalPreparedRun]::new(
            $runText.ToString(), $runWidth, $activeStyle.Foreground, $activeStyle.Background,
            $activeStyle.Bold, $activeStyle.Italic, $activeStyle.Underline
        ))
    }
    $prepared.RenderedWidth = $renderedWidth
    return $prepared
}

function ConvertTo-TerminalPreparedLines {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][object[]]$Lines,
        [ValidateRange(0, [int]::MaxValue)][int]$StartColumn = 0,
        [ValidateRange(1, [int]::MaxValue)][int]$MaxWidth = [int]::MaxValue,
        [ValidateSet('Left', 'Center', 'Right')][string]$Alignment = 'Left'
    )

    $prepared = [System.Collections.Generic.List[TerminalPreparedLine]]::new()
    foreach ($line in $Lines) {
        if ($line -is [TerminalPreparedLine]) {
            $prepared.Add($line)
            continue
        }
        foreach ($row in (Split-TerminalStyledLine -Line $line)) {
            $prepared.Add((ConvertTo-TerminalPreparedLine -Line $row -StartColumn $StartColumn -MaxWidth $MaxWidth -Alignment $Alignment))
        }
    }
    return ,$prepared.ToArray()
}

function ConvertTo-TerminalHexColor {
    param([Parameter(Mandatory)][Spectre.Console.Color]$Color)

    if ($Color -eq [Spectre.Console.Color]::Default) { return $null }
    return '#{0:X2}{1:X2}{2:X2}' -f $Color.R, $Color.G, $Color.B
}

function ConvertTo-SpectreStyledLines {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Renderable,
        [Parameter(Mandatory)][int]$Width,
        [int]$Height = 0,
        [TerminalSlides.Schema.V1.TerminalCapability]$Capability
    )

    if ($Renderable -isnot [Spectre.Console.Rendering.IRenderable]) {
        throw 'Renderable must implement Spectre.Console.Rendering.IRenderable.'
    }
    $capabilities = [TerminalSpectreCapabilities]::new()
    $capabilities.Ansi = if ($null -eq $Capability) { $true } else { $Capability.AnsiSupport }
    $capabilities.Interactive = $false
    $capabilities.Unicode = if ($null -eq $Capability) { $true } else { $Capability.UnicodeSupport }
    $capabilities.Links = $false
    $capabilities.Legacy = $false
    $capabilities.IsTerminal = $true
    $capabilities.ColorSystem = if ($null -eq $Capability -or $Capability.TrueColorSupport) {
        [Spectre.Console.ColorSystem]::TrueColor
    }
    elseif ($Capability.Color256Support) { [Spectre.Console.ColorSystem]::EightBit }
    else { [Spectre.Console.ColorSystem]::NoColors }
    $options = [Spectre.Console.Rendering.RenderOptions]::new(
        $capabilities,
        [Spectre.Console.Size]::new([Math]::Max(1, $Width), [Math]::Max(1, $Height))
    )
    $segmentLines = [Spectre.Console.Rendering.Segment]::SplitLines($Renderable.Render($options, [Math]::Max(1, $Width)))
    $lineCount = if ($Height -gt 0) { [Math]::Min($Height, $segmentLines.Count) } else { $segmentLines.Count }
    $result = [System.Collections.Generic.List[TerminalStyledLine]]::new()
    for ($lineIndex = 0; $lineIndex -lt $lineCount; $lineIndex++) {
        $line = [TerminalStyledLine]::new()
        foreach ($segment in $segmentLines[$lineIndex]) {
            if ($segment.IsControlCode -or -not $segment.Text) { continue }
            $style = $segment.Style
            Add-TerminalStyledRun -Line $line -Text $segment.Text `
                -Foreground (ConvertTo-TerminalHexColor $style.Foreground) `
                -Background (ConvertTo-TerminalHexColor $style.Background) `
                -Bold:($style.Decoration.HasFlag([Spectre.Console.Decoration]::Bold)) `
                -Italic:($style.Decoration.HasFlag([Spectre.Console.Decoration]::Italic)) `
                -Underline:($style.Decoration.HasFlag([Spectre.Console.Decoration]::Underline))
        }
        $result.Add($line)
    }
    return ,$result.ToArray()
}

function ConvertTo-SpectreRenderableLines {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Renderable,
        [Parameter(Mandatory)][int]$Width,
        [int]$Height = 0,
        [TerminalSlides.Schema.V1.TerminalCapability]$Capability
    )

    return ,(ConvertTo-SpectreStyledLines -Renderable $Renderable -Width $Width -Height $Height -Capability $Capability)
}

function ConvertTo-TerminalImageLines {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][int]$Width,
        [int]$Height = 0,
        [Alias('BasePath')][string]$SourceDirectory,
        [TerminalSlides.Schema.V1.TerminalCapability]$Capability
    )

    $resolvedPath = $Path
    if (-not [System.IO.Path]::IsPathRooted($Path)) {
        $resolvedPath = if ($SourceDirectory) { Join-Path $SourceDirectory $Path } else { $Path }
    }

    if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
        Write-Warning "Image '$Path' was not found. Rendering its accessible text fallback."
        return $null
    }

    try {
        $image = Get-SpectreImage -ImagePath $resolvedPath -Format Blocks -ErrorAction Stop
        $maxWidth = [Math]::Max(1, $Width)
        if ($Height -gt 0 -and $image.Width -gt 0 -and $image.Height -gt 0) {
            $heightLimitedWidth = [Math]::Floor(($Height * 2.0 * $image.Width) / $image.Height)
            $maxWidth = [Math]::Min($maxWidth, [Math]::Max(1, $heightLimitedWidth))
        }
        $image.MaxWidth = $maxWidth
        return ,(ConvertTo-SpectreRenderableLines -Renderable $image -Width $Width -Height $Height -Capability $Capability)
    }
    catch {
        Write-Verbose "Image decoder error: $($_.Exception.Message)"
        Write-Warning "Image '$Path' could not be decoded. Rendering its accessible text fallback."
        return $null
    }
}
