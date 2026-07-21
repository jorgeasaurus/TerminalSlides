function Add-SlideText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Text,
        [string]$Region = 'Content',
        [ValidateSet('Left','Center','Right')][string]$Alignment = 'Left',
        [int]$RevealStep = 0,
        [string]$ForegroundColor,
        [string]$BackgroundColor,
        [ValidateSet('Wrap','Truncate','Scroll')][string]$OverflowBehavior = 'Wrap'
    )
    $element = New-InternalSlideElement -Type Text -Content $Text -Region $Region -Alignment $Alignment -RevealStep $RevealStep -ForegroundColor $ForegroundColor -BackgroundColor $BackgroundColor -OverflowBehavior $OverflowBehavior
    Add-CurrentSlideElement -Element $element
}
