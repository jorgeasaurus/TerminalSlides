$script:TerminalSlidesBuildContexts = [System.Collections.Generic.Stack[object]]::new()

function Push-TerminalSlidesBuildContext {
    param([Parameter(Mandatory)][ValidateSet('Slide', 'Diagram')][string]$Kind)

    $context = if ($Kind -eq 'Slide') {
        [pscustomobject]@{
            Kind     = 'Slide'
            Elements = [System.Collections.Generic.List[TerminalSlides.Schema.V1.SlideElement]]::new()
            Notes    = $null
        }
    }
    else {
        [pscustomobject]@{
            Kind  = 'Diagram'
            Nodes = [System.Collections.Generic.List[object]]::new()
            Edges = [System.Collections.Generic.List[object]]::new()
        }
    }

    $script:TerminalSlidesBuildContexts.Push($context)
    return $context
}

function Get-TerminalSlidesBuildContext {
    param([Parameter(Mandatory)][ValidateSet('Slide', 'Diagram')][string]$Kind)

    foreach ($context in $script:TerminalSlidesBuildContexts) {
        if ($context.Kind -eq $Kind) { return $context }
    }
    return $null
}

function Pop-TerminalSlidesBuildContext {
    param([Parameter(Mandatory)][object]$Context)

    if (-not $script:TerminalSlidesBuildContexts.Count -or
        -not [object]::ReferenceEquals($script:TerminalSlidesBuildContexts.Peek(), $Context)) {
        throw 'TerminalSlides build contexts must be closed in nesting order.'
    }
    $null = $script:TerminalSlidesBuildContexts.Pop()
}
