function Copy-TerminalSlide {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)][TerminalPresentation]$Presentation,
        [Parameter(Mandatory)][int]$Index,
        [int]$DestinationIndex = -1
    )
    process {
        if ($Index -lt 1 -or $Index -gt $Presentation.Slides.Count) { throw 'Slide index out of range.' }
        $data = ConvertTo-PresentationData -Presentation (New-TerminalPresentation -Title 'copy')
        $slideHash = (ConvertTo-PresentationData -Presentation $Presentation).Slides[$Index - 1]
        $clone = (New-PresentationFromData -Data @{ Title = 'copy'; Slides = @($slideHash); Metadata = @{ Custom = @{} } }).Slides[0]
        $clone.Id = [guid]::NewGuid().ToString()
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
