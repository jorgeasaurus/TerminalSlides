function Add-SlideBox {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Text,
        [string]$Region = 'Content',
        [int]$RevealStep = 0
    )
    Add-CurrentSlideElement -Element (New-InternalSlideElement -Kind Box -Payload ([TerminalSlides.Schema.V1.TextPayload]::new($Text)) -Region $Region -RevealStep $RevealStep)
}
