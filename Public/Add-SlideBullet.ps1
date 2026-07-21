function Add-SlideBullet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Text,
        [string]$Region = 'Content',
        [int]$RevealStep = 0,
        [string]$ForegroundColor,
        [hashtable]$Style = @{}
    )
    Add-CurrentSlideElement -Element (New-InternalSlideElement -Type Bullet -Content $Text -Region $Region -RevealStep $RevealStep -ForegroundColor $ForegroundColor -Style $Style)
}
