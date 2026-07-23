function Read-TerminalPresentationKey {
    $script:NativePresentationKeyReader.Invoke($true)
}

function Show-TerminalPresentation {
    [CmdletBinding(DefaultParameterSetName='Presentation')]
    param(
        [Parameter(Mandatory, ParameterSetName='Presentation')][TerminalSlides.Schema.V1.TerminalPresentation]$Presentation,
        [Parameter(Mandatory, ParameterSetName='Path')][string]$Path,
        [ValidateSet('Blocks', 'Sixel')][string]$ImageRenderer = 'Blocks'
    )

    if ($PSCmdlet.ParameterSetName -eq 'Path') {
        $Presentation = Import-TerminalPresentation -Path $Path
    }
    if ($Presentation) {
        $Presentation = New-TerminalPresentationView -Presentation $Presentation
    }
    if (-not $Presentation -or -not $Presentation.Slides.Count) {
        Write-Error 'Presentation contains no slides.'
        return
    }

    $capability = Get-TerminalPresentationCapability
    if (-not $capability.Interactive -or $capability.IsRedirected -or -not $capability.AnsiSupport) {
        for ($i = 0; $i -lt $Presentation.Slides.Count; $i++) {
            $maximumRevealStep = Get-TerminalSlideMaximumRevealStep -Slide $Presentation.Slides[$i]
            $text = Render-TerminalPresentationToString -Presentation $Presentation -SlideIndex $i -RevealStep $maximumRevealStep -PlainText -Capability $capability
            Write-Output $text
            if ($i -lt $Presentation.Slides.Count - 1) { Write-Output ("`n" + ('-' * 40) + "`n") }
        }
        return
    }

    $session = New-TerminalPresentationSession
    $startTime = [datetime]::UtcNow
    $escAltOn = "`e[?1049h"
    $escAltOff = "`e[?1049l"
    $hideCursor = "`e[?25l"
    $showCursor = "`e[?25h"
    $imageWarnings = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

    try {
        if ($capability.AlternateBuffer) { Write-Host -NoNewline ($escAltOn + $hideCursor) }
        else { Write-Host -NoNewline $hideCursor }
        do {
            $elapsed = [datetime]::UtcNow - $startTime
            $rendered = Render-TerminalPresentationToString -Presentation $Presentation -SlideIndex $session.SlideIndex -RevealStep $session.RevealStep -ShowNotes:$session.ShowNotes -DisplayMode $session.DisplayMode -Elapsed $elapsed -ShowTimer:$session.ShowTimer -Capability $capability
            Write-Host -NoNewline $rendered
            if ($ImageRenderer -eq 'Sixel') {
                $overlayWarnings = @()
                $imageOverlay = Get-TerminalNativeImageOverlay -Presentation $Presentation `
                    -SlideIndex $session.SlideIndex -RevealStep $session.RevealStep `
                    -DisplayMode $session.DisplayMode -Capability $capability `
                    -WarningAction SilentlyContinue -WarningVariable overlayWarnings
                foreach ($warning in $overlayWarnings) {
                    [void]$imageWarnings.Add([string]$warning.Message)
                }
                if ($imageOverlay) { Write-Host -NoNewline $imageOverlay }
            }
            $key = Read-TerminalPresentationKey
            $action = ConvertTo-TerminalPresentationAction -Key $key
            $session = Invoke-TerminalPresentationAction -Session $session -Action $action -Presentation $Presentation
        } while ($session.IsRunning)
    }
    finally {
        Write-Host -NoNewline (Get-AnsiReset)
        if ($capability.AlternateBuffer) { Write-Host -NoNewline ($showCursor + $escAltOff) }
        else { Write-Host -NoNewline $showCursor }
        foreach ($warning in $imageWarnings) { Write-Warning $warning }
    }
}
