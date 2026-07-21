function Add-SlideBox {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Text,
        [string]$Region = 'Content',
        [int]$RevealStep = 0
    )
    Add-CurrentSlideElement -Element (New-InternalSlideElement -Type Box -Content $Text -Region $Region -RevealStep $RevealStep)
}
