$script:TerminalTabStopWidth = 8

# Generated as start/end pairs from the merged W/F ranges in Unicode 17.0 EastAsianWidth.txt.
$script:TerminalWideIntervalBounds = [int[]]@(
    [int[]]@(0x1100, 0x115F)
    [int[]]@(0x231A, 0x231B)
    [int[]]@(0x2329, 0x232A)
    [int[]]@(0x23E9, 0x23EC)
    [int[]]@(0x23F0, 0x23F0)
    [int[]]@(0x23F3, 0x23F3)
    [int[]]@(0x25FD, 0x25FE)
    [int[]]@(0x2614, 0x2615)
    [int[]]@(0x2630, 0x2637)
    [int[]]@(0x2648, 0x2653)
    [int[]]@(0x267F, 0x267F)
    [int[]]@(0x268A, 0x268F)
    [int[]]@(0x2693, 0x2693)
    [int[]]@(0x26A1, 0x26A1)
    [int[]]@(0x26AA, 0x26AB)
    [int[]]@(0x26BD, 0x26BE)
    [int[]]@(0x26C4, 0x26C5)
    [int[]]@(0x26CE, 0x26CE)
    [int[]]@(0x26D4, 0x26D4)
    [int[]]@(0x26EA, 0x26EA)
    [int[]]@(0x26F2, 0x26F3)
    [int[]]@(0x26F5, 0x26F5)
    [int[]]@(0x26FA, 0x26FA)
    [int[]]@(0x26FD, 0x26FD)
    [int[]]@(0x2705, 0x2705)
    [int[]]@(0x270A, 0x270B)
    [int[]]@(0x2728, 0x2728)
    [int[]]@(0x274C, 0x274C)
    [int[]]@(0x274E, 0x274E)
    [int[]]@(0x2753, 0x2755)
    [int[]]@(0x2757, 0x2757)
    [int[]]@(0x2795, 0x2797)
    [int[]]@(0x27B0, 0x27B0)
    [int[]]@(0x27BF, 0x27BF)
    [int[]]@(0x2B1B, 0x2B1C)
    [int[]]@(0x2B50, 0x2B50)
    [int[]]@(0x2B55, 0x2B55)
    [int[]]@(0x2E80, 0x2E99)
    [int[]]@(0x2E9B, 0x2EF3)
    [int[]]@(0x2F00, 0x2FD5)
    [int[]]@(0x2FF0, 0x303E)
    [int[]]@(0x3041, 0x3096)
    [int[]]@(0x3099, 0x30FF)
    [int[]]@(0x3105, 0x312F)
    [int[]]@(0x3131, 0x318E)
    [int[]]@(0x3190, 0x31E5)
    [int[]]@(0x31EF, 0x321E)
    [int[]]@(0x3220, 0x3247)
    [int[]]@(0x3250, 0xA48C)
    [int[]]@(0xA490, 0xA4C6)
    [int[]]@(0xA960, 0xA97C)
    [int[]]@(0xAC00, 0xD7A3)
    [int[]]@(0xF900, 0xFAFF)
    [int[]]@(0xFE10, 0xFE19)
    [int[]]@(0xFE30, 0xFE52)
    [int[]]@(0xFE54, 0xFE66)
    [int[]]@(0xFE68, 0xFE6B)
    [int[]]@(0xFF01, 0xFF60)
    [int[]]@(0xFFE0, 0xFFE6)
    [int[]]@(0x16FE0, 0x16FE4)
    [int[]]@(0x16FF0, 0x16FF6)
    [int[]]@(0x17000, 0x18CD5)
    [int[]]@(0x18CFF, 0x18D1E)
    [int[]]@(0x18D80, 0x18DF2)
    [int[]]@(0x1AFF0, 0x1AFF3)
    [int[]]@(0x1AFF5, 0x1AFFB)
    [int[]]@(0x1AFFD, 0x1AFFE)
    [int[]]@(0x1B000, 0x1B122)
    [int[]]@(0x1B132, 0x1B132)
    [int[]]@(0x1B150, 0x1B152)
    [int[]]@(0x1B155, 0x1B155)
    [int[]]@(0x1B164, 0x1B167)
    [int[]]@(0x1B170, 0x1B2FB)
    [int[]]@(0x1D300, 0x1D356)
    [int[]]@(0x1D360, 0x1D376)
    [int[]]@(0x1F004, 0x1F004)
    [int[]]@(0x1F0CF, 0x1F0CF)
    [int[]]@(0x1F18E, 0x1F18E)
    [int[]]@(0x1F191, 0x1F19A)
    [int[]]@(0x1F200, 0x1F202)
    [int[]]@(0x1F210, 0x1F23B)
    [int[]]@(0x1F240, 0x1F248)
    [int[]]@(0x1F250, 0x1F251)
    [int[]]@(0x1F260, 0x1F265)
    [int[]]@(0x1F300, 0x1F320)
    [int[]]@(0x1F32D, 0x1F335)
    [int[]]@(0x1F337, 0x1F37C)
    [int[]]@(0x1F37E, 0x1F393)
    [int[]]@(0x1F3A0, 0x1F3CA)
    [int[]]@(0x1F3CF, 0x1F3D3)
    [int[]]@(0x1F3E0, 0x1F3F0)
    [int[]]@(0x1F3F4, 0x1F3F4)
    [int[]]@(0x1F3F8, 0x1F43E)
    [int[]]@(0x1F440, 0x1F440)
    [int[]]@(0x1F442, 0x1F4FC)
    [int[]]@(0x1F4FF, 0x1F53D)
    [int[]]@(0x1F54B, 0x1F54E)
    [int[]]@(0x1F550, 0x1F567)
    [int[]]@(0x1F57A, 0x1F57A)
    [int[]]@(0x1F595, 0x1F596)
    [int[]]@(0x1F5A4, 0x1F5A4)
    [int[]]@(0x1F5FB, 0x1F64F)
    [int[]]@(0x1F680, 0x1F6C5)
    [int[]]@(0x1F6CC, 0x1F6CC)
    [int[]]@(0x1F6D0, 0x1F6D2)
    [int[]]@(0x1F6D5, 0x1F6D8)
    [int[]]@(0x1F6DC, 0x1F6DF)
    [int[]]@(0x1F6EB, 0x1F6EC)
    [int[]]@(0x1F6F4, 0x1F6FC)
    [int[]]@(0x1F7E0, 0x1F7EB)
    [int[]]@(0x1F7F0, 0x1F7F0)
    [int[]]@(0x1F90C, 0x1F93A)
    [int[]]@(0x1F93C, 0x1F945)
    [int[]]@(0x1F947, 0x1F9FF)
    [int[]]@(0x1FA70, 0x1FA7C)
    [int[]]@(0x1FA80, 0x1FA8A)
    [int[]]@(0x1FA8E, 0x1FAC6)
    [int[]]@(0x1FAC8, 0x1FAC8)
    [int[]]@(0x1FACD, 0x1FADC)
    [int[]]@(0x1FADF, 0x1FAEA)
    [int[]]@(0x1FAEF, 0x1FAF8)
    [int[]]@(0x20000, 0x2FFFD)
    [int[]]@(0x30000, 0x3FFFD)
)

function Test-TerminalWideCodePoint {
    param([Parameter(Mandatory)][int]$Value)

    $low = 0
    $high = [int]($script:TerminalWideIntervalBounds.Count / 2) - 1
    while ($low -le $high) {
        $middle = [int][Math]::Floor(($low + $high) / 2)
        $start = $script:TerminalWideIntervalBounds[$middle * 2]
        $end = $script:TerminalWideIntervalBounds[($middle * 2) + 1]
        if ($Value -lt $start) {
            $high = $middle - 1
        }
        elseif ($Value -gt $end) {
            $low = $middle + 1
        }
        else {
            return $true
        }
    }
    return $false
}

function Get-TerminalRuneWidth {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Text.Rune]$Rune)

    $category = [System.Text.Rune]::GetUnicodeCategory($Rune)
    if ($category -in @(
        [System.Globalization.UnicodeCategory]::Control,
        [System.Globalization.UnicodeCategory]::Format,
        [System.Globalization.UnicodeCategory]::NonSpacingMark,
        [System.Globalization.UnicodeCategory]::SpacingCombiningMark,
        [System.Globalization.UnicodeCategory]::EnclosingMark
    )) {
        return 0
    }

    if (Test-TerminalWideCodePoint -Value $Rune.Value) { return 2 }
    return 1
}

function Get-TerminalTextElements {
    [CmdletBinding()]
    param(
        [AllowNull()][string]$Text,
        [ValidateRange(0, [int]::MaxValue)][int]$StartColumn = 0,
        [switch]$PreserveTabs
    )

    $elements = [System.Collections.Generic.List[object]]::new()
    $value = $Text ?? ''
    Assert-TerminalValidUtf16 -Value $value
    $plainText = Strip-AnsiSequences -Text $value
    $enumerator = [System.Globalization.StringInfo]::GetTextElementEnumerator($plainText)
    $column = $StartColumn
    while ($enumerator.MoveNext()) {
        $textElement = $enumerator.GetTextElement()
        if ($textElement -eq "`t") {
            $width = $script:TerminalTabStopWidth - ($column % $script:TerminalTabStopWidth)
            if ($PreserveTabs) {
                $elements.Add([pscustomobject]@{ Text = $textElement; Width = $width })
            }
            else {
                for ($space = 0; $space -lt $width; $space++) {
                    $elements.Add([pscustomobject]@{ Text = ' '; Width = 1 })
                }
            }
            $column += $width
            continue
        }
        if ($textElement.Contains("`r") -or $textElement.Contains("`n")) {
            $elements.Add([pscustomobject]@{ Text = $textElement; Width = 0 })
            $column = $StartColumn
            continue
        }
        $width = 0
        $regionalIndicatorCount = 0
        $hasEmojiVariationSelector = $false
        for ($offset = 0; $offset -lt $textElement.Length;) {
            $rune = [System.Text.Rune]::GetRuneAt($textElement, $offset)
            $width = [Math]::Max($width, (Get-TerminalRuneWidth -Rune $rune))
            if ($rune.Value -ge 0x1F1E6 -and $rune.Value -le 0x1F1FF) { $regionalIndicatorCount++ }
            if ($rune.Value -eq 0xFE0F) { $hasEmojiVariationSelector = $true }
            $offset += $rune.Utf16SequenceLength
        }
        if ($regionalIndicatorCount -ge 2 -or ($hasEmojiVariationSelector -and $width -gt 0)) {
            $width = [Math]::Max(2, $width)
        }
        $elements.Add([pscustomobject]@{ Text = $textElement; Width = $width })
        $column += $width
    }
    return ,$elements.ToArray()
}

function Expand-TerminalTabs {
    [CmdletBinding()]
    param(
        [AllowNull()][string]$Text,
        [ValidateRange(0, [int]::MaxValue)][int]$StartColumn = 0
    )

    return (@(Get-TerminalTextElements -Text ($Text ?? '') -StartColumn $StartColumn | ForEach-Object { $_.Text }) -join '')
}

function Measure-TextWidth {
    [CmdletBinding()]
    param(
        [AllowNull()][string]$Text,
        [ValidateRange(0, [int]::MaxValue)][int]$StartColumn = 0
    )

    $width = 0
    foreach ($element in (Get-TerminalTextElements -Text ($Text ?? '') -StartColumn $StartColumn)) { $width += $element.Width }
    return $width
}

function Limit-TextToCellWidth {
    [CmdletBinding()]
    param(
        [AllowNull()][string]$Text,
        [Parameter(Mandatory)][int]$Width,
        [ValidateRange(0, [int]::MaxValue)][int]$StartColumn = 0,
        [switch]$PreserveTabs
    )

    $builder = [System.Text.StringBuilder]::new()
    $used = 0
    foreach ($element in (Get-TerminalTextElements -Text ($Text ?? '') -StartColumn $StartColumn -PreserveTabs:$PreserveTabs)) {
        if ($used + $element.Width -gt [Math]::Max(0, $Width)) { break }
        [void]$builder.Append($element.Text)
        $used += $element.Width
    }
    return $builder.ToString()
}

function Split-TextByCellWidth {
    [CmdletBinding()]
    param(
        [AllowNull()][string]$Text,
        [Parameter(Mandatory)][int]$Width,
        [ValidateRange(0, [int]::MaxValue)][int]$StartColumn = 0,
        [switch]$PreserveTabs
    )

    $width = [Math]::Max(1, $Width)
    $lines = [System.Collections.Generic.List[string]]::new()
    $builder = [System.Text.StringBuilder]::new()
    $used = 0
    $elements = Get-TerminalTextElements -Text ($Text ?? '') -StartColumn $StartColumn -PreserveTabs:$PreserveTabs
    foreach ($element in $elements) {
        if ($PreserveTabs) {
            $element = @(Get-TerminalTextElements -Text $element.Text -StartColumn ($StartColumn + $used) -PreserveTabs)[0]
        }
        if ($builder.Length -gt 0 -and $used + $element.Width -gt $width) {
            $lines.Add($builder.ToString())
            [void]$builder.Clear()
            $used = 0
            if ($PreserveTabs) {
                $element = @(Get-TerminalTextElements -Text $element.Text -StartColumn $StartColumn -PreserveTabs)[0]
            }
        }
        [void]$builder.Append($element.Text)
        $used += $element.Width
    }
    if ($builder.Length -gt 0 -or $lines.Count -eq 0) { $lines.Add($builder.ToString()) }
    return ,$lines.ToArray()
}

function Pad-TerminalText {
    [CmdletBinding()]
    param(
        [AllowNull()][string]$Text,
        [Parameter(Mandatory)][int]$Width,
        [ValidateRange(0, [int]::MaxValue)][int]$StartColumn = 0
    )

    $value = $Text ?? ''
    return $value + (' ' * [Math]::Max(0, $Width - (Measure-TextWidth -Text $value -StartColumn $StartColumn)))
}
