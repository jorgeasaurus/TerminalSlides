Describe 'Cycle 18 persistence and media boundaries' {
    BeforeAll {
        $script:ModulePath = Join-Path $PSScriptRoot '..' '..' 'TerminalSlides.psd1'
        Import-Module $script:ModulePath -Force

        function Write-InvalidUtf8Psd1 {
            param(
                [Parameter(Mandatory)][string]$Content,
                [Parameter(Mandatory)][string]$Sentinel,
                [Parameter(Mandatory)][string]$Path
            )

            $bytes = [Text.Encoding]::UTF8.GetBytes($Content)
            $index = $Content.IndexOf($Sentinel, [StringComparison]::Ordinal)
            if ($index -lt 0) { throw 'The invalid UTF-8 sentinel was not found.' }
            $bytes[$index] = 0xff
            [IO.File]::WriteAllBytes($Path, $bytes)
        }

        function Write-Cycle18CurrentWireFile {
            param(
                [Parameter(Mandatory)][System.Collections.IDictionary]$Data,
                [Parameter(Mandatory)][ValidateSet('Json','Psd1','Markdown')][string]$Format,
                [Parameter(Mandatory)][string]$Path
            )

            $content = & (Get-Module TerminalSlides) {
                param($WireData, $WireFormat)
                switch ($WireFormat) {
                    'Json' { ConvertTo-TerminalWireJson $WireData }
                    'Psd1' { "@{ TerminalSlidesEnvelope = '$(ConvertTo-TerminalDataMarker $WireData)' }`n" }
                    'Markdown' {
                        $marker = [ordered]@{ MarkerVersion = 1; Presentation = $WireData }
                        '<!-- terminalslides:envelope ' + (ConvertTo-TerminalDataMarker $marker) + ' -->'
                    }
                }
            } $Data $Format
            [IO.File]::WriteAllText($Path, $content)
        }
    }

    It 'rejects malformed UTF-8 before parsing preview and direct PSD1 data' {
        $sentinel = 'InvalidUtf8Sentinel'
        $currentJson = & (Get-Module TerminalSlides) {
            param($Title)
            ConvertTo-TerminalWireJson (ConvertTo-PresentationData (New-TerminalPresentation -Title $Title))
        } $sentinel
        $cases = [ordered]@{
            Preview = "@{ Json = '$currentJson' }"
            Direct = "@{ Title = '$sentinel'; Slides = @() }"
        }

        foreach ($case in $cases.GetEnumerator()) {
            $path = Join-Path $TestDrive "$($case.Key).psd1"
            Write-InvalidUtf8Psd1 -Content $case.Value -Sentinel $sentinel -Path $path
            $original = [Convert]::ToBase64String([IO.File]::ReadAllBytes($path))

            { Import-TerminalPresentation $path } | Should -Throw '*valid UTF-8*'
            [Convert]::ToBase64String([IO.File]::ReadAllBytes($path)) | Should -BeExactly $original
        }
    }

    It 'orders every unordered JSON dictionary while preserving explicitly ordered objects' {
        $modulePathLiteral = "'" + $script:ModulePath.Replace("'", "''") + "'"
        $probe = @"
Import-Module $modulePathLiteral -Force
`$data = @{}
foreach (`$key in 'Zulu','Alpha','Mike','Bravo','Echo','Charlie') { `$data[`$key] = `$key }
`$json = & (Get-Module TerminalSlides) { param(`$Value) ConvertTo-TerminalWireJson `$Value } `$data
[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes(`$json)))
"@
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($probe))
        $hashes = foreach ($run in 1..4) {
            & ([Environment]::ProcessPath) -NoLogo -NoProfile -EncodedCommand $encoded
            $LASTEXITCODE | Should -Be 0
        }
        @($hashes | Where-Object { $_ -is [string] } | Select-Object -Unique).Count | Should -Be 1

        InModuleScope TerminalSlides {
            ConvertTo-TerminalWireJson @{ Zulu = 1; Alpha = 2 } |
                Should -BeExactly '{"Alpha":2,"Zulu":1}'
            ConvertTo-TerminalWireJson ([ordered]@{ Zulu = 1; Alpha = 2 }) |
                Should -BeExactly '{"Zulu":1,"Alpha":2}'
        }
    }

    It 'rejects invalid current-wire dates and renderer domains through every format' {
        $invalidCases = & (Get-Module TerminalSlides) {
            $deck = New-TerminalPresentation -Title InvalidCurrent
            $deck | Add-TerminalSlide -Title Data -Content { Add-SlideText value } | Out-Null
            $base = ConvertTo-PresentationData $deck
            $copy = { ConvertFrom-TerminalWireJson (ConvertTo-TerminalWireJson $base) }
            $created = & $copy; $created.Presentation.CreatedDate = ''
            $modified = & $copy; $modified.Presentation.ModifiedDate = ''
            $layout = & $copy; $layout.Presentation.Slides[0].Layout = 'Bogus'
            $alignment = & $copy; $alignment.Presentation.Slides[0].Elements[0].Alignment = 'Diagonal'
            $region = & $copy; $region.Presentation.Slides[0].Elements[0].Region = 'Bogus'
            $overflow = & $copy; $overflow.Presentation.Slides[0].Elements[0].OverflowBehavior = 'Explode'
            return ,([object[]]@($created, $modified, $layout, $alignment, $region, $overflow))
        }

        foreach ($caseIndex in 0..($invalidCases.Count - 1)) {
            foreach ($format in 'Json','Psd1','Markdown') {
                $path = Join-Path $TestDrive "invalid-domain-$caseIndex.$($format.ToLowerInvariant())"
                Write-Cycle18CurrentWireFile -Data $invalidCases[$caseIndex] -Format $format -Path $path
                { Import-TerminalPresentation $path } | Should -Throw '*current wire*'
            }
        }
    }

    It 'names portable media from the staged snapshot when the source mutates' {
        $sourcePath = Join-Path $TestDrive 'mutable.png'
        [IO.File]::WriteAllText($sourcePath, 'before')
        $targetPath = Join-Path $TestDrive 'deck.json'
        $deck = New-TerminalPresentation -Title MediaSnapshot
        $deck | Add-TerminalSlide -Title Image -Content ({
            Add-SlideImage -Path $sourcePath
            Add-SlideImage -Path $sourcePath
        }.GetNewClosure()) | Out-Null

        InModuleScope TerminalSlides -Parameters @{
            Presentation = $deck
            SourcePath = $sourcePath
            TargetPath = $targetPath
        } {
            Mock Copy-Item {
                [IO.File]::WriteAllText($LiteralPath, 'after')
                [IO.File]::Copy($LiteralPath, $Destination)
            } -ParameterFilter { $LiteralPath -eq $SourcePath }

            $view = New-TerminalPresentationView -Presentation $Presentation
            $portable = New-TerminalPortableExport -Presentation $view -TargetPath $TargetPath -Overwrite $false
            try {
                $assets = @(Get-ChildItem -LiteralPath $portable.Transaction.StagingDirectory -File)
                $assets.Count | Should -Be 1
                $expectedName = (Get-FileHash -LiteralPath $assets[0].FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                [IO.Path]::GetFileNameWithoutExtension($assets[0].Name) | Should -BeExactly $expectedName
                [IO.File]::ReadAllText($assets[0].FullName) | Should -BeExactly after
            }
            finally {
                Remove-Item -LiteralPath $portable.Transaction.StagingDirectory -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
