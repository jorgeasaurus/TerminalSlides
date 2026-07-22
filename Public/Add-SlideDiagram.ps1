function Add-SlideDiagramNode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Label
    )
    $context = Get-TerminalSlidesBuildContext -Kind Diagram
    if ($null -eq $context) { throw 'Add-SlideDiagramNode can only be used inside Add-SlideDiagram.' }
    $context.Nodes.Add([TerminalSlides.Schema.V1.DiagramNode]::new($Id, $Label))
}

function Add-SlideDiagramEdge {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$From,
        [Parameter(Mandatory)][string]$To,
        [string]$Label
    )
    $context = Get-TerminalSlidesBuildContext -Kind Diagram
    if ($null -eq $context) { throw 'Add-SlideDiagramEdge can only be used inside Add-SlideDiagram.' }
    $context.Edges.Add([TerminalSlides.Schema.V1.DiagramEdge]::new($From, $To, $Label))
}

function Add-SlideDiagram {
    [CmdletBinding(DefaultParameterSetName='Dsl')]
    param(
        [Parameter(Mandatory, ParameterSetName='Dsl')][scriptblock]$Content,
        [Parameter(Mandatory, ParameterSetName='Object')][hashtable]$Diagram,
        [string]$Region = 'Content',
        [int]$RevealStep = 0,
        [switch]$SafeMode
    )
    $diagramData = if ($PSCmdlet.ParameterSetName -eq 'Object') {
            $Diagram
        }
        else {
            $context = Push-TerminalSlidesBuildContext -Kind Diagram
            try {
                Invoke-SafeScriptBlock -ScriptBlock $Content -SafeMode:$SafeMode -Scope Local
                @{
                    Nodes = @($context.Nodes)
                    Edges = @($context.Edges)
                }
            }
            finally {
                Pop-TerminalSlidesBuildContext -Context $context
            }
    }
    $nodes = @($diagramData.Nodes | ForEach-Object {
        if ($_ -is [TerminalSlides.Schema.V1.DiagramNode]) { $_ }
        else { [TerminalSlides.Schema.V1.DiagramNode]::new([string](Get-TerminalSemanticProperty $_ Id), [string](Get-TerminalSemanticProperty $_ Label)) }
    })
    $edges = @($diagramData.Edges | ForEach-Object {
        if ($_ -is [TerminalSlides.Schema.V1.DiagramEdge]) { $_ }
        else { [TerminalSlides.Schema.V1.DiagramEdge]::new([string](Get-TerminalSemanticProperty $_ From), [string](Get-TerminalSemanticProperty $_ To), [string](Get-TerminalSemanticProperty $_ Label)) }
    })
    Assert-TerminalDiagramNodeIdentity -Nodes ([TerminalSlides.Schema.V1.DiagramNode[]]$nodes)
    $payload = [TerminalSlides.Schema.V1.DiagramPayload]::new(
        [TerminalSlides.Schema.V1.DiagramNode[]]$nodes,
        [TerminalSlides.Schema.V1.DiagramEdge[]]$edges
    )
    Add-CurrentSlideElement -Element (New-InternalSlideElement -Kind Diagram -Payload $payload -Region $Region -RevealStep $RevealStep)
}
