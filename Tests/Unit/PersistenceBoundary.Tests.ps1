Describe 'Persistence boundary hardening' {
    BeforeAll {
        $script:ModulePath = Join-Path $PSScriptRoot '..' '..' 'TerminalSlides.psd1'
        Import-Module $script:ModulePath -Force

        function Invoke-IsolatedPowerShellProbe {
            param(
                [Parameter(Mandatory)][string]$Script,
                [int]$TimeoutMilliseconds = 10000
            )

            $startInfo = [Diagnostics.ProcessStartInfo]::new()
            $startInfo.FileName = [Environment]::ProcessPath
            $startInfo.UseShellExecute = $false
            $startInfo.CreateNoWindow = $true
            $startInfo.ArgumentList.Add('-NoLogo')
            $startInfo.ArgumentList.Add('-NoProfile')
            $startInfo.ArgumentList.Add('-EncodedCommand')
            $startInfo.ArgumentList.Add([Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Script)))
            $process = [Diagnostics.Process]::new()
            $process.StartInfo = $startInfo
            try {
                if (-not $process.Start()) { throw 'The isolated PowerShell probe could not be started.' }
                if (-not $process.WaitForExit($TimeoutMilliseconds)) {
                    $process.Kill($true)
                    [void]$process.WaitForExit(5000)
                    throw "The isolated PowerShell probe exceeded $TimeoutMilliseconds milliseconds."
                }
                return $process.ExitCode
            }
            finally { $process.Dispose() }
        }

        function Write-TerminalMalformedWireFile {
            param(
                [Parameter(Mandatory)][System.Collections.IDictionary]$Node,
                [Parameter(Mandatory)][ValidateSet('Json','Psd1','Markdown')][string]$Format,
                [Parameter(Mandatory)][string]$Path
            )

            $module = Get-Module TerminalSlides
            $content = & $module {
                param($MetadataNode, $WireFormat)

                $data = ConvertTo-PresentationData (New-TerminalPresentation -Title InvalidWireData)
                $data.Presentation.Metadata.Custom = $MetadataNode
                switch ($WireFormat) {
                    'Json' { ConvertTo-TerminalWireJson $data }
                    'Psd1' { "@{ TerminalSlidesEnvelope = '$(ConvertTo-TerminalDataMarker $data)' }`n" }
                    'Markdown' {
                        $marker = [ordered]@{ MarkerVersion = 1; Presentation = $data }
                        '<!-- terminalslides:envelope ' + (ConvertTo-TerminalDataMarker $marker) + ' -->'
                    }
                }
            } $Node $Format
            [IO.File]::WriteAllText($Path, $content)
        }

        function Write-TerminalMalformedTableWireFile {
            param(
                [Parameter(Mandatory)][object[]]$Names,
                [Parameter(Mandatory)][ValidateSet('Json','Psd1','Markdown')][string]$Format,
                [Parameter(Mandatory)][string]$Path
            )

            $module = Get-Module TerminalSlides
            $content = & $module {
                param($ColumnNames, $WireFormat)

                $deck = New-TerminalPresentation -Title InvalidTable
                $deck | Add-TerminalSlide -Title Data -Content {
                    Add-SlideTable -Data ([ordered]@{ Valid = 'value' })
                } | Out-Null
                $data = ConvertTo-PresentationData $deck
                $data.Presentation.Slides[0].Elements[0].Payload.Rows[0].Cells = @(
                    $ColumnNames | ForEach-Object {
                        [ordered]@{ Name = $_; Kind = 'String'; Value = [string]$_ }
                    }
                )
                switch ($WireFormat) {
                    'Json' { ConvertTo-TerminalWireJson $data }
                    'Psd1' { "@{ TerminalSlidesEnvelope = '$(ConvertTo-TerminalDataMarker $data)' }`n" }
                    'Markdown' {
                        $marker = [ordered]@{ MarkerVersion = 1; Presentation = $data }
                        '<!-- terminalslides:envelope ' + (ConvertTo-TerminalDataMarker $marker) + ' -->'
                    }
                }
            } $Names $Format
            [IO.File]::WriteAllText($Path, $content)
        }

        function Write-TerminalCurrentWireDataFile {
            param(
                [Parameter(Mandatory)][System.Collections.IDictionary]$Data,
                [Parameter(Mandatory)][ValidateSet('Json','Psd1','Markdown')][string]$Format,
                [Parameter(Mandatory)][string]$Path
            )

            $module = Get-Module TerminalSlides
            $content = & $module {
                param($WireData, $WireFormat)

                switch ($WireFormat) {
                    'Json' { ConvertTo-TerminalWireJson $WireData }
                    'Psd1' { "@{ TerminalSlidesEnvelope = '$(ConvertTo-TerminalDataMarker $WireData)' }`n" }
                    'Markdown' {
                        $marker = [ordered]@{ MarkerVersion = 1; Presentation = $WireData }
                        '<!-- terminalslides:envelope ' + (ConvertTo-TerminalDataMarker $marker) + ' -->'
                    }
                }
            } $Data $Format
            [IO.File]::WriteAllText($Path, $content)
        }

        function ConvertTo-InvalidUtf8Bytes {
            param([Parameter(Mandatory)][byte[]]$Bytes)

            $invalid = [byte[]]$Bytes.Clone()
            $sentinel = [Array]::IndexOf($invalid, [byte][char]'X')
            if ($sentinel -lt 0) { throw 'The UTF-8 test sentinel was not found.' }
            $invalid[$sentinel] = 0xff
            return ,$invalid
        }

        function Add-Utf8ByteOrderMark {
            param([Parameter(Mandatory)][byte[]]$Bytes)

            $result = [byte[]]::new($Bytes.Length + 3)
            $result[0] = 0xef
            $result[1] = 0xbb
            $result[2] = 0xbf
            [Array]::Copy($Bytes, 0, $result, 3, $Bytes.Length)
            return ,$result
        }

        function ConvertTo-InvalidUtf8Marker {
            param([Parameter(Mandatory)][string]$Marker)

            $bytes = [Convert]::FromBase64String($Marker)
            return [Convert]::ToBase64String((ConvertTo-InvalidUtf8Bytes -Bytes $bytes))
        }
    }

    It 'rejects cyclic and over-depth metadata before copy or export can hang' {
        $modulePathLiteral = "'" + $script:ModulePath.Replace("'", "''") + "'"
        $copyProbe = @"
`$module = Import-Module $modulePathLiteral -Force -PassThru
try {
    & `$module {
        `$cycle = @{}
        `$cycle.Self = `$cycle
        Copy-TerminalSemanticValue `$cycle | Out-Null
    }
    exit 20
}
catch {
    if (`$_.Exception.Message -notlike '*reference cycle*') { exit 21 }
    exit 0
}
"@
        Invoke-IsolatedPowerShellProbe -Script $copyProbe | Should -Be 0

        $exportProbe = @"
`$module = Import-Module $modulePathLiteral -Force -PassThru
`$path = [IO.Path]::Combine([IO.Path]::GetTempPath(), 'terminalslides-cycle-' + [guid]::NewGuid().ToString('N') + '.json')
`$exitCode = 20
try {
    `$cycle = @{}
    `$cycle.Self = `$cycle
    `$deck = New-TerminalPresentation -Title Cycle -Metadata `$cycle
    try { Export-TerminalPresentation `$deck `$path -Format Json | Out-Null }
    catch { `$exitCode = if (`$_.Exception.Message -like '*reference cycle*') { 0 } else { 21 } }
}
finally {
    Remove-Item -LiteralPath `$path -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (`$path + '.assets') -Recurse -Force -ErrorAction SilentlyContinue
}
exit `$exitCode
"@
        Invoke-IsolatedPowerShellProbe -Script $exportProbe | Should -Be 0

        InModuleScope TerminalSlides {
            $root = @{}
            $cursor = $root
            foreach ($index in 0..32) {
                $next = @{}
                $cursor.Next = $next
                $cursor = $next
            }
            $context = New-TerminalSemanticTraversalContext
            { Copy-TerminalSemanticValue -Value $root -TraversalContext $context } |
                Should -Throw '*supported depth of 32*'
            $context.ActiveReferences.Count | Should -Be 0

            $cycle = @{}
            { ConvertTo-TerminalTaggedValue $cycle } | Should -Not -Throw
            $cycle.Self = $cycle
            { ConvertTo-TerminalTaggedValue $cycle } | Should -Throw '*reference cycle*'
            $context.ActiveReferences.Add($cycle)
            { Copy-TerminalSemanticValue -Value $cycle -TraversalContext $context } |
                Should -Throw '*reference cycle*'
            $context.ActiveReferences.Clear()
            (Copy-TerminalSemanticValue -Value @{ Safe = $true } -TraversalContext $context).Safe |
                Should -BeTrue
        }
    }

    It 'permits repeated acyclic references through copy and every structured format' {
        $shared = [ordered]@{ Value = [int[]](1, 2) }
        $source = [ordered]@{ First = $shared; Second = $shared }
        InModuleScope TerminalSlides -Parameters @{ Source = $source } {
            $copy = Copy-TerminalSemanticValue $Source
            $copy.First.Value[0] | Should -Be 1
            $copy.Second.Value[1] | Should -Be 2
            [object]::ReferenceEquals($copy.First, $copy.Second) | Should -BeFalse
        }

        $deck = New-TerminalPresentation -Title Shared -Metadata @{ First = $shared; Second = $shared }
        foreach ($format in 'Json','Psd1','Markdown') {
            $path = Join-Path $TestDrive "shared-reference.$($format.ToLowerInvariant())"
            Export-TerminalPresentation $deck $path -Format $format | Out-Null
            $roundtrip = Import-TerminalPresentation $path
            $roundtrip.Metadata.Custom.First.Value | Should -Be @(1, 2)
            $roundtrip.Metadata.Custom.Second.Value | Should -Be @(1, 2)
        }
    }

    It 'rejects malformed and case-confusable Regex nodes through every structured format' {
        $invalidNodes = @(
            [ordered]@{ Type = 'Regex'; Value = [ordered]@{ Options = 0 } }
            [ordered]@{ Type = 'Regex'; Value = [ordered]@{ Pattern = 'missing-options' } }
            [ordered]@{ Type = 'Regex'; Value = [ordered]@{ Pattern = 'wrong-case'; Options = 0; matchtimeoutticks = '2500000' } }
            [ordered]@{ Type = 'Regex'; Value = [ordered]@{ Pattern = 'extra'; Options = 0; Extra = 'field' } }
            [ordered]@{ Type = 'Regex'; Value = 'not-an-object' }
            [ordered]@{ Type = 'Regex'; Value = [ordered]@{ Pattern = $null; Options = 0 } }
            [ordered]@{ Type = 'Regex'; Value = [ordered]@{ Pattern = 'invalid-options'; Options = 'not-an-integer' } }
            [ordered]@{ Type = 'Regex'; Value = [ordered]@{ Pattern = '['; Options = 0 } }
        )

        foreach ($nodeIndex in 0..($invalidNodes.Count - 1)) {
            foreach ($format in 'Json','Psd1','Markdown') {
                $path = Join-Path $TestDrive "invalid-regex-$nodeIndex.$($format.ToLowerInvariant())"
                Write-TerminalMalformedWireFile -Node $invalidNodes[$nodeIndex] -Format $format -Path $path

                { Import-TerminalPresentation $path } |
                    Should -Throw '*Persisted regular-expression value is malformed*'
            }
        }
    }

    It 'preserves culture-invariant Regex semantics through every structured format' {
        $priorCulture = [Globalization.CultureInfo]::CurrentCulture
        try {
            [Globalization.CultureInfo]::CurrentCulture = [Globalization.CultureInfo]::GetCultureInfo('tr-TR')
            $expression = [regex]::new(
                '(?i)^i$',
                [Text.RegularExpressions.RegexOptions]::CultureInvariant,
                [timespan]::FromMilliseconds(250)
            )
            $deck = New-TerminalPresentation -Title RegexCulture -Metadata @{
                Scalar = $expression
                Vector = [regex[]]@($expression)
                Nested = [ordered]@{ Expression = $expression }
            }
            $expected = @('I','İ','ı','i' | ForEach-Object { $expression.IsMatch($_) })

            foreach ($format in 'Json','Psd1','Markdown') {
                [Globalization.CultureInfo]::CurrentCulture = [Globalization.CultureInfo]::GetCultureInfo('tr-TR')
                $path = Join-Path $TestDrive "regex-culture.$($format.ToLowerInvariant())"
                Export-TerminalPresentation $deck $path -Format $format | Out-Null

                [Globalization.CultureInfo]::CurrentCulture = [Globalization.CultureInfo]::GetCultureInfo('en-US')
                $roundtrip = Import-TerminalPresentation $path
                foreach ($actual in @(
                    $roundtrip.Metadata.Custom.Scalar
                    $roundtrip.Metadata.Custom.Vector[0]
                    $roundtrip.Metadata.Custom.Nested.Expression
                )) {
                    @('I','İ','ı','i' | ForEach-Object { $actual.IsMatch($_) }) | Should -Be $expected
                    $actual.Options | Should -Be $expression.Options
                    $actual.MatchTimeout | Should -Be $expression.MatchTimeout
                }
                $roundtrip.Metadata.Custom.Vector.GetType().FullName |
                    Should -BeExactly 'System.Text.RegularExpressions.Regex[]'
            }
        }
        finally { [Globalization.CultureInfo]::CurrentCulture = $priorCulture }
    }

    It 'rejects non-invariant Regex persistence and decodes legacy nodes under the current culture' {
        $priorCulture = [Globalization.CultureInfo]::CurrentCulture
        try {
            [Globalization.CultureInfo]::CurrentCulture = [Globalization.CultureInfo]::GetCultureInfo('tr-TR')
            $expression = [regex]::new(
                '(?i)^i$',
                [Text.RegularExpressions.RegexOptions]::None,
                [timespan]::FromMilliseconds(250)
            )
            InModuleScope TerminalSlides -Parameters @{ Expression = $expression } {
                { ConvertTo-TerminalTaggedValue $Expression } | Should -Throw '*CultureInvariant*'
            }

            foreach ($shape in @(
                @{ Scalar = $expression }
                @{ Vector = [regex[]]@($expression) }
                @{ Nested = [ordered]@{ Expression = $expression } }
            )) {
                foreach ($format in 'Json','Psd1','Markdown') {
                    $path = Join-Path $TestDrive "non-invariant-$($shape.Keys)-$($format.ToLowerInvariant())"
                    $deck = New-TerminalPresentation -Title NonInvariantRegex -Metadata $shape
                    { Export-TerminalPresentation $deck $path -Format $format } | Should -Throw '*CultureInvariant*'
                    $path | Should -Not -Exist
                }
            }

            $currentNode = [ordered]@{
                Type = 'Regex'
                Value = [ordered]@{ Pattern = '(?i)^i$'; Options = 0; MatchTimeoutTicks = '2500000' }
            }
            foreach ($format in 'Json','Psd1','Markdown') {
                $path = Join-Path $TestDrive "non-invariant-node.$($format.ToLowerInvariant())"
                Write-TerminalMalformedWireFile -Node $currentNode -Format $format -Path $path
                { Import-TerminalPresentation $path } | Should -Throw '*CultureInvariant*'
            }

            $legacyNode = [ordered]@{ Type = 'Regex'; Value = [ordered]@{ Pattern = '(?i)^i$'; Options = 0 } }
            $turkish = InModuleScope TerminalSlides -Parameters @{ Node = $legacyNode } {
                ConvertFrom-TerminalTaggedValue $Node
            }
            [Globalization.CultureInfo]::CurrentCulture = [Globalization.CultureInfo]::GetCultureInfo('en-US')
            $english = InModuleScope TerminalSlides -Parameters @{ Node = $legacyNode } {
                ConvertFrom-TerminalTaggedValue $Node
            }
            $turkish.IsMatch('I') | Should -BeFalse
            $english.IsMatch('I') | Should -BeTrue
            $english.MatchTimeout | Should -Be ([regex]::new('legacy')).MatchTimeout
        }
        finally { [Globalization.CultureInfo]::CurrentCulture = $priorCulture }
    }

    It 'rejects case-distinct tagged object properties through every structured format' {
        $objectNode = [ordered]@{
            Type = 'Object'
            Properties = @(
                [ordered]@{ Name = 'Name'; Value = [ordered]@{ Type = 'String'; Value = 'first' } }
                [ordered]@{ Name = 'name'; Value = [ordered]@{ Type = 'String'; Value = 'second' } }
            )
        }
        foreach ($format in 'Json','Psd1','Markdown') {
            $path = Join-Path $TestDrive "invalid-object.$($format.ToLowerInvariant())"
            Write-TerminalMalformedWireFile -Node $objectNode -Format $format -Path $path

            { Import-TerminalPresentation $path } |
                Should -Throw '*Metadata object properties must be unique ignoring case*'
        }
    }

    It 'rejects null, non-string, and empty Map or Object names through every structured format' {
        foreach ($kind in 'Map','Object') {
            foreach ($invalidIndex in 0..2) {
                $invalidName = @($null, 1, '')[$invalidIndex]
                $item = [ordered]@{ Name = $invalidName; Value = [ordered]@{ Type = 'String'; Value = 'value' } }
                $node = if ($kind -eq 'Map') {
                    [ordered]@{ Type = 'Map'; Entries = @($item) }
                }
                else { [ordered]@{ Type = 'Object'; Properties = @($item) } }

                InModuleScope TerminalSlides -Parameters @{ Node = $node } {
                    { ConvertFrom-TerminalTaggedValue $Node } | Should -Throw '*must be non-empty strings*'
                }
                foreach ($format in 'Json','Psd1','Markdown') {
                    $path = Join-Path $TestDrive "invalid-$kind-name-$invalidIndex.$($format.ToLowerInvariant())"
                    Write-TerminalMalformedWireFile -Node $node -Format $format -Path $path
                    { Import-TerminalPresentation $path } | Should -Throw '*must be non-empty strings*'
                }
            }
        }
    }

    It 'decodes typed arrays by exact assignability and preserves null reference elements' {
        $nullableStrings = [string[]]::new(2)
        $nullableStrings.SetValue('value', 0)
        $nullableStrings.SetValue($null, 1)
        $expression = [regex]::new('valid', [Text.RegularExpressions.RegexOptions]::CultureInvariant)

        $stringToRegex = [ordered]@{
            Type = 'Array'
            ElementType = 'System.Text.RegularExpressions.Regex'
            Items = @([ordered]@{ Type = 'String'; Value = '(?i)^i$' })
        }
        $nullToInt = [ordered]@{
            Type = 'Array'
            ElementType = 'System.Int32'
            Items = @([ordered]@{ Type = 'Null' })
        }
        InModuleScope TerminalSlides -Parameters @{
            NullableStrings = $nullableStrings
            Expression = $expression
            StringToRegex = $stringToRegex
            NullToInt = $nullToInt
        } {
            $strings = ConvertFrom-TerminalTaggedValue (ConvertTo-TerminalTaggedValue $NullableStrings)
            $strings.GetType().FullName | Should -BeExactly 'System.String[]'
            $strings[0] | Should -BeExactly value
            ($null -eq $strings.GetValue(1)) | Should -BeTrue

            $patterns = ConvertFrom-TerminalTaggedValue (
                ConvertTo-TerminalTaggedValue ([regex[]]@($Expression))
            )
            $patterns[0].Options | Should -Be $Expression.Options
            { ConvertFrom-TerminalTaggedValue $StringToRegex } | Should -Throw '*not assignable*Regex*'
            { ConvertFrom-TerminalTaggedValue $NullToInt } | Should -Throw '*Int32*does not allow null*'
        }

        $deck = New-TerminalPresentation -Title ExactArrays -Metadata @{
            Strings = $nullableStrings
            Patterns = [regex[]]@($expression)
        }
        foreach ($format in 'Json','Psd1','Markdown') {
            $path = Join-Path $TestDrive "exact-array.$($format.ToLowerInvariant())"
            Export-TerminalPresentation $deck $path -Format $format | Out-Null
            $roundtrip = Import-TerminalPresentation $path
            $roundtrip.Metadata.Custom.Strings.GetType().FullName | Should -BeExactly 'System.String[]'
            ($null -eq $roundtrip.Metadata.Custom.Strings.GetValue(1)) | Should -BeTrue
            $roundtrip.Metadata.Custom.Patterns[0].Options | Should -Be $expression.Options

            foreach ($case in @(
                @{ Name = 'string-regex'; Node = $stringToRegex; Error = '*not assignable*Regex*' }
                @{ Name = 'null-int'; Node = $nullToInt; Error = '*Int32*does not allow null*' }
            )) {
                $invalidPath = Join-Path $TestDrive "$($case.Name).$($format.ToLowerInvariant())"
                $root = [ordered]@{
                    Type = 'Map'
                    Entries = @([ordered]@{ Name = 'Value'; Value = $case.Node })
                }
                Write-TerminalMalformedWireFile -Node $root -Format $format -Path $invalidPath
                { Import-TerminalPresentation $invalidPath } | Should -Throw $case.Error
            }
        }
    }

    It 'enforces exact fields and child shapes for every current tagged node' {
        $caseConfusable = [Collections.Specialized.OrderedDictionary]::new([StringComparer]::Ordinal)
        $caseConfusable.Add('Type', 'String')
        $caseConfusable.Add('type', 'Null')
        $caseConfusable.Add('Value', 'value')
        $invalidNodes = @(
            [ordered]@{ Value = 'missing-type' }
            [ordered]@{ Type = 'String' }
            [ordered]@{ Type = 'Null'; Value = 'ignored' }
            $caseConfusable
            [ordered]@{ Type = 'Map' }
            [ordered]@{ Type = 'Map'; Entries = 'not-an-array' }
            [ordered]@{ Type = 'ArrayList'; Items = @('not-an-object') }
            [ordered]@{
                Type = 'Map'
                Entries = @([ordered]@{
                    Name = 'Value'
                    Value = [ordered]@{ Type = 'String'; Value = 'value' }
                    Extra = 'ignored'
                })
            }
            [ordered]@{
                Type = 'Object'
                Properties = @([ordered]@{ Name = 'Value'; Value = 'not-a-tagged-node' })
            }
        )

        InModuleScope TerminalSlides -Parameters @{ InvalidNodes = $invalidNodes } {
            foreach ($node in $InvalidNodes) {
                { ConvertFrom-TerminalTaggedValue $node } | Should -Throw '*is malformed*'
            }
            $valid = ConvertFrom-TerminalTaggedValue ([ordered]@{
                Type = 'Map'
                Entries = @([ordered]@{
                    Name = 'Value'
                    Value = [ordered]@{ Type = 'String'; Value = '' }
                })
            })
            $valid.ContainsKey('Value') | Should -BeTrue
            $valid.Value | Should -BeExactly ''
        }

        foreach ($nodeIndex in 0..($invalidNodes.Count - 1)) {
            foreach ($format in 'Json','Psd1','Markdown') {
                $path = Join-Path $TestDrive "invalid-tag-$nodeIndex.$($format.ToLowerInvariant())"
                Write-TerminalMalformedWireFile -Node $invalidNodes[$nodeIndex] -Format $format -Path $path
                { Import-TerminalPresentation $path } | Should -Throw '*is malformed*'
            }
        }
    }

    It 'rejects ambiguous table column names before row construction or import' {
        $caseCollision = [Collections.Specialized.OrderedDictionary]::new([StringComparer]::Ordinal)
        $caseCollision.Add('Name', 'first')
        $caseCollision.Add('name', 'second')
        $typeCollision = [Collections.Specialized.OrderedDictionary]::new([StringComparer]::Ordinal)
        $typeCollision.Add(1, 'numeric')
        $typeCollision.Add('1', 'string')

        InModuleScope TerminalSlides -Parameters @{
            CaseCollision = $caseCollision
            TypeCollision = $typeCollision
        } {
            { ConvertTo-TerminalDataRows $CaseCollision } |
                Should -Throw '*Table column names must be unique ignoring case*'
            { ConvertTo-TerminalDataRows $TypeCollision } |
                Should -Throw '*Table column names must be non-empty strings*'
            {
                Read-TerminalCurrentPayload -Kind Table -Data ([ordered]@{
                    Rows = @([ordered]@{
                        Cells = @(
                            [ordered]@{ Name = 'Name'; Kind = 'String'; Value = 'first' }
                            [ordered]@{ Name = 'name'; Kind = 'String'; Value = 'second' }
                        )
                    })
                })
            } | Should -Throw '*Table column names must be unique ignoring case*'

            $valid = ConvertTo-TerminalDataRows ([ordered]@{ Name = 'Ada'; Role = 'Engineer' })
            @($valid[0].Cells.Name) | Should -Be @('Name', 'Role')
        }

        foreach ($case in @(
            @{ Name = 'case'; Names = [object[]]@('Name', 'name'); Error = '*unique ignoring case*' }
            @{ Name = 'type'; Names = [object[]]@(1, '1'); Error = '*must be non-empty strings*' }
        )) {
            foreach ($format in 'Json','Psd1','Markdown') {
                $path = Join-Path $TestDrive "invalid-table-$($case.Name).$($format.ToLowerInvariant())"
                Write-TerminalMalformedTableWireFile -Names $case.Names -Format $format -Path $path
                { Import-TerminalPresentation $path } | Should -Throw $case.Error
            }
        }

        $validDeck = New-TerminalPresentation -Title ValidTable
        $validDeck | Add-TerminalSlide -Title Data -Content {
            Add-SlideTable -Data ([ordered]@{ Name = 'Ada'; Role = 'Engineer' })
        } | Out-Null
        foreach ($format in 'Json','Psd1','Markdown') {
            $path = Join-Path $TestDrive "valid-table.$($format.ToLowerInvariant())"
            Export-TerminalPresentation $validDeck $path -Format $format | Out-Null
            $roundtrip = Import-TerminalPresentation $path
            @($roundtrip.Slides[0].Elements[0].Payload.Rows[0].Cells.Name) |
                Should -Be @('Name', 'Role')
        }
    }

    It 'rejects invalid UTF-16 before structured export can commit a file' {
        $unpaired = [string][char]0xD800
        $expression = [regex]::new($unpaired, [Text.RegularExpressions.RegexOptions]::CultureInvariant)
        $invalidDeck = New-TerminalPresentation -Title InvalidUnicode -Metadata @{
            String = $unpaired
            Char = [char]0xD800
            Pattern = $expression
        }
        $validDeck = New-TerminalPresentation -Title ValidUnicode -Metadata @{
            String = "speaker $([char]::ConvertFromUtf32(0x1F680))"
        }

        InModuleScope TerminalSlides -Parameters @{ Unpaired = $unpaired } {
            {
                ConvertTo-TerminalWireJson ([ordered]@{ Value = $Unpaired })
            } | Should -Throw '*valid UTF-16*'
        }

        foreach ($format in 'Json','Psd1','Markdown') {
            $extension = @{ Json = 'json'; Psd1 = 'psd1'; Markdown = 'md' }[$format]
            $path = Join-Path $TestDrive "invalid-unicode.$extension"
            { Export-TerminalPresentation $invalidDeck $path -Format $format } |
                Should -Throw '*valid UTF-16*'
            $path | Should -Not -Exist

            [IO.File]::WriteAllText($path, 'original')
            { Export-TerminalPresentation $invalidDeck $path -Format $format -Force } |
                Should -Throw '*valid UTF-16*'
            [IO.File]::ReadAllText($path) | Should -BeExactly original
            @(Get-ChildItem $TestDrive -Force | Where-Object Name -Like '.*.tmp').Count | Should -Be 0

            Export-TerminalPresentation $validDeck $path -Format $format -Force | Out-Null
            (Import-TerminalPresentation $path).Metadata.Custom.String |
                Should -BeExactly $validDeck.Metadata.Custom.String
        }
    }

    It 'represents the full semantic depth consistently in every structured format' {
        function New-DepthMetadata {
            param([Parameter(Mandatory)][int]$LeafDepth)

            $root = @{}
            $cursor = $root
            foreach ($depth in 1..$LeafDepth) {
                if ($depth -eq $LeafDepth) { $cursor.Leaf = 'value'; continue }
                $next = @{}
                $cursor.Next = $next
                $cursor = $next
            }
            return $root
        }

        $maximum = New-DepthMetadata -LeafDepth 32
        $overMaximum = New-DepthMetadata -LeafDepth 33
        InModuleScope TerminalSlides -Parameters @{ Maximum = $maximum; OverMaximum = $overMaximum } {
            { ConvertTo-TerminalTaggedValue $Maximum } | Should -Not -Throw
            { ConvertTo-TerminalTaggedValue $OverMaximum } | Should -Throw '*supported depth of 32*'
        }

        foreach ($format in 'Json','Psd1','Markdown') {
            $extension = @{ Json = 'json'; Psd1 = 'psd1'; Markdown = 'md' }[$format]
            $path = Join-Path $TestDrive "maximum-depth.$extension"
            $deck = New-TerminalPresentation -Title MaximumDepth -Metadata $maximum
            Export-TerminalPresentation $deck $path -Format $format | Out-Null
            $roundtrip = Import-TerminalPresentation $path
            $cursor = $roundtrip.Metadata.Custom
            foreach ($depth in 1..31) { $cursor = $cursor.Next }
            $cursor.Leaf | Should -BeExactly value

            $invalidPath = Join-Path $TestDrive "over-maximum.$extension"
            $invalidDeck = New-TerminalPresentation -Title OverMaximum -Metadata $overMaximum
            { Export-TerminalPresentation $invalidDeck $invalidPath -Format $format } |
                Should -Throw '*supported depth of 32*'
            $invalidPath | Should -Not -Exist
        }
    }

    It 'rejects noncanonical tagged scalar Value runtime shapes through every structured format' {
        $invalidNodes = @(
            [ordered]@{ Type = 'String'; Value = $null }
            [ordered]@{ Type = 'String'; Value = 42 }
            [ordered]@{ Type = 'Char'; Value = '' }
            [ordered]@{ Type = 'Char'; Value = 'ab' }
            [ordered]@{ Type = 'Boolean'; Value = 'True' }
            [ordered]@{ Type = 'Int32'; Value = 42 }
            [ordered]@{ Type = 'DateTime'; Value = $true }
            [ordered]@{ Type = 'Uri'; Value = 1 }
            [ordered]@{ Type = 'Version'; Value = [ordered]@{} }
        )
        InModuleScope TerminalSlides -Parameters @{ InvalidNodes = $invalidNodes } {
            foreach ($node in $InvalidNodes) {
                { ConvertFrom-TerminalTaggedValue $node } | Should -Throw '*canonical*Value*'
            }
            (ConvertFrom-TerminalTaggedValue ([ordered]@{ Type = 'String'; Value = '' })) |
                Should -BeExactly ''
            (ConvertFrom-TerminalTaggedValue ([ordered]@{ Type = 'Char'; Value = 'x' })) |
                Should -Be ([char]'x')
            (ConvertFrom-TerminalTaggedValue ([ordered]@{ Type = 'Boolean'; Value = $false })) |
                Should -BeFalse
            (ConvertFrom-TerminalTaggedValue ([ordered]@{ Type = 'Int32'; Value = '42' })) |
                Should -BeOfType int
        }

        foreach ($nodeIndex in 0..($invalidNodes.Count - 1)) {
            foreach ($format in 'Json','Psd1','Markdown') {
                $path = Join-Path $TestDrive "invalid-scalar-$nodeIndex.$($format.ToLowerInvariant())"
                Write-TerminalMalformedWireFile -Node $invalidNodes[$nodeIndex] -Format $format -Path $path
                { Import-TerminalPresentation $path } | Should -Throw '*canonical*Value*'
            }
        }
    }

    It 'writes only supported primitive wire values without implicit coercion' {
        InModuleScope TerminalSlides {
            $values = [object[]]@(
                [sbyte]-1, [byte]2, [int16]-3, [uint16]4, [uint32]5, [int64]-6,
                [uint64]7, [single]1.25, [double]2.5, [decimal]3.75
            )
            $json = ConvertTo-TerminalWireJson ([ordered]@{ Values = $values })
            (ConvertFrom-TerminalWireJson $json).Values.Count | Should -Be $values.Count

            $invalidKey = [Collections.Specialized.OrderedDictionary]::new()
            $invalidKey.Add(1, 'value')
            { ConvertTo-TerminalWireJson $invalidKey } | Should -Throw '*keys must be strings*'
            { ConvertTo-TerminalWireJson ([ordered]@{ Value = [version]'1.2.3' }) } |
                Should -Throw '*cannot encode value type*'

            $date = [datetime]'2024-01-02T03:04:05.0000000Z'
            (ConvertFrom-TerminalPersistedScalarText -Kind DateTime -Value $date) |
                Should -BeExactly $date.ToString('o', [Globalization.CultureInfo]::InvariantCulture)
        }
    }

    It 'rejects invalid UTF-8 from JSON and Markdown literal files without changing them' {
        $deck = New-TerminalPresentation -Title 'X café 🚀'
        foreach ($format in 'Json','Markdown') {
            $extension = @{ Json = 'json'; Markdown = 'md' }[$format]
            $path = Join-Path $TestDrive "invalid-file.$extension"
            Export-TerminalPresentation $deck $path -Format $format | Out-Null
            $invalidBytes = ConvertTo-InvalidUtf8Bytes -Bytes ([IO.File]::ReadAllBytes($path))
            [IO.File]::WriteAllBytes($path, $invalidBytes)
            $before = [Convert]::ToBase64String($invalidBytes)

            { Import-TerminalPresentation -Path $path } | Should -Throw '*valid UTF-8*'

            [Convert]::ToBase64String([IO.File]::ReadAllBytes($path)) | Should -BeExactly $before
        }
    }

    It 'rejects invalid UTF-8 from Markdown and current or legacy PSD1 markers' {
        $deck = New-TerminalPresentation -Title 'X marker'
        $markdownPath = Join-Path $TestDrive 'invalid-marker.md'
        Export-TerminalPresentation $deck $markdownPath -Format Markdown | Out-Null
        $markdown = [IO.File]::ReadAllText($markdownPath)
        $markdownMatch = [regex]::Match($markdown, '(?<marker>[A-Za-z0-9+/=]+)(?=\s*-->\s*\z)')
        $invalidMarkdownMarker = ConvertTo-InvalidUtf8Marker $markdownMatch.Groups['marker'].Value
        $invalidMarkdown = $markdown.Remove($markdownMatch.Index, $markdownMatch.Length).Insert(
            $markdownMatch.Index,
            $invalidMarkdownMarker
        )
        [IO.File]::WriteAllText($markdownPath, $invalidMarkdown)

        { Import-TerminalPresentation -Path $markdownPath } | Should -Throw '*valid UTF-8*'
        [IO.File]::ReadAllText($markdownPath) | Should -BeExactly $invalidMarkdown

        $psd1Path = Join-Path $TestDrive 'valid-marker.psd1'
        Export-TerminalPresentation $deck $psd1Path -Format Psd1 | Out-Null
        $psd1 = [IO.File]::ReadAllText($psd1Path)
        $psd1Match = [regex]::Match($psd1, "TerminalSlidesEnvelope\s*=\s*'(?<marker>[A-Za-z0-9+/=]+)'")
        $invalidPsd1Marker = ConvertTo-InvalidUtf8Marker $psd1Match.Groups['marker'].Value
        foreach ($key in 'TerminalSlidesEnvelope','TerminalSlidesData') {
            $path = Join-Path $TestDrive "invalid-$key.psd1"
            $content = "@{ $key = '$invalidPsd1Marker' }`n"
            [IO.File]::WriteAllText($path, $content)

            { Import-TerminalPresentation -Path $path } | Should -Throw '*valid UTF-8*'
            [IO.File]::ReadAllText($path) | Should -BeExactly $content
        }
    }

    It 'imports ordinary Unicode from UTF-8 BOM files through literal paths' {
        $deck = New-TerminalPresentation -Title 'X café 🚀'
        foreach ($format in 'Json','Psd1','Markdown') {
            $extension = @{ Json = 'json'; Psd1 = 'psd1'; Markdown = 'md' }[$format]
            $path = Join-Path $TestDrive "bom[1].$extension"
            Export-TerminalPresentation $deck $path -Format $format | Out-Null
            $bytes = Add-Utf8ByteOrderMark -Bytes ([IO.File]::ReadAllBytes($path))
            [IO.File]::WriteAllBytes($path, $bytes)

            (Import-TerminalPresentation -Path $path).Title | Should -BeExactly $deck.Title
            [Convert]::ToBase64String([IO.File]::ReadAllBytes($path)) |
                Should -BeExactly ([Convert]::ToBase64String($bytes))
        }
    }

    It 'rejects coercible current-wire child shapes before typed construction' {
        $invalidNodes = @(
            [ordered]@{
                Type = 'Map'
                Entries = [object[]]@([ordered]@{
                    Name = [object[]]@('Key')
                    Value = [ordered]@{ Type = 'String'; Value = 'value' }
                })
            }
            [ordered]@{
                Type = 'Array'
                ElementType = [object[]]@('System.String')
                Items = [object[]]@([ordered]@{ Type = 'String'; Value = 'value' })
            }
            [ordered]@{
                Type = 'Regex'
                Value = [ordered]@{
                    Pattern = 'value'
                    Options = [object[]]@('512')
                    MatchTimeoutTicks = [object[]]@('10000000')
                }
            }
            [ordered]@{
                Type = 'Regex'
                Value = [ordered]@{
                    Pattern = 'value'
                    Options = 512
                    MatchTimeoutTicks = [object[]]@('10000000')
                }
            }
        )
        InModuleScope TerminalSlides -Parameters @{ InvalidNodes = $invalidNodes } {
            foreach ($node in $InvalidNodes) {
                { ConvertFrom-TerminalTaggedValue $node } | Should -Throw '*wire*'
            }
        }
        foreach ($nodeIndex in 0..($invalidNodes.Count - 1)) {
            foreach ($format in 'Json','Psd1','Markdown') {
                $path = Join-Path $TestDrive "coercible-tag-$nodeIndex.$($format.ToLowerInvariant())"
                Write-TerminalMalformedWireFile -Node $invalidNodes[$nodeIndex] -Format $format -Path $path
                { Import-TerminalPresentation $path } | Should -Throw '*wire*'
            }
        }

        $module = Get-Module TerminalSlides
        $invalidData = & $module {
            $deck = New-TerminalPresentation -Title InvalidCurrent
            $deck | Add-TerminalSlide -Title Data -Content {
                Add-SlideTable -Data ([ordered]@{ Column = 'value' })
            } | Out-Null
            $base = ConvertTo-PresentationData $deck
            $copy = { ConvertFrom-TerminalWireJson (ConvertTo-TerminalWireJson $base) }
            $table = & $copy
            $table.Presentation.Slides[0].Elements[0].Payload.Rows[0].Cells[0].Name = [object[]]@('Column')
            $table.Presentation.Slides[0].Elements[0].Payload.Rows[0].Cells[0].Kind = [object[]]@('String')
            $table.Presentation.Slides[0].Elements[0].Payload.Rows[0].Cells[0].Value = [object[]]@('value')
            $envelope = & $copy
            $envelope.SchemaVersion = '1'
            $envelope.Presentation.Title = 7
            $boolean = & $copy
            $boolean.Presentation.Slides[0].Elements[0].Border = 'False'
            $enum = & $copy
            $enum.Presentation.Slides[0].Elements[0].Kind = 'table'
            $tag = & $copy
            $tag.Presentation.Metadata.Custom = 'not-an-object'
            $nullCell = & $copy
            $nullCell.Presentation.Slides[0].Elements[0].Payload.Rows[0].Cells[0].Kind = 'Null'
            $nullCell.Presentation.Slides[0].Elements[0].Payload.Rows[0].Cells[0].Value = 'not-null'
            $charCell = & $copy
            $charCell.Presentation.Slides[0].Elements[0].Payload.Rows[0].Cells[0].Kind = 'Char'
            $charCell.Presentation.Slides[0].Elements[0].Payload.Rows[0].Cells[0].Value = 'ab'
            $invalidBoolean = & $copy
            $invalidBoolean.Presentation.Slides[0].Elements[0].Payload.Rows[0].Cells[0].Kind = 'Boolean'
            $invalidBoolean.Presentation.Slides[0].Elements[0].Payload.Rows[0].Cells[0].Value = 'not-a-boolean'
            $invalidInteger = & $copy
            $invalidInteger.Presentation.Slides[0].Elements[0].Payload.Rows[0].Cells[0].Kind = 'Int32'
            $invalidInteger.Presentation.Slides[0].Elements[0].Payload.Rows[0].Cells[0].Value = 'not-an-integer'
            $invalidDate = & $copy
            $invalidDate.Presentation.Slides[0].Elements[0].Payload.Rows[0].Cells[0].Kind = 'DateTime'
            $invalidDate.Presentation.Slides[0].Elements[0].Payload.Rows[0].Cells[0].Value = 'not-a-date'
            $invalidGuid = & $copy
            $invalidGuid.Presentation.Slides[0].Elements[0].Payload.Rows[0].Cells[0].Kind = 'Guid'
            $invalidGuid.Presentation.Slides[0].Elements[0].Payload.Rows[0].Cells[0].Value = 'not-a-guid'
            return ,([object[]]@(
                $table, $envelope, $boolean, $enum, $tag, $nullCell, $charCell,
                $invalidBoolean, $invalidInteger, $invalidDate, $invalidGuid
            ))
        }
        foreach ($dataIndex in 0..($invalidData.Count - 1)) {
            foreach ($format in 'Json','Psd1','Markdown') {
                $path = Join-Path $TestDrive "coercible-current-$dataIndex.$($format.ToLowerInvariant())"
                Write-TerminalCurrentWireDataFile -Data $invalidData[$dataIndex] -Format $format -Path $path
                { Import-TerminalPresentation $path } | Should -Throw '*wire*'
            }
        }

        $validScalars = [ordered]@{
            Null = $null; String = 'value'; Char = [char]'X'; Boolean = $true
            SByte = [sbyte]-1; Byte = [byte]1; Int16 = [int16]-2; UInt16 = [uint16]2
            Int32 = [int32]-3; UInt32 = [uint32]3; Int64 = [int64]-4; UInt64 = [uint64]4
            Single = [single]1.25; Double = [double]2.5; Decimal = [decimal]3.75
            DateTime = [datetime]'2024-01-02T03:04:05Z'
            DateTimeOffset = [datetimeoffset]'2024-01-02T03:04:05+02:00'
            TimeSpan = [timespan]'01:02:03'; Guid = [guid]'7dc321bd-415f-4a05-b5fc-62fc43be5d77'
        }
        $valid = New-TerminalPresentation -Title ValidCurrent -Metadata @{ Array = [string[]]@('value') }
        $valid | Add-TerminalSlide -Title Data -Content ({ Add-SlideTable -Data $validScalars }.GetNewClosure()) | Out-Null
        foreach ($format in 'Json','Psd1','Markdown') {
            $path = Join-Path $TestDrive "valid-current.$($format.ToLowerInvariant())"
            Export-TerminalPresentation $valid $path -Format $format | Out-Null
            $roundtrip = Import-TerminalPresentation $path
            $roundtrip.Metadata.Custom.Array[0] | Should -BeExactly value
            InModuleScope TerminalSlides -Parameters @{ Presentation = $roundtrip } {
                $cells = $Presentation.Slides[0].Elements[0].Payload.Rows[0].Cells
                $cells.Count | Should -Be 19
                foreach ($cell in $cells) { { ConvertFrom-TerminalScalarValue $cell.Value } | Should -Not -Throw }
            }
        }
    }

    It 'serializes unordered maps deterministically while preserving ordered member order' {
        $modulePathLiteral = "'" + $script:ModulePath.Replace("'", "''") + "'"
        foreach ($format in 'Json','Psd1','Markdown') {
            $probe = @"
Import-Module $modulePathLiteral -Force
`$metadata = @{}
foreach (`$key in 'Zulu','Alpha','Mike','Bravo','Echo','Charlie') { `$metadata[`$key] = `$key }
`$deck = New-TerminalPresentation -Title Determinism -Metadata `$metadata
`$row = @{}
foreach (`$key in 'Zulu','Alpha','Mike','Bravo','Echo','Charlie') { `$row[`$key] = `$key }
`$deck | Add-TerminalSlide -Title Data -Content ({ Add-SlideTable -Data `$row }.GetNewClosure()) | Out-Null
`$fixed = [datetime]'2024-01-02T03:04:05.0000000Z'
`$deck.Slides[0].Id = 'slide-fixed'
`$deck.Slides[0].Elements[0].Id = 'element-fixed'
`$deck.CreatedDate = `$fixed
`$deck.ModifiedDate = `$fixed
`$path = [IO.Path]::GetTempFileName()
try {
    Export-TerminalPresentation `$deck `$path -Format $format -Force | Out-Null
    [Convert]::ToBase64String([IO.File]::ReadAllBytes(`$path))
}
finally { [IO.File]::Delete(`$path) }
"@
            $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($probe))
            $outputs = foreach ($run in 1..4) {
                & ([Environment]::ProcessPath) -NoLogo -NoProfile -EncodedCommand $encoded
                $LASTEXITCODE | Should -Be 0
            }
            @($outputs | Where-Object { $_ -is [string] } | Select-Object -Unique).Count | Should -Be 1
        }

        InModuleScope TerminalSlides {
            (ConvertTo-TerminalTaggedValue @{ Zulu = 1; Alpha = 2 }).Entries.Name |
                Should -Be @('Alpha','Zulu')
            (ConvertTo-TerminalTaggedValue ([ordered]@{ Zulu = 1; Alpha = 2 })).Entries.Name |
                Should -Be @('Zulu','Alpha')
            (ConvertTo-TerminalDataRows @{ Zulu = 1; Alpha = 2 })[0].Cells.Name |
                Should -Be @('Alpha','Zulu')
            (ConvertTo-TerminalDataRows ([ordered]@{ Zulu = 1; Alpha = 2 }))[0].Cells.Name |
                Should -Be @('Zulu','Alpha')
        }
    }
}
