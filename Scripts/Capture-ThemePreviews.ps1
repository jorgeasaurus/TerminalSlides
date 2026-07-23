#Requires -Version 7.4

[CmdletBinding()]
param(
    [ValidateSet(
        'HighContrast',
        'Midnight',
        'Minimal',
        'Monochrome',
        'PowerShell',
        'RetroTerminal',
        'SolarizedDark',
        'SolarizedLight'
    )]
    [string[]]$Theme = @(
        'Midnight',
        'PowerShell',
        'SolarizedDark',
        'SolarizedLight',
        'RetroTerminal',
        'Minimal',
        'Monochrome',
        'HighContrast'
    ),

    [string]$OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-TerminalThemePreviewSlug {
    param([Parameter(Mandatory)][string]$Name)

    return [regex]::Replace($Name, '(?<=[a-z0-9])(?=[A-Z])', '-').ToLowerInvariant()
}

function ConvertTo-VhsTheme {
    param([Parameter(Mandatory)][hashtable]$Definition)

    $theme = [ordered]@{
        name = $Definition.Name
        black = $Definition.Background
        red = $Definition.ErrorColor
        green = $Definition.SuccessColor
        yellow = $Definition.WarningColor
        blue = $Definition.Primary
        magenta = $Definition.Accent
        cyan = $Definition.Heading
        white = $Definition.Foreground
        brightBlack = $Definition.Muted
        brightRed = $Definition.ErrorColor
        brightGreen = $Definition.SuccessColor
        brightYellow = $Definition.WarningColor
        brightBlue = $Definition.Primary
        brightMagenta = $Definition.Accent
        brightCyan = $Definition.Heading
        brightWhite = $Definition.Foreground
        background = $Definition.Background
        foreground = $Definition.Foreground
        selection = $Definition.Accent
        cursor = $Definition.Foreground
    }
    return $theme | ConvertTo-Json -Compress
}

function ConvertTo-VhsQuotedString {
    param([Parameter(Mandatory)][string]$Value)

    return '"' + $Value.Replace('\', '\\').Replace('"', '\"') + '"'
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $repositoryRoot 'docs/theme-previews'
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory, $repositoryRoot)
[void][IO.Directory]::CreateDirectory($OutputDirectory)

$vhs = Get-Command vhs -CommandType Application -ErrorAction Stop
[void](Get-Command ttyd -CommandType Application -ErrorAction Stop)
[void](Get-Command pwsh -CommandType Application -ErrorAction Stop)

$temporaryDirectory = Join-Path (
    [IO.Path]::GetTempPath()
) ('terminalslides-theme-previews-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporaryDirectory)

try {
    foreach ($themeName in $Theme) {
        $definitionPath = Join-Path $repositoryRoot "Themes/$themeName.psd1"
        $definition = Import-PowerShellDataFile -LiteralPath $definitionPath
        $slug = ConvertTo-TerminalThemePreviewSlug -Name $themeName
        $screenshotPath = Join-Path $OutputDirectory "$slug.png"
        $temporaryGifPath = Join-Path $temporaryDirectory "$slug.gif"
        $tapePath = Join-Path $temporaryDirectory "$slug.tape"
        $vhsTheme = ConvertTo-VhsTheme -Definition $definition

        $tape = @(
            'Require pwsh'
            ''
            "Output $(ConvertTo-VhsQuotedString -Value $temporaryGifPath)"
            ''
            'Set Shell "zsh"'
            'Set Width 1600'
            'Set Height 900'
            'Set FontSize 18'
            'Set FontFamily "Menlo"'
            'Set LineHeight 1.1'
            'Set TypingSpeed 0ms'
            "Set Theme $vhsTheme"
            'Set Padding 30'
            'Set Margin 24'
            "Set MarginFill $(ConvertTo-VhsQuotedString -Value $definition.Background)"
            'Set BorderRadius 12'
            ''
            'Hide'
            "Type $(ConvertTo-VhsQuotedString -Value "cd '$repositoryRoot'")"
            'Enter'
            "Type $(ConvertTo-VhsQuotedString -Value "./Scripts/show-theme-preview '$themeName'")"
            'Enter'
            'Wait+Screen /Slide 1 of 1/'
            'Show'
            'Sleep 750ms'
            "Screenshot $(ConvertTo-VhsQuotedString -Value $screenshotPath)"
            'Sleep 250ms'
            'Type "q"'
        )
        [IO.File]::WriteAllLines($tapePath, $tape, [Text.UTF8Encoding]::new($false))

        Write-Host "Capturing $themeName..." -ForegroundColor Cyan
        & $vhs.Source $tapePath
        if ($LASTEXITCODE -ne 0) {
            throw "VHS failed while capturing theme '$themeName'."
        }
        Get-Item -LiteralPath $screenshotPath
    }
}
finally {
    if (Test-Path -LiteralPath $temporaryDirectory) {
        Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force
    }
}
