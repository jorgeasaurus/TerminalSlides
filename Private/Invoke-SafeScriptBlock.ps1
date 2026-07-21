function Invoke-SafeScriptBlock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [switch]$SafeMode,
        [ValidateSet('Current','Local')][string]$Scope = 'Current',
        [string[]]$AllowedCommands = @('Add-SlideTitle','Add-SlideSubtitle','Add-SlideText','Add-SlideBullet','Add-SlideCode','Add-SlideTable','Add-SlideChart','Add-SlideDiagram','Add-SlideImage','Add-SlideQuote','Add-SlideBox','Add-SlideNotes','Node','Edge')
    )

    if ($SafeMode) {
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($ScriptBlock.ToString(), [ref]$tokens, [ref]$errors)
        if ($errors.Count -gt 0) {
            throw 'The supplied content script block could not be parsed safely.'
        }
        $commandAsts = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)
        $commands = $commandAsts | ForEach-Object { $_.GetCommandName() } | Where-Object { $_ } | Select-Object -Unique
        $disallowed = @($commands | Where-Object { $_ -notin $AllowedCommands })
        if ($disallowed.Count -gt 0) {
            throw "SafeMode blocked content commands: $($disallowed -join ', ')"
        }
    }
    if ($Scope -eq 'Local') { . $ScriptBlock } else { & $ScriptBlock }
}
