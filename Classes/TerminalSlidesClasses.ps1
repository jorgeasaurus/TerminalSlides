# Data classes (TerminalCapability, ThemeDefinition, PresentationMetadata,
# SlideMetadata, SlideElement, Slide, TerminalPresentation) are compiled from
# Classes/TerminalSlides.DataClasses.cs by the module loader. Keeping them in a
# real assembly gives them a stable identity across module re-imports and
# avoids the "PowerShell Class Assembly" stale-type binding failure where a
# presentation created before Import-Module -Force cannot be passed back to
# module functions.

class FrameBufferCell {
    [char]$Char
    [string]$Fg
    [string]$Bg
    [bool]$Bold
    [bool]$Italic
    [bool]$Underline
    [bool]$Strikethrough
}

class FrameBuffer {
    [int]$Width
    [int]$Height
    [FrameBufferCell[][]]$Cells
    [FrameBufferCell[][]]$PreviousCells

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
        $this.PreviousCells = $null
        $this.Clear()
    }

    [void] Clear() {
        for ($r = 0; $r -lt $this.Height; $r++) {
            for ($c = 0; $c -lt $this.Width; $c++) {
                $cell = $this.Cells[$r][$c]
                $cell.Char = ' '
                $cell.Fg = $null
                $cell.Bg = $null
                $cell.Bold = $false
                $cell.Italic = $false
                $cell.Underline = $false
                $cell.Strikethrough = $false
            }
        }
    }

    [void] SetCell([int]$row, [int]$col, [char]$ch, [string]$fg, [string]$bg, [bool]$bold, [bool]$italic, [bool]$underline) {
        if ($row -ge 0 -and $row -lt $this.Height -and $col -ge 0 -and $col -lt $this.Width) {
            $cell = $this.Cells[$row][$col]
            $cell.Char = $ch
            $cell.Fg = $fg
            $cell.Bg = $bg
            $cell.Bold = $bold
            $cell.Italic = $italic
            $cell.Underline = $underline
        }
    }

    [bool] CellEquals([FrameBufferCell]$a, [FrameBufferCell]$b) {
        return ($a.Char -eq $b.Char -and $a.Fg -eq $b.Fg -and $a.Bg -eq $b.Bg -and
                $a.Bold -eq $b.Bold -and $a.Italic -eq $b.Italic -and $a.Underline -eq $b.Underline)
    }

    [FrameBufferCell[][]] SnapshotCells() {
        $rows = [FrameBufferCell[][]]::new($this.Height)
        for ($r = 0; $r -lt $this.Height; $r++) {
            $rows[$r] = [FrameBufferCell[]]::new($this.Width)
            for ($c = 0; $c -lt $this.Width; $c++) {
                $src = $this.Cells[$r][$c]
                $copy = [FrameBufferCell]::new()
                $copy.Char = $src.Char
                $copy.Fg = $src.Fg
                $copy.Bg = $src.Bg
                $copy.Bold = $src.Bold
                $copy.Italic = $src.Italic
                $copy.Underline = $src.Underline
                $copy.Strikethrough = $src.Strikethrough
                $rows[$r][$c] = $copy
            }
        }
        return $rows
    }

    [string] Render([bool]$diffOnly) {
        $sb = [System.Text.StringBuilder]::new()
        $currentFg = $null
        $currentBg = $null
        $currentBold = $false
        $currentItalic = $false
        $currentUnderline = $false
        $hasPrevious = ($null -ne $this.PreviousCells -and $this.PreviousCells.Count -eq $this.Height)

        for ($r = 0; $r -lt $this.Height; $r++) {
            $rowDirty = $true
            if ($diffOnly -and $hasPrevious) {
                $rowDirty = $false
                for ($c = 0; $c -lt $this.Width; $c++) {
                    if (-not $this.CellEquals($this.Cells[$r][$c], $this.PreviousCells[$r][$c])) { $rowDirty = $true; break }
                }
            }
            if (-not $rowDirty) { continue }
            [void]$sb.Append("`e[$($r + 1);1H")
            for ($c = 0; $c -lt $this.Width; $c++) {
                $cell = $this.Cells[$r][$c]
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
                        $rgb = Convert-HexToRgb -Hex $cell.Fg
                        [void]$sb.Append("`e[38;2;$($rgb[0]);$($rgb[1]);$($rgb[2])m")
                        $currentFg = $cell.Fg
                    }
                    if ($cell.Bg) {
                        $rgb = Convert-HexToRgb -Hex $cell.Bg
                        [void]$sb.Append("`e[48;2;$($rgb[0]);$($rgb[1]);$($rgb[2])m")
                        $currentBg = $cell.Bg
                    }
                }
                [void]$sb.Append($cell.Char)
            }
        }
        [void]$sb.Append("`e[0m")
        $this.PreviousCells = $this.SnapshotCells()
        return $sb.ToString()
    }
}
