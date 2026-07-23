function ConvertTo-PowerShellStyledLine {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][TerminalSlides.Schema.V1.ThemeDefinition]$Theme
    )

    $tokens = $null
    $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tokens, [ref]$errors)
    $line = [TerminalStyledLine]::new()
    $position = 0
    foreach ($token in $tokens) {
        if ($token.Kind -eq [System.Management.Automation.Language.TokenKind]::EndOfInput) { continue }
        $start = [Math]::Max(0, $token.Extent.StartOffset)
        $end = [Math]::Min($Text.Length, $token.Extent.EndOffset)
        if ($start -gt $position) {
            Add-TerminalStyledRun -Line $line -Text $Text.Substring($position, $start - $position)
        }
        if ($end -le $start) { continue }
        $foreground = $null
        $bold = $false
        if ($token.Kind -eq [System.Management.Automation.Language.TokenKind]::Comment) {
            $foreground = if ($Theme.Muted) { $Theme.Muted } else { $Theme.Foreground }
        }
        elseif ($token.Kind -in @(
            [System.Management.Automation.Language.TokenKind]::StringLiteral,
            [System.Management.Automation.Language.TokenKind]::StringExpandable,
            [System.Management.Automation.Language.TokenKind]::HereStringLiteral,
            [System.Management.Automation.Language.TokenKind]::HereStringExpandable
        )) {
            $foreground = if ($Theme.SuccessColor) { $Theme.SuccessColor } else { $Theme.Foreground }
        }
        elseif ($token.TokenFlags.HasFlag([System.Management.Automation.Language.TokenFlags]::Keyword)) {
            $foreground = if ($Theme.Accent) { $Theme.Accent } else { $Theme.Primary }
            $bold = $true
        }
        Add-TerminalStyledRun -Line $line -Text $Text.Substring($start, $end - $start) -Foreground $foreground -Bold:$bold
        $position = $end
    }
    if ($position -lt $Text.Length) {
        Add-TerminalStyledRun -Line $line -Text $Text.Substring($position)
    }
    return $line
}

function ConvertTo-KeywordStyledLine {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][string[]]$Keywords,
        [Parameter(Mandatory)][TerminalSlides.Schema.V1.ThemeDefinition]$Theme
    )

    $pattern = '(?<![\w-])(?:' + (($Keywords | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')(?![\w-])'
    $line = [TerminalStyledLine]::new()
    $position = 0
    foreach ($match in [regex]::Matches($Text, $pattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
        if ($match.Index -gt $position) {
            Add-TerminalStyledRun -Line $line -Text $Text.Substring($position, $match.Index - $position)
        }
        $keywordColor = if ($Theme.Accent) { $Theme.Accent } else { $Theme.Primary }
        Add-TerminalStyledRun -Line $line -Text $match.Value -Foreground $keywordColor -Bold
        $position = $match.Index + $match.Length
    }
    if ($position -lt $Text.Length) { Add-TerminalStyledRun -Line $line -Text $Text.Substring($position) }
    return $line
}

function Get-SyntaxHighlight {
    [CmdletBinding()]
    param(
        [AllowNull()][string]$Code,
        [string]$Language = 'text',
        [TerminalSlides.Schema.V1.ThemeDefinition]$Theme
    )

    $value = $Code ?? ''
    $lines = Split-TerminalLogicalRows -Text $value
    if (-not $Theme) { return ,$lines }
    if ($Language -ieq 'powershell') {
        $styledSource = ConvertTo-PowerShellStyledLine -Text $value -Theme $Theme
        return (Split-TerminalStyledLine -Line $styledSource)
    }
    $result = foreach ($line in $lines) {
        if ($Language -iin @('json', 'yaml', 'text')) {
            New-TerminalStyledLine -Text $line
        }
        else {
            ConvertTo-KeywordStyledLine -Text $line -Keywords @('function','class','return','if','else','for','while') -Theme $Theme
        }
    }
    return @($result)
}
