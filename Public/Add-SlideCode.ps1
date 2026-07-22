function Add-SlideCode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Code,
        [string]$Language = 'text',
        [string]$Region = 'Content',
        [int]$RevealStep = 0,
        [switch]$Border
    )
    $payload = [TerminalSlides.Schema.V1.CodePayload]::new($Code, $Language)
    Add-CurrentSlideElement -Element (New-InternalSlideElement -Kind Code -Payload $payload -Region $Region -RevealStep $RevealStep -Border:$Border -Padding 1)
}
