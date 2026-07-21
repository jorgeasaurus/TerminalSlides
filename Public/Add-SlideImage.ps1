function Add-SlideImage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$AltText,
        [string]$Region = 'Content',
        [int]$RevealStep = 0
    )
    $resolved = if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path (Get-Location) $Path }
    Add-CurrentSlideElement -Element (New-InternalSlideElement -Type Image -Content @{ Path = $resolved; AltText = $AltText } -Region $Region -RevealStep $RevealStep)
}
