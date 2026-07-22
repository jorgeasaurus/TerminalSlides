# Public data contracts are loaded from the packaged schema assembly. These
# PowerShell classes are private rendering models and never cross the module API.

class FrameBufferCell {
    [string]$Char
    [bool]$Continuation
    [string]$Fg
    [string]$Bg
    [bool]$Bold
    [bool]$Italic
    [bool]$Underline
}

class TerminalStyledRun {
    [string]$Text
    [string]$Foreground
    [string]$Background
    [bool]$Bold
    [bool]$Italic
    [bool]$Underline

    TerminalStyledRun([string]$text, [string]$foreground, [string]$background, [bool]$bold, [bool]$italic, [bool]$underline) {
        $this.Text = $text
        $this.Foreground = $foreground
        $this.Background = $background
        $this.Bold = $bold
        $this.Italic = $italic
        $this.Underline = $underline
    }
}

class TerminalStyledLine {
    [System.Collections.Generic.List[TerminalStyledRun]]$Runs

    TerminalStyledLine() {
        $this.Runs = [System.Collections.Generic.List[TerminalStyledRun]]::new()
    }

    [string] GetText() {
        $builder = [System.Text.StringBuilder]::new()
        foreach ($run in $this.Runs) {
            [void]$builder.Append($run.Text)
        }
        return $builder.ToString()
    }

    [string] ToString() {
        return $this.GetText()
    }
}

class TerminalStyledGrapheme {
    [string]$Text
    [TerminalStyledRun]$Style

    TerminalStyledGrapheme([string]$text, [TerminalStyledRun]$style) {
        $this.Text = $text
        $this.Style = $style
    }
}

class TerminalStyledTextElement {
    [string]$Text
    [int]$Width
    [TerminalStyledRun]$Style

    TerminalStyledTextElement([string]$text, [int]$width, [TerminalStyledRun]$style) {
        $this.Text = $text
        $this.Width = $width
        $this.Style = $style
    }
}

class TerminalPreparedRun {
    [string]$Text
    [int]$Width
    [string]$Foreground
    [string]$Background
    [bool]$Bold
    [bool]$Italic
    [bool]$Underline

    TerminalPreparedRun([string]$text, [int]$width, [string]$foreground, [string]$background, [bool]$bold, [bool]$italic, [bool]$underline) {
        $this.Text = $text
        $this.Width = $width
        $this.Foreground = $foreground
        $this.Background = $background
        $this.Bold = $bold
        $this.Italic = $italic
        $this.Underline = $underline
    }
}

class TerminalPreparedLine {
    [System.Collections.Generic.List[TerminalPreparedRun]]$Runs
    [int]$Width
    [int]$RenderedWidth
    [int]$StartColumn
    [int]$AvailableWidth

    TerminalPreparedLine([int]$startColumn, [int]$availableWidth) {
        $this.Runs = [System.Collections.Generic.List[TerminalPreparedRun]]::new()
        $this.StartColumn = $startColumn
        $this.AvailableWidth = $availableWidth
    }

    [string] GetText() {
        $builder = [System.Text.StringBuilder]::new()
        foreach ($run in $this.Runs) {
            [void]$builder.Append($run.Text)
        }
        return $builder.ToString()
    }

    [string] ToString() {
        return $this.GetText()
    }
}

class TerminalSpectreCapabilities : Spectre.Console.IReadOnlyCapabilities {
    [Spectre.Console.ColorSystem]$ColorSystem
    [bool]$Ansi
    [bool]$Links
    [bool]$Legacy
    [bool]$IsTerminal
    [bool]$Interactive
    [bool]$Unicode
}

class FrameBuffer {
    [int]$Width
    [int]$Height
    [FrameBufferCell[][]]$Cells

    FrameBuffer([int]$width, [int]$height) {
        $this.Width = [Math]::Max(1, $width)
        $this.Height = [Math]::Max(1, $height)
        $rows = [FrameBufferCell[][]]::new($this.Height)
        for ($r = 0; $r -lt $this.Height; $r++) {
            $rows[$r] = [FrameBufferCell[]]::new($this.Width)
            for ($c = 0; $c -lt $this.Width; $c++) {
                $rows[$r][$c] = [FrameBufferCell]::new()
            }
        }
        $this.Cells = $rows
        $this.Clear()
    }

    [void] Clear() {
        for ($r = 0; $r -lt $this.Height; $r++) {
            for ($c = 0; $c -lt $this.Width; $c++) {
                $cell = $this.Cells[$r][$c]
                $cell.Char = ' '
                $cell.Continuation = $false
                $cell.Fg = $null
                $cell.Bg = $null
                $cell.Bold = $false
                $cell.Italic = $false
                $cell.Underline = $false
            }
        }
    }

    [void] ClearCellOccupant([int]$row, [int]$col) {
        if ($row -lt 0 -or $row -ge $this.Height -or $col -lt 0 -or $col -ge $this.Width) { return }
        $lead = $col
        while ($lead -gt 0 -and $this.Cells[$row][$lead].Continuation) { $lead-- }
        $index = $lead
        do {
            $cell = $this.Cells[$row][$index]
            $cell.Char = ' '
            $cell.Continuation = $false
            $cell.Fg = $null
            $cell.Bg = $null
            $cell.Bold = $false
            $cell.Italic = $false
            $cell.Underline = $false
            $index++
        } while ($index -lt $this.Width -and $this.Cells[$row][$index].Continuation)
    }

    [void] SetCell([int]$row, [int]$col, [string]$ch, [string]$fg, [string]$bg, [bool]$bold, [bool]$italic, [bool]$underline) {
        if ($row -ge 0 -and $row -lt $this.Height -and $col -ge 0 -and $col -lt $this.Width) {
            $this.ClearCellOccupant($row, $col)
            $cell = $this.Cells[$row][$col]
            $cell.Char = $ch
            $cell.Fg = $fg
            $cell.Bg = $bg
            $cell.Bold = $bold
            $cell.Italic = $italic
            $cell.Underline = $underline
        }
    }

    [void] SetContinuationCell([int]$row, [int]$col, [string]$fg, [string]$bg, [bool]$bold, [bool]$italic, [bool]$underline) {
        if ($row -ge 0 -and $row -lt $this.Height -and $col -ge 0 -and $col -lt $this.Width) {
            $cell = $this.Cells[$row][$col]
            $cell.Char = ' '
            $cell.Continuation = $true
            $cell.Fg = $fg
            $cell.Bg = $bg
            $cell.Bold = $bold
            $cell.Italic = $italic
            $cell.Underline = $underline
        }
    }

    [string] GetRowText([int]$row) {
        if ($row -lt 0 -or $row -ge $this.Height) { return '' }
        $builder = [System.Text.StringBuilder]::new()
        foreach ($cell in $this.Cells[$row]) {
            if (-not $cell.Continuation) { [void]$builder.Append($cell.Char) }
        }
        return $builder.ToString()
    }

    hidden [int] GetColor256Index([string]$hex) {
        $rgb = Convert-HexToRgb -Hex $hex
        return 16 + (36 * [Math]::Round($rgb[0] / 51.0)) + (6 * [Math]::Round($rgb[1] / 51.0)) + [Math]::Round($rgb[2] / 51.0)
    }

    [string] Render([bool]$trueColorSupport, [bool]$color256Support) {
        $sb = [System.Text.StringBuilder]::new()
        $currentFg = $null
        $currentBg = $null
        $currentBold = $false
        $currentItalic = $false
        $currentUnderline = $false

        for ($r = 0; $r -lt $this.Height; $r++) {
            [void]$sb.Append("`e[$($r + 1);1H")
            for ($c = 0; $c -lt $this.Width; $c++) {
                $cell = $this.Cells[$r][$c]
                if ($cell.Continuation) { continue }
                $needReset = $false
                if ($cell.Bold -ne $currentBold -or $cell.Italic -ne $currentItalic -or $cell.Underline -ne $currentUnderline) {
                    $needReset = $true
                }
                if ($needReset -or $cell.Fg -ne $currentFg -or $cell.Bg -ne $currentBg) {
                    [void]$sb.Append("`e[0m")
                    $currentFg = $null; $currentBg = $null; $currentBold = $false; $currentItalic = $false; $currentUnderline = $false
                    if ($cell.Bold) { [void]$sb.Append("`e[1m"); $currentBold = $true }
                    if ($cell.Italic) { [void]$sb.Append("`e[3m"); $currentItalic = $true }
                    if ($cell.Underline) { [void]$sb.Append("`e[4m"); $currentUnderline = $true }
                    if ($cell.Fg) {
                        if ($trueColorSupport) {
                            $rgb = Convert-HexToRgb -Hex $cell.Fg
                            [void]$sb.Append("`e[38;2;$($rgb[0]);$($rgb[1]);$($rgb[2])m")
                        }
                        elseif ($color256Support) {
                            $index = $this.GetColor256Index($cell.Fg)
                            [void]$sb.Append("`e[38;5;$index" + 'm')
                        }
                        $currentFg = $cell.Fg
                    }
                    if ($cell.Bg) {
                        if ($trueColorSupport) {
                            $rgb = Convert-HexToRgb -Hex $cell.Bg
                            [void]$sb.Append("`e[48;2;$($rgb[0]);$($rgb[1]);$($rgb[2])m")
                        }
                        elseif ($color256Support) {
                            $index = $this.GetColor256Index($cell.Bg)
                            [void]$sb.Append("`e[48;5;$index" + 'm')
                        }
                        $currentBg = $cell.Bg
                    }
                }
                [void]$sb.Append($cell.Char)
            }
        }
        [void]$sb.Append("`e[0m")
        return $sb.ToString()
    }
}
