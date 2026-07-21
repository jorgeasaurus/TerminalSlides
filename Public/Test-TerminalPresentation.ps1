function Test-TerminalPresentation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][TerminalPresentation]$Presentation,
        [string[]]$Viewport = @('80x24', '120x35', '160x45')
    )

    $results = foreach ($vp in $Viewport) {
        if ($vp -notmatch '^(\d+)x(\d+)$') {
            Write-Warning "Viewport '$vp' is invalid."
            continue
        }
        $capability = [TerminalCapability]::new()
        $capability.Width = [int]$matches[1]
        $capability.Height = [int]$matches[2]
        $capability.AnsiSupport = $true
        $capability.Interactive = $false
        for ($i = 0; $i -lt $Presentation.Slides.Count; $i++) {
            $text = Render-TerminalPresentationToString -Presentation $Presentation -SlideIndex $i -RevealStep $Presentation.Slides[$i].MaxRevealStep -PlainText -Capability $capability
            $lineOverflow = @($text -split "`n" | Where-Object { $_.Length -gt $capability.Width })
            [pscustomobject]@{
                Viewport = $vp
                Slide = $i + 1
                Fits = ($lineOverflow.Count -eq 0)
                OverflowLines = $lineOverflow.Count
            }
        }
    }
    foreach ($item in $results | Where-Object { -not $_.Fits }) {
        Write-Warning "Slide $($item.Slide) exceeds viewport $($item.Viewport)."
    }
    return $results
}
