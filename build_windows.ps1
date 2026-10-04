$ErrorActionPreference = 'Stop'

if (-not $IsWindows -and $env:OS -ne 'Windows_NT') {
  throw 'このスクリプトはWindowsで実行してください。Linux/macOSからFlutter Windows exeはビルドできません。'
}

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $projectRoot

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw 'Flutter SDKが見つかりません。Flutterをインストールし、flutterをPATHに追加してください。'
}

Write-Host '依存関係を取得しています…' -ForegroundColor Cyan
flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'flutter pub getに失敗しました。' }

Write-Host 'Windows Release版をビルドしています…' -ForegroundColor Cyan
flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw 'Windowsビルドに失敗しました。Visual Studio 2022のC++デスクトップ開発環境を確認してください。' }

$releaseDir = Join-Path $projectRoot 'build\windows\x64\runner\Release'
if (-not (Test-Path (Join-Path $releaseDir 'h_backtask.exe'))) {
  $releaseDir = Join-Path $projectRoot 'build\windows\runner\Release'
}
if (-not (Test-Path (Join-Path $releaseDir 'h_backtask.exe'))) {
  throw 'ビルド後のh_backtask.exeが見つかりません。build\windowsを確認してください。'
}

$dist = Join-Path $projectRoot 'dist'
New-Item -ItemType Directory -Path $dist -Force | Out-Null
$zip = Join-Path $dist 'H-backtask-windows-x64.zip'
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $releaseDir '*') -DestinationPath $zip -CompressionLevel Optimal
Write-Host "完了: $releaseDir\h_backtask.exe" -ForegroundColor Green
Write-Host "配布用一式: $zip" -ForegroundColor Green
Write-Host '注意: exe単体ではなくReleaseフォルダー内の全ファイルを一緒に配布してください。'
