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

    It 'does not split slides on --- inside fenced code blocks' {
        $path = Join-Path $script:WorkPath 'fenced-separator.md'
        @'
# Slide One

```yaml
key: value
---
other: thing
```

# Slide Two

text
'@ | Set-Content -Path $path
        $deck = Import-TerminalPresentation -Path $path
        $deck.Slides.Count | Should -Be 1
        $deck.Slides[0].Title | Should -Be 'Slide One'
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

    It 'exports ANSI with a separator between every slide' {
        $deck = New-TerminalPresentation -Title 'Ansi'
        $deck | Add-TerminalSlide -Title 'One' -Content { Add-SlideText 'first' } | Out-Null
        $deck | Add-TerminalSlide -Title 'Two' -Content { Add-SlideText 'second' } | Out-Null
        $path = Join-Path $script:WorkPath 'deck.ansi'
        Export-TerminalPresentation -Presentation $deck -Format Ansi -Path $path | Out-Null
        $raw = Get-Content -Path $path -Raw
        ([regex]::Matches($raw, ('-' * 40))).Count | Should -Be 1
        $plain = $raw -replace "`e\[[\d;]*m", ''
        $plain | Should -Match 'first'
        $plain | Should -Match 'second'
    }

    It 'preserves ModifiedDate through PSD1 roundtrip' {
        $deck = New-TerminalPresentation -Title 'Dates'
        $deck | Add-TerminalSlide -Title 'S' -Content { Add-SlideText 'x' } | Out-Null
        $deck.ModifiedDate = [datetime]'2020-01-02T03:04:05Z'
        $path = Join-Path $script:WorkPath 'dates.psd1'
        Export-TerminalPresentation -Presentation $deck -Format Psd1 -Path $path | Out-Null
        $imported = Import-TerminalPresentation -Path $path
        $imported.ModifiedDate.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss') | Should -Be '2020-01-02T03:04:05'
    }

    It 'imports a deck with no slides' {
        $path = Join-Path $script:WorkPath 'empty.json'
        '{"Title":"Empty","Slides":null}' | Set-Content -Path $path
        $deck = Import-TerminalPresentation -Path $path
        $deck.Title | Should -Be 'Empty'
        $deck.Slides.Count | Should -Be 0
    }

    It 'exports HTML with expected content' {
        $deck = New-TerminalPresentation -Title 'Html'
        $deck | Add-TerminalSlide -Title 'Slide' -Content { Add-SlideText 'Hello HTML' } | Out-Null
        $path = Join-Path $script:WorkPath 'deck.html'
        Export-TerminalPresentation -Presentation $deck -Format Html -Path $path | Out-Null
        (Get-Content -Path $path -Raw) | Should -Match 'Hello HTML'
    }
}
