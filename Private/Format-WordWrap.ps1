function Format-WordWrap {
    [CmdletBinding()]
    param(
        [AllowNull()][string]$Text,
        [Parameter(Mandatory)][int]$Width,
        [ValidateSet('Wrap','Truncate','Scroll')][string]$OverflowBehavior = 'Wrap'
    )

    $Width = [Math]::Max(1, $Width)
    $text = ($Text ?? '') -replace "`r", ''
    $paragraphs = $text -split "`n", -1
    $lines = [System.Collections.Generic.List[string]]::new()

    foreach ($paragraph in $paragraphs) {
        if ($paragraph.Length -eq 0) {
            $lines.Add('')
            continue
        }
        switch ($OverflowBehavior) {
            'Truncate' {
                $plain = Strip-AnsiSequences -Text $paragraph
                $lines.Add($plain.Substring(0, [Math]::Min($plain.Length, $Width)))
            }
            'Scroll' {
                $plain = Strip-AnsiSequences -Text $paragraph
                for ($i = 0; $i -lt $plain.Length; $i += $Width) {
                    $lines.Add($plain.Substring($i, [Math]::Min($Width, $plain.Length - $i)))
                }
            }
            default {
                $words = [regex]::Split($paragraph, '(\s+)')
                $current = ''
                foreach ($word in $words) {
                    if ($word -eq '') { continue }
                    $candidate = if ($current) { "$current$word" } else { $word }
                    $candidateWidth = Measure-TextWidth -Text $candidate
                    if ($candidateWidth -le $Width) {
                        $current = $candidate
                        continue
                    }
                    if ($current) {
                        $lines.Add($current.TrimEnd())
                        $current = ''
                    }
                    $wordText = $word.Trim()
                    if ((Measure-TextWidth -Text $wordText) -le $Width) {
                        $current = $word.TrimStart()
                    }
                    else {
                        $plainWord = Strip-AnsiSequences -Text $wordText
                        for ($idx = 0; $idx -lt $plainWord.Length; $idx += $Width) {
                            $segment = $plainWord.Substring($idx, [Math]::Min($Width, $plainWord.Length - $idx))
                            if ($segment.Length -eq $Width) {
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
