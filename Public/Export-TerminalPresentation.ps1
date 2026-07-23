function Write-TerminalExportFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content,
        [Parameter(Mandatory)][bool]$Overwrite,
        [AllowNull()][object]$MediaTransaction
    )

    Assert-TerminalValidUtf16 -Value $Content
    $parent = Split-Path -Path $Path -Parent
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        [void][System.IO.Directory]::CreateDirectory($parent)
    }
    $temporaryPath = Join-Path $parent ('.' + [System.IO.Path]::GetFileName($Path) + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
    $assetBackup = $null
    try {
        [System.IO.File]::WriteAllText($temporaryPath, $Content, [System.Text.UTF8Encoding]::new($false))
        if ($MediaTransaction -and $MediaTransaction.HasAssets) {
            $assetBackup = Install-TerminalStagedAssets -Transaction $MediaTransaction
        }
        try {
            [System.IO.File]::Move($temporaryPath, $Path, $Overwrite)
        }
        catch {
            if ($MediaTransaction -and $MediaTransaction.HasAssets -and
                (Test-Path -LiteralPath $MediaTransaction.FinalDirectory)) {
                Remove-Item -LiteralPath $MediaTransaction.FinalDirectory -Recurse -Force -ErrorAction SilentlyContinue
            }
            if ($assetBackup -and (Test-Path -LiteralPath $assetBackup)) {
                Move-Item -LiteralPath $assetBackup -Destination $MediaTransaction.FinalDirectory
                $assetBackup = $null
            }
            throw
        }
        if ($assetBackup -and (Test-Path -LiteralPath $assetBackup)) {
            Remove-Item -LiteralPath $assetBackup -Recurse -Force
            $assetBackup = $null
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
        if ($MediaTransaction -and $MediaTransaction.StagingDirectory -and
            (Test-Path -LiteralPath $MediaTransaction.StagingDirectory)) {
            Remove-Item -LiteralPath $MediaTransaction.StagingDirectory -Recurse -Force -ErrorAction SilentlyContinue
        }
        if ($assetBackup -and (Test-Path -LiteralPath $assetBackup) -and -not (Test-Path -LiteralPath $MediaTransaction.FinalDirectory)) {
            Move-Item -LiteralPath $assetBackup -Destination $MediaTransaction.FinalDirectory -ErrorAction SilentlyContinue
        }
    }
}

function Export-TerminalPresentation {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)][TerminalSlides.Schema.V1.TerminalPresentation]$Presentation,
        [Parameter(Mandatory)][string]$Path,
        [ValidateSet('Ansi','PlainText','Markdown','Html','Psd1','Json')][string]$Format = 'PlainText',
        [switch]$Force
    )

    $targetPath = [System.IO.Path]::GetFullPath($Path, (Get-Location).Path)
    $exists = Test-Path -LiteralPath $targetPath -PathType Leaf
    if ($exists -and -not $Force) {
        throw "Path '$targetPath' already exists. Use -Force to overwrite it."
    }
    if (-not $PSCmdlet.ShouldProcess($targetPath, "Export presentation as $Format")) { return }

    $visiblePresentation = New-TerminalPresentationView -Presentation $Presentation
    $portableFormats = @('Markdown','Html','Psd1','Json')
    $portableExport = if ($Format -in $portableFormats) {
        New-TerminalPortableExport -Presentation $visiblePresentation -TargetPath $targetPath -Overwrite:$Force.IsPresent
    }
    else { [pscustomobject]@{ Presentation = $visiblePresentation; Transaction = $null } }
    $exportPresentation = $portableExport.Presentation
    $slides = @($exportPresentation.Slides)
    try {
        $content = switch ($Format) {
        'Ansi' {
            $rendered = foreach ($slide in $slides) {
                Render-TerminalPresentationToString -Presentation $exportPresentation -SlideIndex ($slide.Index - 1) -RevealStep (Get-TerminalSlideMaximumRevealStep -Slide $slide)
            }
            $rendered -join ([Environment]::NewLine + [Environment]::NewLine + ('-' * 40) + [Environment]::NewLine)
        }
        'PlainText' {
            $rendered = foreach ($slide in $slides) {
                Render-TerminalPresentationToString -Presentation $exportPresentation -SlideIndex ($slide.Index - 1) -RevealStep (Get-TerminalSlideMaximumRevealStep -Slide $slide) -PlainText
            }
            $rendered -join ("`n" + ('-' * 40) + "`n")
        }
        'Markdown' {
            $visibleDocument = ConvertTo-TerminalMarkdownDocument $exportPresentation
            $presentationData = ConvertTo-PresentationData -Presentation $exportPresentation
            $marker = [ordered]@{
                MarkerVersion = 2
                ProjectionHash = Get-TerminalMarkdownProjectionHash -VisibleDocument $visibleDocument -PresentationData $presentationData
                Presentation = $presentationData
            }
            $visibleDocument + '<!-- terminalslides:envelope ' + (ConvertTo-TerminalDataMarker $marker) + ' -->'
        }
        'Html' {
            $encode = { param($Value) ConvertTo-TerminalHtmlEncodedText -Value $Value }
            $style = ConvertTo-TerminalHtmlStyle (Resolve-TerminalPresentationTheme -Presentation $exportPresentation)
            $slidesHtml = foreach ($slide in $slides) {
                $body = foreach ($element in $slide.Elements) { ConvertTo-TerminalHtmlElement -Element $element }
                '<section class="slide"><h2>' + (& $encode $slide.Title) + '</h2>' + ($body -join '') + '</section>'
            }
            @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>$(& $encode $Presentation.Title)</title>
<style>
$style
</style>
</head>
<body>
<h1>$(& $encode $Presentation.Title)</h1>
$($slidesHtml -join [Environment]::NewLine)
</body>
</html>
"@
        }
        'Psd1' {
            $data = ConvertTo-PresentationData -Presentation $exportPresentation
            $marker = ConvertTo-TerminalDataMarker -Data $data
            "@{ TerminalSlidesEnvelope = '$marker' }" + [Environment]::NewLine
        }
        'Json' { ConvertTo-TerminalWireJson (ConvertTo-PresentationData -Presentation $exportPresentation) }
        }

        Write-TerminalExportFile -Path $targetPath -Content ([string]$content) -Overwrite:$Force.IsPresent -MediaTransaction $portableExport.Transaction
    }
    finally {
        if ($portableExport.Transaction -and $portableExport.Transaction.StagingDirectory -and
            (Test-Path -LiteralPath $portableExport.Transaction.StagingDirectory)) {
            Remove-Item -LiteralPath $portableExport.Transaction.StagingDirectory -Recurse -Force -ErrorAction SilentlyContinue
        }
        if ($portableExport.Transaction) {
            Remove-TerminalCreatedDirectoriesIfEmpty `
                -Paths ([string[]]@($portableExport.Transaction.CreatedTargetDirectories))
        }
    }
    Get-Item -LiteralPath $targetPath
}
