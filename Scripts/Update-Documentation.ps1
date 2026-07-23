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

function Get-ParameterDefaultValue {
    param(
        [Parameter(Mandatory)]$Command,
        [Parameter(Mandatory)][string]$Name
    )

    $parameterBlock = if (
        $Command.ScriptBlock.Ast -is [System.Management.Automation.Language.FunctionDefinitionAst]
    ) {
        $Command.ScriptBlock.Ast.Body.ParamBlock
    }
    else {
        $Command.ScriptBlock.Ast.ParamBlock
    }
    $parameterAst = $parameterBlock.Parameters |
        Where-Object { $_.Name.VariablePath.UserPath -eq $Name } |
        Select-Object -First 1
    if (-not $parameterAst.DefaultValue) { return 'None' }
    if ($parameterAst.DefaultValue -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
        $parameterAst.DefaultValue -is [System.Management.Automation.Language.ExpandableStringExpressionAst] -or
        $parameterAst.DefaultValue -is [System.Management.Automation.Language.ConstantExpressionAst]) {
        return [string]$parameterAst.DefaultValue.Value
    }
    return $parameterAst.DefaultValue.Extent.Text
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
    $defaultValue = ConvertTo-XmlText (Get-ParameterDefaultValue -Command $Command -Name $Parameter.Name)
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
$indent  <dev:defaultValue>$defaultValue</dev:defaultValue>
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
            IsMandatory                     = @($instances | Where-Object IsMandatory).Count -gt 0
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

function ConvertTo-HtmlText {
    param([AllowEmptyString()][string]$Text)

    return [System.Net.WebUtility]::HtmlEncode($Text)
}

function Get-CommandSyntaxText {
    param([Parameter(Mandatory)]$Command)

    $lines = foreach ($parameterSet in $Command.ParameterSets) {
        $parts = [System.Collections.Generic.List[string]]::new()
        $parts.Add($Command.Name)
        foreach ($parameter in $parameterSet.Parameters) {
            if ($parameter.Name -in $commonParameters) { continue }
            $value = if ($parameter.ParameterType -eq [System.Management.Automation.SwitchParameter]) {
                "-$($parameter.Name)"
            }
            else {
                "-$($parameter.Name) <$($parameter.ParameterType.Name)>"
            }
            if (-not $parameter.IsMandatory) { $value = "[$value]" }
            $parts.Add($value)
        }
        $parts -join ' '
    }
    return $lines -join "`n`n"
}

function Get-CommandParameterDocumentation {
    param([Parameter(Mandatory)]$Command)

    $parameterSets = @($Command.ParameterSets)
    foreach ($name in $Command.Parameters.Keys | Sort-Object) {
        if ($name -in $commonParameters) { continue }
        $instances = @($parameterSets.Parameters | Where-Object Name -eq $name)
        if ($instances.Count -eq 0) { continue }
        $positions = @($instances.Position | Where-Object { $_ -ge 0 } | Sort-Object -Unique)
        $parameter = $Command.Parameters[$name]
        $validateSet = $parameter.Attributes |
            Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } |
            Select-Object -First 1
        [pscustomobject]@{
            Name = $name
            Type = $parameter.ParameterType.FullName
            Required = @($instances | Where-Object IsMandatory).Count -gt 0
            Position = if ($positions.Count -eq 1) { [string]$positions[0] } else { 'Named' }
            Pipeline = Get-PipelineInputText -Parameter ([pscustomobject]@{
                ValueFromPipeline = @($instances | Where-Object ValueFromPipeline).Count -gt 0
                ValueFromPipelineByPropertyName =
                    @($instances | Where-Object ValueFromPipelineByPropertyName).Count -gt 0
            })
            AcceptedValues = if ($validateSet) { $validateSet.ValidValues -join ', ' } else { $null }
        }
    }
}

function New-CommandGuideHtml {
    param(
        [Parameter(Mandatory)]$Entry,
        [Parameter(Mandatory)]$Command,
        [AllowNull()]$PreviousEntry,
        [AllowNull()]$NextEntry
    )

    $name = ConvertTo-HtmlText $Entry.Name
    $description = ConvertTo-HtmlText $Entry.Description
    $example = ConvertTo-HtmlText $Entry.Example
    $syntax = ConvertTo-HtmlText (Get-CommandSyntaxText -Command $Command)
    $parameters = @(Get-CommandParameterDocumentation -Command $Command)
    $parameterHtml = if ($parameters.Count -eq 0) {
        '<p>This command has no command-specific parameters.</p>'
    }
    else {
        ($parameters | ForEach-Object {
            $acceptedValues = if ($_.AcceptedValues) {
                "<p><strong>Accepted values:</strong> $(ConvertTo-HtmlText $_.AcceptedValues)</p>"
            }
            else { '' }
            @"
        <section class="parameter-card" id="parameter-$($_.Name.ToLowerInvariant())">
          <h3>-$([System.Net.WebUtility]::HtmlEncode($_.Name))</h3>
          <p>Specifies the $([System.Net.WebUtility]::HtmlEncode($_.Name)) value.</p>
          $acceptedValues
          <dl>
            <div><dt>Type</dt><dd><code>$(ConvertTo-HtmlText $_.Type)</code></dd></div>
            <div><dt>Required</dt><dd>$($_.Required.ToString().ToLowerInvariant())</dd></div>
            <div><dt>Position</dt><dd>$(ConvertTo-HtmlText $_.Position)</dd></div>
            <div><dt>Pipeline input</dt><dd>$(ConvertTo-HtmlText $_.Pipeline)</dd></div>
          </dl>
        </section>
"@
        }) -join "`n"
    }
    $previousLink = if ($PreviousEntry) {
        "<a href=`"../$($PreviousEntry.Name.ToLowerInvariant())/`"><span>Previous</span>$([System.Net.WebUtility]::HtmlEncode($PreviousEntry.Name))</a>"
    }
    else { '<span></span>' }
    $nextLink = if ($NextEntry) {
        "<a class=`"next`" href=`"../$($NextEntry.Name.ToLowerInvariant())/`"><span>Next</span>$([System.Net.WebUtility]::HtmlEncode($NextEntry.Name))</a>"
    }
    else { '<span></span>' }

    return @"
<!doctype html>
<html lang="en" data-theme="dark">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="description" content="$description">
  <title>$name | TerminalSlides</title>
  <link rel="stylesheet" href="../../../guides.css">
  <script src="../../../guides.js" defer></script>
</head>
<body data-root="../../../" data-current-command="$name">
  <a class="skip-link" href="#content">Skip to content</a>
  <header class="docs-header">
    <a class="docs-brand" href="../../../"><span>&gt;_</span> TerminalSlides</a>
    <div class="docs-header-actions">
      <button type="button" class="header-search" data-search-focus>Search <kbd>/</kbd></button>
      <a href="https://github.com/jorgeasaurus/TerminalSlides">GitHub</a>
      <button type="button" class="icon-button" data-theme-toggle aria-label="Switch color theme">◐</button>
      <button type="button" class="icon-button menu-button" data-sidebar-toggle aria-label="Open guide navigation">Menu</button>
    </div>
  </header>
  <div class="docs-shell">
    <aside class="docs-sidebar" data-sidebar>
      <label class="sidebar-search"><span>Search commands</span><input type="search" data-command-search placeholder="Filter commands"></label>
      <nav data-command-navigation aria-label="Guide navigation"></nav>
    </aside>
    <main class="docs-article" id="content">
      <p class="breadcrumb"><a href="../../">Guides</a> / Command reference</p>
      <h1>$name</h1>
      <section id="description">
        <h2>Description</h2>
        <p>$description</p>
      </section>
      <section id="examples">
        <h2>Examples</h2>
        <h3>Example 1</h3>
        <pre><code>$example</code></pre>
      </section>
      <section id="parameters">
        <h2>Parameters</h2>
$parameterHtml
      </section>
      <section id="syntax">
        <h2>Syntax</h2>
        <pre><code>$syntax</code></pre>
      </section>
      <nav class="pagination" aria-label="Command pagination">$previousLink$nextLink</nav>
    </main>
    <aside class="page-toc">
      <strong>On this page</strong>
      <a href="#description">Description</a>
      <a href="#examples">Examples</a>
      <a href="#parameters">Parameters</a>
      <a href="#syntax">Syntax</a>
    </aside>
  </div>
</body>
</html>
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

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $parent -Force)
    }
    Set-Content -LiteralPath $Path -Value $normalizedContent -Encoding utf8NoBOM -NoNewline
}

Assert-CommandCatalog
$websiteData = $catalog | ConvertTo-Json -Depth 10
Set-GeneratedFile -Path $websiteDataPath -Content $websiteData
Set-GeneratedFile -Path $helpPath -Content (New-NativeHelp)
$sortedCatalog = @($catalog | Sort-Object Name)
for ($index = 0; $index -lt $sortedCatalog.Count; $index++) {
    $entry = $sortedCatalog[$index]
    $command = Get-Command -Module $module.Name -Name $entry.Name -CommandType Function
    $previousEntry = if ($index -gt 0) { $sortedCatalog[$index - 1] } else { $null }
    $nextEntry = if ($index -lt $sortedCatalog.Count - 1) { $sortedCatalog[$index + 1] } else { $null }
    $guidePath = Join-Path $repositoryRoot 'docs' 'guides' 'commands' `
        $entry.Name.ToLowerInvariant() 'index.html'
    Set-GeneratedFile -Path $guidePath -Content (
        New-CommandGuideHtml -Entry $entry -Command $command `
            -PreviousEntry $previousEntry -NextEntry $nextEntry
    )
}

if (-not $Check) {
    Write-Output 'Generated website command data, command guides, and native PowerShell help.'
}
