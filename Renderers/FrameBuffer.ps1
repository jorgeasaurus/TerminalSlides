function Set-FrameText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][FrameBuffer]$FrameBuffer,
        [Parameter(Mandatory)][int]$X,
        [Parameter(Mandatory)][int]$Y,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [string]$Foreground,
        [string]$Background,
        [switch]$Bold,
        [switch]$Italic,
        [switch]$Underline
    )
    $row = $Y
    $col = $X
    foreach ($element in (Get-TerminalTextElements -Text $Text -StartColumn $X)) {
        if ($col + $element.Width -gt $FrameBuffer.Width) { break }
        if ($element.Width -le 0) { continue }
        for ($offset = 0; $offset -lt $element.Width; $offset++) {
            $FrameBuffer.ClearCellOccupant($row, $col + $offset)
        }
        $FrameBuffer.SetCell($row, $col, $element.Text, $Foreground, $Background, $Bold.IsPresent, $Italic.IsPresent, $Underline.IsPresent)
        for ($continuation = 1; $continuation -lt $element.Width; $continuation++) {
            if ($col + $continuation -ge $FrameBuffer.Width) { break }
            $FrameBuffer.SetContinuationCell($row, $col + $continuation, $Foreground, $Background, $Bold.IsPresent, $Italic.IsPresent, $Underline.IsPresent)
        }
        $col += $element.Width
    }
}

function Fill-FrameRegion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][FrameBuffer]$FrameBuffer,
        [int]$X = 0,
        [int]$Y = 0,
        [int]$Width = $FrameBuffer.Width,
        [int]$Height = $FrameBuffer.Height,
        [char]$Char = ' ',
        [string]$Foreground,
        [string]$Background
    )
    for ($row = $Y; $row -lt [Math]::Min($FrameBuffer.Height, $Y + $Height); $row++) {
        for ($col = $X; $col -lt [Math]::Min($FrameBuffer.Width, $X + $Width); $col++) {
            $FrameBuffer.SetCell($row, $col, $Char, $Foreground, $Background, $false, $false, $false)
        }
    }
}

function Get-BoxCharacters {
    param([string]$Style = 'unicode')
    switch ($Style) {
        'ascii' { return @{ Tl='+'; Tr='+'; Bl='+'; Br='+'; H='-'; V='|' } }
        'double' { return @{ Tl='╔'; Tr='╗'; Bl='╚'; Br='╝'; H='═'; V='║' } }
        'rounded' { return @{ Tl='╭'; Tr='╮'; Bl='╰'; Br='╯'; H='─'; V='│' } }
        default { return @{ Tl='┌'; Tr='┐'; Bl='└'; Br='┘'; H='─'; V='│' } }
    }
}

function Draw-FrameBox {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][FrameBuffer]$FrameBuffer,
        [Parameter(Mandatory)][int]$X,
        [Parameter(Mandatory)][int]$Y,
        [Parameter(Mandatory)][int]$Width,
        [Parameter(Mandatory)][int]$Height,
        [string]$Foreground,
        [string]$Background,
        [string]$Style = 'unicode'
    )
    if ($Width -lt 2 -or $Height -lt 2) { return }
    $chars = Get-BoxCharacters -Style $Style
    for ($col = $X + 1; $col -lt $X + $Width - 1; $col++) {
        $FrameBuffer.SetCell($Y, $col, $chars.H, $Foreground, $Background, $false, $false, $false)
        $FrameBuffer.SetCell($Y + $Height - 1, $col, $chars.H, $Foreground, $Background, $false, $false, $false)
    }
    for ($row = $Y + 1; $row -lt $Y + $Height - 1; $row++) {
        $FrameBuffer.SetCell($row, $X, $chars.V, $Foreground, $Background, $false, $false, $false)
        $FrameBuffer.SetCell($row, $X + $Width - 1, $chars.V, $Foreground, $Background, $false, $false, $false)
    }
    $FrameBuffer.SetCell($Y, $X, $chars.Tl, $Foreground, $Background, $false, $false, $false)
    $FrameBuffer.SetCell($Y, $X + $Width - 1, $chars.Tr, $Foreground, $Background, $false, $false, $false)
    $FrameBuffer.SetCell($Y + $Height - 1, $X, $chars.Bl, $Foreground, $Background, $false, $false, $false)
    $FrameBuffer.SetCell($Y + $Height - 1, $X + $Width - 1, $chars.Br, $Foreground, $Background, $false, $false, $false)
}
