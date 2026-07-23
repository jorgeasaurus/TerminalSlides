function New-TerminalPresentation {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Title,
        [string]$Subtitle,
        [string]$Author,
        [string]$Description,
        [string]$Theme = 'Midnight',
        [ValidateScript({ $_ -eq 0 -or $_ -ge 20 })][int]$Width = 0,
        [ValidateScript({ $_ -eq 0 -or $_ -ge 10 })][int]$Height = 0,
        [string]$DefaultLayout = 'TitleAndContent',
        [hashtable]$Metadata = @{}
    )

    try {
        $resolvedTheme = Get-ResolvedTheme -Name $Theme
        Assert-TerminalSlideLayout -Layout $DefaultLayout
        $presentation = [TerminalSlides.Schema.V1.TerminalPresentation]::new()
        $presentation.Title = $Title
        $presentation.Subtitle = $Subtitle
        $presentation.Author = $Author
        $presentation.Description = $Description
        $presentation.Theme = $Theme
        $presentation.EmbeddedTheme = Copy-TerminalThemeDefinition $resolvedTheme
        $presentation.Width = $Width
        $presentation.Height = $Height
        $presentation.DefaultLayout = $DefaultLayout
        $presentation.Metadata.Title = $Title
        $presentation.Metadata.Subtitle = $Subtitle
        $presentation.Metadata.Author = $Author
        $presentation.Metadata.Description = $Description
        $presentation.Metadata.Custom = $Metadata
        return $presentation
    }
    catch {
        throw
    }
}
