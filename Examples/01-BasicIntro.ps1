Import-Module (Join-Path $PSScriptRoot '..' 'TerminalSlides.psd1') -Force
$deck = New-TerminalPresentation -Title 'Demo' -Subtitle 'Hello from PowerShell' -Theme Midnight
$deck |
    Add-TerminalSlide -Title 'Hello' -Content {
        Add-SlideTitle 'Hello, Terminal'
        Add-SlideText 'This presentation is running entirely in PowerShell.'
    } |
    Add-TerminalSlide -Title 'Features' -Content {
        Add-SlideBullet 'Cross-platform'
        Add-SlideBullet 'Keyboard navigation'
        Add-SlideBullet 'ANSI rendering'
    } | Out-Null
Show-TerminalPresentation -Presentation $deck
