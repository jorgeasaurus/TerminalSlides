Describe 'Build automation' {
    BeforeAll {
        $script:RepositoryRoot = Join-Path $PSScriptRoot '..' '..'
        $script:BuildPath = Join-Path $script:RepositoryRoot 'build.ps1'
        $script:PowerShellPath = Get-Command pwsh -CommandType Application `
            -ErrorAction Stop | Select-Object -First 1 -ExpandProperty Source
        $script:PublishScript = Join-Path $script:RepositoryRoot 'Scripts/Publish-ModuleVersion.ps1'

        function New-PublishFixture {
            param([Parameter(Mandatory)][string]$Path)

            New-Item -Path $Path -ItemType Directory -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $Path 'TerminalSlides.psm1') -Value ''
            New-ModuleManifest -Path (Join-Path $Path 'TerminalSlides.psd1') `
                -RootModule 'TerminalSlides.psm1' -ModuleVersion '9.8.7'
        }

        function New-SchemaBuildFixture {
            param([Parameter(Mandatory)][string]$Path)

            foreach ($relativePath in @(
                'Scripts/Build-SchemaAssembly.ps1'
                'Classes/TerminalSlides.Schema.csproj'
                'Classes/TerminalSlides.DataClasses.cs'
                'lib/TerminalSlides.Schema.dll'
                'global.json'
            )) {
                $destination = Join-Path $Path $relativePath
                New-Item -Path (Split-Path -Parent $destination) -ItemType Directory -Force | Out-Null
                Copy-Item -LiteralPath (Join-Path $script:RepositoryRoot $relativePath) -Destination $destination
            }
        }

        function Set-SchemaAssemblyStale {
            param([Parameter(Mandatory)][string]$Path)

            $bytes = [System.IO.File]::ReadAllBytes($Path)
            $bytes[0] = $bytes[0] -bxor 0xff
            [System.IO.File]::WriteAllBytes($Path, $bytes)
        }

        function Get-WorkflowJobBlocks {
            param([Parameter(Mandatory)][string]$Text)

            return @([regex]::Matches(
                $Text,
                '(?ms)^  (?<Name>[a-z0-9-]+):\r?\n(?<Body>.*?)(?=^  [a-z0-9-]+:|\z)'
            ) | ForEach-Object {
                [pscustomobject]@{ Name = $_.Groups['Name'].Value; Body = $_.Groups['Body'].Value }
            })
        }
    }

    It 'gates normal builds on the reproducible schema assembly' {
        $build = Get-Content -LiteralPath $script:BuildPath -Raw
        $schemaGate = "& (Join-Path `$PSScriptRoot 'Scripts/Build-SchemaAssembly.ps1') -Check"

        $build.IndexOf($schemaGate) | Should -BeGreaterOrEqual 0
        $build.IndexOf($schemaGate) |
            Should -BeLessThan $build.IndexOf("& (Join-Path `$PSScriptRoot 'Scripts/Update-Documentation.ps1') -Check")
    }

    It 'uses the repository SDK and restores an external caller location on success and failure' {
        $fixtureRoot = Join-Path $TestDrive 'schema-repository'
        $callerRoot = Join-Path $TestDrive 'hostile-caller'
        New-SchemaBuildFixture -Path $fixtureRoot
        New-Item -Path $callerRoot -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $callerRoot 'global.json') -Value @'
{"sdk":{"version":"99.0.100","rollForward":"disable"}}
'@

        Push-Location -LiteralPath $callerRoot
        try {
            $callerLocation = (Get-Location).Path
            { & (Join-Path $fixtureRoot 'Scripts/Build-SchemaAssembly.ps1') -Check } |
                Should -Not -Throw
            (Get-Location).Path | Should -BeExactly $callerLocation

            Set-SchemaAssemblyStale -Path (Join-Path $fixtureRoot 'lib/TerminalSlides.Schema.dll')
            { & (Join-Path $fixtureRoot 'Scripts/Build-SchemaAssembly.ps1') -Check } |
                Should -Throw '*Packaged schema assembly is stale*'
            (Get-Location).Path | Should -BeExactly $callerLocation
        }
        finally {
            Pop-Location
        }
    }

    It 'returns a nonzero process exit code when a Pester test fails' {
        $fixturePath = Join-Path $script:RepositoryRoot 'TestInfrastructure/Fixtures/Failing.Tests.ps1'
        $resultPath = Join-Path $TestDrive 'failing-test-results.xml'

        $output = & $script:PowerShellPath -NoProfile -File $script:BuildPath `
            -TestPath $fixturePath -TestResultPath $resultPath -SkipCodeCoverage -SkipScriptAnalyzer 2>&1

        $LASTEXITCODE | Should -Not -Be 0
        ($output -join "`n") | Should -Match 'Pester reported result.*Failed'
    }

    It 'fails explicitly when tmux tests are requested without tmux on PATH' {
        $resultPath = Join-Path $TestDrive 'tmux-test-results.xml'
        $originalPath = $env:PATH
        $originalTmuxSetting = $env:TERMINALSLIDES_RUN_TMUX_TESTS
        try {
            $env:PATH = $TestDrive
            $env:TERMINALSLIDES_RUN_TMUX_TESTS = '1'
            $output = & $script:PowerShellPath -NoProfile -File $script:BuildPath `
                -TestPath $PSCommandPath -TestResultPath $resultPath -SkipCodeCoverage -SkipScriptAnalyzer 2>&1
        }
        finally {
            $env:PATH = $originalPath
            $env:TERMINALSLIDES_RUN_TMUX_TESTS = $originalTmuxSetting
        }

        $LASTEXITCODE | Should -Not -Be 0
        ($output -join "`n") | Should -Match 'TERMINALSLIDES_RUN_TMUX_TESTS=1 requires tmux'
    }

    It 'skips an immutable module version that is already published' {
        $modulePath = Join-Path $TestDrive 'already-published'
        New-PublishFixture -Path $modulePath
        Mock Find-Module { [pscustomobject]@{ Name = 'TerminalSlides'; Version = [version]'9.8.7' } }
        Mock Publish-Module {}

        & $script:PublishScript -ModulePath $modulePath -ApiKey secret | Should -Match 'already published'

        Should -Invoke Find-Module -Times 1 -Exactly
        Should -Invoke Publish-Module -Times 0 -Exactly
    }

    It 'publishes a module version that is not present' {
        $modulePath = Join-Path $TestDrive 'not-published'
        New-PublishFixture -Path $modulePath
        Mock Find-Module {}
        Mock Publish-Module {}

        & $script:PublishScript -ModulePath $modulePath -ApiKey secret | Should -Match 'is published'

        Should -Invoke Publish-Module -Times 1 -Exactly -ParameterFilter {
            $Path -eq $modulePath -and $NuGetApiKey -eq 'secret' -and $Repository -eq 'PSGallery'
        }
    }

    It 'treats a publish response failure as success only when the exact version is now visible' {
        $modulePath = Join-Path $TestDrive 'lost-response'
        New-PublishFixture -Path $modulePath
        $script:FindInvocation = 0
        Mock Find-Module {
            $script:FindInvocation++
            if ($script:FindInvocation -gt 1) {
                [pscustomobject]@{ Name = 'TerminalSlides'; Version = [version]'9.8.7' }
            }
        }
        Mock Publish-Module { throw 'INTENTIONAL-LOST-PUBLISH-RESPONSE' }

        { & $script:PublishScript -ModulePath $modulePath -ApiKey secret } | Should -Not -Throw

        Should -Invoke Find-Module -Times 2 -Exactly
        Should -Invoke Publish-Module -Times 1 -Exactly
    }

    It 'fails publication when the immutable version remains unavailable after an error' {
        $modulePath = Join-Path $TestDrive 'failed-publish'
        New-PublishFixture -Path $modulePath
        Mock Find-Module {}
        Mock Publish-Module { throw 'INTENTIONAL-PUBLISH-FAILURE' }

        { & $script:PublishScript -ModulePath $modulePath -ApiKey secret } |
            Should -Throw '*INTENTIONAL-PUBLISH-FAILURE*'

        Should -Invoke Find-Module -Times 2 -Exactly
        Should -Invoke Publish-Module -Times 1 -Exactly
    }

    It 'keeps quality gates single-run and makes release and Pages deployment retry-safe' {
        $ci = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot '.github/workflows/ci.yml') -Raw
        $pages = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot '.github/workflows/pages.yml') -Raw

        @([regex]::Matches($ci, '(?m)^\s+run: \./build\.ps1\s*$')) | Should -HaveCount 1
        $ci | Should -Match 'run: \./build\.ps1 -SkipCodeCoverage -SkipScriptAnalyzer'
        @([regex]::Matches($ci, '(?m)^\s+if-no-files-found: warn\r?$')) |
            Should -HaveCount 3
        $ci | Should -Match 'Scripts/Publish-ModuleVersion\.ps1'
        $ci | Should -Match 'gh release view .*--json isDraft'
        $ci.IndexOf('Publish to PowerShell Gallery') |
            Should -BeLessThan $ci.IndexOf('Finalize GitHub release')

        $pages | Should -Match 'npm ci'
        $pages | Should -Match 'playwright install --with-deps chromium'
        $pages.IndexOf('npm run test:docs') | Should -BeLessThan $pages.IndexOf('Upload site')
    }

    It 'pins one exact SDK for every workflow job that validates the schema assembly' {
        $sdk = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot 'global.json') -Raw |
            ConvertFrom-Json
        $ci = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot '.github/workflows/ci.yml') -Raw
        $pages = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot '.github/workflows/pages.yml') -Raw
        $setupAction = 'actions/setup-dotnet@d4c94342e560b34958eacfc5d055d21461ed1c5d'
        $schemaEntrypoints = '\./build\.ps1|Build-SchemaAssembly\.ps1|Stage-Module\.ps1'
        $schemaJobs = @(Get-WorkflowJobBlocks -Text "$ci`n$pages" |
            Where-Object Body -Match $schemaEntrypoints)

        $sdk.sdk.version | Should -BeExactly '10.0.301'
        $sdk.sdk.rollForward | Should -BeExactly 'disable'
        $sdk.sdk.allowPrerelease | Should -BeFalse
        @($schemaJobs.Name) | Should -Be @('quality', 'compatibility', 'keyboard-controls', 'deploy')
        foreach ($job in $schemaJobs) {
            $job.Body | Should -Match ([regex]::Escape($setupAction))
            $job.Body | Should -Match "dotnet-version:\s*'$([regex]::Escape($sdk.sdk.version))'"
        }
    }

    It 'does not allow packaged Markdown changes to bypass CI' {
        $ci = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot '.github/workflows/ci.yml') -Raw
        $packageDefinition = Import-PowerShellDataFile (
            Join-Path $script:RepositoryRoot 'Scripts/ModulePackage.psd1'
        )
        $packagedMarkdown = @($packageDefinition.Files | Where-Object { [IO.Path]::GetExtension($_) -eq '.md' })

        $packagedMarkdown | Should -Contain 'README.md'
        $ci | Should -Not -Match "(?m)^\s*-\s*['`"]?\*\*\.md['`"]?\s*$"
    }

    It 'unloads conflicting module versions before importing pinned tools' {
        $buildScript = Get-Content -LiteralPath $script:BuildPath -Raw

        $buildScript | Should -Match 'Get-Module -Name \$Name'
        $buildScript | Should -Match 'Where-Object Version -ne \$Version'
        $buildScript | Should -Match 'Remove-Module -Force'
    }

    It 'does not expose an inert code coverage switch' {
        $buildScript = Get-Content -LiteralPath $script:BuildPath -Raw
        $coverageSwitchReferences = @([regex]::Matches($buildScript, '\$SkipCodeCoverage')).Count

        $coverageSwitchReferences | Should -Not -Be 1
    }
}
