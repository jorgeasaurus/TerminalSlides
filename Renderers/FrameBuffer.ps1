function ConvertFrom-AnsiToSegments {
    [CmdletBinding()]
    param([AllowNull()][string]$Text)
    $segments = [System.Collections.Generic.List[object]]::new()
    if ($null -eq $Text -or $Text -eq '') { return $segments.ToArray() }
    $fg = $null
    $bold = $false
    $pos = 0
    foreach ($match in [regex]::Matches($Text, "`e\[([\d;]*)m")) {
        if ($match.Index -gt $pos) {
            $segments.Add([pscustomobject]@{ Text = $Text.Substring($pos, $match.Index - $pos); Foreground = $fg; Bold = $bold })
        }
        $rawCodes = $match.Groups[1].Value
        $codes = if ([string]::IsNullOrEmpty($rawCodes)) { @(0) } else { @($rawCodes -split ';' | ForEach-Object { if ($_ -eq '') { 0 } else { [int]$_ } }) }
        if ($codes.Count -eq 1 -and $codes[0] -eq 0) { $fg = $null; $bold = $false }
        else {
            for ($i = 0; $i -lt $codes.Count; $i++) {
                if ($codes[$i] -eq 1) { $bold = $true }
                elseif ($codes[$i] -eq 38 -and $i + 4 -lt $codes.Count -and $codes[$i + 1] -eq 2) {
                    $fg = '#{0:X2}{1:X2}{2:X2}' -f $codes[$i + 2], $codes[$i + 3], $codes[$i + 4]
                    $i += 4
                }
            }
        }
        $pos = $match.Index + $match.Length
    }
    if ($pos -lt $Text.Length) {
        $segments.Add([pscustomobject]@{ Text = $Text.Substring($pos); Foreground = $fg; Bold = $bold })
    }
    return $segments.ToArray()
}

function Set-FrameText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][FrameBuffer]$FrameBuffer,
        [Parameter(Mandatory)][int]$X,
        [Parameter(Mandatory)][int]$Y,
        [Parameter(Mandatory)][string]$Text,
        [string]$Foreground,
        [string]$Background,
        [switch]$Bold,
        [switch]$Italic,
        [switch]$Underline,
        [switch]$NoClip
    )
    $row = $Y
    $col = $X
    foreach ($ch in (Strip-AnsiSequences -Text $Text).ToCharArray()) {
        if (-not $NoClip -and $col -ge $FrameBuffer.Width) { break }
        $FrameBuffer.SetCell($row, $col, $ch, $Foreground, $Background, $Bold.IsPresent, $Italic.IsPresent, $Underline.IsPresent)
        $col++
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
