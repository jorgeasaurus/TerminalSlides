function Test-TerminalPresentation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][TerminalSlides.Schema.V1.TerminalPresentation]$Presentation,
        [string[]]$Viewport = @('80x24', '120x35', '160x45')
    )

    $view = New-TerminalPresentationView -Presentation $Presentation
    $results = foreach ($viewportSize in $Viewport) {
        if ($viewportSize -notmatch '^(\d+)x(\d+)$') {
            Write-Warning "Viewport '$viewportSize' is invalid."
            continue
        }
        $capability = [TerminalSlides.Schema.V1.TerminalCapability]::new()
        $capability.Width = [int]$matches[1]
        $capability.Height = [int]$matches[2]
        $capability.AnsiSupport = $true
        $capability.Interactive = $false

        for ($index = 0; $index -lt $view.Slides.Count; $index++) {
            $plan = Get-TerminalSlideLayoutPlan -Presentation $view -SlideIndex $index -Capability $capability
            [pscustomobject]@{
                Viewport = $viewportSize
                Slide = $index + 1
                Fits = ($plan.OverflowLines -eq 0)
                OverflowLines = $plan.OverflowLines
            }
        }
    }
    foreach ($item in $results | Where-Object { -not $_.Fits }) {
        Write-Warning "Slide $($item.Slide) exceeds viewport $($item.Viewport)."
    }
    return $results
}
