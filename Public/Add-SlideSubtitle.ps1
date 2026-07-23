function Add-SlideSubtitle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Subtitle,
        [string]$Region = 'Content',
        [ValidateSet('Left','Center','Right')][string]$Alignment = 'Center',
        [int]$RevealStep = 0,
        [string]$ForegroundColor
    )
    Add-CurrentSlideElement -Element (New-InternalSlideElement -Kind Subtitle -Payload ([TerminalSlides.Schema.V1.TextPayload]::new($Subtitle)) -Region $Region -Alignment $Alignment -RevealStep $RevealStep -ForegroundColor $ForegroundColor)
}
