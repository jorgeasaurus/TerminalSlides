function Measure-TextWidth {
    [CmdletBinding()]
    param([AllowNull()][string]$Text)
    $plain = Strip-AnsiSequences -Text ($Text ?? '')
    return ($plain.ToCharArray() | Measure-Object).Count
}
