Describe 'Import and export' {
    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '..' '..' 'TerminalSlides.psd1') -Force
        $work = Join-Path $PSScriptRoot '_artifacts'
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        $script:WorkPath = $work
    }

    It 'roundtrips PSD1 export and import' {
        $deck = New-TerminalPresentation -Title 'Roundtrip'
        $deck | Add-TerminalSlide -Title 'Slide' -Content { Add-SlideText 'Hello' } | Out-Null
        $path = Join-Path $script:WorkPath 'deck.psd1'
        Export-TerminalPresentation -Presentation $deck -Format Psd1 -Path $path | Out-Null
        $imported = Import-TerminalPresentation -Path $path
        $imported.Title | Should -Be 'Roundtrip'
        $imported.Slides[0].Elements[0].Content | Should -Be 'Hello'
    }

    It 'imports markdown' {
        $path = Join-Path $script:WorkPath 'deck.md'
        @"
---
title: Markdown Deck
author: Jorge
theme: Midnight
---

# Intro
- One
- Two
"@ | Set-Content -Path $path
        $deck = Import-TerminalPresentation -Path $path
        $deck.Title | Should -Be 'Markdown Deck'
        $deck.Slides.Count | Should -Be 1
    }

    It 'imports markdown with unclosed trailing code block' {
        $path = Join-Path $script:WorkPath 'unclosed.md'
        @'
# Code Slide

```powershell
Get-Process
'@ | Set-Content -Path $path
        $deck = Import-TerminalPresentation -Path $path
        $codeElement = $deck.Slides[0].Elements | Where-Object { $_.Type -eq 'Code' }
        $codeElement | Should -Not -BeNullOrEmpty
        $codeElement.Content.Code | Should -Match 'Get-Process'
    }

    It 'throws on missing import path' {
        { Import-TerminalPresentation -Path (Join-Path $script:WorkPath 'does-not-exist.md') } | Should -Throw
    }

    It 'exports HTML with expected content' {
        $deck = New-TerminalPresentation -Title 'Html'
        $deck | Add-TerminalSlide -Title 'Slide' -Content { Add-SlideText 'Hello HTML' } | Out-Null
        $path = Join-Path $script:WorkPath 'deck.html'
        Export-TerminalPresentation -Presentation $deck -Format Html -Path $path | Out-Null
        (Get-Content -Path $path -Raw) | Should -Match 'Hello HTML'
    }
}
