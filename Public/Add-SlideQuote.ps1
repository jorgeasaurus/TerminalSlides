function Add-SlideQuote {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Text,
        [string]$Attribution,
        [string]$Region = 'Content',
        [int]$RevealStep = 0
    )
    Add-CurrentSlideElement -Element (New-InternalSlideElement -Type Quote -Content @{ Text = $Text; Attribution = $Attribution } -Region $Region -RevealStep $RevealStep -Alignment Center)
}
