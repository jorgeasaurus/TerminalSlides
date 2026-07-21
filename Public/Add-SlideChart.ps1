function Add-SlideChart {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Data,
        [ValidateSet('HorizontalBar','Bar','Line','Sparkline','Gauge')][string]$ChartType = 'HorizontalBar',
        [string]$Region = 'Content',
        [int]$RevealStep = 0,
        [string]$Title
    )
    Add-CurrentSlideElement -Element (New-InternalSlideElement -Type Chart -Content $Data -Region $Region -RevealStep $RevealStep -Properties @{ ChartType = $ChartType; Title = $Title })
}
