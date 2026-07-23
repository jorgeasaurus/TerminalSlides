Describe 'Module package staging' {
    BeforeAll {
        $script:RepositoryRoot = Join-Path $PSScriptRoot '..' '..'
        $script:StageScript = Join-Path $script:RepositoryRoot 'Scripts/Stage-Module.ps1'
        $script:PackageDefinitionPath = Join-Path $script:RepositoryRoot 'Scripts/ModulePackage.psd1'
        $script:PackageFiles = @((Import-PowerShellDataFile $script:PackageDefinitionPath).Files)

        function New-TestPackageSource {
            param([Parameter(Mandatory)][string]$Path)

            foreach ($relativePath in $script:PackageFiles) {
                $source = Join-Path $script:RepositoryRoot $relativePath
                $destination = Join-Path $Path $relativePath
                New-Item -Path (Split-Path -Parent $destination) -ItemType Directory -Force | Out-Null
                Copy-Item -LiteralPath $source -Destination $destination
            }
            foreach ($relativePath in @(
                'Scripts/Stage-Module.ps1'
                'Scripts/ModulePackage.psd1'
                'Scripts/Build-SchemaAssembly.ps1'
                'Classes/TerminalSlides.Schema.csproj'
                'Classes/TerminalSlides.DataClasses.cs'
                'global.json'
            )) {
                $destination = Join-Path $Path $relativePath
                New-Item -Path (Split-Path -Parent $destination) -ItemType Directory -Force | Out-Null
                Copy-Item -LiteralPath (Join-Path $script:RepositoryRoot $relativePath) -Destination $destination
            }
        }

        function Get-PackageRelativeFiles {
            param([Parameter(Mandatory)][string]$Path)

            return @(Get-ChildItem -LiteralPath $Path -File -Recurse | ForEach-Object {
                [System.IO.Path]::GetRelativePath($Path, $_.FullName).Replace('\', '/')
            } | Sort-Object)
        }
    }

    It 'creates a validated package with exactly the declared distributable inventory' {
        $destination = Join-Path $TestDrive 'TerminalSlides'
        $manifest = Import-PowerShellDataFile (Join-Path $script:RepositoryRoot 'TerminalSlides.psd1')
        $runtimeFiles = @(
            'Classes/TerminalSlidesClasses.ps1'
            foreach ($directory in 'Layouts', 'Private', 'Public', 'Renderers') {
                Get-ChildItem -LiteralPath (Join-Path $script:RepositoryRoot $directory) -Filter '*.ps1' -File |
                    ForEach-Object { [System.IO.Path]::GetRelativePath($script:RepositoryRoot, $_.FullName).Replace('\', '/') }
            }
            Get-ChildItem -LiteralPath (Join-Path $script:RepositoryRoot 'Themes') -Filter '*.psd1' -File |
                ForEach-Object { [System.IO.Path]::GetRelativePath($script:RepositoryRoot, $_.FullName).Replace('\', '/') }
            $manifest.RequiredAssemblies
        )

        @($runtimeFiles | Where-Object { $_ -notin $script:PackageFiles }) | Should -BeNullOrEmpty
        & $script:StageScript -Destination $destination | Out-Null

        Get-PackageRelativeFiles -Path $destination |
            Should -Be @($script:PackageFiles | Sort-Object)
        Get-PackageRelativeFiles -Path $destination |
            Should -Not -Contain 'Classes/TerminalSlides.DataClasses.cs'
        Get-PackageRelativeFiles -Path $destination |
            Should -Not -Contain 'Classes/TerminalSlides.Schema.csproj'
        Get-PackageRelativeFiles -Path $destination |
            Should -Not -Contain 'global.json'
        { Test-ModuleManifest (Join-Path $destination 'TerminalSlides.psd1') } | Should -Not -Throw
    }

    It 'does not package ignored or undeclared files from a runtime source directory' {
        $sourceRoot = Join-Path $TestDrive 'source-with-incidental'
        New-TestPackageSource -Path $sourceRoot
        Set-Content -LiteralPath (Join-Path $sourceRoot 'Private/local-debug.log') -Value 'not distributable'
        Set-Content -LiteralPath (Join-Path $sourceRoot 'Assets/.DS_Store') -Value 'not distributable'
        $destination = Join-Path $TestDrive 'incidental-stage'

        & (Join-Path $sourceRoot 'Scripts/Stage-Module.ps1') -Destination $destination | Out-Null

        Get-PackageRelativeFiles -Path $destination |
            Should -Be @($script:PackageFiles | Sort-Object)
    }

    It 'preserves a prior stage when validation fails' {
        $sourceRoot = Join-Path $TestDrive 'invalid-source'
        New-TestPackageSource -Path $sourceRoot
        Set-Content -LiteralPath (Join-Path $sourceRoot 'TerminalSlides.psd1') -Value '@{ this is not valid data }'
        $destination = Join-Path $TestDrive 'validated-stage'
        New-Item -Path $destination -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $destination 'preserved.txt') -Value preserved

        { & (Join-Path $sourceRoot 'Scripts/Stage-Module.ps1') -Destination $destination } |
            Should -Throw

        (Get-Content -LiteralPath (Join-Path $destination 'preserved.txt') -Raw).Trim() |
            Should -Be 'preserved'
        Join-Path $destination 'TerminalSlides.psd1' | Should -Not -Exist
    }

    It 'rejects a stale copied schema assembly before replacing a prior stage' {
        $sourceRoot = Join-Path $TestDrive 'stale-schema-source'
        New-TestPackageSource -Path $sourceRoot
        $assemblyPath = Join-Path $sourceRoot 'lib/TerminalSlides.Schema.dll'
        $bytes = [System.IO.File]::ReadAllBytes($assemblyPath)
        $bytes[0] = $bytes[0] -bxor 0xff
        [System.IO.File]::WriteAllBytes($assemblyPath, $bytes)
        $destination = Join-Path $TestDrive 'preserved-schema-stage'
        New-Item -Path $destination -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $destination 'preserved.txt') -Value preserved

        { & (Join-Path $sourceRoot 'Scripts/Stage-Module.ps1') -Destination $destination } |
            Should -Throw '*Packaged schema assembly is stale*'

        (Get-Content -LiteralPath (Join-Path $destination 'preserved.txt') -Raw).Trim() |
            Should -Be 'preserved'
        Join-Path $destination 'TerminalSlides.psd1' | Should -Not -Exist
    }

    It 'restores a prior stage when the atomic swap fails' {
        $destination = Join-Path $TestDrive 'swap-stage'
        New-Item -Path $destination -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $destination 'preserved.txt') -Value preserved
        $script:MoveInvocation = 0
        Mock Move-Item {
            param($Path, $LiteralPath, $Destination)

            $script:MoveInvocation++
            if ($script:MoveInvocation -eq 2) {
                throw 'INTENTIONAL-STAGE-SWAP-FAILURE'
            }
            if ($LiteralPath) {
                Microsoft.PowerShell.Management\Move-Item -LiteralPath $LiteralPath -Destination $Destination
            }
            else {
                Microsoft.PowerShell.Management\Move-Item -Path $Path -Destination $Destination
            }
        }

        { & $script:StageScript -Destination $destination } |
            Should -Throw '*INTENTIONAL-STAGE-SWAP-FAILURE*'

        (Get-Content -LiteralPath (Join-Path $destination 'preserved.txt') -Raw).Trim() |
            Should -Be 'preserved'
        Join-Path $destination 'TerminalSlides.psd1' | Should -Not -Exist
    }

    It 'rejects the repository, its ancestors, runtime directories, and the build root before writing' {
        $repositoryParent = Split-Path -Parent ([System.IO.Path]::GetFullPath($script:RepositoryRoot))
        $publicDirectory = Join-Path $script:RepositoryRoot 'Public'
        $buildRoot = Join-Path $script:RepositoryRoot 'build'

        { & $script:StageScript -Destination $script:RepositoryRoot } |
            Should -Throw '*repository root or one of its ancestors*'
        { & $script:StageScript -Destination $repositoryParent } |
            Should -Throw '*repository root or one of its ancestors*'
        { & $script:StageScript -Destination $publicDirectory } |
            Should -Throw '*strict descendant of build*'
        { & $script:StageScript -Destination $buildRoot } |
            Should -Throw '*strict descendant of build*'
    }

    It 'permits an isolated destination and a strict descendant of build' {
        $isolatedDestination = Join-Path $TestDrive 'isolated/TerminalSlides'
        $buildDestination = Join-Path $script:RepositoryRoot 'build/package-contract/TerminalSlides'

        { & $script:StageScript -Destination $isolatedDestination } | Should -Not -Throw
        { & $script:StageScript -Destination $buildDestination } | Should -Not -Throw
    }

    It 'permits the standard macOS temporary-directory symlink' -Skip:(-not $IsMacOS) {
        $destination = "/tmp/TerminalSlidesPackage-$PID-$([guid]::NewGuid().ToString('N'))"
        try {
            { & $script:StageScript -Destination $destination } | Should -Not -Throw
            Test-Path (Join-Path $destination 'TerminalSlides.psd1') | Should -BeTrue
        }
        finally {
            Remove-Item -LiteralPath $destination -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects a destination that reaches runtime content through a symbolic link' {
        $linkPath = Join-Path $script:RepositoryRoot 'build/package-contract-link'
        try {
            New-Item -Path $linkPath -ItemType SymbolicLink `
                -Target (Join-Path $script:RepositoryRoot 'Public') -ErrorAction Stop | Out-Null
        }
        catch {
            Set-ItResult -Skipped -Because 'This runner cannot create symbolic links.'
            return
        }

        try {
            { & $script:StageScript -Destination (Join-Path $linkPath 'TerminalSlides') } |
                Should -Throw '*strict descendant of build*'
        }
        finally {
            Remove-Item -LiteralPath $linkPath -Force
        }
    }
}
