function Add-SlideNotes {
    [CmdletBinding()]
    param([Parameter(Mandatory, Position = 0)][string]$Text)
    $context = Get-TerminalSlidesStateValue -Name CurrentSlideContext
    if (-not $context) {
        return [pscustomobject]@{ __TerminalSlidesNote = $true; Text = $Text }
    }
    $context.Notes = $Text
    Set-TerminalSlidesStateValue -Name CurrentSlideContext -Value $context
}
