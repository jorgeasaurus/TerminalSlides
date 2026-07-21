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
        [int]$Width = 0,
        [int]$Height = 0,
        [string]$DefaultTransition = 'None',
        [string]$DefaultLayout = 'TitleAndContent',
        [hashtable]$Metadata = @{}
    )

    try {
        $null = Get-ResolvedTheme -Name $Theme
        $presentation = [TerminalPresentation]::new()
        $presentation.Title = $Title
        $presentation.Subtitle = $Subtitle
        $presentation.Author = $Author
        $presentation.Description = $Description
        $presentation.Theme = $Theme
        $presentation.Width = $Width
        $presentation.Height = $Height
        $presentation.DefaultTransition = $DefaultTransition
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
