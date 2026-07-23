#Requires -Version 7.4

[CmdletBinding()]
param(
    [string]$OutputPath,
    [switch]$KeepVhsOutput
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $repositoryRoot 'Assets/terminalslides-social-demo.mp4'
}
$OutputPath = [IO.Path]::GetFullPath($OutputPath, $repositoryRoot)
$outputDirectory = Split-Path -Parent $OutputPath
[void][IO.Directory]::CreateDirectory($outputDirectory)

$vhs = Get-Command vhs -CommandType Application -ErrorAction Stop
$ffmpeg = Get-Command ffmpeg -CommandType Application -ErrorAction Stop
$ffprobe = Get-Command ffprobe -CommandType Application -ErrorAction Stop
[void](Get-Command pwsh -CommandType Application -ErrorAction Stop)

$tapePath = Join-Path $repositoryRoot 'Demos/terminalslides-social.tape'
$vhsOutputPath = Join-Path $repositoryRoot 'build/social/terminalslides-social-vhs.mp4'
[void][IO.Directory]::CreateDirectory((Split-Path -Parent $vhsOutputPath))

Push-Location $repositoryRoot
try {
    & $vhs.Source $tapePath
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $vhsOutputPath)) {
        throw 'VHS failed to produce the social demo.'
    }

    & $ffmpeg.Source `
        -hide_banner -loglevel error -y `
        -i $vhsOutputPath `
        -an -c:v libx264 -preset medium -crf 20 `
        -pix_fmt yuv420p -r 30 -movflags '+faststart' `
        $OutputPath
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $OutputPath)) {
        throw 'ffmpeg failed to normalize the social demo.'
    }

    $probeJson = & $ffprobe.Source `
        -v error `
        -select_streams v:0 `
        -show_entries 'stream=codec_name,width,height,pix_fmt,r_frame_rate:format=duration' `
        -of json `
        $OutputPath
    if ($LASTEXITCODE -ne 0) {
        throw 'ffprobe failed to inspect the social demo.'
    }

    $probe = $probeJson | ConvertFrom-Json
    $stream = $probe.streams[0]
    $duration = [double]::Parse(
        [string]$probe.format.duration,
        [Globalization.CultureInfo]::InvariantCulture
    )
    if (
        $stream.codec_name -ne 'h264' -or
        $stream.width -ne 1280 -or
        $stream.height -ne 720 -or
        $stream.pix_fmt -ne 'yuv420p' -or
        $stream.r_frame_rate -ne '30/1' -or
        $duration -lt 15 -or
        $duration -gt 45
    ) {
        throw "Unexpected video properties: $($probe | ConvertTo-Json -Compress -Depth 4)"
    }

    [pscustomobject]@{
        Path = $OutputPath
        DurationSeconds = [Math]::Round($duration, 2)
        Resolution = "$($stream.width)x$($stream.height)"
        Codec = $stream.codec_name
        PixelFormat = $stream.pix_fmt
        FrameRate = $stream.r_frame_rate
        SizeBytes = (Get-Item -LiteralPath $OutputPath).Length
    }
}
finally {
    Pop-Location
    if (-not $KeepVhsOutput -and (Test-Path -LiteralPath $vhsOutputPath)) {
        Remove-Item -LiteralPath $vhsOutputPath -Force
    }
}
