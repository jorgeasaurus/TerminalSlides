function Add-SlideNotes {
    [CmdletBinding()]
    param([Parameter(Mandatory, Position = 0)][string]$Text)
    $context = Get-TerminalSlidesBuildContext -Kind Slide
    if (-not $context) {
        return [pscustomobject]@{ __TerminalSlidesNote = $true; Text = $Text }
    }
    $context.Notes = $Text
}
