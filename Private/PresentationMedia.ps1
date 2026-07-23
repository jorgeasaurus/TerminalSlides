function Resolve-TerminalImagePath {
    param([Parameter(Mandatory)][TerminalSlides.Schema.V1.SlideElement]$Element)

    if ($Element.Kind -ne [TerminalSlides.Schema.V1.ElementKind]::Image) { throw 'Only image elements have media paths.' }
    $path = $Element.Payload.Path
    if ([IO.Path]::IsPathRooted($path)) { return [IO.Path]::GetFullPath($path) }
    $origin = Get-TerminalMediaOrigin $Element
    if (-not $origin) { throw "Relative image '$path' has no source origin." }
    return [IO.Path]::GetFullPath((Join-Path $origin $path))
}

function Copy-TerminalElementWithPayload {
    param(
        [Parameter(Mandatory)][TerminalSlides.Schema.V1.SlideElement]$Element,
        [Parameter(Mandatory)][TerminalSlides.Schema.V1.ElementPayload]$Payload
    )

    $copy = [TerminalSlides.Schema.V1.SlideElement]::new($Element.Kind, $Payload)
    foreach ($property in 'Id','Region','X','Y','Width','Height','Alignment','VerticalAlignment','Padding','ForegroundColor','BackgroundColor','Border','BorderStyle','RevealStep','OverflowBehavior') {
        $copy.$property = $Element.$property
    }
    return $copy
}

function Add-TerminalPortableAsset {
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$StagingDirectory
    )

    $snapshotPath = Join-Path $StagingDirectory ('.asset-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        Copy-Item -LiteralPath $SourcePath -Destination $snapshotPath
        $hash = (Get-FileHash -LiteralPath $snapshotPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $extension = [IO.Path]::GetExtension($SourcePath).ToLowerInvariant()
        $fileName = $hash + $extension
        $destinationPath = Join-Path $StagingDirectory $fileName
        if (-not (Test-Path -LiteralPath $destinationPath -PathType Leaf)) {
            [IO.File]::Move($snapshotPath, $destinationPath)
        }
        return $fileName
    }
    finally {
        if (Test-Path -LiteralPath $snapshotPath) {
            Remove-Item -LiteralPath $snapshotPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-TerminalMissingDirectoryChain {
    param([Parameter(Mandatory)][string]$Path)

    $missing = [Collections.Generic.List[string]]::new()
    $directory = [IO.DirectoryInfo]::new([IO.Path]::GetFullPath($Path))
    while (-not $directory.Exists) {
        $missing.Add($directory.FullName)
        $directory = $directory.Parent
    }
    return $missing.ToArray()
}

function Remove-TerminalCreatedDirectoriesIfEmpty {
    param([Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Paths)

    foreach ($path in $Paths) {
        if (-not (Test-Path -LiteralPath $path -PathType Container)) { continue }
        try { [IO.Directory]::Delete($path, $false) }
        catch [IO.IOException] { }
        catch [UnauthorizedAccessException] { }
    }
}

function Move-TerminalDirectoryAtomically {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )

    [IO.Directory]::Move($Source, $Destination)
}

function Install-TerminalStagedAssets {
    param([Parameter(Mandatory)][object]$Transaction)

    $backup = $null
    if (Test-Path -LiteralPath $Transaction.FinalDirectory) {
        if (-not $Transaction.ReplaceExistingAssets) {
            throw "Asset path '$($Transaction.FinalDirectory)' already exists. Use -Force to overwrite it."
        }
        $backup = $Transaction.FinalDirectory + '.' + [guid]::NewGuid().ToString('N') + '.backup'
        Move-Item -LiteralPath $Transaction.FinalDirectory -Destination $backup
    }
    try {
        Move-TerminalDirectoryAtomically -Source $Transaction.StagingDirectory -Destination $Transaction.FinalDirectory
    }
    catch {
        if ($backup) {
            if (Test-Path -LiteralPath $Transaction.FinalDirectory) {
                Remove-Item -LiteralPath $Transaction.FinalDirectory -Recurse -Force -ErrorAction SilentlyContinue
            }
            if (Test-Path -LiteralPath $backup) {
                Move-Item -LiteralPath $backup -Destination $Transaction.FinalDirectory
            }
        }
        throw
    }
    return $backup
}

function New-TerminalPortableExport {
    param(
        [Parameter(Mandatory)][TerminalSlides.Schema.V1.TerminalPresentation]$Presentation,
        [Parameter(Mandatory)][string]$TargetPath,
        [Parameter(Mandatory)][bool]$Overwrite
    )

    $targetDirectory = Split-Path -Parent $TargetPath
    $createdTargetDirectories = @(Get-TerminalMissingDirectoryChain -Path $targetDirectory)
    $assetDirectoryName = [IO.Path]::GetFileName($TargetPath) + '.assets'
    $assetDirectory = Join-Path $targetDirectory $assetDirectoryName
    $imageElements = @($Presentation.Slides.Elements | Where-Object Kind -eq Image)
    $hasAssets = $imageElements.Count -gt 0
    $stagingDirectory = if ($hasAssets) {
        Join-Path $targetDirectory ('.' + $assetDirectoryName + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
    }
    else { $null }

    if ($hasAssets -and (Test-Path -LiteralPath $assetDirectory) -and -not $Overwrite) {
        throw "Asset path '$assetDirectory' already exists. Use -Force to overwrite it."
    }

    try {
        [void][IO.Directory]::CreateDirectory($targetDirectory)
        if ($hasAssets) {
            [void][IO.Directory]::CreateDirectory($stagingDirectory)
            foreach ($slide in $Presentation.Slides) {
                for ($index = 0; $index -lt $slide.Elements.Count; $index++) {
                    $element = $slide.Elements[$index]
                    if ($element.Kind -ne [TerminalSlides.Schema.V1.ElementKind]::Image) { continue }

                    $sourcePath = Resolve-TerminalImagePath $element
                    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
                        throw "Image '$($element.Payload.Path)' was not found at '$sourcePath'."
                    }
                    $fileName = Add-TerminalPortableAsset -SourcePath $sourcePath -StagingDirectory $stagingDirectory

                    $portablePath = ($assetDirectoryName + '/' + $fileName).Replace('\', '/')
                    $portable = Copy-TerminalElementWithPayload -Element $element -Payload (
                        [TerminalSlides.Schema.V1.ImagePayload]::new($portablePath, $element.Payload.AltText)
                    )
                    Set-TerminalMediaOrigin -Element $portable -Directory $targetDirectory
                    $slide.Elements[$index] = $portable
                }
            }
        }
        return [pscustomobject]@{
            Presentation = $Presentation
            Transaction = [pscustomobject]@{
                StagingDirectory = $stagingDirectory
                FinalDirectory = $assetDirectory
                HasAssets = $hasAssets
                ReplaceExistingAssets = $Overwrite
                CreatedTargetDirectories = $createdTargetDirectories
            }
        }
    }
    catch {
        if ($stagingDirectory) {
            Remove-Item -LiteralPath $stagingDirectory -Recurse -Force -ErrorAction SilentlyContinue
        }
        Remove-TerminalCreatedDirectoriesIfEmpty -Paths $createdTargetDirectories
        throw
    }
}

function ConvertTo-TerminalMarkdownImageAlt {
    param([AllowNull()][string]$Text)
    return ([string]$Text).Replace('\', '\\').Replace(']', '\]')
}

function ConvertTo-TerminalMarkdownImageDestination {
    param([Parameter(Mandatory)][string]$Path)

    $normalized = $Path.Replace('\', '/')
    $encoded = ($normalized -split '/' | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/'
    return '<' + $encoded.Replace('>', '%3E').Replace('<', '%3C') + '>'
}
