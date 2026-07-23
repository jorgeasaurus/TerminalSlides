Describe 'Build automation' {
    BeforeAll {
        $script:RepositoryRoot = Join-Path $PSScriptRoot '..' '..'
        $script:BuildPath = Join-Path $script:RepositoryRoot 'build.ps1'
        $script:PowerShellPath = Get-Command pwsh -CommandType Application `
            -ErrorAction Stop | Select-Object -First 1 -ExpandProperty Source
    }

    It 'returns a nonzero process exit code when a Pester test fails' {
        $fixturePath = Join-Path $script:RepositoryRoot `
            'TestInfrastructure/Fixtures/Failing.Tests.ps1'
        $resultPath = Join-Path $TestDrive 'failing-test-results.xml'

        $output = & $script:PowerShellPath -NoProfile -File $script:BuildPath `
            -TestPath $fixturePath -TestResultPath $resultPath `
            -SkipScriptAnalyzer 2>&1

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
                -TestPath $PSCommandPath -TestResultPath $resultPath `
                -SkipScriptAnalyzer 2>&1
        }
        finally {
            $env:PATH = $originalPath
            $env:TERMINALSLIDES_RUN_TMUX_TESTS = $originalTmuxSetting
        }

        $LASTEXITCODE | Should -Not -Be 0
        ($output -join "`n") | Should -Match `
            'TERMINALSLIDES_RUN_TMUX_TESTS=1 requires tmux'
    }

    It 'uses the build script as the single workflow test entry point' {
        $workflow = Get-Content -LiteralPath (
            Join-Path $script:RepositoryRoot '.github/workflows/ci.yml'
        ) -Raw

        @([regex]::Matches($workflow, '(?m)^\s+run: \./build\.ps1(?:\s.*)?$')) |
            Should -HaveCount 2
        $workflow | Should -Not -Match '(?m)^\s+run: Invoke-Pester'
        @([regex]::Matches($workflow, '(?m)^\s+if-no-files-found: warn\r?$')) |
            Should -HaveCount 2
    }

    It 'unloads conflicting module versions before importing pinned tools' {
        $buildScript = Get-Content -LiteralPath $script:BuildPath -Raw

        $buildScript | Should -Match 'Get-Module -Name \$Name'
        $buildScript | Should -Match 'Where-Object Version -ne \$Version'
        $buildScript | Should -Match 'Remove-Module -Force'
    }
}
