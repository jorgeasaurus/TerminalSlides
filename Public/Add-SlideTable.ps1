function Add-SlideTable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Data,
        [string]$Region = 'Content',
        [int]$RevealStep = 0,
        [switch]$Border
    )
    $payload = [TerminalSlides.Schema.V1.TablePayload]::new((ConvertTo-TerminalDataRows $Data))
    Add-CurrentSlideElement -Element (New-InternalSlideElement -Kind Table -Payload $payload -Region $Region -RevealStep $RevealStep -Border:$Border)
}
