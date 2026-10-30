# Terminal2

macOS ネイティブのターミナル。[fuba/terminal](https://github.com/fuba/terminal) の機能を、AppKit・SwiftUI・Metal・OpenSSH で実装しています。

macOS 26 以降、Xcode 26 以降 / Swift 6.2 以降が必要です。開発・検証環境は Apple Silicon、macOS 27、Xcode 27.2 です。

## ビルドと起動

```sh
git clone https://github.com/fuba/terminal2.git
cd terminal2
swift package resolve
scripts/build.sh
open build/Terminal2.app
```

`build/Terminal2.app` を `~/Applications` または `/Applications` に置いて利用できます。ビルド時に ad hoc 署名を行います。Developer ID 署名・公証は行っていません。

`scripts/install.sh` で `~/Applications/Terminal2.app` に配置できます。既存の同名アプリがある場合は前のバンドルを残します。リビルドも別バンドルで行い、起動中のセッションの実行ファイルを上書きしません。

```sh
scripts/test.sh
scripts/run.sh              # Debug build and launch
```

依存は `Package.resolved` に固定しています。ビルド・テスト用スクリプトは、直接・間接の依存がレビュー済みで公開後24時間以上経過していることを検査し、自動更新を禁止します。依存を更新する場合は [依存監査](docs/dependency-audit.json) も更新してください。

## 機能

- Metal 描画、Retina / CJK フォールバック、日本語 IME のインライン入力。
- タブ、ログインシェルの自動検出、接続先のサイドバーと検索。
- `~/.ssh/config` の Host / Include、鍵・パスフレーズ・パスワード・ssh-agent・ProxyJump を含む OpenSSH 接続。
- Tailscale の実際のピア情報を取得。接続先の追加、ブックマーク、お気に入り。
- SSH 接続への画像・ファイル・フォルダのペースト / ドロップ。SFTP で `/tmp/terminal2.*` へ転送し、パスを入力。
- VT、TrueColor / 256色、スクロールバック、代替画面、スクロール領域、DECCKM、ブラケット付きペースト、OSC タイトル。
- Sixel、iTerm2 インライン画像、OSC 52 のクリップボード書き込み。
- tmux 内でもドラッグによるローカル選択。右クリックでペースト、⌘クリックで URL を開く。
- ネイティブ設定画面とカラーピッカー、設定ファイルの変更を自動反映。
- グローバルホットキー、ディスプレイごとの位置保存、F11 で画面の高さに合わせる。
- タブごとのプレーンテキストログ、クラッシュログ、描画・解析の性能ログ、ビルド日時のタイトル表示。
- Finder のサービス「Open in Terminal2」、フォルダの起動引数対応。

元の機能との対応、Windows 固有機能の置き換え、検証範囲は [機能対応表](docs/feature-parity.md) を参照してください。

## 操作

| キー | 操作 |
| --- | --- |
| ⌘T / ⌘W | 新しいタブ / タブを閉じる |
| ⌘⇧] / ⌘⇧[ | 次 / 前のタブ |
| ⌘1 … ⌘9 | タブを選択 |
| ⌘K / ⌘⇧S | 接続先を検索 / SSH 接続 |
| ⌘C / ⌘V | コピー / ペースト |
| ⌃C | 選択があればコピー、なければ SIGINT の端末入力 |
| ⌘F | 端末内を検索 |
| ⌘L | セッションログの開始 / 停止 |
| ⌘, | 設定 |
| ⌘+ / ⌘− / ⌘0 | 文字を拡大 / 縮小 / 元に戻す |
| ⌘⇧L | サイドバーを表示 / 非表示 |
| ⇧Page Up / ⇧Page Down | 履歴をページ単位で移動 |
| ⌘Home / ⌘End | 履歴の先頭 / 末尾 |
| F11 | ウィンドウを画面の高さに合わせる |
| ⌥⇧V | どのアプリからでも表示 / 非表示（変更可能） |

通常のホイール操作は、アプリケーションがマウス入力を要求している場合は端末へ送ります。⇧ホイールは常にローカル履歴をスクロールします。Option を Meta に使うかは設定できます。標準設定では日本語・各国キーボードの文字入力を優先します。

## 設定とログ

設定は `~/Library/Application Support/Terminal2/config.json`。GUI と手動編集の両方を利用でき、正常な変更は1秒以内に反映されます。不正な編集時は直前の動作設定を維持し、エラーを表示します。[設定例](config.example.json) は既定の外観と接続先の書式を示しています。SSH の資格情報やパスワードは JSON に保存せず、OpenSSH の設定・agent・対話入力を使用します。

ログは `~/Library/Logs/Terminal2/`。セッションログはタブごとに明示的に開始し、制御文字・OSC / DCS ペイロードを除去します。`app.log` は起動・終了・エラー、`crash.log` は例外・致命的シグナル、`perf.log` は遅い解析・描画を記録します。完全なネイティブクラッシュレポートは macOS の `DiagnosticReports` も参照してください。

`TERMINAL_SLOW_FRAME_MS=8` で性能記録の閾値を変更できます。`SWIFTTERM_PROFILE=1` では Instruments の signpost も利用できます。

SSH のホスト鍵は OpenSSH の `known_hosts` で検証します。初回接続は端末内の確認に従ってください。OSC 52 によるクリップボード読み取りは拒否し、書き込みに対応しています。SSH 転送先のファイルはコマンドで引き続き使えるように自動削除しません。

## 構成

`TerminalCore` が設定、SSH 引数・転送、接続先の検出、プロセス実行、エスケープ除去を担当します。`TerminalApp` がウィンドウ、ネイティブメニュー、SwiftUI 画面、PTY、描画、クリップボード、ホットキーを担当します。端末エミュレーションには MIT ライセンスの [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm/tree/v1.99.1) を利用します。ブラウザ / WebView は使用していません。

アイコン原本は [AppIcon.svg](Resources/AppIcon.svg)、背景なしのマークは [Mark.svg](Resources/Mark.svg)。ビルド時に同じ SVG パスからすべてのアイコンサイズを生成します。

MIT License.
