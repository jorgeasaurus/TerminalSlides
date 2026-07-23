function Remove-TerminalSlide {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)][TerminalSlides.Schema.V1.TerminalPresentation]$Presentation,
        [Parameter(Mandatory)][int]$Index
    )
    process {
        if ($Index -lt 1 -or $Index -gt $Presentation.Slides.Count) { throw 'Slide index out of range.' }
        $Presentation.Slides.RemoveAt($Index - 1)
        Update-SlideIndices -Presentation $Presentation
        $Presentation
    }
}
