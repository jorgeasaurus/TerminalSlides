function Import-TerminalPresentation {
    [CmdletBinding()]
    [OutputType([object])]
    param([Parameter(Mandatory)][string]$Path)

    try {
        $resolvedPath = if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path (Get-Location) $Path }
        if (-not (Test-Path $resolvedPath)) { throw "Path '$resolvedPath' was not found." }
        $extension = [System.IO.Path]::GetExtension($resolvedPath).ToLowerInvariant()
        switch ($extension) {
            '.psd1' {
                $data = Import-PowerShellDataFile -Path $resolvedPath
                if ($data.ContainsKey('Json')) {
                    return New-PresentationFromData -Data ($data.Json | ConvertFrom-Json -AsHashtable)
                }
                return New-PresentationFromData -Data $data
            }
            '.json' {
                return New-PresentationFromData -Data ((Get-Content -Path $resolvedPath -Raw) | ConvertFrom-Json -AsHashtable)
            }
            '.md' { }
            '.markdown' { }
            default { throw "Unsupported presentation format '$extension'." }
        }
        $content = Get-Content -Path $resolvedPath -Raw
        $title = 'Imported Presentation'
        $author = $null
        $theme = 'Midnight'
        $frontmatterMatch = [regex]::Match($content, '(?ms)^---\s*\r?\n(?<frontmatter>.*?)\r?\n---\s*(\r?\n)?')
        if ($frontmatterMatch.Success) {
            $frontmatter = $frontmatterMatch.Groups['frontmatter'].Value
            foreach ($line in ($frontmatter -split "`n")) {
                if ($line -match '^title:\s*(.+)$') { $title = $matches[1].Trim() }
                if ($line -match '^author:\s*(.+)$') { $author = $matches[1].Trim() }
                if ($line -match '^theme:\s*(.+)$') { $theme = $matches[1].Trim() }
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
        return $presentation
    }
    catch {
        throw
    }
}
