function New-TerminalSlidesDemoPresentation {
    $presentation = New-TerminalPresentation -Title 'TerminalSlides Feature Tour' -Subtitle 'A guided walkthrough of terminal-native presentations' -Author 'TerminalSlides' -Theme Midnight
    $photoPath = Join-Path $script:ModuleRoot 'Assets/presentation-team-photo.jpg'

    $presentation | Add-TerminalSlide -Title 'Welcome' -Content {
        Add-SlideTitle 'Present from the terminal'
        Add-SlideSubtitle 'Press Right to reveal each point'
        Add-SlideText 'TerminalSlides turns familiar PowerShell objects into a focused, keyboard-driven presentation.'
        Add-SlideBullet 'Build decks with PowerShell' -RevealStep 1
        Add-SlideBullet 'Reveal ideas at your pace' -RevealStep 2
        Add-SlideBullet 'Use Q or Escape to exit at any time' -RevealStep 3
        Add-SlideNotes 'Introduce the deck, then use Right Arrow to show incremental reveals.'
    } | Out-Null

    $presentation | Add-TerminalSlide -Title 'Code' -Content {
        Add-SlideCode -Language powershell -Border -Code @'
$deck = New-TerminalPresentation -Title 'Demo'
$deck | Add-TerminalSlide -Title 'Hello' -Content {
    Add-SlideText 'Built in PowerShell'
}
Show-TerminalPresentation -Presentation $deck
'@
    } | Out-Null

    $presentation | Add-TerminalSlide -Title 'Tables' -Content {
        Add-SlideTable -Border -Data @(
            [pscustomobject]@{ Feature = 'Text'; Purpose = 'Narrative and annotations' }
            [pscustomobject]@{ Feature = 'Code'; Purpose = 'Syntax-highlighted snippets' }
            [pscustomobject]@{ Feature = 'Data'; Purpose = 'Tables and charts' }
        )
    } | Out-Null

    $presentation | Add-TerminalSlide -Title 'Charts' -Content {
        Add-SlideChart -ChartType HorizontalBar -Title 'Build confidence' -Data @(
            [pscustomobject]@{ Label = 'Design'; Value = 35 }
            [pscustomobject]@{ Label = 'Data'; Value = 65 }
            [pscustomobject]@{ Label = 'Delivery'; Value = 90 }
        )
    } | Out-Null

    $presentation | Add-TerminalSlide -Title 'Diagrams' -Content {
        Add-SlideDiagram -Content {
            Add-SlideDiagramNode -Id 'idea' -Label 'Idea'
            Add-SlideDiagramNode -Id 'deck' -Label 'Deck'
            Add-SlideDiagramNode -Id 'terminal' -Label 'Terminal'
            Add-SlideDiagramEdge -From 'idea' -To 'deck' -Label 'compose'
            Add-SlideDiagramEdge -From 'deck' -To 'terminal' -Label 'present'
        }
    } | Out-Null

    $presentation | Add-TerminalSlide -Title 'Callouts and media' -Content {
        Add-SlideQuote -Text 'The best presentation tool is the one already in your workflow.' -Attribution 'TerminalSlides'
        Add-SlideBox -Text 'Use callout boxes to make a decision, warning, or takeaway impossible to miss.'
    } | Out-Null

    $presentation | Add-TerminalSlide -Title 'Visual storytelling' -Layout ImageFocus -Content {
        Add-SlideImage -Path $photoPath -AltText 'Three software engineers collaborating around a laptop during a presentation rehearsal.' -Region Image
    } | Out-Null

    $presentation | Add-TerminalSlide -Title 'Presentation controls' -Content {
        Add-SlideText 'Navigate with arrows, Space, N, PageUp, PageDown, Home, and End.'
        Add-SlideText 'Toggle notes, overview, blanking, timer, and help with S, O, B, T, and H.' -RevealStep 1
        Add-SlideBox -Text 'Try ? for the in-presentation control reference, then Q to return to PowerShell.' -RevealStep 2
    } | Out-Null

    return $presentation
}

function New-IntuneHydrationKitDemoPresentation {
    $presentation = New-TerminalPresentation `
        -Title 'Intune Hydration Kit' `
        -Subtitle 'Automate. Hydrate. Protect.' `
        -Author 'Jorgeasaurus' `
        -Description 'A guided tour of production-first Microsoft Intune tenant hydration.' `
        -Theme PowerShell `
        -Metadata @{ Showcase = 'IntuneHydrationKit'; SourceVersion = '1.2.0' }
    $tuiPath = Join-Path $script:ModuleRoot 'Assets/intune-hydration-kit-tui.png'

    $presentation | Add-TerminalSlide -Title 'Intune Hydration Kit' -Content {
        Add-SlideTitle 'Automate. Hydrate. Protect.'
        Add-SlideSubtitle 'Production-first Microsoft Intune tenant hydration'
        Add-SlideText 'Turn a deliberate workload plan into repeatable Microsoft Graph operations.'
        Add-SlideBullet 'Start with a guided terminal experience' -RevealStep 1
        Add-SlideBullet 'Move the same plan into repeatable automation' -RevealStep 2
        Add-SlideBullet 'Keep safety checks and evidence in every run' -RevealStep 3
        Add-SlideNotes 'Frame the kit as an orchestration layer: curated templates, guarded execution, and auditable results.'
    } | Out-Null

    $presentation | Add-TerminalSlide -Title 'One command. 1,000+ building blocks.' -Content {
        Add-SlideChart -ChartType HorizontalBar -Title 'Bundled, validated catalog' -Data @(
            [pscustomobject]@{ Label = 'CIS policies'; Value = 728 }
            [pscustomobject]@{ Label = 'Open baseline'; Value = 99 }
            [pscustomobject]@{ Label = 'Groups'; Value = 64 }
            [pscustomobject]@{ Label = 'Filters'; Value = 38 }
            [pscustomobject]@{ Label = 'Apps'; Value = 36 }
        )
        Add-SlideBox -Text 'Baselines, targeting, compliance, enrollment, apps, and access controls ship as a tested catalog.' -RevealStep 1
    } | Out-Null

    $presentation | Add-TerminalSlide -Title 'Install, then hydrate' -Layout CodeFocus -Content {
        Add-SlideCode -Language powershell -Border -Region Code -Code @'
Install-Module -Name IntuneHydrationKit -Scope CurrentUser

# Launch the guided terminal workflow.
Invoke-IntuneHydration

# Explore the complete public surface.
Get-Command -Module IntuneHydrationKit
Get-Help Invoke-IntuneHydration -Detailed
'@
    } | Out-Null

    $presentation | Add-TerminalSlide -Title 'Guided TUI, deliberate choices' -Layout ImageFocus -Content {
        Add-SlideImage `
            -Path $tuiPath `
            -AltText 'Intune Hydration Kit terminal review showing an obfuscated tenant, create operation, selected workloads, and confirmation prompt.' `
            -Region Image
        Add-SlideNotes 'The TUI reviews the cloud, operation, workloads, platforms, logging, and final confirmation before execution.'
    } | Out-Null

    $presentation | Add-TerminalSlide -Title 'Choose only what you need' -Content {
        Add-SlideTable -Border -Data @(
            [pscustomobject]@{ Area = 'Targeting'; Workloads = 'Dynamic groups, static groups, device filters' }
            [pscustomobject]@{ Area = 'Baselines'; Workloads = 'OpenIntuneBaseline, CIS baselines' }
            [pscustomobject]@{ Area = 'Endpoint'; Workloads = 'Compliance, app protection, enrollment' }
            [pscustomobject]@{ Area = 'Access'; Workloads = 'Conditional Access starter policies' }
            [pscustomobject]@{ Area = 'Apps'; Workloads = 'Mobile apps and WinGet Win32 apps' }
            [pscustomobject]@{ Area = 'Messaging'; Workloads = 'Notification templates' }
        )
        Add-SlideText 'Platform filters narrow supported workloads to Windows, macOS, iOS, Android, or Linux.' -RevealStep 1
    } | Out-Null

    $presentation | Add-TerminalSlide -Title 'Preview before Graph writes' -Layout CodeFocus -Content {
        Add-SlideCode -Language powershell -Border -Region Code -Code @'
Invoke-IntuneHydration `
    -TenantId '00000000-0000-0000-0000-000000000000' `
    -Interactive `
    -Create `
    -DeviceFilters `
    -Platform Windows `
    -WhatIf
'@
        Add-SlideNotes 'Dry-run create in the TUI follows the same preview path. Authentication and read-only prerequisite checks still run.'
    } | Out-Null

    $presentation | Add-TerminalSlide -Title 'Windows apps, ready for Intune' -Layout TwoColumn -Content {
        Add-SlideCode -Language powershell -Border -Region Left -Code @'
Import-IntuneWinGetApp `
    -PresetId 'starter-pack'

Import-IntuneWinGetApp `
    -TemplateId 'google-chrome'
'@
        Add-SlideBullet 'Builds .intunewin content without IntuneWinAppUtil.exe' -Region Right
        Add-SlideBullet 'Uses the bundled WinGet application catalog' -Region Right -RevealStep 1
        Add-SlideBullet 'Leaves generated remediations unassigned for review' -Region Right -RevealStep 2
        Add-SlideBox -Text 'Package once. Review assignments. Deploy intentionally.' -Region Right -RevealStep 3
    } | Out-Null

    $presentation | Add-TerminalSlide -Title 'Repeatable automation' -Layout TwoColumn -Content {
        Add-SlideCode -Language powershell -Border -Region Left -Code @'
Copy-Item `
    settings.example.json `
    settings.json

Invoke-IntuneHydration `
    -SettingsPath ./settings.json `
    -WhatIf
'@
        Add-SlideDiagram -Region Right -Content {
            Add-SlideDiagramNode -Id 'settings' -Label 'Plan'
            Add-SlideDiagramNode -Id 'engine' -Label 'Engine'
            Add-SlideDiagramNode -Id 'reports' -Label 'Reports'
            Add-SlideDiagramEdge -From 'settings' -To 'engine' -Label 'apply'
            Add-SlideDiagramEdge -From 'engine' -To 'reports' -Label 'record'
        }
    } | Out-Null

    $presentation | Add-TerminalSlide -Title 'Guardrails, not guesswork' -Content {
        Add-SlideBullet 'Idempotent imports skip existing configurations'
        Add-SlideBullet 'Dry-run and -WhatIf preview intended changes' -RevealStep 1
        Add-SlideBullet 'Cleanup targets only kit-owned objects' -RevealStep 2
        Add-SlideBullet 'Conditional Access starter policies are created disabled' -RevealStep 3
        Add-SlideBox -Text 'Test in a non-production tenant first. Review every selected workload before applying.' -RevealStep 4
    } | Out-Null

    $presentation | Add-TerminalSlide -Title 'Evidence at the finish line' -Content {
        Add-SlideTable -Border -Data @(
            [pscustomobject]@{ Evidence = 'Live status'; Purpose = 'Created, updated, skipped, previewed, or failed' }
            [pscustomobject]@{ Evidence = 'Detailed log'; Purpose = 'Operational audit trail and diagnostics' }
            [pscustomobject]@{ Evidence = 'Markdown'; Purpose = 'Human-readable hydration summary' }
            [pscustomobject]@{ Evidence = 'JSON'; Purpose = 'Machine-readable result processing' }
            [pscustomobject]@{ Evidence = 'Elapsed time'; Purpose = 'End-to-end execution duration' }
        )
        Add-SlideBox -Text 'First run: launch the TUI, choose Dry-run create, select Device Filters, then review.' -RevealStep 1
        Add-SlideNotes 'Close with the smallest safe first step, not an all-workloads production run.'
    } | Out-Null

    return $presentation
}

function Start-TerminalSlidesDemo {
    [CmdletBinding()]
    param(
        [ValidateSet('TerminalSlides', 'IntuneHydrationKit')]
        [string]$Name = 'TerminalSlides',
        [switch]$PassThru
    )

    $presentation = switch ($Name) {
        'IntuneHydrationKit' { New-IntuneHydrationKitDemoPresentation }
        default { New-TerminalSlidesDemoPresentation }
    }
    if ($PassThru) { return $presentation }

    Show-TerminalPresentation -Presentation $presentation
}
