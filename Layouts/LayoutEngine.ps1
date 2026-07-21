function Get-LayoutRegions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Layout,
        [Parameter(Mandatory)][int]$Width,
        [Parameter(Mandatory)][int]$Height
    )
    $w = [Math]::Max(20, $Width)
    $h = [Math]::Max(10, $Height)
    switch ($Layout) {
        'Title' {
            return @{
                Title = @{ X = 2; Y = [Math]::Max(1, [Math]::Floor($h / 3)); Width = $w - 4; Height = 4 }
                Content = @{ X = 2; Y = [Math]::Floor($h / 2); Width = $w - 4; Height = [Math]::Max(2, $h / 3) }
            }
        }
        'SectionHeader' {
            return @{
                Title = @{ X = 2; Y = [Math]::Floor($h / 2) - 1; Width = $w - 4; Height = 3 }
                Content = @{ X = 2; Y = [Math]::Floor($h / 2) + 2; Width = $w - 4; Height = 4 }
            }
        }
        'TwoColumn' {
            $contentY = 4
            $contentHeight = $h - 7
            $columnWidth = [Math]::Floor(($w - 6) / 2)
            return @{
                Title = @{ X = 2; Y = 1; Width = $w - 4; Height = 2 }
                Left = @{ X = 2; Y = $contentY; Width = $columnWidth; Height = $contentHeight }
                Right = @{ X = 4 + $columnWidth; Y = $contentY; Width = $columnWidth; Height = $contentHeight }
                Content = @{ X = 2; Y = $contentY; Width = $w - 4; Height = $contentHeight }
            }
        }
        'ThreeColumn' {
            $contentY = 4
            $contentHeight = $h - 7
            $columnWidth = [Math]::Floor(($w - 8) / 3)
            return @{
                Title = @{ X = 2; Y = 1; Width = $w - 4; Height = 2 }
                Left = @{ X = 2; Y = $contentY; Width = $columnWidth; Height = $contentHeight }
                Center = @{ X = 4 + $columnWidth; Y = $contentY; Width = $columnWidth; Height = $contentHeight }
                Right = @{ X = 6 + ($columnWidth * 2); Y = $contentY; Width = $columnWidth; Height = $contentHeight }
                Content = @{ X = 2; Y = $contentY; Width = $w - 4; Height = $contentHeight }
            }
        }
        'CodeFocus' {
            return @{
                Title = @{ X = 2; Y = 1; Width = $w - 4; Height = 2 }
                Code = @{ X = 2; Y = 4; Width = $w - 4; Height = $h - 7 }
                Content = @{ X = 2; Y = 4; Width = $w - 4; Height = $h - 7 }
            }
        }
        'ImageFocus' {
            return @{
                Title = @{ X = 2; Y = 1; Width = $w - 4; Height = 2 }
                Image = @{ X = 2; Y = 4; Width = $w - 4; Height = $h - 7 }
                Content = @{ X = 2; Y = 4; Width = $w - 4; Height = $h - 7 }
            }
        }
        'Quote' {
            return @{
                Title = @{ X = 2; Y = 1; Width = $w - 4; Height = 2 }
                Quote = @{ X = 6; Y = [Math]::Max(4, [Math]::Floor($h / 3)); Width = $w - 12; Height = [Math]::Max(4, [Math]::Floor($h / 3)) }
                Content = @{ X = 6; Y = [Math]::Max(4, [Math]::Floor($h / 3)); Width = $w - 12; Height = [Math]::Max(4, [Math]::Floor($h / 3)) }
            }
        }
        'Blank' {
            return @{ Content = @{ X = 1; Y = 1; Width = $w - 2; Height = $h - 3 } }
        }
        default {
            return @{
                Title = @{ X = 2; Y = 1; Width = $w - 4; Height = 2 }
                Content = @{ X = 2; Y = 4; Width = $w - 4; Height = $h - 7 }
            }
        }
    }
}
