$repositoryRoot = Join-Path $PSScriptRoot '..' '..'
$exampleCases = @(
    Get-ChildItem -LiteralPath (Join-Path $repositoryRoot 'Examples') -Filter '*.ps1' -File |
        Sort-Object Name |
        ForEach-Object {
            @{
                Name = $_.BaseName
                Path = $_.FullName
            }
        }
)

Describe 'Shipped examples' {
    It 'executes <Name> successfully in a non-interactive host' -ForEach $exampleCases {
        $escapedPath = $Path.Replace("'", "''")
        $command = @"
`$ErrorActionPreference = 'Stop'
`$PSNativeCommandUseErrorActionPreference = `$true
& '$escapedPath'
"@
        $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
        $startInfo = [Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = (Get-Command pwsh -ErrorAction Stop).Source
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        [void]$startInfo.ArgumentList.Add('-NoLogo')
        [void]$startInfo.ArgumentList.Add('-NoProfile')
        [void]$startInfo.ArgumentList.Add('-EncodedCommand')
        [void]$startInfo.ArgumentList.Add($encodedCommand)

        $process = [Diagnostics.Process]::Start($startInfo)
        $standardOutput = $process.StandardOutput.ReadToEndAsync()
        $standardError = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()

        $standardError.Result | Should -BeNullOrEmpty
        $process.ExitCode | Should -Be 0
        $standardOutput.Result | Should -Not -BeNullOrEmpty
    }
}
