function Set-TerminalSlide {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)][TerminalSlides.Schema.V1.TerminalPresentation]$Presentation,
        [Parameter(Mandatory)][int]$Index,
        [string]$Title,
        [string]$Layout,
        [string]$Notes,
        [string]$Background,
        [switch]$Hidden
    )
    process {
        if ($Index -lt 1 -or $Index -gt $Presentation.Slides.Count) { throw 'Slide index out of range.' }
        $slide = $Presentation.Slides[$Index - 1]
        if ($PSBoundParameters.ContainsKey('Title')) { $slide.Title = $Title }
        if ($PSBoundParameters.ContainsKey('Layout')) {
            Assert-TerminalSlideLayout -Layout $Layout
            $slide.Layout = $Layout
        }
        if ($PSBoundParameters.ContainsKey('Notes')) { $slide.Notes = $Notes }
        if ($PSBoundParameters.ContainsKey('Background')) { $slide.Background = $Background }
        if ($PSBoundParameters.ContainsKey('Hidden')) { $slide.Hidden = $Hidden.IsPresent }
        Update-SlideIndices -Presentation $Presentation
        $Presentation
    }
}
