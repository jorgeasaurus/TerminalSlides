function Get-TerminalPresentationTheme {
    [CmdletBinding()]
    [OutputType([object])]
    param([string]$Name)

    if ($Name) {
        return Get-ResolvedTheme -Name $Name
    }
    return $script:Themes.Values | Sort-Object Name
}
