<#
.SYNOPSIS
    既存の音声ファイルに環境音をオーバーラップして新しい MP3 を生成します。

.EXAMPLE
    ./scripts/add-noise.ps1 -AudioFile mp3/n1-1.mp3 -NoiseFile Noise/museum_hall.mp3 -OutFile mp3/n1-1_noisy.mp3
    ./scripts/add-noise.ps1 -AudioFile mp3/n1-1.mp3 -NoiseFile Noise/museum_hall.mp3 -NoiseVolume 0.5 -OutFile mp3/n1-1_noisy.mp3
#>
param(
    [Parameter(Mandatory)][string]$AudioFile,
    [Parameter(Mandatory)][string]$NoiseFile,
    [Parameter(Mandatory)][string]$OutFile,
    # 環境音の倍率（1.0 = 元の音量のまま）
    [double]$NoiseVolume = 0.1,
    # メイン音声の倍率（電話録音など音量が低い場合に上げる）
    [double]$VoiceVolume = 2.0,
    [string]$FFmpeg = 'C:\Users\ketana\AppData\Local\Microsoft\WinGet\Packages\Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe\ffmpeg-8.1.1-full_build\bin\ffmpeg.exe'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$audioFull = (Resolve-Path $AudioFile).Path
$noiseFull = (Resolve-Path $NoiseFile).Path
$outFull   = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $OutFile))

$outDir = Split-Path -Parent $outFull
if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Force $outDir | Out-Null }

Write-Host "Audio : $audioFull  (voice volume x$VoiceVolume)"
Write-Host "Noise : $noiseFull  (noise volume x$NoiseVolume)"
Write-Host "Output: $outFull"

# volume フィルタで個別に音量を調整してから amix（normalize=0 で加算のみ）
$filter = "[0:a]volume=${VoiceVolume}[main];[1:a]volume=${NoiseVolume}[noise];[main][noise]amix=inputs=2:duration=first:normalize=0[out]"

& $FFmpeg -y `
    -i $audioFull `
    -stream_loop -1 -i $noiseFull `
    -filter_complex $filter `
    -map "[out]" `
    -codec:a libmp3lame -qscale:a 2 `
    $outFull

if ($LASTEXITCODE -ne 0) { throw "ffmpeg failed (exit $LASTEXITCODE)" }
Write-Host "Done -> $outFull"
