function Copy-TerminalSlide {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)][TerminalSlides.Schema.V1.TerminalPresentation]$Presentation,
        [Parameter(Mandatory)][int]$Index,
        [int]$DestinationIndex = -1
    )
    process {
        if ($Index -lt 1 -or $Index -gt $Presentation.Slides.Count) { throw 'Slide index out of range.' }
        $clone = Copy-TerminalSlideModel -Slide $Presentation.Slides[$Index - 1]
        $clone.Id = [guid]::NewGuid().ToString()
        foreach ($element in $clone.Elements) {
            $element.Id = [guid]::NewGuid().ToString()
        }
        if ($DestinationIndex -lt 1 -or $DestinationIndex -gt $Presentation.Slides.Count + 1) {
            $Presentation.Slides.Add($clone)
        }
        else {
            $Presentation.Slides.Insert($DestinationIndex - 1, $clone)
        }
        Update-SlideIndices -Presentation $Presentation
        $Presentation
    }
}
