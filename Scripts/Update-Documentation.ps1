[CmdletBinding()]
param([switch]$Check)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$catalogPath = Join-Path $repositoryRoot 'docs/command-catalog.json'
$websiteDataPath = Join-Path $repositoryRoot 'docs/commands.json'
$helpPath = Join-Path $repositoryRoot 'en-US/TerminalSlides-help.xml'
$manifest = Import-PowerShellDataFile (Join-Path $repositoryRoot 'TerminalSlides.psd1')
$catalog = @(Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json)
$module = Import-Module (Join-Path $repositoryRoot 'TerminalSlides.psd1') -Force -PassThru
$commonParameters = @(
    'Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction', 'ProgressAction',
    'ErrorVariable', 'WarningVariable', 'InformationVariable', 'OutVariable', 'OutBuffer', 'PipelineVariable'
)

function ConvertTo-XmlText {
    param([AllowEmptyString()][string]$Text)

    return [System.Security.SecurityElement]::Escape($Text)
}

function Assert-CommandCatalog {
    $catalogNames = @($catalog.Name)
    if ($catalogNames.Count -ne $manifest.FunctionsToExport.Count) {
        throw "The command catalog contains $($catalogNames.Count) entries; the manifest exports $($manifest.FunctionsToExport.Count)."
    }
    if (@($catalogNames | Sort-Object -Unique).Count -ne $catalogNames.Count) {
        throw 'The command catalog contains duplicate command names.'
    }

    $difference = @(Compare-Object $manifest.FunctionsToExport $catalogNames)
    if ($difference.Count -gt 0) {
        throw "The command catalog does not match FunctionsToExport: $($difference.InputObject -join ', ')."
    }

    foreach ($entry in $catalog) {
        foreach ($property in 'Name', 'Category', 'Description', 'Example') {
            if ([string]::IsNullOrWhiteSpace([string]$entry.$property)) {
                throw "Catalog entry '$($entry.Name)' has no $property."
            }
        }

        $tokens = $null
        $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseInput(
            $entry.Example,
            [ref]$tokens,
            [ref]$parseErrors
        )
        if ($parseErrors.Count -gt 0) {
            throw "Catalog example '$($entry.Name)' is not valid PowerShell: $($parseErrors.Message -join '; ')"
        }
    }
}

function ConvertTo-XmlBoolean {
    param([bool]$Value)

    return $Value.ToString().ToLowerInvariant()
}

function Get-PipelineInputText {
    param([Parameter(Mandatory)]$Parameter)

    $bindings = @()
    if ($Parameter.ValueFromPipeline) { $bindings += 'ByValue' }
    if ($Parameter.ValueFromPipelineByPropertyName) { $bindings += 'ByPropertyName' }
    if ($bindings.Count -eq 0) { return 'false' }
    return "true ($($bindings -join ', '))"
}

function Get-ParameterDescription {
    param(
        [Parameter(Mandatory)]$Command,
        [Parameter(Mandatory)][string]$Name
    )

    $description = "Specifies the $Name value."
    $validateSet = $Command.Parameters[$Name].Attributes |
        Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } |
        Select-Object -First 1
    if ($validateSet) {
        $description += " Accepted values: $($validateSet.ValidValues -join ', ')."
    }
    return $description
}

function New-ParameterXml {
    param(
        [Parameter(Mandatory)]$Command,
        [Parameter(Mandatory)]$Parameter,
        [switch]$Syntax
    )

    $name = ConvertTo-XmlText $Parameter.Name
    $required = ConvertTo-XmlBoolean $Parameter.IsMandatory
    $position = if ($Parameter.Position -ge 0) { [string]$Parameter.Position } else { 'named' }
    $pipelineInput = ConvertTo-XmlText (Get-PipelineInputText -Parameter $Parameter)
    $aliases = if ($Parameter.Aliases.Count -gt 0) { $Parameter.Aliases -join ', ' } else { 'none' }
    $aliases = ConvertTo-XmlText $aliases
    $typeName = ConvertTo-XmlText $Parameter.ParameterType.FullName
    $description = ConvertTo-XmlText (Get-ParameterDescription -Command $Command -Name $Parameter.Name)
    $indent = if ($Syntax) { '      ' } else { '    ' }
    $parameterValue = if ($Parameter.ParameterType -ne [System.Management.Automation.SwitchParameter]) {
        "`n$indent  <command:parameterValue required=`"$required`" variableLength=`"false`">$typeName</command:parameterValue>"
    }
    else {
        ''
    }
    return @"
$indent<command:parameter required="$required" variableLength="false" globbing="false" pipelineInput="$pipelineInput" position="$position" aliases="$aliases">
$indent  <maml:name>$name</maml:name>
$indent  <maml:description><maml:para>$description</maml:para></maml:description>$parameterValue
$indent  <dev:type><maml:name>$typeName</maml:name><maml:uri /></dev:type>
$indent  <dev:defaultValue>None</dev:defaultValue>
$indent</command:parameter>
"@
}

function New-CommandSyntaxXml {
    param([Parameter(Mandatory)]$Command)

    $items = foreach ($parameterSet in $Command.ParameterSets) {
        $parameters = foreach ($parameter in $parameterSet.Parameters) {
            if ($parameter.Name -notin $commonParameters) {
                New-ParameterXml -Command $Command -Parameter $parameter -Syntax
            }
        }
        @"
    <command:syntaxItem>
      <maml:name>$(ConvertTo-XmlText $Command.Name)</maml:name>
$($parameters -join "`n")
    </command:syntaxItem>
"@
    }
    return $items -join "`n"
}

function New-CommandParametersXml {
    param([Parameter(Mandatory)]$Command)

    $parameterSets = @($Command.ParameterSets)
    $parameters = foreach ($name in $Command.Parameters.Keys) {
        if ($name -in $commonParameters) { continue }
        $instances = @($parameterSets.Parameters | Where-Object Name -eq $name)
        if ($instances.Count -eq 0) { continue }

        $positions = @($instances.Position | Where-Object { $_ -ge 0 } | Sort-Object -Unique)
        $parameter = [pscustomobject]@{
            Name                            = $name
            IsMandatory                     = $instances.Count -eq $parameterSets.Count -and
                                              @($instances | Where-Object { -not $_.IsMandatory }).Count -eq 0
            Position                        = if ($positions.Count -eq 1) { $positions[0] } else { -1 }
            ValueFromPipeline                = @($instances | Where-Object ValueFromPipeline).Count -gt 0
            ValueFromPipelineByPropertyName  = @($instances | Where-Object ValueFromPipelineByPropertyName).Count -gt 0
            Aliases                          = @($instances.Aliases | Sort-Object -Unique)
            ParameterType                    = $instances[0].ParameterType
        }
        New-ParameterXml -Command $Command -Parameter $parameter
    }
    return $parameters -join "`n"
}

function New-NativeHelp {
    $commands = foreach ($entry in $catalog | Sort-Object Name) {
        $command = Get-Command -Module $module.Name -Name $entry.Name -CommandType Function
        if (-not $command) { throw "Exported command '$($entry.Name)' is not loaded." }
        $name = ConvertTo-XmlText $entry.Name
        $description = ConvertTo-XmlText $entry.Description
        $example = ConvertTo-XmlText $entry.Example
        $verb, $noun = $entry.Name -split '-', 2
        $verb = ConvertTo-XmlText $verb
        $noun = ConvertTo-XmlText $noun
        $syntax = New-CommandSyntaxXml -Command $command
        $parameters = New-CommandParametersXml -Command $command
        @"
  <command:command xmlns:maml="http://schemas.microsoft.com/maml/2004/10" xmlns:command="http://schemas.microsoft.com/maml/dev/command/2004/10" xmlns:dev="http://schemas.microsoft.com/maml/dev/2004/10">
    <command:details>
      <command:name>$name</command:name>
      <command:verb>$verb</command:verb>
      <command:noun>$noun</command:noun>
      <maml:description><maml:para>$description</maml:para></maml:description>
    </command:details>
    <maml:description><maml:para>$description</maml:para></maml:description>
    <command:syntax>
$syntax
    </command:syntax>
    <command:parameters>
$parameters
    </command:parameters>
    <command:inputTypes />
    <command:returnValues />
    <command:examples>
      <command:example>
        <maml:title>Example 1</maml:title>
        <dev:code>$example</dev:code>
        <dev:remarks><maml:para>Demonstrates $name in a TerminalSlides workflow.</maml:para></dev:remarks>
      </command:example>
    </command:examples>
    <command:relatedLinks />
  </command:command>
"@
    }

    return @"
<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by Scripts/Update-Documentation.ps1. Do not edit directly. -->
<helpItems schema="maml" xmlns="http://msh">
$($commands -join "`n")
</helpItems>
"@
}

function Set-GeneratedFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content
    )

    $normalizedContent = $Content.TrimEnd("`r", "`n") + "`n"
    if ($Check) {
        $actual = if (Test-Path -LiteralPath $Path) {
            (Get-Content -LiteralPath $Path -Raw).Replace("`r`n", "`n")
        }
        else {
            ''
        }
        if ($actual -ne $normalizedContent.Replace("`r`n", "`n")) {
            throw "Generated documentation is stale: $Path. Run Scripts/Update-Documentation.ps1."
        }
        return
    }

    Set-Content -LiteralPath $Path -Value $normalizedContent -Encoding utf8NoBOM -NoNewline
}

Assert-CommandCatalog
$websiteData = $catalog | ConvertTo-Json -Depth 10
Set-GeneratedFile -Path $websiteDataPath -Content $websiteData
Set-GeneratedFile -Path $helpPath -Content (New-NativeHelp)

if (-not $Check) {
    Write-Output 'Generated website command data and native PowerShell help.'
}
