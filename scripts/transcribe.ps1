#!/usr/bin/env pwsh
<#
.SYNOPSIS
  MAI-Transcribe-1 (Azure Speech Fast Transcription) を Entra ID 認証で呼ぶ
.DESCRIPTION
  Ocp-Apim-Subscription-Key の代わりに Authorization: Bearer <token> を使用。
  カスタムサブドメイン (*.cognitiveservices.azure.com) のエンドポイントが必須。
.EXAMPLE
  az login
  ./scripts/transcribe.ps1 -AudioFile wav/smcc.wav -Locales en -OutFile out/smcc.json
#>
param(
    [Parameter(Mandatory = $true)][string]$AudioFile,
    [string[]]$Locales = @('en'),
    [string]$Endpoint = $env:AZURE_SPEECH_ENDPOINT,
    [string]$SubscriptionId = '571e49d7-d4d6-4cb5-884f-2e14bfaa662c',
    [string]$Model = 'mai-transcribe-1',
    [string]$ApiVersion = '2025-10-15',
    [string]$OutFile
)

$ErrorActionPreference = 'Stop'

# curl.exe からの UTF-8 出力を文字化けさせないため
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()
$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'

if (-not $Endpoint) { $Endpoint = 'https://aif-ketana-ext-mai-eastus.cognitiveservices.azure.com/' }
if (-not (Test-Path $AudioFile)) { throw "AudioFile が見つかりません: $AudioFile" }

if ($Endpoint -match 'api\.cognitive\.microsoft\.com') {
    throw "Entra 認証では custom subdomain (*.cognitiveservices.azure.com) エンドポイントが必要です: $Endpoint"
}

$audioFull = (Resolve-Path $AudioFile).Path
$uri = "$($Endpoint.TrimEnd('/'))/speechtotext/transcriptions:transcribe?api-version=$ApiVersion"

Write-Host "Acquiring Entra token..." -ForegroundColor Cyan
$null = & az account set --subscription $SubscriptionId 2>&1
$token = (& az account get-access-token --resource 'https://cognitiveservices.azure.com' --query accessToken -o tsv).Trim()
if (-not $token) { throw "Entra token 取得に失敗しました。az login を実行してください。" }

$definition = @{
    locales      = $Locales
    enhancedMode = @{
        enabled = $true
        model   = $Model
    }
} | ConvertTo-Json -Compress -Depth 5

Write-Host "POST $uri" -ForegroundColor Cyan
Write-Host "definition=$definition" -ForegroundColor DarkGray
Write-Host "audio=$audioFull" -ForegroundColor DarkGray

$curlArgs = @(
    '--silent', '--show-error', '--fail-with-body',
    '--location', $uri,
    '--header', "Authorization: Bearer $token",
    '--form', "audio=@`"$audioFull`"",
    '--form', "definition=$definition;type=application/json"
)

$response = & curl.exe @curlArgs
if ($LASTEXITCODE -ne 0) {
    Write-Error "curl 失敗 (exit=$LASTEXITCODE): $response"
    exit $LASTEXITCODE
}

if ($OutFile) {
    $dir = Split-Path -Parent $OutFile
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    $response | Out-File -FilePath $OutFile -Encoding utf8
    Write-Host "Saved -> $OutFile" -ForegroundColor Green
}

try {
    $json = $response | ConvertFrom-Json
    if ($json.combinedPhrases) {
        Write-Host "`n--- combinedPhrases ---" -ForegroundColor Yellow
        $json.combinedPhrases | ForEach-Object { Write-Host $_.text }
    } else {
        $response
    }
} catch {
    $response
}
