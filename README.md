# ai-mai

Azure Speech の **MAI-Transcribe-1** モデルを使った音声文字起こしスクリプト集。

---

## 前提条件

- **Azure CLI** がインストール済みで `az login` 済みであること
- **ffmpeg** がインストール済みであること（winget 経由: `winget install Gyan.FFmpeg`）
- Azure Speech リソース（カスタムサブドメイン `*.cognitiveservices.azure.com`）へのアクセス権限
- API キー認証は無効のため **Entra ID 認証（Bearer トークン）** を使用

---

## ディレクトリ構成

```
ai-mai/
├── mp3/          # 入力音声（MP3）
├── wav/          # 入力音声（WAV）
├── out/          # 文字起こし出力（JSON / TXT）
└── scripts/
    ├── transcribe.ps1          # 短尺音声用（1ファイルをそのまま送信）
    └── transcribe-chunked.ps1  # 長尺音声用（分割して順次送信・結合）
```

---

## WAV → MP3 変換

```powershell
$ffmpeg = 'C:\Users\<USER>\AppData\Local\Microsoft\WinGet\Packages\Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe\ffmpeg-8.1.1-full_build\bin\ffmpeg.exe'
& $ffmpeg -y -i wav\<input>.wav -codec:a libmp3lame -qscale:a 2 mp3\<output>.mp3
```

---

## 文字起こし

### 短尺音声（目安: 5分以下）— `transcribe.ps1`

```powershell
# 事前に az login とサブスクリプション設定
az login
az account set --subscription 571e49d7-d4d6-4cb5-884f-2e14bfaa662c

# 実行例（日本語）
./scripts/transcribe.ps1 -AudioFile mp3/audio_file.mp3 -Locales ja -OutFile out/audio_file.json
# 実行例（英語）
./scripts/transcribe.ps1 -AudioFile mp3/audio_file.mp3 -Locales en -OutFile out/audio_file.json
```

**パラメータ**

| パラメータ | 既定値 | 説明 |
|---|---|---|
| `-AudioFile` | （必須） | 入力音声ファイルパス（WAV / MP3 / FLAC） |
| `-Locales` | `en` | 認識ロケール（`ja`, `en` など） |
| `-Endpoint` | `$env:AZURE_SPEECH_ENDPOINT` または組み込み値 | Speech エンドポイント |
| `-SubscriptionId` | `571e49d7-...` | Azure サブスクリプション ID |
| `-Model` | `mai-transcribe-1` | 使用モデル |
| `-OutFile` | なし | 結果 JSON の保存先 |

### 長尺音声（5分超）— `transcribe-chunked.ps1`

音声を指定秒数のチャンクに分割（16kHz mono MP3 に再エンコード）し、順次 API に送信して結合テキストを出力します。

```powershell
./scripts/transcribe-chunked.ps1 -AudioFile wav/audio_file.wav -Locales ja -ChunkSeconds 300 -OutFile out/audio_file.txt
```

**パラメータ**（`transcribe.ps1` のパラメータに加えて）

| パラメータ | 既定値 | 説明 |
|---|---|---|
| `-ChunkSeconds` | `300` | 1チャンクの秒数 |
| `-OutFile` | `out/transcript.txt` | 結合テキストの保存先 |
| `-FFmpeg` | winget インストールパス | ffmpeg.exe のフルパス |

チャンク MP3 と各チャンクの JSON は `<OutFileディレクトリ>/_chunks_<ファイル名>/` に保存されます。

---

## 出力形式

`-OutFile *.json` を指定すると API レスポンスをそのまま保存します。  
`combinedPhrases[].text` に文字起こし全文、`phrases[]` にオフセット・信頼度付きのセグメントが含まれます。

