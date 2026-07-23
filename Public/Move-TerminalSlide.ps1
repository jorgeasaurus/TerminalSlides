function Move-TerminalSlide {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)][TerminalSlides.Schema.V1.TerminalPresentation]$Presentation,
        [Parameter(Mandatory)][int]$Index,
        [Parameter(Mandatory)][int]$DestinationIndex
    )
    process {
        if ($Index -lt 1 -or $Index -gt $Presentation.Slides.Count) { throw 'Slide index out of range.' }
        if ($DestinationIndex -lt 1 -or $DestinationIndex -gt $Presentation.Slides.Count) { throw 'Destination index out of range.' }
        $slide = $Presentation.Slides[$Index - 1]
        $Presentation.Slides.RemoveAt($Index - 1)
        $Presentation.Slides.Insert($DestinationIndex - 1, $slide)
        Update-SlideIndices -Presentation $Presentation
        $Presentation
    }
}
