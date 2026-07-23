Describe 'Presentation formats and layouts' {
    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '..' '..' 'TerminalSlides.psd1') -Force
        $script:deck = New-TerminalPresentation -Title 'Formats' -Author 'Author'
        $script:deck | Add-TerminalSlide -Title 'Elements' -Content {
            Add-SlideTitle 'Heading'
            Add-SlideSubtitle 'Subheading'
            Add-SlideText 'Text'
            Add-SlideBullet 'Bullet'
            Add-SlideCode -Code 'Write-Output "code"' -Language powershell
            Add-SlideQuote -Text 'Quote' -Attribution 'Author'
        } | Out-Null
        $script:outputRoot = Join-Path ([System.IO.Path]::GetTempPath()) "TerminalSlidesFormatTests-$PID"
        New-Item -Path $script:outputRoot -ItemType Directory -Force | Out-Null
    }

    AfterAll {
        if (Test-Path $script:outputRoot) {
            Remove-Item -Path $script:outputRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'defines regions for every supported layout at the minimum viewport' {
        InModuleScope TerminalSlides {
            foreach ($layout in 'Title', 'SectionHeader', 'TwoColumn', 'ThreeColumn', 'CodeFocus', 'ImageFocus', 'Quote', 'Blank', 'TitleAndContent') {
                $regions = Get-LayoutRegions -Layout $layout -Width 1 -Height 1
                $regions.Count | Should -BeGreaterThan 0
                foreach ($region in $regions.Values) {
                    $region.Width | Should -BeGreaterThan 0
                    $region.Height | Should -BeGreaterThan 0
                }
            }
        }
    }

    It 'exports the presentation in every supported format' -TestCases @(
        @{ Format = 'Ansi'; Extension = 'ansi' }
        @{ Format = 'PlainText'; Extension = 'txt' }
        @{ Format = 'Markdown'; Extension = 'md' }
        @{ Format = 'Html'; Extension = 'html' }
        @{ Format = 'Psd1'; Extension = 'psd1' }
        @{ Format = 'Json'; Extension = 'json' }
    ) {
        param($Format, $Extension)

        $path = Join-Path $outputRoot "deck.$Extension"
        $file = Export-TerminalPresentation -Presentation $deck -Path $path -Format $Format

        $file.FullName | Should -Be $path
        (Get-Content -Path $path -Raw) | Should -Not -BeNullOrEmpty
    }

    It 'validates all requested viewports and reports invalid entries' {
        $warnings = @()
        $result = Test-TerminalPresentation -Presentation $deck -Viewport @('40x10', 'invalid') -WarningVariable warnings

        @($result).Count | Should -Be 1
        $warnings.Message | Should -Contain "Viewport 'invalid' is invalid."
    }

    It 'exports dictionary-backed tables and normalized code languages' {
        InModuleScope TerminalSlides {
            (ConvertTo-TerminalMarkdownTable ([ordered]@{ Name = 'Ada'; Score = 10 })) -join "`n" |
                Should -Match '\| Name \| Score \|'
            $element = New-InternalSlideElement -Kind Code -Payload ([TerminalSlides.Schema.V1.CodePayload]::new('value', $null))
            ConvertTo-TerminalMarkdownElement $element | Should -Match '^```text'
        }
    }
}
