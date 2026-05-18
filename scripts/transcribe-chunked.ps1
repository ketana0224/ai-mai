#!/usr/bin/env pwsh
<#
.SYNOPSIS
  長尺音声を分割して MAI-Transcribe-1 で文字起こしし、結合して出力する。
.EXAMPLE
  ./scripts/transcribe-chunked.ps1 -AudioFile wav/smcc.wav -Locales en -ChunkSeconds 300 -OutFile out/smcc.txt
#>
param(
    [Parameter(Mandatory = $true)][string]$AudioFile,
    [string[]]$Locales = @('en'),
    [int]$ChunkSeconds = 300,
    [string]$Endpoint = $env:AZURE_SPEECH_ENDPOINT,
    [string]$SubscriptionId = '571e49d7-d4d6-4cb5-884f-2e14bfaa662c',
    [string]$Model = 'mai-transcribe-1',
    [string]$ApiVersion = '2025-10-15',
    [string]$OutFile = 'out/transcript.txt',
    [string]$FFmpeg = 'C:\Users\ketana\AppData\Local\Microsoft\WinGet\Packages\Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe\ffmpeg-8.1.1-full_build\bin\ffmpeg.exe'
)

$ErrorActionPreference = 'Stop'

[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()
$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'

if (-not $Endpoint) { $Endpoint = 'https://aif-ketana-ext-mai-eastus.cognitiveservices.azure.com/' }
if (-not (Test-Path $AudioFile)) { throw "AudioFile not found: $AudioFile" }
if (-not (Test-Path $FFmpeg)) { throw "ffmpeg not found: $FFmpeg" }

$audioFull = (Resolve-Path $AudioFile).Path
$baseName  = [IO.Path]::GetFileNameWithoutExtension($audioFull)
# チャンクは OutFile と同じディレクトリ配下に作る（入力フォルダを汚さない）
$outDirForChunks = Split-Path -Parent $OutFile
if (-not $outDirForChunks) { $outDirForChunks = '.' }
if (-not (Test-Path $outDirForChunks)) { New-Item -ItemType Directory -Path $outDirForChunks | Out-Null }
$workDir   = Join-Path $outDirForChunks ("_chunks_" + $baseName)
if (Test-Path $workDir) { Remove-Item $workDir -Recurse -Force }
New-Item -ItemType Directory -Path $workDir | Out-Null

# 1) チャンクに分割（再エンコードして 16kHz mono mp3 にしてサイズも縮小）
Write-Host "Splitting into ${ChunkSeconds}s chunks (16kHz mono mp3) -> $workDir" -ForegroundColor Cyan
$pattern = Join-Path $workDir "chunk_%03d.mp3"
& $FFmpeg -hide_banner -loglevel error -y -i $audioFull `
    -ac 1 -ar 16000 -codec:a libmp3lame -qscale:a 4 `
    -f segment -segment_time $ChunkSeconds -reset_timestamps 1 $pattern
if ($LASTEXITCODE -ne 0) { throw "ffmpeg split failed" }

$chunks = Get-ChildItem $workDir -Filter 'chunk_*.mp3' | Sort-Object Name
Write-Host ("Chunks: {0}" -f $chunks.Count) -ForegroundColor Cyan

# 2) Entra token
Write-Host "Acquiring Entra token..." -ForegroundColor Cyan
$null = & az account set --subscription $SubscriptionId 2>&1
$token = (& az account get-access-token --resource 'https://cognitiveservices.azure.com' --query accessToken -o tsv).Trim()
if (-not $token) { throw "Entra token 取得失敗。az login を実行してください。" }

$uri = "$($Endpoint.TrimEnd('/'))/speechtotext/transcriptions:transcribe?api-version=$ApiVersion"
$definition = @{
    locales      = $Locales
    enhancedMode = @{ enabled = $true; model = $Model }
} | ConvertTo-Json -Compress -Depth 5

# 3) 各チャンクを transcribe
$allText = New-Object System.Collections.Generic.List[string]
$jsonDir = Join-Path $workDir 'json'
New-Item -ItemType Directory -Path $jsonDir | Out-Null

for ($i = 0; $i -lt $chunks.Count; $i++) {
    $c = $chunks[$i]
    $idx = '{0:D3}' -f $i
    Write-Host "[$idx] $($c.Name) ($([math]::Round($c.Length/1MB,2)) MB) ..." -ForegroundColor Yellow

    $curlArgs = @(
        '--silent', '--show-error', '--fail-with-body',
        '--location', $uri,
        '--header', "Authorization: Bearer $token",
        '--form', "audio=@`"$($c.FullName)`"",
        '--form', "definition=$definition;type=application/json"
    )
    $resp = & curl.exe @curlArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "  failed: $resp"
        $allText.Add("[chunk $idx FAILED] $resp")
        continue
    }
    $resp | Out-File (Join-Path $jsonDir "chunk_$idx.json") -Encoding utf8

    try {
        $json = $resp | ConvertFrom-Json
        if ($json.combinedPhrases) {
            $text = ($json.combinedPhrases | ForEach-Object { $_.text }) -join " "
            $allText.Add($text)
            Write-Host "  -> $($text.Substring(0,[math]::Min(80,$text.Length)))..." -ForegroundColor DarkGray
        } else {
            $allText.Add("[chunk $idx no combinedPhrases]")
        }
    } catch {
        $allText.Add("[chunk $idx parse error]")
    }
}

# 4) 結合保存
$outDir = Split-Path -Parent $OutFile
if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
($allText -join "`n`n") | Out-File -FilePath $OutFile -Encoding utf8
Write-Host "`nSaved transcript -> $OutFile" -ForegroundColor Green
Write-Host "Chunk JSONs -> $jsonDir" -ForegroundColor Green
