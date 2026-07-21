Import-Module (Join-Path $PSScriptRoot '..' 'TerminalSlides.psd1') -Force
$deck = New-TerminalPresentation -Title 'Code Demo' -Theme PowerShell
$deck | Add-TerminalSlide -Title 'PowerShell' -Layout CodeFocus -Content {
    Add-SlideCode -Language powershell -Code @"
Get-Process |
    Sort-Object CPU -Descending |
    Select-Object -First 5 Name, CPU
"@
    Add-SlideNotes 'Talk about using CodeFocus for demos.'
} | Out-Null
Show-TerminalPresentation -Presentation $deck
