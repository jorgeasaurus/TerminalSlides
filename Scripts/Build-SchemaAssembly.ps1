[CmdletBinding()]
param([switch]$Check)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$project = Join-Path $repositoryRoot 'Classes/TerminalSlides.Schema.csproj'
$libraryDirectory = Join-Path $repositoryRoot 'lib'
$assemblyPath = Join-Path $libraryDirectory 'TerminalSlides.Schema.dll'
$temporaryOutput = Join-Path ([IO.Path]::GetTempPath()) "TerminalSlides-schema-$([guid]::NewGuid().ToString('N'))"

Push-Location -LiteralPath $repositoryRoot
try {
    & dotnet build $project --configuration Release --output $temporaryOutput --nologo --verbosity quiet
    if ($LASTEXITCODE -ne 0) { throw 'Schema assembly build failed.' }

    $builtAssembly = Join-Path $temporaryOutput 'TerminalSlides.Schema.dll'
    if ($Check) {
        if (-not (Test-Path -LiteralPath $assemblyPath -PathType Leaf)) {
            throw "Packaged schema assembly is missing: $assemblyPath"
        }
        if ((Get-FileHash -LiteralPath $builtAssembly).Hash -ne (Get-FileHash -LiteralPath $assemblyPath).Hash) {
            throw 'Packaged schema assembly is stale. Run Scripts/Build-SchemaAssembly.ps1.'
        }
        return
    }

    [void][IO.Directory]::CreateDirectory($libraryDirectory)
    Copy-Item -LiteralPath $builtAssembly -Destination $assemblyPath -Force
}
finally {
    try {
        Pop-Location
    }
    finally {
        if (Test-Path -LiteralPath $temporaryOutput) {
            Remove-Item -LiteralPath $temporaryOutput -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
