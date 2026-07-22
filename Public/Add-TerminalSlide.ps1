function Add-TerminalSlide {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [TerminalSlides.Schema.V1.TerminalPresentation]$Presentation,
        [Parameter(Mandatory)]
        [string]$Title,
        [scriptblock]$Content,
        [string]$Layout,
        [string]$Background,
        [hashtable]$Metadata = @{},
        [switch]$Hidden,
        [switch]$SafeMode
    )

    process {
        $resolvedLayout = if ($Layout) { $Layout } else { $Presentation.DefaultLayout }
        Assert-TerminalSlideLayout -Layout $resolvedLayout
        $slide = [TerminalSlides.Schema.V1.Slide]::new()
        $slide.Title = $Title
        $slide.Layout = $resolvedLayout
        $slide.Background = $Background
        $slide.Hidden = $Hidden.IsPresent
        $slide.Metadata.Custom = $Metadata
        $context = Push-TerminalSlidesBuildContext -Kind Slide
        try {
            $contentResults = if ($Content) {
                @(Invoke-SafeScriptBlock -ScriptBlock $Content -SafeMode:$SafeMode)
            }
            else { @() }

            foreach ($item in $contentResults) {
                if ($item -is [TerminalSlides.Schema.V1.SlideElement] -and
                    -not $context.Elements.Contains($item)) {
                    Add-CurrentSlideElement -Element $item
                }
                elseif ($item -and $item.PSObject.Properties.Name -contains '__TerminalSlidesNote') {
                    $context.Notes = [string]$item.Text
                }
            }
            foreach ($element in $context.Elements) { $slide.Elements.Add($element) }
            $slide.Notes = $context.Notes
            $slide.MaxRevealStep = Get-TerminalSlideMaximumRevealStep -Slide $slide
            $Presentation.Slides.Add($slide)
            Update-SlideIndices -Presentation $Presentation
            $Presentation
        }
        finally {
            Pop-TerminalSlidesBuildContext -Context $context
        }
    }
}
