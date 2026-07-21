function Invoke-SafeScriptBlock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [switch]$SafeMode,
        [string[]]$AllowedCommands = @('Add-SlideTitle','Add-SlideSubtitle','Add-SlideText','Add-SlideBullet','Add-SlideCode','Add-SlideTable','Add-SlideChart','Add-SlideDiagram','Add-SlideImage','Add-SlideQuote','Add-SlideBox','Add-SlideNotes','Node','Edge')
    )

    if ($SafeMode) {
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseInput($ScriptBlock.ToString(), [ref]$tokens, [ref]$errors) | Out-Null
        if ($errors.Count -gt 0) {
            throw 'The supplied content script block could not be parsed safely.'
        }
        $commands = $tokens.Where({ $_.Kind -eq 'Generic' }).Text | Select-Object -Unique
        $disallowed = @($commands | Where-Object { $_ -and $_ -notin $AllowedCommands })
        if ($disallowed.Count -gt 0) {
            throw "SafeMode blocked content commands: $($disallowed -join ', ')"
        }
    }
    & $ScriptBlock
}
