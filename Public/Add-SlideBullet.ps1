function Add-SlideBullet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Text,
        [string]$Region = 'Content',
        [int]$RevealStep = 0,
        [string]$ForegroundColor
    )
    Add-CurrentSlideElement -Element (New-InternalSlideElement -Kind Bullet -Payload ([TerminalSlides.Schema.V1.TextPayload]::new($Text)) -Region $Region -RevealStep $RevealStep -ForegroundColor $ForegroundColor)
}
