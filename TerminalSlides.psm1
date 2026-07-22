using namespace System.Collections.Generic

$script:ModuleRoot = $PSScriptRoot
$script:TerminalSlidesState = @{
    CurrentSlideElements = $null
    CurrentSlideContext  = $null
}
$script:Themes = @{}
$script:Capabilities = $null

# Load the data classes from a compiled assembly. Classes defined in dot-sourced
# .ps1 files are emitted into a per-import dynamic "PowerShell Class Assembly";
# after Import-Module -Force (or Remove-Module + Import-Module) objects created
# earlier no longer satisfy [TerminalPresentation] parameter binding and throw
# "Cannot convert the value of type TerminalPresentation to type
# TerminalPresentation". A compiled assembly keeps one stable identity, so
# presentations always bind across re-imports.
$dataClassesPath = Join-Path $PSScriptRoot 'Classes/TerminalSlides.DataClasses.cs'
if (-not ('TerminalPresentation' -as [type])) {
    Add-Type -Path $dataClassesPath -ReferencedAssemblies @(
        'System.Collections'
    )
}

. (Join-Path $PSScriptRoot 'Classes/TerminalSlidesClasses.ps1')

$privateFiles = @(
    'Private/Get-AnsiSequence.ps1'
    'Private/Measure-TextWidth.ps1'
    'Private/Format-WordWrap.ps1'
    'Private/Get-SyntaxHighlight.ps1'
    'Private/Invoke-SafeScriptBlock.ps1'
    'Private/ConvertFrom-AnsiString.ps1'
)
foreach ($file in $privateFiles) { . (Join-Path $PSScriptRoot $file) }

function New-ThemeDefinitionFromHashtable {
    param([hashtable]$Definition)
    $theme = [ThemeDefinition]::new()
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
    param([SlideElement]$Element)
    $elements = Get-TerminalSlidesStateValue -Name CurrentSlideElements
    if (-not $elements) {
        return $Element
    }
    if (-not $Element.Id) { $Element.Id = [guid]::NewGuid().ToString() }
    $elements.Add($Element)
    $context = Get-TerminalSlidesStateValue -Name CurrentSlideContext
    if ($Element.RevealStep -gt ($context.MaxRevealStep ?? 0)) {
        $context.MaxRevealStep = $Element.RevealStep
        Set-TerminalSlidesStateValue -Name CurrentSlideContext -Value $context
    }
}

function Set-TerminalSlidesStateValue {
    param(
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()]$Value
    )
    $script:TerminalSlidesState[$Name] = $Value
}

function Get-TerminalSlidesStateValue {
    param([Parameter(Mandatory)][string]$Name)
    # Write-Object with -NoEnumerate prevents empty collections (e.g., a fresh
    # diagram node list) from being unrolled to $null on return.
    ,$script:TerminalSlidesState[$Name] | Write-Output -NoEnumerate
}

function New-InternalSlideElement {
    param(
        [Parameter(Mandatory)][string]$Type,
        [Parameter(Mandatory)][object]$Content,
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
        [hashtable]$Style = @{},
        [hashtable]$Properties = @{},
        [int]$X = 0,
        [int]$Y = 0,
        [int]$Width = 0,
        [int]$Height = 0
    )
    $element = [SlideElement]::new()
    $element.Id = [guid]::NewGuid().ToString()
    $element.Type = $Type
    $element.Content = $Content
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
    $element.Style = $Style
    $element.Properties = $Properties
    $element.X = $X
    $element.Y = $Y
    $element.Width = $Width
    $element.Height = $Height
    return $element
}

function Update-SlideIndices {
    param([TerminalPresentation]$Presentation)
    for ($i = 0; $i -lt $Presentation.Slides.Count; $i++) {
        $Presentation.Slides[$i].Index = $i + 1
    }
    $Presentation.ModifiedDate = [datetime]::UtcNow
}

function ConvertTo-PresentationData {
    param([TerminalPresentation]$Presentation)
    return [ordered]@{
        Title = $Presentation.Title
        Subtitle = $Presentation.Subtitle
        Author = $Presentation.Author
        Description = $Presentation.Description
        Theme = $Presentation.Theme
        Width = $Presentation.Width
        Height = $Presentation.Height
        DefaultTransition = $Presentation.DefaultTransition
        DefaultLayout = $Presentation.DefaultLayout
        CreatedDate = $Presentation.CreatedDate.ToString('o')
        ModifiedDate = $Presentation.ModifiedDate.ToString('o')
        Metadata = [ordered]@{
            Title = $Presentation.Metadata.Title
            Subtitle = $Presentation.Metadata.Subtitle
            Author = $Presentation.Metadata.Author
            Description = $Presentation.Metadata.Description
            Version = $Presentation.Metadata.Version
            Custom = $Presentation.Metadata.Custom
        }
        Configuration = $Presentation.Configuration
        Slides = @(
            foreach ($slide in $Presentation.Slides) {
                [ordered]@{
                    Id = $slide.Id
                    Index = $slide.Index
                    Title = $slide.Title
                    Layout = $slide.Layout
                    Notes = $slide.Notes
                    Background = $slide.Background
                    Transition = $slide.Transition
                    Hidden = $slide.Hidden
                    MaxRevealStep = $slide.MaxRevealStep
                    Metadata = [ordered]@{
                        Author = $slide.Metadata.Author
                        Custom = $slide.Metadata.Custom
                    }
                    Elements = @(
                        foreach ($element in $slide.Elements) {
                            [ordered]@{
                                Id = $element.Id
                                Type = $element.Type
                                Content = $element.Content
                                Region = $element.Region
                                X = $element.X
                                Y = $element.Y
                                Width = $element.Width
                                Height = $element.Height
                                Alignment = $element.Alignment
                                VerticalAlignment = $element.VerticalAlignment
                                Padding = $element.Padding
                                ForegroundColor = $element.ForegroundColor
                                BackgroundColor = $element.BackgroundColor
                                Border = $element.Border
                                BorderStyle = $element.BorderStyle
                                Style = $element.Style
                                RevealStep = $element.RevealStep
                                OverflowBehavior = $element.OverflowBehavior
                                Properties = $element.Properties
                            }
                        }
                    )
                }
            }
        )
    }
}

function New-PresentationFromData {
    param([hashtable]$Data)
    $presentation = [TerminalPresentation]::new()
    foreach ($key in 'Title','Subtitle','Author','Description','Theme','Width','Height','DefaultTransition','DefaultLayout','Configuration') {
        if ($Data.ContainsKey($key)) { $presentation.$key = $Data[$key] }
    }
    if ($Data.ContainsKey('CreatedDate')) { $presentation.CreatedDate = [datetime]::Parse($Data.CreatedDate) }
    $importedModifiedDate = $null
    if ($Data.ContainsKey('ModifiedDate') -and $Data.ModifiedDate) { $importedModifiedDate = [datetime]::Parse($Data.ModifiedDate) }
    if ($Data.ContainsKey('Metadata') -and $Data.Metadata) {
        foreach ($key in 'Title','Subtitle','Author','Description','Version','Custom') {
            if ($Data.Metadata.ContainsKey($key)) { $presentation.Metadata.$key = $Data.Metadata[$key] }
        }
    }
    foreach ($slideData in @($Data.Slides ?? @())) {
        $slide = [Slide]::new()
        foreach ($key in 'Id','Index','Title','Layout','Notes','Background','Transition','Hidden','MaxRevealStep') {
            if ($slideData.ContainsKey($key)) { $slide.$key = $slideData[$key] }
        }
        if ($slideData.ContainsKey('Metadata') -and $slideData.Metadata) {
            foreach ($key in 'Author','Custom') {
                if ($slideData.Metadata.ContainsKey($key)) { $slide.Metadata.$key = $slideData.Metadata[$key] }
            }
        }
        foreach ($elementData in @($slideData.Elements ?? @())) {
            $element = [SlideElement]::new()
            foreach ($key in 'Id','Type','Content','Region','X','Y','Width','Height','Alignment','VerticalAlignment','Padding','ForegroundColor','BackgroundColor','Border','BorderStyle','Style','RevealStep','OverflowBehavior','Properties') {
                if ($elementData.ContainsKey($key)) { $element.$key = $elementData[$key] }
            }
            $slide.Elements.Add($element)
        }
        $presentation.Slides.Add($slide)
    }
    Update-SlideIndices -Presentation $presentation
    if ($importedModifiedDate) { $presentation.ModifiedDate = $importedModifiedDate }
    return $presentation
}

. (Join-Path $PSScriptRoot 'Renderers/FrameBuffer.ps1')
. (Join-Path $PSScriptRoot 'Renderers/AnsiRenderer.ps1')
. (Join-Path $PSScriptRoot 'Layouts/LayoutEngine.ps1')

$publicFiles = Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1' | Sort-Object Name
foreach ($file in $publicFiles) { . $file.FullName }

Initialize-TerminalSlidesThemes
$script:Capabilities = Get-TerminalPresentationCapability
Export-ModuleMember -Function @(
    'New-TerminalPresentation','Add-TerminalSlide','Add-SlideText','Add-SlideTitle','Add-SlideSubtitle','Add-SlideBullet','Add-SlideCode','Add-SlideTable','Add-SlideChart','Add-SlideDiagram','Node','Edge','Add-SlideImage','Add-SlideQuote','Add-SlideBox','Add-SlideNotes','Show-TerminalPresentation','Export-TerminalPresentation','Import-TerminalPresentation','Get-TerminalPresentationTheme','New-TerminalPresentationTheme','Test-TerminalPresentation','Get-TerminalPresentationCapability','Set-TerminalSlide','Remove-TerminalSlide','Copy-TerminalSlide','Move-TerminalSlide','Get-TerminalSlide'
)
