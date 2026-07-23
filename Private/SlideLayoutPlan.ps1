function Assert-TerminalElementPadding {
    param(
        [Parameter(Mandatory)][TerminalSlides.Schema.V1.SlideElement]$Element,
        [Parameter(Mandatory)][hashtable]$Region,
        [Parameter(Mandatory)][string]$RegionName
    )

    $borderWidth = if ($Element.Border) { 2 } else { 0 }
    $maximumPadding = [Math]::Floor(($Region.Width - $borderWidth - 1) / 2)
    if ($Element.Padding -lt 0 -or $Element.Padding -gt $maximumPadding) {
        throw "Element padding '$($Element.Padding)' is invalid for region '$RegionName' width '$($Region.Width)'. Padding must be between 0 and $maximumPadding to leave content space after two-sided padding and border cells."
    }
}

function Get-TerminalSlideLayoutPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][TerminalSlides.Schema.V1.TerminalPresentation]$Presentation,
        [Parameter(Mandatory)][int]$SlideIndex,
        [int]$RevealStep = [int]::MaxValue,
        [Parameter(Mandatory)][TerminalSlides.Schema.V1.TerminalCapability]$Capability
    )

    $theme = Resolve-TerminalPresentationTheme -Presentation $Presentation
    $dimensions = Get-SlideRenderDimensions -Presentation $Presentation -Capability $Capability
    $slide = $Presentation.Slides[$SlideIndex]
    [void](Get-TerminalSlideMaximumRevealStep -Slide $slide)
    $regions = Get-LayoutRegions -Layout $slide.Layout -Width $dimensions.Width -Height $dimensions.Height
    $elementRegionNames = @(Get-TerminalElementRegionNames -Regions $regions)
    $resolvedElementRegions = @(
        foreach ($element in $slide.Elements) {
            if ([string]::IsNullOrWhiteSpace($element.Region)) { 'Content' } else { $element.Region }
        }
    )
    foreach ($regionName in $resolvedElementRegions) {
        if ($regionName -notin $elementRegionNames) {
            throw "Region '$regionName' is not available in layout '$($slide.Layout)'. Supported element regions: $($elementRegionNames -join ', ')."
        }
    }
    Assert-TerminalElementRegionCombination -Layout $slide.Layout -Regions $regions -RegionNames $resolvedElementRegions
    for ($elementIndex = 0; $elementIndex -lt $slide.Elements.Count; $elementIndex++) {
        $regionName = $resolvedElementRegions[$elementIndex]
        Assert-TerminalElementPadding -Element $slide.Elements[$elementIndex] -Region $regions[$regionName] -RegionName $regionName
    }
    $revealedElements = @($slide.Elements | Where-Object { $_.RevealStep -le $RevealStep })
    $placements = [System.Collections.Generic.List[object]]::new()
    $overflowLines = 0

    if ($regions.ContainsKey('Title') -and $slide.Title) {
        $title = New-InternalSlideElement -Kind Title -Payload ([TerminalSlides.Schema.V1.TextPayload]::new($slide.Title)) -ForegroundColor $theme.Heading
        $rawTitleLines = ConvertTo-ElementLines -Element $title -Theme $theme -Width $regions.Title.Width -Capability $Capability -StartColumn $regions.Title.X
        $titleLines = ConvertTo-TerminalPreparedLines -Lines $rawTitleLines -StartColumn $regions.Title.X -MaxWidth $regions.Title.Width -Alignment $title.Alignment
        $placements.Add([pscustomobject]@{
            Element = $title
            Lines = $titleLines
            Region = $regions.Title
            StartY = $regions.Title.Y
            Border = $false
            BorderHeight = 0
        })
        $overflowLines += @($titleLines | Where-Object { $_.Width -gt $_.AvailableWidth }).Count
        $overflowLines += [Math]::Max(0, $titleLines.Count - $regions.Title.Height)

        if ($Presentation.Subtitle -and $slide.Layout -eq 'Title') {
            $subtitle = New-InternalSlideElement -Kind Subtitle -Payload ([TerminalSlides.Schema.V1.TextPayload]::new($Presentation.Subtitle)) -ForegroundColor $theme.Muted
            $subtitleRegion = $regions.Subtitle
            $rawSubtitleLines = ConvertTo-ElementLines -Element $subtitle -Theme $theme -Width $subtitleRegion.Width -Capability $Capability -StartColumn $subtitleRegion.X
            $subtitleLines = ConvertTo-TerminalPreparedLines -Lines $rawSubtitleLines -StartColumn $subtitleRegion.X -MaxWidth $subtitleRegion.Width -Alignment $subtitle.Alignment
            $placements.Add([pscustomobject]@{
                Element = $subtitle
                Lines = $subtitleLines
                Region = $subtitleRegion
                StartY = $subtitleRegion.Y
                Border = $false
                BorderHeight = 0
            })
            $overflowLines += @($subtitleLines | Where-Object { $_.Width -gt $_.AvailableWidth }).Count
            $overflowLines += [Math]::Max(0, $subtitleLines.Count - $subtitleRegion.Height)
        }
    }

    foreach ($regionName in $elementRegionNames) {
        $region = $regions[$regionName]
        $y = $region.Y
        $elements = $revealedElements | Where-Object {
            $resolvedRegion = if ([string]::IsNullOrWhiteSpace($_.Region)) { 'Content' } else { $_.Region }
            $resolvedRegion -eq $regionName
        }

        foreach ($element in $elements) {
            if ($element.Border) {
                $contentWidth = [Math]::Max(1, $region.Width - 2 - ($element.Padding * 2))
                $remainingHeight = [Math]::Max(0, $region.Height - ($y - $region.Y))
                $contentStartColumn = $region.X + 1 + $element.Padding
                $rawLines = ConvertTo-ElementLines -Element $element -Theme $theme -Width $contentWidth -Height ([Math]::Max(1, $remainingHeight - 2)) -Capability $Capability -StartColumn $contentStartColumn
                $lines = ConvertTo-TerminalPreparedLines -Lines $rawLines -StartColumn $contentStartColumn -MaxWidth $contentWidth -Alignment $element.Alignment
                $requiredHeight = [Math]::Max(3, $lines.Count + 2)
                $visibleHeight = [Math]::Min($remainingHeight, $requiredHeight)
                if ($visibleHeight -ge 3) {
                    $innerRegion = @{ X=$region.X + 1; Y=$y + 1; Width=$region.Width - 2; Height=$visibleHeight - 2 }
                    $placements.Add([pscustomobject]@{
                        Element = $element
                        Lines = $lines
                        Region = $innerRegion
                        StartY = $y + 1
                        Border = $true
                        BorderRegion = @{ X=$region.X; Y=$y; Width=$region.Width; Height=$visibleHeight }
                        BorderHeight = $visibleHeight
                    })
                }
                $overflowLines += @($lines | Where-Object { $_.Width -gt $_.AvailableWidth }).Count
                $overflowLines += [Math]::Max(0, $requiredHeight - $remainingHeight)
                $y += $requiredHeight + 1
            }
            else {
                $contentWidth = [Math]::Max(1, $region.Width - ($element.Padding * 2))
                $remainingHeight = [Math]::Max(0, $region.Height - ($y - $region.Y))
                $contentStartColumn = $region.X + $element.Padding
                $rawLines = ConvertTo-ElementLines -Element $element -Theme $theme -Width $contentWidth -Height ([Math]::Max(1, $remainingHeight)) -Capability $Capability -StartColumn $contentStartColumn
                $lines = ConvertTo-TerminalPreparedLines -Lines $rawLines -StartColumn $contentStartColumn -MaxWidth $contentWidth -Alignment $element.Alignment
                $placements.Add([pscustomobject]@{
                    Element = $element
                    Lines = $lines
                    Region = $region
                    StartY = $y
                    Border = $false
                    BorderHeight = 0
                })
                $overflowLines += @($lines | Where-Object { $_.Width -gt $_.AvailableWidth }).Count
                $overflowLines += [Math]::Max(0, $lines.Count - $remainingHeight)
                $y += $lines.Count + 1
            }
        }
    }

    return [pscustomobject]@{
        Dimensions = $dimensions
        Theme = $theme
        Slide = $slide
        Regions = $regions
        Placements = $placements.ToArray()
        OverflowLines = $overflowLines
    }
}
