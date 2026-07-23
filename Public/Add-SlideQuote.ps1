function Add-SlideQuote {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Text,
        [string]$Attribution,
        [string]$Region = 'Content',
        [int]$RevealStep = 0
    )
    $payload = [TerminalSlides.Schema.V1.QuotePayload]::new($Text, $Attribution)
    Add-CurrentSlideElement -Element (New-InternalSlideElement -Kind Quote -Payload $payload -Region $Region -RevealStep $RevealStep -Alignment Center)
}
