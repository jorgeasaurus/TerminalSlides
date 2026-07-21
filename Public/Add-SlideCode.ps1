function Add-SlideCode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Code,
        [string]$Language = 'text',
        [string]$Region = 'Content',
        [int]$RevealStep = 0,
        [switch]$Border
    )
    $content = [ordered]@{ Code = $Code; Language = $Language }
    Add-CurrentSlideElement -Element (New-InternalSlideElement -Type Code -Content $content -Region $Region -RevealStep $RevealStep -Border:$Border -Padding 1 -Properties @{ Language = $Language })
}
