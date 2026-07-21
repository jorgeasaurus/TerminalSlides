function Get-TerminalSlide {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)][TerminalPresentation]$Presentation,
        [int]$Index,
        [string]$Title
    )
    process {
        if ($PSBoundParameters.ContainsKey('Index')) {
            if ($Index -lt 1 -or $Index -gt $Presentation.Slides.Count) { throw 'Slide index out of range.' }
            return $Presentation.Slides[$Index - 1]
        }
        if ($PSBoundParameters.ContainsKey('Title')) {
            return $Presentation.Slides | Where-Object Title -eq $Title
        }
        return $Presentation.Slides
    }
}
