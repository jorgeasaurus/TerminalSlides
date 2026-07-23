function Add-SlideChart {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Data,
        [ValidateSet('HorizontalBar','Bar','Line','Sparkline','Gauge')][string]$ChartType = 'HorizontalBar',
        [string]$Region = 'Content',
        [int]$RevealStep = 0,
        [string]$Title
    )
    $points = foreach ($item in $Data) {
        $label = Get-TerminalSemanticProperty $item Label
        $value = Get-TerminalSemanticProperty $item Value
        if ($null -eq $label -or $null -eq $value) { throw 'Chart rows require Label and Value properties.' }
        try { $number = [decimal]::Parse([string]$value, [Globalization.CultureInfo]::InvariantCulture) }
        catch { throw "Chart value '$value' is not numeric." }
        [TerminalSlides.Schema.V1.ChartPoint]::new([string]$label, $number)
    }
    $payload = [TerminalSlides.Schema.V1.ChartPayload]::new(
        [TerminalSlides.Schema.V1.ChartPoint[]]@($points),
        [TerminalSlides.Schema.V1.ChartKind]$ChartType,
        $Title
    )
    Add-CurrentSlideElement -Element (New-InternalSlideElement -Kind Chart -Payload $payload -Region $Region -RevealStep $RevealStep)
}
