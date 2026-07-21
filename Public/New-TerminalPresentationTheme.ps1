function New-TerminalPresentationTheme {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Background,
        [Parameter(Mandatory)][string]$Foreground,
        [Parameter(Mandatory)][string]$Primary,
        [string]$Accent = $Primary,
        [string]$Muted = $Foreground,
        [string]$Heading = $Primary,
        [string]$Border = $Primary,
        [string]$CodeTheme = 'Default',
        [string]$BulletSymbol = '•',
        [ValidateSet('unicode','ascii','double','rounded','single')][string]$BoxDrawingStyle = 'unicode',
        [ValidateSet('plain','bold','banner')][string]$HeadingStyle = 'bold',
        [string[]]$ChartPalette = @(),
        [string]$ErrorColor = '#FF0000',
        [string]$WarningColor = '#FFFF00',
        [string]$SuccessColor = '#00FF00',
        [hashtable]$Metadata = @{}
    )
    foreach ($color in @($Background,$Foreground,$Primary,$Accent,$Muted,$Heading,$Border,$ErrorColor,$WarningColor,$SuccessColor) + $ChartPalette) {
        if ($color) { $null = Convert-HexToRgb -Hex $color }
    }
    $theme = [ThemeDefinition]::new()
    $theme.Name = $Name
    $theme.Background = $Background
    $theme.Foreground = $Foreground
    $theme.Primary = $Primary
    $theme.Accent = $Accent
    $theme.Muted = $Muted
    $theme.Heading = $Heading
    $theme.Border = $Border
    $theme.CodeTheme = $CodeTheme
    $theme.BulletSymbol = $BulletSymbol
    $theme.BoxDrawingStyle = $BoxDrawingStyle
    $theme.HeadingStyle = $HeadingStyle
    $theme.ChartPalette = if ($ChartPalette.Count) { $ChartPalette } else { @($Primary,$Accent,$Foreground) }
    $theme.ErrorColor = $ErrorColor
    $theme.WarningColor = $WarningColor
    $theme.SuccessColor = $SuccessColor
    $theme.Metadata = $Metadata
    if (-not $script:Themes) { $script:Themes = @{} }
    $script:Themes[$theme.Name] = $theme
    return $theme
}
