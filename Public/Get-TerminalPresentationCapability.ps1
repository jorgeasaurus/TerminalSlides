function Invoke-TerminalCapabilityProbe {
    param(
        [Parameter(Mandatory)][scriptblock]$Operation,
        [AllowNull()]$Fallback
    )

    try { & $Operation } catch { $Fallback }
}

function Get-TerminalPresentationCapability {
    [CmdletBinding()]
    [OutputType([object])]
    param()

    $capability = [TerminalSlides.Schema.V1.TerminalCapability]::new()
    $capability.HostName = $Host.Name
    $capability.OS = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
    $capability.PSVersion = $PSVersionTable.PSVersion.ToString()
    $capability.Width = Invoke-TerminalCapabilityProbe -Operation { [Console]::WindowWidth } -Fallback 80
    $capability.Height = Invoke-TerminalCapabilityProbe -Operation { [Console]::WindowHeight } -Fallback 24
    $term = $env:TERM
    $colorterm = $env:COLORTERM
    $supportsVirtualTerminal = $null
    $supportsVirtualTerminal = Invoke-TerminalCapabilityProbe -Operation { $Host.UI.SupportsVirtualTerminal } -Fallback $null
    $capability.AnsiSupport = [bool]($IsWindows ? ($supportsVirtualTerminal ?? [bool]($env:WT_SESSION -or $env:TERM_PROGRAM)) : ($term -and $term -ne 'dumb'))
    $capability.TrueColorSupport = [bool]($colorterm -match 'truecolor|24bit' -or $env:WT_SESSION -or $env:TERM_PROGRAM -eq 'iTerm.app')
    $capability.Color256Support = [bool]($term -match '256' -or $capability.TrueColorSupport)
    $capability.UnicodeSupport = $OutputEncoding.WebName -match 'utf'
    $capability.IsRedirected = [Console]::IsOutputRedirected -or [Console]::IsInputRedirected
    $capability.Interactive = -not $capability.IsRedirected -and -not [Console]::IsErrorRedirected
    $capability.AlternateBuffer = $capability.AnsiSupport -and -not $capability.IsRedirected
    $capability.SixelSupport = [bool]($env:TERM -match 'xterm' -and $env:DECGRI)
    $capability.KittyGraphics = [bool]$env:KITTY_WINDOW_ID
    $capability.ITermImages = [bool]($env:TERM_PROGRAM -eq 'iTerm.app')
    $capability.EnvironmentVars = @{ TERM = $term; COLORTERM = $colorterm; WT_SESSION = $env:WT_SESSION; TERM_PROGRAM = $env:TERM_PROGRAM }
    return $capability
}
