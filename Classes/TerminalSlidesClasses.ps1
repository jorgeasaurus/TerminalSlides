class TerminalCapability {
    [string]$HostName
    [string]$OS
    [string]$PSVersion
    [int]$Width
    [int]$Height
    [bool]$AnsiSupport
    [bool]$TrueColorSupport
    [bool]$Color256Support
    [bool]$UnicodeSupport
    [bool]$Interactive
    [bool]$AlternateBuffer
    [bool]$SixelSupport
    [bool]$KittyGraphics
    [bool]$ITermImages
    [bool]$IsRedirected
    [hashtable]$EnvironmentVars
}

class ThemeDefinition {
    [string]$Name
    [string]$Background
    [string]$Foreground
    [string]$Primary
    [string]$Accent
    [string]$Muted
    [string]$Heading
    [string]$Border
    [string]$CodeTheme
    [string]$CodeBackground
    [string]$CodeForeground
    [string]$BulletSymbol
    [string]$BoxDrawingStyle
    [string]$HeadingStyle
    [string[]]$ChartPalette
    [string]$ErrorColor
    [string]$WarningColor
    [string]$SuccessColor
    [hashtable]$Metadata
}

class PresentationMetadata {
    [string]$Title
    [string]$Subtitle
    [string]$Author
    [string]$Description
    [string]$Version
    [hashtable]$Custom

    PresentationMetadata() {
        $this.Custom = @{}
    }
}

class SlideMetadata {
    [string]$Author
    [hashtable]$Custom

    SlideMetadata() {
        $this.Custom = @{}
    }
}

class SlideElement {
    [string]$Id
    [string]$Type
    [object]$Content
    [string]$Region
    [int]$X
    [int]$Y
    [int]$Width
    [int]$Height
    [string]$Alignment
    [string]$VerticalAlignment
    [int]$Padding
    [string]$ForegroundColor
    [string]$BackgroundColor
    [bool]$Border
    [string]$BorderStyle
    [hashtable]$Style
    [int]$RevealStep
    [string]$OverflowBehavior
    [hashtable]$Properties

    SlideElement() {
        $this.Style = @{}
        $this.Properties = @{}
        $this.Alignment = 'Left'
        $this.VerticalAlignment = 'Top'
        $this.OverflowBehavior = 'Wrap'
        $this.Region = 'Content'
    }
}

class Slide {
    [string]$Id
    [int]$Index
    [string]$Title
    [string]$Layout
    [System.Collections.Generic.List[SlideElement]]$Elements
    [string]$Notes
    [string]$Background
    [string]$Transition
    [bool]$Hidden
    [SlideMetadata]$Metadata
    [int]$MaxRevealStep

    Slide() {
        $this.Id = [System.Guid]::NewGuid().ToString()
        $this.Elements = [System.Collections.Generic.List[SlideElement]]::new()
        $this.Metadata = [SlideMetadata]::new()
        $this.Layout = 'TitleAndContent'
        $this.Transition = 'None'
        $this.Hidden = $false
        $this.MaxRevealStep = 0
    }
}

class TerminalPresentation {
    [string]$Title
    [string]$Subtitle
    [string]$Author
    [string]$Description
    [string]$Theme
    [int]$Width
    [int]$Height
    [System.Collections.Generic.List[Slide]]$Slides
    [PresentationMetadata]$Metadata
    [datetime]$CreatedDate
    [datetime]$ModifiedDate
    [string]$DefaultTransition
    [string]$DefaultLayout
    [hashtable]$Configuration

    TerminalPresentation() {
        $this.Slides = [System.Collections.Generic.List[Slide]]::new()
        $this.Metadata = [PresentationMetadata]::new()
        $this.CreatedDate = [datetime]::UtcNow
        $this.ModifiedDate = [datetime]::UtcNow
        $this.Theme = 'Midnight'
        $this.DefaultTransition = 'None'
        $this.DefaultLayout = 'TitleAndContent'
        $this.Width = 0
        $this.Height = 0
        $this.Configuration = @{}
    }
}

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

    [string] Render([bool]$diffOnly) {
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
        $this.PreviousCells = $this.Cells
        return $sb.ToString()
    }
}
