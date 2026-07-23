function Set-TerminalImportedSourceDirectory {
    param(
        [Parameter(Mandatory)][TerminalSlides.Schema.V1.TerminalPresentation]$Presentation,
        [Parameter(Mandatory)][string]$SourcePath
    )

    $basePath = Split-Path -Path $SourcePath -Parent
    foreach ($element in @($Presentation.Slides.Elements | Where-Object Kind -eq Image)) {
        if (-not [System.IO.Path]::IsPathRooted($element.Payload.Path)) {
            Set-TerminalMediaOrigin -Element $element -Directory $basePath
        }
    }
    return $Presentation
}

function Import-TerminalPowerShellDataSnapshot {
    param([Parameter(Mandatory)][byte[]]$Bytes)

    [void](ConvertFrom-TerminalUtf8Bytes -Bytes $Bytes -RemoveByteOrderMark)
    $snapshotPath = Join-Path ([IO.Path]::GetTempPath()) ('terminalslides-' + [guid]::NewGuid().ToString('N') + '.psd1')
    try {
        $stream = [IO.FileStream]::new(
            $snapshotPath,
            [IO.FileMode]::CreateNew,
            [IO.FileAccess]::Write,
            [IO.FileShare]::Read
        )
        try {
            $stream.Write($Bytes, 0, $Bytes.Length)
            $stream.Flush($true)
        }
        finally { $stream.Dispose() }
        return Microsoft.PowerShell.Utility\Import-PowerShellDataFile -LiteralPath $snapshotPath
    }
    finally {
        Remove-Item -LiteralPath $snapshotPath -Force -ErrorAction SilentlyContinue
    }
}

function Import-TerminalPresentation {
    [CmdletBinding()]
    [OutputType([object])]
    param([Parameter(Mandatory)][string]$Path)

    try {
        $resolvedPath = if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path (Get-Location) $Path }
        if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) { throw "Path '$resolvedPath' was not found." }
        $extension = [System.IO.Path]::GetExtension($resolvedPath).ToLowerInvariant()
        switch ($extension) {
            '.psd1' {
                $data = Import-TerminalPowerShellDataSnapshot -Bytes ([IO.File]::ReadAllBytes($resolvedPath))
                if ($data.ContainsKey('TerminalSlidesEnvelope')) {
                    $presentation = New-PresentationFromData -Data (ConvertFrom-TerminalDataMarker -Marker $data.TerminalSlidesEnvelope)
                    return Set-TerminalImportedSourceDirectory -Presentation $presentation -SourcePath $resolvedPath
                }
                if ($data.ContainsKey('TerminalSlidesData')) {
                    $presentation = New-PresentationFromData -Data (ConvertFrom-TerminalDataMarker -Marker $data.TerminalSlidesData)
                    return Set-TerminalImportedSourceDirectory -Presentation $presentation -SourcePath $resolvedPath
                }
                if ($data.ContainsKey('Json')) {
                    $presentation = New-PresentationFromData -Data (ConvertFrom-TerminalWireJson -Json ([string]$data.Json))
                    return Set-TerminalImportedSourceDirectory -Presentation $presentation -SourcePath $resolvedPath
                }
                $presentation = New-PresentationFromData -Data $data
                return Set-TerminalImportedSourceDirectory -Presentation $presentation -SourcePath $resolvedPath
            }
            '.json' {
                $json = ConvertFrom-TerminalUtf8Bytes -Bytes ([IO.File]::ReadAllBytes($resolvedPath)) -RemoveByteOrderMark
                $presentation = New-PresentationFromData -Data (ConvertFrom-TerminalWireJson -Json $json)
                return Set-TerminalImportedSourceDirectory -Presentation $presentation -SourcePath $resolvedPath
            }
            '.md' { }
            '.markdown' { }
            default { throw "Unsupported presentation format '$extension'." }
        }
        $content = ConvertFrom-TerminalUtf8Bytes -Bytes ([IO.File]::ReadAllBytes($resolvedPath)) -RemoveByteOrderMark
        $canonicalMatch = [regex]::Match($content, '<!--\s*terminalslides:envelope\s+(?<data>[A-Za-z0-9+/=]+)\s*-->\s*\z')
        if ($canonicalMatch.Success) {
            $marker = ConvertFrom-TerminalDataMarker -Marker $canonicalMatch.Groups['data'].Value
            Assert-TerminalMarkdownEnvelope -Envelope $marker
            $visibleDocument = $content.Remove($canonicalMatch.Index, $canonicalMatch.Length)
            if ([uint64]$marker.MarkerVersion -eq 2) {
                $actualHash = Get-TerminalMarkdownProjectionHash -VisibleDocument $visibleDocument -PresentationData $marker.Presentation
                if ($actualHash -cne $marker.ProjectionHash) {
                    throw 'The visible Markdown was edited, or its embedded presentation no longer matches, after export.'
                }
            }
            $sourceThemeName = [string]$marker.Presentation.Presentation.Theme
            $presentation = New-PresentationFromData -Data $marker.Presentation
            if ([uint64]$marker.MarkerVersion -eq 1 -and -not
                (Test-TerminalMarkdownV1Projection -VisibleDocument $visibleDocument -Presentation $presentation -SourceThemeName $sourceThemeName)) {
                throw 'The visible Markdown was edited after export. Remove the terminalslides:envelope marker to import the visible Markdown dialect, or re-export the deck.'
            }
            return Set-TerminalImportedSourceDirectory -Presentation $presentation -SourcePath $resolvedPath
        }
        if ($content -match '<!--\s*terminalslides:envelope(?:\s|-->)') {
            throw 'The Markdown TerminalSlides envelope is malformed or is not the trailing document envelope.'
        }
        if ($content -match '<!--\s*terminalslides:data\s+') {
            throw 'Legacy Markdown data markers have no integrity binding. Remove the terminalslides:data marker to import the visible Markdown dialect.'
        }
        $title = 'Imported Presentation'
        $author = $null
        $theme = 'Midnight'
        $frontmatterMatch = [regex]::Match($content, '(?ms)^---\s*\r?\n(?<frontmatter>.*?)\r?\n---\s*(\r?\n)?')
        if ($frontmatterMatch.Success) {
            $frontmatter = $frontmatterMatch.Groups['frontmatter'].Value
            foreach ($line in ($frontmatter -split "`n")) {
                if ($line -match '^(title|author|theme):\s*(.+)$') {
                    $name = $matches[1]
                    $rawValue = $matches[2].Trim()
                    try { $value = ConvertFrom-TerminalJsonValue -Json $rawValue }
                    catch { $value = $rawValue }
                    switch ($name) {
                        'title' { $title = [string]$value }
                        'author' { $author = [string]$value }
                        'theme' { $theme = [string]$value }
                    }
                }
            }
            $content = $content.Substring($frontmatterMatch.Length).TrimStart()
        }
        $presentation = New-TerminalPresentation -Title $title -Author $author -Theme $theme
        $slideBuffer = [System.Collections.Generic.List[string]]::new()
        $slides = [System.Collections.Generic.List[string]]::new()
        $inFence = $false
        foreach ($line in ($content -split "\r?\n")) {
            if ($line.TrimStart() -match '^```') { $inFence = -not $inFence }
            if ($line.Trim() -eq '---' -and -not $inFence) {
                $candidate = ($slideBuffer -join "`n").Trim()
                if ($candidate) { $slides.Add($candidate) }
                $slideBuffer.Clear()
                continue
            }
            $slideBuffer.Add($line)
        }
        $candidate = ($slideBuffer -join "`n").Trim()
        if ($candidate) { $slides.Add($candidate) }
        foreach ($slideText in $slides) {
            $trimmed = $slideText.Trim()
            if (-not $trimmed) { continue }
            $lines = $trimmed -split "`n"
            $slideTitle = ($lines | Where-Object { $_ -match '^#\s+' } | Select-Object -First 1)
            $slideTitle = if ($slideTitle) { $slideTitle -replace '^#\s+', '' } else { 'Slide' }
            $presentation | Add-TerminalSlide -Title $slideTitle -Content {
                $inCode = $false
                $codeLang = 'text'
                $codeLines = [System.Collections.Generic.List[string]]::new()
                foreach ($line in $lines) {
                    $current = $line.TrimEnd("`r")
                    if ($current -match '^#\s+') { continue }
                    if ($current -match '^```(.*)$') {
                        if (-not $inCode) {
                            $inCode = $true
                            $codeLang = if ($matches[1]) { $matches[1].Trim() } else { 'text' }
                        }
                        else {
                            Add-SlideCode -Code ($codeLines -join "`n") -Language $codeLang
                            $codeLines.Clear()
                            $inCode = $false
                        }
                        continue
                    }
                    if ($inCode) { $codeLines.Add($current); continue }
                    if ($current -match '^##\s+') { Add-SlideTitle ($current -replace '^##\s+', ''); continue }
                    if ($current -match '^###\s+') { Add-SlideSubtitle ($current -replace '^###\s+', ''); continue }
                    if ($current -match '^-\s+') { Add-SlideBullet ($current -replace '^-\s+', ''); continue }
                    if ($current -match '^>\s+') { Add-SlideQuote -Text ($current -replace '^>\s+', ''); continue }
                    if ($current -match '^<!--\s*Notes:\s*(.*?)\s*-->$') { Add-SlideNotes $matches[1]; continue }
                    if ($current.Trim()) { Add-SlideText $current.Trim() }
                }
                if ($inCode -and $codeLines.Count -gt 0) {
                    Add-SlideCode -Code ($codeLines -join "`n") -Language $codeLang
                }
            } | Out-Null
        }
        return Set-TerminalImportedSourceDirectory -Presentation $presentation -SourcePath $resolvedPath
    }
    catch {
        throw
    }
}
