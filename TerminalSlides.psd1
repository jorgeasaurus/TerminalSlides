@{
    RootModule = 'TerminalSlides.psm1'
    ModuleVersion = '0.1.0'
    GUID = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author = 'Jorge'
    CompanyName = 'TerminalSlides'
    Copyright = '(c) 2024 Jorge. All rights reserved.'
    Description = 'A PowerShell module for building and delivering terminal-based slide presentations'
    PowerShellVersion = '7.4'
    RequiredAssemblies = @('lib/TerminalSlides.Schema.dll')
    RequiredModules = @(
        @{ ModuleName = 'PwshSpectreConsole'; RequiredVersion = '2.6.3' }
    )
    FunctionsToExport = @(
        'New-TerminalPresentation'
        'Add-TerminalSlide'
        'Add-SlideText'
        'Add-SlideTitle'
        'Add-SlideSubtitle'
        'Add-SlideBullet'
        'Add-SlideCode'
        'Add-SlideTable'
        'Add-SlideChart'
        'Add-SlideDiagram'
        'Add-SlideDiagramNode'
        'Add-SlideDiagramEdge'
        'Add-SlideImage'
        'Add-SlideQuote'
        'Add-SlideBox'
        'Add-SlideNotes'
        'Show-TerminalPresentation'
        'Start-TerminalSlidesDemo'
        'Export-TerminalPresentation'
        'Import-TerminalPresentation'
        'Get-TerminalPresentationTheme'
        'New-TerminalPresentationTheme'
        'Test-TerminalPresentation'
        'Get-TerminalPresentationCapability'
        'Set-TerminalSlide'
        'Remove-TerminalSlide'
        'Copy-TerminalSlide'
        'Move-TerminalSlide'
        'Get-TerminalSlide'
    )
    PrivateData = @{
        PSData = @{
            Tags = @('presentation','terminal','slides','ansi','cross-platform')
            LicenseUri = 'https://github.com/jorgeasaurus/TerminalSlides/blob/main/LICENSE'
            ProjectUri = 'https://github.com/jorgeasaurus/TerminalSlides'
        }
    }
}
