function Node {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Label
    )
    $nodes = Get-TerminalSlidesStateValue -Name CurrentDiagramNodes
    if (-not $nodes) { throw 'Node can only be used inside Add-SlideDiagram.' }
    $nodes.Add([pscustomobject]@{ Id = $Id; Label = $Label })
    Set-TerminalSlidesStateValue -Name CurrentDiagramNodes -Value $nodes
}

function Edge {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$From,
        [Parameter(Mandatory)][string]$To,
        [string]$Label
    )
    $edges = Get-TerminalSlidesStateValue -Name CurrentDiagramEdges
    if (-not $edges) { throw 'Edge can only be used inside Add-SlideDiagram.' }
    $edges.Add([pscustomobject]@{ From = $From; To = $To; Label = $Label })
    Set-TerminalSlidesStateValue -Name CurrentDiagramEdges -Value $edges
}

function Add-SlideDiagram {
    [CmdletBinding(DefaultParameterSetName='Dsl')]
    param(
        [Parameter(Mandatory, ParameterSetName='Dsl')][scriptblock]$Content,
        [Parameter(Mandatory, ParameterSetName='Object')][hashtable]$Diagram,
        [string]$Region = 'Content',
        [int]$RevealStep = 0
    )
    try {
        $payload = if ($PSCmdlet.ParameterSetName -eq 'Object') {
            $Diagram
        }
        else {
            Set-TerminalSlidesStateValue -Name CurrentDiagramNodes -Value ([System.Collections.Generic.List[object]]::new())
            Set-TerminalSlidesStateValue -Name CurrentDiagramEdges -Value ([System.Collections.Generic.List[object]]::new())
            try {
                Invoke-SafeScriptBlock -ScriptBlock $Content -SafeMode
                @{
                    Nodes = @(Get-TerminalSlidesStateValue -Name CurrentDiagramNodes)
                    Edges = @(Get-TerminalSlidesStateValue -Name CurrentDiagramEdges)
                }
            }
            finally {
                Set-TerminalSlidesStateValue -Name CurrentDiagramNodes -Value $null
                Set-TerminalSlidesStateValue -Name CurrentDiagramEdges -Value $null
            }
        }
        Add-CurrentSlideElement -Element (New-InternalSlideElement -Type Diagram -Content $payload -Region $Region -RevealStep $RevealStep)
    }
    catch {
        Write-Error $_
    }
}
