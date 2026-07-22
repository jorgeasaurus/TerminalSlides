using namespace System.Collections.Generic

$script:ModuleRoot = $PSScriptRoot
$script:Themes = @{}
$script:Capabilities = $null

. (Join-Path $PSScriptRoot 'Classes/TerminalSlidesClasses.ps1')

$privateFiles = @(
    'Private/Get-AnsiSequence.ps1'
    'Private/TerminalTextBoundary.ps1'
    'Private/Measure-TextWidth.ps1'
    'Private/PresentationSemantics.ps1'
    'Private/PresentationWireCodec.ps1'
    'Private/PresentationWireValidation.ps1'
    'Private/PresentationWireParser.ps1'
    'Private/PresentationMedia.ps1'
    'Private/PresentationExportCodecs.ps1'
    'Private/PresentationMarkdownEnvelope.ps1'
    'Private/Format-WordWrap.ps1'
    'Private/Get-SyntaxHighlight.ps1'
    'Private/Invoke-SafeScriptBlock.ps1'
    'Private/ConvertFrom-AnsiString.ps1'
    'Private/BuildContext.ps1'
)
foreach ($file in $privateFiles) { . (Join-Path $PSScriptRoot $file) }

function New-ThemeDefinitionFromHashtable {
    param([hashtable]$Definition)
    $theme = [TerminalSlides.Schema.V1.ThemeDefinition]::new()
    foreach ($key in $Definition.Keys) {
        if ($theme.PSObject.Properties.Name -contains $key) {
            $theme.$key = $Definition[$key]
        }
        else {
            if (-not $theme.Metadata) { $theme.Metadata = @{} }
            $theme.Metadata[$key] = $Definition[$key]
        }
    }
    if (-not $theme.Metadata) { $theme.Metadata = @{} }
    if (-not $theme.CodeTheme) { $theme.CodeTheme = 'Default' }
    if (-not $theme.BulletSymbol) { $theme.BulletSymbol = '•' }
    if (-not $theme.ChartPalette) { $theme.ChartPalette = @($theme.Primary, $theme.Accent, $theme.Foreground) }
    return $theme
}

function Initialize-TerminalSlidesThemes {
    $themePath = Join-Path $PSScriptRoot 'Themes'
    Get-ChildItem -Path $themePath -Filter '*.psd1' | ForEach-Object {
        $data = Import-PowerShellDataFile -Path $_.FullName
        $theme = New-ThemeDefinitionFromHashtable -Definition $data
        $script:Themes[$theme.Name] = $theme
    }
}

function Get-ResolvedTheme {
    param([string]$Name)
    if (-not $script:Themes.Count) { Initialize-TerminalSlidesThemes }
    if (-not $Name) { $Name = 'Midnight' }
    if (-not $script:Themes.ContainsKey($Name)) {
        throw "Theme '$Name' was not found."
    }
    return $script:Themes[$Name]
}

function Add-CurrentSlideElement {
    param([TerminalSlides.Schema.V1.SlideElement]$Element)
    $context = Get-TerminalSlidesBuildContext -Kind Slide
    if ($null -eq $context) {
        return $Element
    }
    if (-not $Element.Id) { $Element.Id = [guid]::NewGuid().ToString() }
    $context.Elements.Add($Element)
}

function New-InternalSlideElement {
    param(
        [Parameter(Mandatory)][TerminalSlides.Schema.V1.ElementKind]$Kind,
        [Parameter(Mandatory)][TerminalSlides.Schema.V1.ElementPayload]$Payload,
        [string]$Region = 'Content',
        [string]$Alignment = 'Left',
        [string]$VerticalAlignment = 'Top',
        [int]$Padding = 0,
        [string]$ForegroundColor,
        [string]$BackgroundColor,
        [switch]$Border,
        [string]$BorderStyle = 'single',
        [int]$RevealStep = 0,
        [string]$OverflowBehavior = 'Wrap',
        [int]$X = 0,
        [int]$Y = 0,
        [int]$Width = 0,
        [int]$Height = 0
    )
    $element = [TerminalSlides.Schema.V1.SlideElement]::new($Kind, $Payload)
    $element.Region = $Region
    $element.Alignment = $Alignment
    $element.VerticalAlignment = $VerticalAlignment
    $element.Padding = $Padding
    $element.ForegroundColor = $ForegroundColor
    $element.BackgroundColor = $BackgroundColor
    $element.Border = $Border.IsPresent
    $element.BorderStyle = $BorderStyle
    $element.RevealStep = $RevealStep
    $element.OverflowBehavior = $OverflowBehavior
    $element.X = $X
    $element.Y = $Y
    $element.Width = $Width
    $element.Height = $Height
    return $element
}

function Update-SlideIndices {
    param([TerminalSlides.Schema.V1.TerminalPresentation]$Presentation)
    for ($i = 0; $i -lt $Presentation.Slides.Count; $i++) {
        $Presentation.Slides[$i].Index = $i + 1
    }
    $Presentation.ModifiedDate = [datetime]::UtcNow
}

. (Join-Path $PSScriptRoot 'Renderers/FrameBuffer.ps1')
. (Join-Path $PSScriptRoot 'Renderers/AnsiRenderer.ps1')
. (Join-Path $PSScriptRoot 'Layouts/LayoutEngine.ps1')

$publicFiles = Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1' | Sort-Object Name
foreach ($file in $publicFiles) { . $file.FullName }

Initialize-TerminalSlidesThemes
$script:Capabilities = Get-TerminalPresentationCapability
$manifest = Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'TerminalSlides.psd1')
Export-ModuleMember -Function $manifest.FunctionsToExport
