#Requires -Modules Pester

$tmuxRequested = $env:TERMINALSLIDES_RUN_TMUX_TESTS -eq '1'
$tmuxCommand = Get-Command tmux -ErrorAction SilentlyContinue
if ($tmuxRequested -and -not $tmuxCommand) {
    throw 'TERMINALSLIDES_RUN_TMUX_TESTS=1 requires tmux to be installed and available on PATH.'
}

Describe 'Show-TerminalPresentation keyboard controls in tmux' -Tag 'Tmux' -Skip:(-not $tmuxRequested) {
    BeforeAll {
        $script:ModulePath = Join-Path $PSScriptRoot '..' '..' 'TerminalSlides.psd1'
        Import-Module $script:ModulePath -Force
        $script:TerminalSlidesModule = Get-Module TerminalSlides
        $script:TmuxPath = (Get-Command tmux -ErrorAction Stop).Source
        $script:TmuxTestRoot = Join-Path ([System.IO.Path]::GetTempPath()) "TerminalSlidesTmuxTests-$PID"
        New-Item -Path $script:TmuxTestRoot -ItemType Directory -Force | Out-Null

        function Test-TmuxSession {
            param([Parameter(Mandatory)][string]$SessionName)

            & $script:TmuxPath has-session -t $SessionName 2>$null
            return $LASTEXITCODE -eq 0
        }

        function Assert-TmuxSession {
            param([Parameter(Mandatory)][string]$SessionName)

            if (-not (Test-TmuxSession -SessionName $SessionName)) {
                throw "tmux session '$SessionName' ended before the expected presenter state was observed."
            }
        }

        function Get-TmuxPaneText {
            param([Parameter(Mandatory)][string]$SessionName)

            Assert-TmuxSession -SessionName $SessionName
            $paneText = (& $script:TmuxPath capture-pane -p -e -t $SessionName) -join "`n"
            if ($LASTEXITCODE -ne 0) {
                throw "Could not capture tmux session '$SessionName'."
            }
            return $paneText
        }

        function Wait-TmuxPaneText {
            param(
                [Parameter(Mandatory)][string]$SessionName,
                [Parameter(Mandatory)][string]$ExpectedText,
                [int]$TimeoutSeconds = 5
            )

            $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
            do {
                $paneText = Get-TmuxPaneText -SessionName $SessionName
                if ($paneText -match [regex]::Escape($ExpectedText)) { return $paneText }
                Start-Sleep -Milliseconds 100
            } while ([DateTime]::UtcNow -lt $deadline)

            throw "Expected '$ExpectedText' in tmux pane. Actual pane: $paneText"
        }

        function Wait-TmuxPaneWithoutText {
            param(
                [Parameter(Mandatory)][string]$SessionName,
                [Parameter(Mandatory)][string]$UnexpectedText,
                [int]$TimeoutSeconds = 5,
                [int]$StableMilliseconds = 300
            )

            $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
            $absenceStarted = $null
            do {
                $paneText = Get-TmuxPaneText -SessionName $SessionName
                if ($paneText -match [regex]::Escape($UnexpectedText)) {
                    $absenceStarted = $null
                }
                elseif ($null -eq $absenceStarted) {
                    $absenceStarted = [DateTime]::UtcNow
                }
                elseif ([DateTime]::UtcNow -ge $absenceStarted.AddMilliseconds($StableMilliseconds)) {
                    return $paneText
                }
                Start-Sleep -Milliseconds 100
            } while ([DateTime]::UtcNow -lt $deadline)

            throw "Did not expect '$UnexpectedText' in tmux pane. Actual pane: $paneText"
        }

        function Send-TmuxKey {
            param(
                [Parameter(Mandatory)][string]$SessionName,
                [Parameter(Mandatory)][string]$Key
            )

            Assert-TmuxSession -SessionName $SessionName
            if ($Key.StartsWith('literal:', [System.StringComparison]::Ordinal)) {
                & $script:TmuxPath send-keys -t $SessionName -l $Key.Substring('literal:'.Length)
            }
            else {
                & $script:TmuxPath send-keys -t $SessionName $Key
            }
            if ($LASTEXITCODE -ne 0) {
                throw "Could not send '$Key' to tmux session '$SessionName'."
            }
        }

        function Wait-TmuxPresentationExit {
            param(
                [Parameter(Mandatory)]$Presentation,
                [int]$TimeoutSeconds = 5
            )

            $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
            while (-not (Test-Path $Presentation.StatusPath) -and [DateTime]::UtcNow -lt $deadline) {
                if (-not (Test-TmuxSession -SessionName $Presentation.SessionName)) {
                    $statusDeadline = [DateTime]::UtcNow.AddMilliseconds(250)
                    while (-not (Test-Path $Presentation.StatusPath) -and
                        [DateTime]::UtcNow -lt $statusDeadline) {
                        Start-Sleep -Milliseconds 10
                    }
                    if (-not (Test-Path $Presentation.StatusPath)) {
                        Assert-TmuxSession -SessionName $Presentation.SessionName
                    }
                    break
                }
                Start-Sleep -Milliseconds 100
            }

            if (-not (Test-Path $Presentation.StatusPath)) {
                $paneText = Get-TmuxPaneText -SessionName $Presentation.SessionName
                throw "Presentation did not exit. Pane output: $paneText"
            }

            $status = (Get-Content -LiteralPath $Presentation.StatusPath -Raw).Trim()
            if ($status -ne 'success') {
                $errorText = if (Test-Path -LiteralPath $Presentation.ErrorPath) {
                    Get-Content -LiteralPath $Presentation.ErrorPath -Raw
                }
                else {
                    'No error details were recorded.'
                }
                $paneText = Get-TmuxPaneText -SessionName $Presentation.SessionName
                throw "Presentation process failed. Error: $errorText Pane output: $paneText"
            }
        }

        function Start-TmuxPresentation {
            param(
                [switch]$Demo,
                [switch]$Crash
            )

            $sessionName = "terminal-slides-$PID-$([Guid]::NewGuid().ToString('N').Substring(0, 8))"
            $scriptPath = Join-Path $script:TmuxTestRoot "$sessionName.ps1"
            $statusPath = Join-Path $script:TmuxTestRoot "$sessionName.status"
            $errorPath = Join-Path $script:TmuxTestRoot "$sessionName.error"
            $moduleLiteral = "'$($script:ModulePath -replace "'", "''")'"
            $statusLiteral = "'$($statusPath -replace "'", "''")'"
            $errorLiteral = "'$($errorPath -replace "'", "''")'"
            $presentationInvocation = if ($Crash) {
                "throw 'INTENTIONAL-TMUX-PROCESS-FAILURE'"
            }
            elseif ($Demo) {
                'Start-TerminalSlidesDemo'
            }
            else {
                @'
$deck = New-TerminalPresentation -Title 'Keyboard test'
$deck | Add-TerminalSlide -Title 'FIRST-SLIDE-MARKER' -Content {
    Add-SlideText 'FIRST-VISIBLE-MARKER'
    Add-SlideText 'FIRST-REVEAL-MARKER' -RevealStep 1
    Add-SlideNotes 'FIRST-NOTES-MARKER'
} | Out-Null
$deck | Add-TerminalSlide -Title 'SECOND-SLIDE-MARKER' -Content { Add-SlideText 'Second slide' } | Out-Null
$deck | Add-TerminalSlide -Title 'THIRD-SLIDE-MARKER' -Content { Add-SlideText 'Third slide' } | Out-Null
Show-TerminalPresentation -Presentation $deck
'@
            }
            $scriptText = @"
`$ErrorActionPreference = 'Stop'
try {
    Import-Module -Name $moduleLiteral -Force
    $presentationInvocation
    Set-Content -Path $statusLiteral -Value 'success' -Encoding utf8
} catch {
    (`$_ | Out-String) | Set-Content -Path $errorLiteral -Encoding utf8
    Set-Content -Path $statusLiteral -Value 'failure' -Encoding utf8
}
"@
            Set-Content -Path $scriptPath -Value $scriptText -Encoding utf8

            $scriptLiteral = "'$($scriptPath -replace "'", "''")'"
            $runnerCommand = "& $scriptLiteral; while (`$true) { Start-Sleep -Seconds 3600 }"
            & $script:TmuxPath new-session -d -s $sessionName -x 120 -y 36 pwsh -NoLogo -NoProfile -Command $runnerCommand
            if ($LASTEXITCODE -ne 0) { throw "Failed to start tmux session '$sessionName'." }

            return [pscustomobject]@{
                SessionName = $sessionName
                StatusPath  = $statusPath
                ErrorPath   = $errorPath
            }
        }

        function Stop-TmuxPresentation {
            param([Parameter(Mandatory)]$Presentation)

            $exitError = $null
            try {
                if (Test-TmuxSession -SessionName $Presentation.SessionName) {
                    Send-TmuxKey -SessionName $Presentation.SessionName -Key 'literal:q'
                }
                Wait-TmuxPresentationExit -Presentation $Presentation
            }
            catch {
                $exitError = $_
            }
            finally {
                if (Test-TmuxSession -SessionName $Presentation.SessionName) {
                    & $script:TmuxPath kill-session -t $Presentation.SessionName 2>$null
                    if ($LASTEXITCODE -ne 0 -and (Test-TmuxSession -SessionName $Presentation.SessionName)) {
                        throw "Could not clean up tmux session '$($Presentation.SessionName)'."
                    }
                }
            }
            if ($exitError) { throw $exitError }
        }
    }

    AfterAll {
        $sessionPrefix = "terminal-slides-$PID-"
        $sessionNames = @(& $script:TmuxPath list-sessions -F '#{session_name}' 2>$null)
        foreach ($sessionName in $sessionNames | Where-Object { $_.StartsWith($sessionPrefix) }) {
            & $script:TmuxPath kill-session -t $sessionName 2>$null
        }
        if (Test-Path $script:TmuxTestRoot) {
            Remove-Item -Path $script:TmuxTestRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'matches tmux cursor width for emoji-presentation graphemes' -TestCases @(
        @{ Text = '🇺🇸'; ExpectedWidth = 2 }
        @{ Text = '1️⃣'; ExpectedWidth = 2 }
        @{ Text = '❤️'; ExpectedWidth = 2 }
        @{ Text = '☕'; ExpectedWidth = 2 }
        @{ Text = '⚽'; ExpectedWidth = 2 }
        @{ Text = '⏰'; ExpectedWidth = 2 }
        @{ Text = '⌚'; ExpectedWidth = 2 }
        @{ Text = '☀'; ExpectedWidth = 1 }
        @{ Text = '☀️'; ExpectedWidth = 2 }
        @{ Text = '©'; ExpectedWidth = 1 }
        @{ Text = '©️'; ExpectedWidth = 2 }
        @{ Text = '™'; ExpectedWidth = 1 }
        @{ Text = '™️'; ExpectedWidth = 2 }
        @{ Text = [string][char]0xFE0F; ExpectedWidth = 0 }
        @{ Text = "$([char]0x0301)$([char]0xFE0F)"; ExpectedWidth = 0 }
        @{ Text = [string][char]0x20E3; ExpectedWidth = 0 }
        @{ Text = "$([char]0x0301)$([char]0x20E3)"; ExpectedWidth = 0 }
        @{ Text = "1$([char]0x20E3)"; ExpectedWidth = 1 }
        @{ Text = "`t"; ExpectedWidth = 8 }
        @{ Text = "ABC`t"; ExpectedWidth = 8 }
        @{ Text = "`t`t"; ExpectedWidth = 16 }
        @{ Text = "界`t"; ExpectedWidth = 8 }
        @{ Text = "  A`tB"; ExpectedWidth = 9 }
        @{ Text = "A`tB"; ExpectedWidth = 9; Ansi = $true }
    ) {
        param($Text, $ExpectedWidth, $Ansi)

        if ($Ansi) {
            $escape = [string][char]0x1B
            $Text = "$escape[31m$Text$escape[0m"
        }

        $modeledWidth = & $script:TerminalSlidesModule {
            param($Value)

            $width = Measure-TextWidth -Text $Value
            $frame = [FrameBuffer]::new(24, 1)
            Set-FrameText -FrameBuffer $frame -X 0 -Y 0 -Text ($Value + 'X')
            $followingCell = -1
            for ($column = 0; $column -lt $frame.Width; $column++) {
                if ($frame.Cells[0][$column].Char -eq 'X') {
                    $followingCell = $column
                    break
                }
            }
            return [pscustomobject]@{ Width = $width; FollowingCell = $followingCell }
        } $Text
        $modeledWidth.Width | Should -Be $ExpectedWidth
        $modeledWidth.FollowingCell | Should -Be $ExpectedWidth

        $sessionName = "terminal-slides-$PID-width-$([Guid]::NewGuid().ToString('N').Substring(0, 8))"
        & $script:TmuxPath new-session -d -s $sessionName -x 20 -y 5
        if ($LASTEXITCODE -ne 0) { throw "Failed to start tmux width-probe session '$sessionName'." }
        try {
            $escapedText = ([Text.Encoding]::UTF8.GetBytes([string]$Text) |
                ForEach-Object { '\x{0:X2}' -f $_ }) -join ''
            Send-TmuxKey -SessionName $sessionName -Key "literal:clear; printf '$escapedText'; sleep 5"
            Send-TmuxKey -SessionName $sessionName -Key Enter

            $deadline = [DateTime]::UtcNow.AddSeconds(2)
            $cursorX = -1
            do {
                Assert-TmuxSession -SessionName $sessionName
                $cursorX = [int](& $script:TmuxPath display-message -p -t $sessionName '#{cursor_x}')
                if ($cursorX -eq $ExpectedWidth) { break }
                Start-Sleep -Milliseconds 50
            } while ([DateTime]::UtcNow -lt $deadline)

            $cursorX | Should -Be $ExpectedWidth
        }
        finally {
            if (Test-TmuxSession -SessionName $sessionName) {
                & $script:TmuxPath kill-session -t $sessionName 2>$null
            }
        }
    }

    It 'reveals deferred content before advancing when the user presses Right Arrow' {
        $presentation = Start-TmuxPresentation
        try {
            Wait-TmuxPaneText -SessionName $presentation.SessionName -ExpectedText 'FIRST-SLIDE-MARKER' | Should -Not -BeNullOrEmpty

            Send-TmuxKey -SessionName $presentation.SessionName -Key Right

            Wait-TmuxPaneText -SessionName $presentation.SessionName -ExpectedText 'FIRST-REVEAL-MARKER' | Should -Not -BeNullOrEmpty
            (Get-TmuxPaneText -SessionName $presentation.SessionName) | Should -Match ([regex]::Escape('FIRST-SLIDE-MARKER'))
        }
        finally {
            Stop-TmuxPresentation -Presentation $presentation
        }
    }

    It 'advances to the next slide with every documented next-navigation key' -TestCases @(
        @{ Name = 'Right Arrow'; Key = 'Right'; Presses = 2 }
        @{ Name = 'Space'; Key = 'Space'; Presses = 2 }
        @{ Name = 'N'; Key = 'literal:n'; Presses = 2 }
        @{ Name = 'PageDown'; Key = 'NPage'; Presses = 1 }
    ) {
        param($Name, $Key, $Presses)

        $presentation = Start-TmuxPresentation
        try {
            Wait-TmuxPaneText -SessionName $presentation.SessionName -ExpectedText 'FIRST-SLIDE-MARKER' | Should -Not -BeNullOrEmpty

            for ($press = 0; $press -lt $Presses; $press++) {
                Send-TmuxKey -SessionName $presentation.SessionName -Key $Key
            }

            Wait-TmuxPaneText -SessionName $presentation.SessionName -ExpectedText 'SECOND-SLIDE-MARKER' | Should -Not -BeNullOrEmpty
        }
        finally {
            Stop-TmuxPresentation -Presentation $presentation
        }
    }

    It 'returns to the previous slide with every documented previous-navigation key' -TestCases @(
        @{ Name = 'Left Arrow'; Key = 'Left' }
        @{ Name = 'Backspace'; Key = 'BSpace' }
        @{ Name = 'P'; Key = 'literal:p' }
        @{ Name = 'PageUp'; Key = 'PPage' }
    ) {
        param($Name, $Key)

        $presentation = Start-TmuxPresentation
        try {
            Wait-TmuxPaneText -SessionName $presentation.SessionName -ExpectedText 'FIRST-SLIDE-MARKER' | Should -Not -BeNullOrEmpty
            Send-TmuxKey -SessionName $presentation.SessionName -Key 'NPage'
            Wait-TmuxPaneText -SessionName $presentation.SessionName -ExpectedText 'SECOND-SLIDE-MARKER' | Should -Not -BeNullOrEmpty

            Send-TmuxKey -SessionName $presentation.SessionName -Key $Key

            Wait-TmuxPaneText -SessionName $presentation.SessionName -ExpectedText 'FIRST-SLIDE-MARKER' | Should -Not -BeNullOrEmpty
        }
        finally {
            Stop-TmuxPresentation -Presentation $presentation
        }
    }

    It 'jumps to the first and last slides with Home and End' {
        $presentation = Start-TmuxPresentation
        try {
            Wait-TmuxPaneText -SessionName $presentation.SessionName -ExpectedText 'FIRST-SLIDE-MARKER' | Should -Not -BeNullOrEmpty

            Send-TmuxKey -SessionName $presentation.SessionName -Key End
            Wait-TmuxPaneText -SessionName $presentation.SessionName -ExpectedText 'THIRD-SLIDE-MARKER' | Should -Not -BeNullOrEmpty

            Send-TmuxKey -SessionName $presentation.SessionName -Key Home
            Wait-TmuxPaneText -SessionName $presentation.SessionName -ExpectedText 'FIRST-SLIDE-MARKER' | Should -Not -BeNullOrEmpty
        }
        finally {
            Stop-TmuxPresentation -Presentation $presentation
        }
    }

    It 'toggles the documented display controls' {
        $presentation = Start-TmuxPresentation
        try {
            Wait-TmuxPaneText -SessionName $presentation.SessionName -ExpectedText 'FIRST-SLIDE-MARKER' | Should -Not -BeNullOrEmpty

            Send-TmuxKey -SessionName $presentation.SessionName -Key 'literal:s'
            Wait-TmuxPaneText -SessionName $presentation.SessionName -ExpectedText 'FIRST-NOTES-MARKER' | Should -Not -BeNullOrEmpty

            Send-TmuxKey -SessionName $presentation.SessionName -Key 'literal:o'
            Wait-TmuxPaneText -SessionName $presentation.SessionName -ExpectedText 'THIRD-SLIDE-MARKER' | Should -Not -BeNullOrEmpty

            Send-TmuxKey -SessionName $presentation.SessionName -Key 'literal:b'
            $null = Wait-TmuxPaneWithoutText -SessionName $presentation.SessionName -UnexpectedText 'FIRST-SLIDE-MARKER'

            Send-TmuxKey -SessionName $presentation.SessionName -Key 'literal:b'
            Wait-TmuxPaneText -SessionName $presentation.SessionName -ExpectedText 'FIRST-SLIDE-MARKER' | Should -Not -BeNullOrEmpty
            $null = Wait-TmuxPaneWithoutText -SessionName $presentation.SessionName -UnexpectedText 'THIRD-SLIDE-MARKER'
            Send-TmuxKey -SessionName $presentation.SessionName -Key 'literal:t'
            Wait-TmuxPaneText -SessionName $presentation.SessionName -ExpectedText '00:00:' | Should -Not -BeNullOrEmpty
        }
        finally {
            Stop-TmuxPresentation -Presentation $presentation
        }
    }

    It 'opens the help overlay with both documented keys' -TestCases @(
        @{ Name = 'H'; Key = 'literal:h' }
        @{ Name = 'Question mark'; Key = 'literal:?' }
    ) {
        param($Name, $Key)

        $presentation = Start-TmuxPresentation
        try {
            Wait-TmuxPaneText -SessionName $presentation.SessionName -ExpectedText 'FIRST-SLIDE-MARKER' | Should -Not -BeNullOrEmpty

            Send-TmuxKey -SessionName $presentation.SessionName -Key $Key

            Wait-TmuxPaneText -SessionName $presentation.SessionName -ExpectedText 'TerminalSlides Help' | Should -Not -BeNullOrEmpty
        }
        finally {
            Stop-TmuxPresentation -Presentation $presentation
        }
    }

    It 'runs the feature demo as an interactive presentation' {
        $presentation = Start-TmuxPresentation -Demo
        try {
            Wait-TmuxPaneText -SessionName $presentation.SessionName -ExpectedText 'Present from the terminal' | Should -Not -BeNullOrEmpty

            Send-TmuxKey -SessionName $presentation.SessionName -Key 'literal:?'
            Wait-TmuxPaneText -SessionName $presentation.SessionName -ExpectedText 'TerminalSlides Help' | Should -Not -BeNullOrEmpty
        }
        finally {
            Stop-TmuxPresentation -Presentation $presentation
        }
    }

    It 'reports a presentation process crash as a failed exit' {
        $presentation = Start-TmuxPresentation -Crash
        { Stop-TmuxPresentation -Presentation $presentation } |
            Should -Throw -ExpectedMessage '*INTENTIONAL-TMUX-PROCESS-FAILURE*'
        Test-TmuxSession -SessionName $presentation.SessionName | Should -BeFalse
    }

    It 'reports a lost tmux session immediately instead of timing out' {
        $lostPresentation = [pscustomobject]@{
            SessionName = "missing-terminal-slides-$([Guid]::NewGuid().ToString('N'))"
            StatusPath  = Join-Path $script:TmuxTestRoot 'missing.status'
            ErrorPath   = Join-Path $script:TmuxTestRoot 'missing.error'
        }

        { Wait-TmuxPresentationExit -Presentation $lostPresentation } |
            Should -Throw "*ended before the expected presenter state*"
    }

    It 'quits when the user presses Q or Escape' -TestCases @(
        @{ Name = 'Q'; Key = 'literal:q' }
        @{ Name = 'Escape'; Key = 'Escape' }
    ) {
        param($Name, $Key)

        $presentation = Start-TmuxPresentation
        try {
            Wait-TmuxPaneText -SessionName $presentation.SessionName -ExpectedText 'FIRST-SLIDE-MARKER' | Should -Not -BeNullOrEmpty

            Send-TmuxKey -SessionName $presentation.SessionName -Key $Key

            { Wait-TmuxPresentationExit -Presentation $presentation } | Should -Not -Throw
        }
        finally {
            if (Test-TmuxSession -SessionName $presentation.SessionName) {
                & $script:TmuxPath kill-session -t $presentation.SessionName 2>$null
            }
        }
    }
}
