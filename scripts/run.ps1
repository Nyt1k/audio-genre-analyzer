# One-command start (Windows): sets up the Python venv, launches the app
# (prebuilt exe if present, otherwise builds it with Flutter) and runs the
# inference server in the foreground. Ctrl+C stops the server.
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")

if (!(Test-Path ".venv")) {
    Write-Host "creating Python venv..."
    python -m venv .venv
}
& .venv\Scripts\python -c "import torch, fastapi, librosa" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "installing Python dependencies (first run takes a few minutes)..."
    & .venv\Scripts\pip install -q -r requirements.txt
}

$app = "app\build\windows\x64\runner\Release\genre_analyzer.exe"
if (!(Test-Path $app)) {
    if (Get-Command flutter -ErrorAction SilentlyContinue) {
        Push-Location app
        flutter build windows --release
        Pop-Location
    } else {
        Write-Host "No prebuilt app and no Flutter SDK found."
        Write-Host "Install Flutter (https://flutter.dev) or download the prebuilt"
        Write-Host "app from GitHub Releases and unzip it into the path above."
        exit 1
    }
}
Start-Process $app

Write-Host "starting inference server on :8000 (Ctrl+C to stop)"
& .venv\Scripts\uvicorn server.main:app --port 8000
