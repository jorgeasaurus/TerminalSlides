function Invoke-SafeScriptBlock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [switch]$SafeMode,
        [ValidateSet('Current','Local')][string]$Scope = 'Current',
        [string[]]$AllowedCommands = @('Add-SlideTitle','Add-SlideSubtitle','Add-SlideText','Add-SlideBullet','Add-SlideCode','Add-SlideTable','Add-SlideChart','Add-SlideDiagram','Add-SlideDiagramNode','Add-SlideDiagramEdge','Add-SlideImage','Add-SlideQuote','Add-SlideBox','Add-SlideNotes')
    )

    if ($SafeMode) {
        # CheckRestrictedLanguage applies PowerShell's data-section grammar. It
        # rejects method calls, type expressions, dynamic invocation, variable
        # access, redirection, and commands outside this explicit DSL surface.
        try {
            $ScriptBlock.CheckRestrictedLanguage(
                [string[]]$AllowedCommands,
                [string[]]@('true', 'false', 'null'),
                $false
            )
        }
        catch {
            throw "SafeMode restricted language validation failed: $($_.Exception.Message)"
        }
    }
    if ($Scope -eq 'Local') { . $ScriptBlock } else { & $ScriptBlock }
}
