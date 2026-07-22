function Split-TerminalLogicalRows {
    [CmdletBinding()]
    param([AllowNull()][string]$Text)

    $value = $Text ?? ''
    Assert-TerminalValidUtf16 -Value $value
    return ,([regex]::Split($value, '\r\n|\r|\n'))
}

function Format-WordWrap {
    [CmdletBinding()]
    param(
        [AllowNull()][string]$Text,
        [Parameter(Mandatory)][int]$Width,
        [ValidateSet('Wrap','Truncate','Scroll')][string]$OverflowBehavior = 'Wrap',
        [ValidateRange(0, [int]::MaxValue)][int]$StartColumn = 0
    )

    $Width = [Math]::Max(1, $Width)
    $text = Strip-AnsiSequences -Text ($Text ?? '')
    $paragraphs = Split-TerminalLogicalRows -Text $text
    $lines = [System.Collections.Generic.List[string]]::new()

    foreach ($paragraph in $paragraphs) {
        if ($paragraph.Length -eq 0) {
            $lines.Add('')
            continue
        }
        switch ($OverflowBehavior) {
            'Truncate' {
                $lines.Add((Limit-TextToCellWidth -Text $paragraph -Width $Width -StartColumn $StartColumn -PreserveTabs))
            }
            'Scroll' {
                foreach ($segment in (Split-TextByCellWidth -Text $paragraph -Width $Width -StartColumn $StartColumn -PreserveTabs)) { $lines.Add($segment) }
            }
            default {
                $words = [regex]::Split($paragraph, '(\s+)')
                $current = ''
                foreach ($word in $words) {
                    if ($word -eq '') { continue }
                    $candidate = if ($current) { "$current$word" } else { $word }
                    $candidateWidth = Measure-TextWidth -Text $candidate -StartColumn $StartColumn
                    if ($candidateWidth -le $Width) {
                        $current = $candidate
                        continue
                    }
                    if ($current) {
                        $lines.Add($current.TrimEnd())
                        $current = ''
                    }
                    $wordText = $word.Trim()
                    if ((Measure-TextWidth -Text $wordText -StartColumn $StartColumn) -le $Width) {
                        $current = $word.TrimStart()
                    }
                    else {
                        $segments = Split-TextByCellWidth -Text $wordText -Width $Width -StartColumn $StartColumn -PreserveTabs
                        for ($idx = 0; $idx -lt $segments.Count; $idx++) {
                            $segment = $segments[$idx]
                            if ($idx -lt $segments.Count - 1) {
                                $lines.Add($segment)
                            }
                            else {
                                $current = $segment
                            }
                        }
                    }
                }
                if ($current -or $paragraph -match '\s$') {
                    $lines.Add($current.TrimEnd())
                }
            }
        }
    }

    return ,$lines.ToArray()
}
