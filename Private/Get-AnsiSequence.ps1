function Convert-HexToRgb {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Hex)
    $clean = $Hex.Trim()
    if ($clean -notmatch '^#?[0-9A-Fa-f]{6}$') {
        throw "Invalid hex color '$Hex'. Expected #RRGGBB."
    }
    $clean = $clean.TrimStart('#')
    return @(
        [Convert]::ToInt32($clean.Substring(0,2), 16),
        [Convert]::ToInt32($clean.Substring(2,2), 16),
        [Convert]::ToInt32($clean.Substring(4,2), 16)
    )
}

function Get-AnsiReset { "`e[0m" }
function Get-AnsiBold { "`e[1m" }
function Get-AnsiItalic { "`e[3m" }
function Get-AnsiUnderline { "`e[4m" }

function Get-AnsiFg {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Color)
    $rgb = Convert-HexToRgb -Hex $Color
    return "`e[38;2;$($rgb[0]);$($rgb[1]);$($rgb[2])m"
}

function Get-AnsiBg {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Color)
    $rgb = Convert-HexToRgb -Hex $Color
    return "`e[48;2;$($rgb[0]);$($rgb[1]);$($rgb[2])m"
}

function Strip-AnsiSequences {
    [CmdletBinding()]
    param([AllowNull()][string]$Text)
    if ($null -eq $Text) { return $null }
    return ([regex]::Replace($Text, "`e\[[0-9;?]*[ -/]*[@-~]", ''))
}
