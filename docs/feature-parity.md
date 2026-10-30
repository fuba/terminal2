# fuba/terminal との対応

調査対象: [fuba/terminal@31c1dbd50f9cb89808a6a25a27a45055873eb770](https://github.com/fuba/terminal/tree/31c1dbd50f9cb89808a6a25a27a45055873eb770)。README と `src/app`、`src/config`、`src/pty`、`src/image`、`src/terminal`、キー・ログ・クラッシュ処理を参照し、UI の模倣や Windows ソースの移植は行っていません。

| 元の機能 | macOS での対応 | 実装 |
| --- | --- | --- |
| Direct2D / DirectWrite、ClearType、DPI、CJK | Metal / Core Graphics、Core Text、Retina、システムフォールバック | SwiftTerm、TerminalSession |
| タブと新規タブメニュー | ネイティブメニュー、タブ列、サイドバー、接続検索 | WorkspaceView、AppDelegate |
| ConPTY と Windows シェル自動検出 | Unix PTY と /etc/shells、zsh / bash / fish / nu / pwsh の実行ファイル検出 | LocalProcess、Shell.available |
| SSH と SSH 設定読み込み | 標準 OpenSSH、Host / Include の候補検出、設定本体の解釈は ssh に委譲 | SSH、Discovery |
| 鍵・パスフレーズ・パスワード認証 | OpenSSH の PTY 対話、ssh-agent | TerminalSession |
| SSH ファイル / 画像ペースト | ControlMaster を共有して SFTP 転送、/tmp の private ディレクトリ、シェル引用したパスをペースト | SSHConnection.upload、pasteFiles |
| Tailscale | 実 CLI の status --json、オンライン状態、再読み込み | TailscalePeer |
| ブックマーク、お気に入り | GUI 追加・削除、右クリックでお気に入り | Workspace、SettingsView |
| TrueColor / 256色、VT、スクロール領域 | SwiftTerm のエミュレーション | TerminalSession |
| スクロールバック、代替画面 | SwiftTerm、履歴操作メニュー | TerminalSession、AppDelegate |
| DECCKM、ブラケット付きペースト、OSC タイトル | SwiftTerm のモード追従、pasteText、タイトル delegate | TerminalSession |
| Sixel / iTerm2 インライン画像 | SwiftTerm、ローカル PTY / SSH の両方で DCS を維持 | SwiftTerm native renderer |
| Win32 クリップボード / OSC 52 | NSPasteboard、OSC 52 write、read は拒否 | TerminalSession |
| カーソル位置に追従する日本語 IME | NSTextInputClient、marked text と候補位置 | SwiftTerm native input |
| グローバルホットキー | Carbon RegisterEventHotKey、既定 ⌥⇧V、キー / 修飾キー変更 | GlobalHotkey |
| モニターごとの位置記憶 / 切断時復帰 | NSScreen ID ごとの保存、可視領域へのクランプ | TerminalWindowController |
| ビルド日時表示 | ビルド生成の CFBundleVersion をタイトルへ表示 | build.sh、SessionPane |
| F11 の高さドック / ディスプレイ変更追従 | visibleFrame の高さ、元のフレーム復元、画面変更通知 | TerminalWindowController |
| ライブ設定 / 色選択 / 不透明度 / 行列 | SwiftUI Form、NSColorPanel、背景だけの不透明度、行列指定でリサイズ、JSON の自動反映 | SettingsView、Workspace |
| タブごとのログ | UTF-8 を保持した ANSI / OSC / DCS 除去、開始・停止、private ログファイル | SessionLog、EscapeFilter |
| クラッシュログ | NSException と fatal signal、macOS DiagnosticReports | Diagnostics |
| 遅いフレームの性能ログ | パース時間、SwiftTerm の実測描画・IO 分布、15秒ごとの遅い区間記録 | Diagnostics、TerminalProfiling |
| アプリから独立した選択 / コピー | クリック・ドラッグをローカル処理、⌘C、選択中の ⌃C | NativeTerminalView、イベント監視 |
| ホイールのアプリ送信 / ⇧ホイール履歴 | SwiftTerm の通常ルーティング、⇧は常にローカル | AppDelegate |
| 右クリックペースト、URL の修飾クリック | 右クリックでペースト、⌘クリックでブラウザ、HTTP(S) / mailto に限定 | NativeTerminalView、requestOpenLink |
| Explorer の Open in Terminal | Finder サービス Open in Terminal2、フォルダ起動引数 | Info.plist、AppDelegate |

## 意図的なプラットフォーム差

Windows 用の PowerShell / cmd / WSL / Git Bash は、Mac に存在するログインシェルへ置き換えます。`pwsh` がインストール済みなら候補に入ります。ショートカットは macOS の Command 中心に変更しました。

設定ファイルの形式は JSON です。Windows の TOML ファイルを自動移行する機能は含めていません。Windows 固有の認証・レジストリ・ConPTY・ClearType は使用しません。SSH の実装言語は Rust から標準 OpenSSH に変わり、標準のホスト鍵検証、SSH 設定の全機能を利用します。

macOS 26 以降を対象にしています。Intel Mac、実ディスプレイの抜き差し、パスワード / パスフレーズの全環境での認証、日本語 IME の全入力モードはこの環境では実機検証できていません。対応済みの実装と検証済みのシナリオは区別して [検証記録](validation.md) に記載します。
