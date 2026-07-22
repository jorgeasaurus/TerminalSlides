$script:TerminalSlidesStrictUtf8 = [Text.UTF8Encoding]::new($false, $true)

function Split-TerminalLogicalRows {
    [CmdletBinding()]
    param([AllowNull()][string]$Text)

    $value = $Text ?? ''
    Assert-TerminalValidUtf16 -Value $value
    return ,([regex]::Split($value, '\r\n|\r|\n'))
}

function Assert-TerminalValidUtf16 {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)

    try { [void]$script:TerminalSlidesStrictUtf8.GetByteCount($Value) }
    catch [Text.EncoderFallbackException] { throw 'TerminalSlides text requires valid UTF-16.' }
}

function ConvertTo-TerminalLfText {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)

    Assert-TerminalValidUtf16 -Value $Value
    return $Value.Replace("`r`n", "`n").Replace("`r", "`n")
}

function ConvertTo-TerminalHtmlEncodedText {
    param([AllowNull()][object]$Value)

    $text = [string]$Value
    Assert-TerminalValidUtf16 -Value $text
    return [Net.WebUtility]::HtmlEncode($text)
}
