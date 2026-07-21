function Add-SlideTitle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Title,
        [string]$Region = 'Content',
        [ValidateSet('Left','Center','Right')][string]$Alignment = 'Center',
        [int]$RevealStep = 0,
        [string]$ForegroundColor
    )
    Add-CurrentSlideElement -Element (New-InternalSlideElement -Type Title -Content $Title -Region $Region -Alignment $Alignment -RevealStep $RevealStep -ForegroundColor $ForegroundColor)
}
