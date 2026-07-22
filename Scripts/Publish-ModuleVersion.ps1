[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ModulePath,
    [Parameter(Mandatory)][string]$ApiKey,
    [string]$Repository = 'PSGallery'
)

$ErrorActionPreference = 'Stop'
$resolvedModulePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ModulePath)
$manifestPath = Get-ChildItem -LiteralPath $resolvedModulePath -Filter '*.psd1' -File |
    Select-Object -First 1 -ExpandProperty FullName
if (-not $manifestPath) {
    throw "No module manifest was found in '$resolvedModulePath'."
}

$manifest = Test-ModuleManifest -Path $manifestPath
$moduleName = [System.IO.Path]::GetFileNameWithoutExtension($manifestPath)
$version = [version]$manifest.Version

function Find-PublishedModuleVersion {
    Find-Module -Name $moduleName -RequiredVersion $version -Repository $Repository -ErrorAction SilentlyContinue
}

$publishedModule = Find-PublishedModuleVersion
if ($publishedModule) {
    Write-Output "$moduleName $version is already published to $Repository."
    return
}

try {
    Publish-Module -Path $resolvedModulePath -NuGetApiKey $ApiKey -Repository $Repository -Force
}
catch {
    # A prior attempt can publish successfully while the workflow loses its response.
    # Confirm the immutable version before deciding that this retry failed.
    if (-not (Find-PublishedModuleVersion)) {
        throw
    }
}

Write-Output "$moduleName $version is published to $Repository."
