function Add-SlideTable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Data,
        [string]$Region = 'Content',
        [int]$RevealStep = 0,
        [switch]$Border
    )
    Add-CurrentSlideElement -Element (New-InternalSlideElement -Type Table -Content $Data -Region $Region -RevealStep $RevealStep -Border:$Border)
}
