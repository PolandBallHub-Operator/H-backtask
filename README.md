# H-backtask

AndroidOS / FireOS端末の待機バケット（App Standby Bucket）を、WindowsのMaterial You（Flutter Material 3）UIから確認・変更するデスクトップアプリです。root権限は要求せず、Windowsにインストール済みのADBを利用します。

## 機能

- `adb devices -l` で端末を検出し、複数台なら接続先を選択
- `adb shell pm list packages` で端末上のパッケージ一覧を取得
- 各パッケージに `adb shell am get-standby-bucket <package>` を実行し、バケット値・名称を表示
- 各行の歯車から5種類を個別適用
  - `10 ACTIVE` → `active`
  - `20 WORKING_SET` → `working_set`
  - `30 FREQUENT` → `frequent`
  - `40 RARE` → `rare`
  - `50 NEVER` → `never`
- 複数選択して一括適用、またはSystemUI/framework等を除いた通常アプリ全体に一括適用
- 既定では `android`、`com.android.systemui`、名前に`framework`を含むパッケージを隠す
- **設定 → アプリバージョン**を7回連続タップすると、隠したシステムパッケージを表示（再度7回で元に戻る）
- **設定 → 現在の設定をバックアップ**から、パッケージ名と取得したバケットを`Downloads`にJSON保存
- ライト／ダークはWindowsのシステム設定に追従

## Windowsでビルド

### 必要なもの

- Flutter SDK（Windows desktop support）
- Visual Studio 2022の **Desktop development with C++** ワークロード
- Android Platform Tools（`adb.exe`をPATHに追加）

### 手順

PowerShellでこのフォルダーに移動して実行します。

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\build_windows.ps1
```

または手動で実行します。

```powershell
flutter doctor -v
flutter pub get
flutter build windows --release
```

通常、実行ファイルは`build\windows\x64\runner\Release\h_backtask.exe`に出力されます。FlutterランタイムDLLや`data`フォルダーも必要なので、`h_backtask.exe`だけでなくReleaseフォルダー全体を配布してください。スクリプトは一式を`dist\H-backtask-windows-x64.zip`にまとめます。

## 端末接続

1. Android / FireOS端末の開発者向けオプションでUSBデバッグを有効化します。
2. USB接続後、端末に表示されるRSAフィンガープリント確認を承認します。
3. H-backtaskの **ADBデバイスに接続** を押します。

Wi-Fi ADBを利用する場合も、先に`adb connect <host>:<port>`で接続済みにしてください。

## 注意

- 待機バケットはAndroidのバックグラウンド実行制御に関する設定です。端末を軽くすることや、RAMを直接解放することを保証する機能ではありません。Android/FireOSのバージョン・メーカー実装によってコマンドや変更可能な対象が異なります。
- `NEVER`など強い制限を適用すると、対象アプリのバックグラウンド処理・通知・同期に影響する場合があります。
- システムパッケージは既定で除外します。隠し表示を解除した後に設定変更すると、端末の挙動に影響する可能性があります。
- このアプリはADBコマンドを引数配列で呼び出し、シェル文字列の組み立ては行いません。
- バックアップJSONは**現在の状態の記録**です。JSONからの復元・再適用機能は含みません。

## 開発・確認

```powershell
flutter analyze
flutter test
```

プロジェクトのWindowsランナーはFlutter標準テンプレートを使用しています。
