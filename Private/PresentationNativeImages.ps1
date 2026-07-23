function New-TerminalSpectreRenderOptions {
    param(
        [Parameter(Mandatory)][int]$Width,
        [Parameter(Mandatory)][int]$Height,
        [Parameter(Mandatory)][TerminalSlides.Schema.V1.TerminalCapability]$Capability
    )

    $capabilities = [TerminalSpectreCapabilities]::new()
    $capabilities.Ansi = $true
    $capabilities.Interactive = $false
    $capabilities.Unicode = $Capability.UnicodeSupport
    $capabilities.Links = $false
    $capabilities.Legacy = $false
    $capabilities.IsTerminal = $true
    $capabilities.ColorSystem = if ($Capability.TrueColorSupport) {
        [Spectre.Console.ColorSystem]::TrueColor
    }
    elseif ($Capability.Color256Support) {
        [Spectre.Console.ColorSystem]::EightBit
    }
    else {
        [Spectre.Console.ColorSystem]::NoColors
    }

    return [Spectre.Console.Rendering.RenderOptions]::new(
        $capabilities,
        [Spectre.Console.Size]::new([Math]::Max(1, $Width), [Math]::Max(1, $Height))
    )
}

function Get-TerminalNativeImageOverlay {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][TerminalSlides.Schema.V1.TerminalPresentation]$Presentation,
        [Parameter(Mandatory)][int]$SlideIndex,
        [Parameter(Mandatory)][int]$RevealStep,
        [Parameter(Mandatory)][ValidateSet('Slide', 'Overview', 'Help', 'Blank')][string]$DisplayMode,
        [Parameter(Mandatory)][TerminalSlides.Schema.V1.TerminalCapability]$Capability
    )

    if ($DisplayMode -ne 'Slide') { return }

    $plan = Get-TerminalSlideLayoutPlan -Presentation $Presentation -SlideIndex $SlideIndex `
        -RevealStep $RevealStep -Capability $Capability
    $overlays = [System.Text.StringBuilder]::new()

    foreach ($placement in $plan.Placements) {
        $element = $placement.Element
        if ($element.Kind -ne [TerminalSlides.Schema.V1.ElementKind]::Image) { continue }

        $availableWidth = [Math]::Max(1, $placement.Region.Width - ($element.Padding * 2))
        $availableHeight = [Math]::Max(
            1,
            ($placement.Region.Y + $placement.Region.Height) - $placement.StartY
        )
        try {
            $resolvedPath = Resolve-TerminalImagePath -Element $element
            if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
                throw "Image file '$resolvedPath' was not found."
            }

            $image = Get-SpectreImage -ImagePath $resolvedPath -MaxWidth $availableWidth `
                -Format Sixel -ErrorAction Stop
            if ($image.PSObject.Properties.Name -contains 'MaxWidth') {
                $image.MaxWidth = $availableWidth
            }
            $options = New-TerminalSpectreRenderOptions -Width $availableWidth `
                -Height $availableHeight -Capability $Capability
            $rawImage = (@($image.Render($options, $availableWidth)).Text -join '').TrimEnd("`r", "`n")
            if (-not $rawImage.Contains("`eP")) {
                throw 'The image renderer did not return a Sixel control stream.'
            }

            $row = $placement.StartY + 1
            $column = $placement.Region.X + $element.Padding + 1
            [void]$overlays.Append("`e[$row;${column}H")
            [void]$overlays.Append($rawImage)
        }
        catch {
            Write-Verbose "Sixel image renderer error: $($_.Exception.Message)"
            Write-Warning "Sixel rendering is unavailable for '$($element.Payload.Path)'; keeping the block image fallback."
        }
    }

    if ($overlays.Length -eq 0) { return }
    [void]$overlays.Append("`e[H")
    return $overlays.ToString()
}
