function Get-SyntaxHighlight {
    [CmdletBinding()]
    param(
        [AllowNull()][string]$Code,
        [string]$Language = 'text',
        [ThemeDefinition]$Theme
    )

    $code = $Code ?? ''
    $lines = $code -replace "`r", '' -split "`n", -1
    if (-not $Theme) { return ,$lines }
    $keywordColor = if ($Theme.Accent) { $Theme.Accent } else { $Theme.Primary }
    $stringColor = if ($Theme.SuccessColor) { $Theme.SuccessColor } else { $Theme.Foreground }
    $commentColor = if ($Theme.Muted) { $Theme.Muted } else { $Theme.Foreground }
    $keywords = switch ($Language.ToLowerInvariant()) {
        'powershell' { 'function','param','if','else','foreach','return','switch','class','try','catch','throw' }
        'json' { @() }
        'yaml' { @() }
        default { 'function','class','return','if','else','for','while' }
    }
    $result = foreach ($line in $lines) {
        $rendered = $line
        if ($Language -eq 'powershell') {
            $rendered = $rendered -replace '(#.*)$', "$(Get-AnsiFg $commentColor)`$1$(Get-AnsiReset)"
            $rendered = $rendered -replace "'([^']*)'", "$(Get-AnsiFg $stringColor)'`$1'$(Get-AnsiReset)"
        }
        foreach ($keyword in $keywords) {
            $rendered = [regex]::Replace($rendered, "(?<![\w-])$keyword(?![\w-])", "$(Get-AnsiBold)$(Get-AnsiFg $keywordColor)$keyword$(Get-AnsiReset)")
        }
        $rendered
    }
    return ,$result
}
