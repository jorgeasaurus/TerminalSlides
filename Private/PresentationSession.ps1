function New-TerminalPresentationSession {
    [OutputType([pscustomobject])]
    param()

    return [pscustomobject]@{
        SlideIndex   = 0
        RevealStep   = 0
        ShowNotes    = $false
        DisplayMode  = 'Slide'
        ShowTimer    = $false
        IsRunning    = $true
    }
}

function ConvertTo-TerminalPresentationAction {
    param([Parameter(Mandatory)][ConsoleKeyInfo]$Key)

    $action = switch ($Key.Key) {
        { $_ -in @([ConsoleKey]::RightArrow, [ConsoleKey]::Spacebar, [ConsoleKey]::N) } { 'NextStep'; break }
        ([ConsoleKey]::PageDown) { 'NextSlide'; break }
        { $_ -in @([ConsoleKey]::LeftArrow, [ConsoleKey]::Backspace, [ConsoleKey]::P) } { 'PreviousStep'; break }
        ([ConsoleKey]::PageUp) { 'PreviousSlide'; break }
        ([ConsoleKey]::Home) { 'FirstSlide'; break }
        ([ConsoleKey]::End) { 'LastSlide'; break }
        ([ConsoleKey]::S) { 'ToggleNotes'; break }
        ([ConsoleKey]::O) { 'ToggleOverview'; break }
        ([ConsoleKey]::B) { 'ToggleBlank'; break }
        ([ConsoleKey]::T) { 'ToggleTimer'; break }
        ([ConsoleKey]::H) { 'ToggleHelp'; break }
        ([ConsoleKey]::Escape) { 'Quit'; break }
        default {
            switch ($Key.KeyChar) {
                '?' { 'ToggleHelp'; break }
                { $_ -in @('q', 'Q') } { 'Quit'; break }
                default { 'None' }
            }
        }
    }
    return $action
}

function Invoke-TerminalPresentationAction {
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][pscustomobject]$Session,
        [Parameter(Mandatory)][ValidateSet('None','NextStep','NextSlide','PreviousStep','PreviousSlide','FirstSlide','LastSlide','ToggleNotes','ToggleOverview','ToggleHelp','ToggleBlank','ToggleTimer','Quit')][string]$Action,
        [Parameter(Mandatory)][TerminalSlides.Schema.V1.TerminalPresentation]$Presentation
    )

    if ($Session.DisplayMode -notin @('Slide', 'Overview', 'Help', 'Blank')) {
        throw "Unknown presentation display mode '$($Session.DisplayMode)'."
    }

    $next = [pscustomobject]@{
        SlideIndex   = $Session.SlideIndex
        RevealStep   = $Session.RevealStep
        ShowNotes    = $Session.ShowNotes
        DisplayMode  = $Session.DisplayMode
        ShowTimer    = $Session.ShowTimer
        IsRunning    = $Session.IsRunning
    }
    $lastSlide = $Presentation.Slides.Count - 1
    $currentMaximumRevealStep = Get-TerminalSlideMaximumRevealStep -Slide $Presentation.Slides[$next.SlideIndex]

    switch ($Action) {
        'NextStep' {
            if ($next.RevealStep -lt $currentMaximumRevealStep) {
                $next.RevealStep++
            }
            elseif ($next.SlideIndex -lt $lastSlide) {
                $next.SlideIndex++
                $next.RevealStep = 0
            }
        }
        'NextSlide' {
            if ($next.SlideIndex -lt $lastSlide) {
                $next.SlideIndex++
                $next.RevealStep = 0
            }
        }
        'PreviousStep' {
            if ($next.RevealStep -gt 0) {
                $next.RevealStep--
            }
            elseif ($next.SlideIndex -gt 0) {
                $next.SlideIndex--
                $next.RevealStep = Get-TerminalSlideMaximumRevealStep -Slide $Presentation.Slides[$next.SlideIndex]
            }
        }
        'PreviousSlide' {
            if ($next.SlideIndex -gt 0) {
                $next.SlideIndex--
                $next.RevealStep = Get-TerminalSlideMaximumRevealStep -Slide $Presentation.Slides[$next.SlideIndex]
            }
        }
        'FirstSlide' {
            $next.SlideIndex = 0
            $next.RevealStep = 0
        }
        'LastSlide' {
            $next.SlideIndex = $lastSlide
            $next.RevealStep = Get-TerminalSlideMaximumRevealStep -Slide $Presentation.Slides[$lastSlide]
        }
        'ToggleNotes' { $next.ShowNotes = -not $next.ShowNotes }
        'ToggleOverview' { $next.DisplayMode = if ($next.DisplayMode -eq 'Overview') { 'Slide' } else { 'Overview' } }
        'ToggleHelp' { $next.DisplayMode = if ($next.DisplayMode -eq 'Help') { 'Slide' } else { 'Help' } }
        'ToggleBlank' { $next.DisplayMode = if ($next.DisplayMode -eq 'Blank') { 'Slide' } else { 'Blank' } }
        'ToggleTimer' { $next.ShowTimer = -not $next.ShowTimer }
        'Quit' { $next.IsRunning = $false }
    }

    return $next
}
