# Build a release archive of the app for Windows into dist/.
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")
New-Item -ItemType Directory -Force -Path dist | Out-Null

Push-Location app
flutter build windows --release
Pop-Location

Compress-Archive -Force `
    -Path "app\build\windows\x64\runner\Release\*" `
    -DestinationPath "dist\GenreAnalyzer-windows-x64.zip"
Write-Host "dist\GenreAnalyzer-windows-x64.zip"
