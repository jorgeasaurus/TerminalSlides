function ConvertFrom-AnsiString {
    [CmdletBinding()]
    param([AllowNull()][string]$Text)
    return (Strip-AnsiSequences -Text $Text)
}
