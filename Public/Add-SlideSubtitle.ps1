function Add-SlideSubtitle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Subtitle,
        [string]$Region = 'Content',
        [ValidateSet('Left','Center','Right')][string]$Alignment = 'Center',
        [int]$RevealStep = 0,
        [string]$ForegroundColor
    )
    Add-CurrentSlideElement -Element (New-InternalSlideElement -Type Subtitle -Content $Subtitle -Region $Region -Alignment $Alignment -RevealStep $RevealStep -ForegroundColor $ForegroundColor)
}
