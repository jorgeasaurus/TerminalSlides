# Diagram DSL state lives in script scope (module scope after dot-sourcing) so
# Node/Edge can reach it regardless of where the DSL scriptblock was authored.
$script:DiagramNodes = $null
$script:DiagramEdges = $null

function Node {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Label
    )
    if ($null -eq $script:DiagramNodes) { throw 'Node can only be used inside Add-SlideDiagram.' }
    $script:DiagramNodes.Add([pscustomobject]@{ Id = $Id; Label = $Label })
}

function Edge {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$From,
        [Parameter(Mandatory)][string]$To,
        [string]$Label
    )
    if ($null -eq $script:DiagramEdges) { throw 'Edge can only be used inside Add-SlideDiagram.' }
    $script:DiagramEdges.Add([pscustomobject]@{ From = $From; To = $To; Label = $Label })
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
    try {
        $payload = if ($PSCmdlet.ParameterSetName -eq 'Object') {
            $Diagram
        }
        else {
            $script:DiagramNodes = [System.Collections.Generic.List[object]]::new()
            $script:DiagramEdges = [System.Collections.Generic.List[object]]::new()
            try {
                # Dot-source into the current scope so script-scoped Node/Edge are
                # visible to the content scriptblock wherever it was authored.
                Invoke-SafeScriptBlock -ScriptBlock $Content -SafeMode:$SafeMode -Scope Local
                @{
                    Nodes = @($script:DiagramNodes)
                    Edges = @($script:DiagramEdges)
                }
            }
            finally {
                $script:DiagramNodes = $null
                $script:DiagramEdges = $null
            }
        }
        Add-CurrentSlideElement -Element (New-InternalSlideElement -Type Diagram -Content $payload -Region $Region -RevealStep $RevealStep)
    }
    catch {
        throw
    }
}
