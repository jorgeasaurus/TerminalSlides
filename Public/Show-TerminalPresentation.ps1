function Show-TerminalPresentation {
    [CmdletBinding(DefaultParameterSetName='Presentation')]
    param(
        [Parameter(Mandatory, ParameterSetName='Presentation')][TerminalPresentation]$Presentation,
        [Parameter(Mandatory, ParameterSetName='Path')][string]$Path,
        [switch]$SafeMode
    )

    if ($PSCmdlet.ParameterSetName -eq 'Path') {
        $Presentation = Import-TerminalPresentation -Path $Path
    }
    if (-not $Presentation -or -not $Presentation.Slides.Count) {
        Write-Error 'Presentation contains no slides.'
        return
    }

    $capability = Get-TerminalPresentationCapability
    if (-not $capability.Interactive -or $capability.IsRedirected) {
        for ($i = 0; $i -lt $Presentation.Slides.Count; $i++) {
            $text = Render-TerminalPresentationToString -Presentation $Presentation -SlideIndex $i -RevealStep $Presentation.Slides[$i].MaxRevealStep -PlainText -Capability $capability
            Write-Output $text
            if ($i -lt $Presentation.Slides.Count - 1) { Write-Output ("`n" + ('-' * 40) + "`n") }
        }
        return
    }

    $slideIndex = 0
    $revealStep = 0
    $showNotes = $false
    $overviewMode = $false
    $showHelp = $false
    $blank = $false
    $showTimer = $false
    $startTime = [datetime]::UtcNow
    $escAltOn = "`e[?1049h"
    $escAltOff = "`e[?1049l"
    $hideCursor = "`e[?25l"
    $showCursor = "`e[?25h"

    try {
        Write-Host -NoNewline ($escAltOn + $hideCursor)
        do {
            $elapsed = [datetime]::UtcNow - $startTime
            $rendered = Render-TerminalPresentationToString -Presentation $Presentation -SlideIndex $slideIndex -RevealStep $revealStep -ShowNotes:$showNotes -OverviewMode:$overviewMode -ShowHelp:$showHelp -Blank:$blank -Elapsed $elapsed -ShowTimer:$showTimer -Capability $capability
            Write-Host -NoNewline $rendered
            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                'RightArrow' { if ($revealStep -lt $Presentation.Slides[$slideIndex].MaxRevealStep) { $revealStep++ } elseif ($slideIndex -lt $Presentation.Slides.Count - 1) { $slideIndex++; $revealStep = 0 } }
                'Spacebar' { if ($revealStep -lt $Presentation.Slides[$slideIndex].MaxRevealStep) { $revealStep++ } elseif ($slideIndex -lt $Presentation.Slides.Count - 1) { $slideIndex++; $revealStep = 0 } }
                'N' { if ($revealStep -lt $Presentation.Slides[$slideIndex].MaxRevealStep) { $revealStep++ } elseif ($slideIndex -lt $Presentation.Slides.Count - 1) { $slideIndex++; $revealStep = 0 } }
                'PageDown' { if ($slideIndex -lt $Presentation.Slides.Count - 1) { $slideIndex++; $revealStep = 0 } }
                'LeftArrow' { if ($revealStep -gt 0) { $revealStep-- } elseif ($slideIndex -gt 0) { $slideIndex--; $revealStep = $Presentation.Slides[$slideIndex].MaxRevealStep } }
                'Backspace' { if ($revealStep -gt 0) { $revealStep-- } elseif ($slideIndex -gt 0) { $slideIndex--; $revealStep = $Presentation.Slides[$slideIndex].MaxRevealStep } }
                'P' { if ($revealStep -gt 0) { $revealStep-- } elseif ($slideIndex -gt 0) { $slideIndex--; $revealStep = $Presentation.Slides[$slideIndex].MaxRevealStep } }
                'PageUp' { if ($slideIndex -gt 0) { $slideIndex--; $revealStep = $Presentation.Slides[$slideIndex].MaxRevealStep } }
                'Home' { $slideIndex = 0; $revealStep = 0 }
                'End' { $slideIndex = $Presentation.Slides.Count - 1; $revealStep = $Presentation.Slides[$slideIndex].MaxRevealStep }
                'S' { $showNotes = -not $showNotes }
                'O' { $overviewMode = -not $overviewMode }
                'B' { $blank = -not $blank }
                'T' { $showTimer = -not $showTimer }
                'H' { $showHelp = -not $showHelp }
                'Escape' { break }
                default {
                    if ($key.KeyChar -in @('q','Q','?')) {
                        if ($key.KeyChar -eq '?') { $showHelp = -not $showHelp } else { break }
                    }
                }
            }
        } while ($true)
    }
    finally {
        Write-Host -NoNewline (Get-AnsiReset)
        Write-Host -NoNewline ($showCursor + $escAltOff)
    }
}
