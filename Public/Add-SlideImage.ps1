function Add-SlideImage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$AltText,
        [string]$Region = 'Content',
        [int]$RevealStep = 0
    )
    $payload = [TerminalSlides.Schema.V1.ImagePayload]::new($Path, $AltText)
    $element = New-InternalSlideElement -Kind Image -Payload $payload -Region $Region -RevealStep $RevealStep
    if (-not [System.IO.Path]::IsPathRooted($Path)) { Set-TerminalMediaOrigin -Element $element -Directory (Get-Location).Path }
    Add-CurrentSlideElement -Element $element
}
