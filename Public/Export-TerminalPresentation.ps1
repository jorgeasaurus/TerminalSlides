function Export-TerminalPresentation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][TerminalPresentation]$Presentation,
        [Parameter(Mandatory)][string]$Path,
        [ValidateSet('Ansi','PlainText','Markdown','Html','Psd1','Json')][string]$Format = 'PlainText'
    )

    try {
        $targetPath = if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path (Get-Location) $Path }
        $parent = Split-Path -Path $targetPath -Parent
        if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        switch ($Format) {
            'Ansi' {
                $content = for ($i = 0; $i -lt $Presentation.Slides.Count; $i++) {
                    Render-TerminalPresentationToString -Presentation $Presentation -SlideIndex $i -RevealStep $Presentation.Slides[$i].MaxRevealStep
                }
                Set-Content -Path $targetPath -Value ($content -join [Environment]::NewLine + [Environment]::NewLine + ('-' * 40) + [Environment]::NewLine) -NoNewline
            }
            'PlainText' {
                $content = for ($i = 0; $i -lt $Presentation.Slides.Count; $i++) {
                    Render-TerminalPresentationToString -Presentation $Presentation -SlideIndex $i -RevealStep $Presentation.Slides[$i].MaxRevealStep -PlainText
                }
                Set-Content -Path $targetPath -Value ($content -join ("`n" + ('-' * 40) + "`n"))
            }
            'Markdown' {
                $sb = [System.Text.StringBuilder]::new()
                [void]$sb.AppendLine('---')
                [void]$sb.AppendLine("title: $($Presentation.Title)")
                if ($Presentation.Author) { [void]$sb.AppendLine("author: $($Presentation.Author)") }
                if ($Presentation.Theme) { [void]$sb.AppendLine("theme: $($Presentation.Theme)") }
                [void]$sb.AppendLine('---')
                [void]$sb.AppendLine()
                foreach ($slide in $Presentation.Slides) {
                    [void]$sb.AppendLine("# $($slide.Title)")
                    foreach ($element in $slide.Elements) {
                        switch ($element.Type) {
                            'Title' { [void]$sb.AppendLine("## $($element.Content)") }
                            'Subtitle' { [void]$sb.AppendLine("### $($element.Content)") }
                            'Bullet' { [void]$sb.AppendLine("- $($element.Content)") }
                            'Code' {
                                $language = if ($element.Properties -and $element.Properties.ContainsKey('Language')) { $element.Properties.Language } else { 'text' }
                                $codeText = if ($element.Content -is [System.Collections.IDictionary]) { [string]$element.Content['Code'] } else { [string]$element.Content.Code }
                                [void]$sb.AppendLine('```' + $language)
                                [void]$sb.AppendLine($codeText)
                                [void]$sb.AppendLine('```')
                            }
                            'Quote' { [void]$sb.AppendLine('> ' + $element.Content.Text) }
                            default { [void]$sb.AppendLine([string]$element.Content) }
                        }
                    }
                    if ($slide.Notes) { [void]$sb.AppendLine(); [void]$sb.AppendLine('<!-- Notes: ' + $slide.Notes + ' -->') }
                    [void]$sb.AppendLine(); [void]$sb.AppendLine('---'); [void]$sb.AppendLine()
                }
                Set-Content -Path $targetPath -Value $sb.ToString()
            }
            'Html' {
                $slidesHtml = foreach ($slide in $Presentation.Slides) {
                    $body = foreach ($element in $slide.Elements) {
                        switch ($element.Type) {
                            'Bullet' { "<li>$([System.Net.WebUtility]::HtmlEncode([string]$element.Content))</li>" }
                            'Code' {
                                $codeText = if ($element.Content -is [System.Collections.IDictionary]) { [string]$element.Content['Code'] } else { [string]$element.Content.Code }
                                "<pre><code>$([System.Net.WebUtility]::HtmlEncode($codeText))</code></pre>"
                            }
                            'Quote' { "<blockquote><p>$([System.Net.WebUtility]::HtmlEncode($element.Content.Text))</p><footer>$([System.Net.WebUtility]::HtmlEncode($element.Content.Attribution))</footer></blockquote>" }
                            default { "<p>$([System.Net.WebUtility]::HtmlEncode([string]$element.Content))</p>" }
                        }
                    }
                    "<section class='slide'><h2>$([System.Net.WebUtility]::HtmlEncode($slide.Title))</h2>$($body -join '')</section>"
                }
                $html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset='utf-8' />
<title>$([System.Net.WebUtility]::HtmlEncode($Presentation.Title))</title>
<style>
body { font-family: system-ui, sans-serif; background: #111827; color: #f9fafb; margin: 0; padding: 2rem; }
.slide { background: #1f2937; border-radius: 12px; padding: 2rem; margin-bottom: 2rem; }
pre { background: #0f172a; padding: 1rem; overflow-x: auto; }
blockquote { border-left: 4px solid #60a5fa; margin: 1rem 0; padding-left: 1rem; }
</style>
</head>
<body>
<h1>$([System.Net.WebUtility]::HtmlEncode($Presentation.Title))</h1>
$($slidesHtml -join [Environment]::NewLine)
</body>
</html>
"@
                Set-Content -Path $targetPath -Value $html
            }
            'Psd1' {
                $data = ConvertTo-PresentationData -Presentation $Presentation
                $psd1 = ($data | ConvertTo-Json -Depth 20)
                $content = '@{' + [Environment]::NewLine + "    Json = @'" + [Environment]::NewLine + $psd1 + [Environment]::NewLine + "'@" + [Environment]::NewLine + '}' + [Environment]::NewLine
                Set-Content -Path $targetPath -Value $content
            }
            'Json' {
                $data = ConvertTo-PresentationData -Presentation $Presentation
                $json = $data | ConvertTo-Json -Depth 20
                Set-Content -Path $targetPath -Value $json
            }
        }
        Get-Item -Path $targetPath
    }
    catch {
        throw
    }
}
