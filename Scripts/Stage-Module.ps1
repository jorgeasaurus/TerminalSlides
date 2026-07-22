[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Destination
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$comparison = if ($IsWindows) {
    [System.StringComparison]::OrdinalIgnoreCase
}
else {
    [System.StringComparison]::Ordinal
}

function Resolve-PhysicalPath {
    param([Parameter(Mandatory)][string]$Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $root = [System.IO.Path]::GetPathRoot($fullPath)
    $current = $root
    $relativePath = $fullPath.Substring($root.Length)
    $parts = $relativePath.Split(
        [char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar),
        [System.StringSplitOptions]::RemoveEmptyEntries
    )
    foreach ($part in $parts) {
        $candidate = Join-Path $current $part
        if (Test-Path -LiteralPath $candidate) {
            $item = Get-Item -LiteralPath $candidate -Force
            if ($item.LinkType) {
                $target = $item.ResolveLinkTarget($true)
                if ($null -eq $target) { throw "Symbolic link '$candidate' could not be resolved." }
                $current = $target.FullName
                continue
            }
            $current = $item.FullName
            continue
        }
        $current = $candidate
    }
    return [System.IO.Path]::GetFullPath($current)
}

function Test-PathAncestor {
    param(
        [Parameter(Mandatory)][string]$Ancestor,
        [Parameter(Mandatory)][string]$Path
    )

    $ancestorWithSeparator = $Ancestor.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    ) + [System.IO.Path]::DirectorySeparatorChar
    return $Path.StartsWith($ancestorWithSeparator, $comparison)
}

$unresolvedDestination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Destination)
$resolvedRepositoryRoot = Resolve-PhysicalPath $repositoryRoot
$resolvedDestination = Resolve-PhysicalPath $unresolvedDestination

$destinationIsRepository = $resolvedDestination.Equals($resolvedRepositoryRoot, $comparison)
$destinationContainsRepository = Test-PathAncestor -Ancestor $resolvedDestination -Path $resolvedRepositoryRoot
$destinationIsInRepository = Test-PathAncestor -Ancestor $resolvedRepositoryRoot -Path $resolvedDestination
$buildRoot = Resolve-PhysicalPath (Join-Path $resolvedRepositoryRoot 'build')
$destinationIsBuildRoot = $resolvedDestination.Equals($buildRoot, $comparison)
$destinationIsInBuild = Test-PathAncestor -Ancestor $buildRoot -Path $resolvedDestination

if ($destinationIsRepository -or $destinationContainsRepository) {
    throw 'The module staging destination cannot be the repository root or one of its ancestors.'
}
if ($destinationIsInRepository -and ($destinationIsBuildRoot -or -not $destinationIsInBuild)) {
    throw 'A staging destination inside the repository must be a strict descendant of build/.'
}
& (Join-Path $PSScriptRoot 'Build-SchemaAssembly.ps1') -Check

$parent = Split-Path -Parent $resolvedDestination
New-Item -Path $parent -ItemType Directory -Force | Out-Null
$temporaryDestination = Join-Path $parent ".TerminalSlides-stage-$([Guid]::NewGuid().ToString('N'))"
$backupDestination = $null
$packageDefinitionPath = Join-Path $PSScriptRoot 'ModulePackage.psd1'
$packageDefinition = Import-PowerShellDataFile -Path $packageDefinitionPath
$packageFiles = @($packageDefinition.Files)
if ($packageFiles.Count -eq 0) {
    throw 'The module package inventory is empty.'
}
if (@($packageFiles | Sort-Object -Unique).Count -ne $packageFiles.Count) {
    throw 'The module package inventory contains duplicate paths.'
}
foreach ($relativePath in $packageFiles) {
    if ([System.IO.Path]::IsPathRooted($relativePath) -or
        $relativePath -split '[/\\]' -contains '..') {
        throw "The module package inventory contains an unsafe path: $relativePath"
    }
    $sourcePath = Join-Path $resolvedRepositoryRoot $relativePath
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "The module package inventory references a missing file: $relativePath"
    }
}

try {
    New-Item -Path $temporaryDestination -ItemType Directory | Out-Null
    foreach ($relativePath in $packageFiles) {
        $sourcePath = Join-Path $resolvedRepositoryRoot $relativePath
        $destinationPath = Join-Path $temporaryDestination $relativePath
        $destinationDirectory = Split-Path -Parent $destinationPath
        New-Item -Path $destinationDirectory -ItemType Directory -Force | Out-Null
        Copy-Item -LiteralPath $sourcePath -Destination $destinationPath
    }

    $stagedManifest = Join-Path $temporaryDestination 'TerminalSlides.psd1'
    Test-ModuleManifest -Path $stagedManifest | Out-Null
    & (Get-Process -Id $PID).Path -NoProfile -Command "Import-Module '$($stagedManifest.Replace("'", "''"))' -Force -ErrorAction Stop"
    if ($LASTEXITCODE -ne 0) {
        throw 'The staged module could not be imported in an isolated PowerShell process.'
    }

    if (Test-Path -LiteralPath $resolvedDestination) {
        $backupDestination = Join-Path $parent ".TerminalSlides-backup-$([Guid]::NewGuid().ToString('N'))"
        Move-Item -LiteralPath $resolvedDestination -Destination $backupDestination
    }
    try {
        Move-Item -LiteralPath $temporaryDestination -Destination $resolvedDestination
    }
    catch {
        if ($backupDestination -and (Test-Path -LiteralPath $backupDestination)) {
            Move-Item -LiteralPath $backupDestination -Destination $resolvedDestination
        }
        throw
    }
    if ($backupDestination -and (Test-Path -LiteralPath $backupDestination)) {
        Remove-Item -LiteralPath $backupDestination -Recurse -Force
    }
}
finally {
    if (Test-Path -LiteralPath $temporaryDestination) {
        Remove-Item -LiteralPath $temporaryDestination -Recurse -Force
    }
    if ($backupDestination -and
        (Test-Path -LiteralPath $backupDestination) -and
        (Test-Path -LiteralPath $resolvedDestination)) {
        Remove-Item -LiteralPath $backupDestination -Recurse -Force
    }
}

Get-Item -LiteralPath $resolvedDestination
