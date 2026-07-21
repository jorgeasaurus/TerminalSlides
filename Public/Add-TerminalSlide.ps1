function Add-TerminalSlide {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [TerminalPresentation]$Presentation,
        [Parameter(Mandatory)]
        [string]$Title,
        [scriptblock]$Content,
        [string]$Layout,
        [string]$Transition,
        [string]$Background,
        [hashtable]$Metadata = @{},
        [switch]$Hidden,
        [switch]$SafeMode
    )

    process {
        try {
            $slide = [Slide]::new()
            $slide.Title = $Title
            $slide.Layout = if ($Layout) { $Layout } else { $Presentation.DefaultLayout }
            $slide.Transition = if ($Transition) { $Transition } else { $Presentation.DefaultTransition }
            $slide.Background = $Background
            $slide.Hidden = $Hidden.IsPresent
            $slide.Metadata.Custom = $Metadata
            Set-TerminalSlidesStateValue -Name CurrentSlideElements -Value ([System.Collections.Generic.List[SlideElement]]::new())
            Set-TerminalSlidesStateValue -Name CurrentSlideContext -Value @{ Notes = $null; MaxRevealStep = 0 }
            try {
                $contentResults = @()
                if ($Content) {
                    $contentResults = @(Invoke-SafeScriptBlock -ScriptBlock $Content -SafeMode:$SafeMode)
                }
                foreach ($item in $contentResults) {
                    if ($item -is [SlideElement]) {
                        $slide.Elements.Add($item)
                        if ($item.RevealStep -gt $slide.MaxRevealStep) { $slide.MaxRevealStep = $item.RevealStep }
                    }
                    elseif ($item -and $item.PSObject.Properties.Name -contains '__TerminalSlidesNote') {
                        $slide.Notes = [string]$item.Text
                    }
                }
                # Collect elements that were queued via Add-Slide* helpers during the Content scriptblock.
                # These helpers write to $script:TerminalSlidesState rather than returning values,
                # so they are captured separately from the scriptblock return values above.
                foreach ($element in (Get-TerminalSlidesStateValue -Name CurrentSlideElements)) { $slide.Elements.Add($element) }
                $context = Get-TerminalSlidesStateValue -Name CurrentSlideContext
                if ($context.Notes) { $slide.Notes = $context.Notes }
                $slide.MaxRevealStep = [int][Math]::Max($slide.MaxRevealStep, $context.MaxRevealStep)
                $Presentation.Slides.Add($slide)
                Update-SlideIndices -Presentation $Presentation
                $Presentation
            }
            finally {
                Set-TerminalSlidesStateValue -Name CurrentSlideElements -Value $null
                Set-TerminalSlidesStateValue -Name CurrentSlideContext -Value $null
            }
        }
        catch {
            throw
        }
    }
}
