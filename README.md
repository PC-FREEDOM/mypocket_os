MyPocketOSは、DebianとOpenboxをベースにした、
日本語環境を持ち歩ける軽量デスクトップLinuxです。

USBからLive起動でき、必要に応じて設定、データ、
追加アプリを永続保存できます。内蔵ストレージへの
通常インストールにも対応します。

Tailsの携帯性を参考にしていますが、
匿名化や高度な痕跡防止を目的としたOSではありません。

## ビルド手順

Debian 13 (trixie) 上で live-build を使い、ISOイメージをビルドします。

### 前提

- Debian 13 (trixie) の環境であること
- `live-build` パッケージがインストールされていること
- `sudo` でroot権限を取得できること (`lb clean` / `lb build` はroot権限が必要)

### 実行方法

```sh
./scripts/build.sh
```

`scripts/build.sh` は以下の順に実行します。

1. `sudo lb clean` — 前回のビルド生成物 (chroot・binary・各段階の生成物) を削除。パッケージキャッシュは再利用のため残す
2. `lb config` — `auto/config` (`lb config noauto ...`) を実行し、`config/` 以下の設定を生成
3. `sudo lb build` — chrootの構築とISOイメージの生成

実行ログは `build.log` に保存されます。

ビルドに成功すると、プロジェクトルート直下に `live-image-amd64.hybrid.iso` が生成されます。出力ISOおよび live-build の作業生成物 (`config/binary` などの生成済み設定、`chroot/`、`cache/`、`local/`、`.build/` 等) はGit管理対象外です。

### 今回の実装範囲

初回起動確認用の最小構成であり、以下を含みます。

- amd64 / iso-hybrid、Debian 13 trixie (archive areas: main contrib non-free-firmware)
- Openbox + tint2 + LightDM (GTK greeter) + PCManFM + LXTerminal
- NetworkManager (nm-applet) / lxpolkit (PolicyKit認証エージェント)
- 日本語ロケール (ja_JP.UTF-8) ・ 日本語キーボード (jp) ・ タイムゾーン (Asia/Tokyo)
- Noto CJKフォント / Fcitx5-Mozc
- SPICEクリップボード・画面統合
- PipeWire音声基盤
- 音量設定とトレイアイコン
- zram圧縮スワップ
- jgmenuアプリメニュー
- tint2メニューボタン
- Openbox右クリックメニューとの併用
- Conkyシステム情報表示
- Openboxキーボードショートカット
- 日本語Openbox右クリックメニュー

以下は未実装です (今後の課題)。

- 永続化 (persistence)
- Calamaresによるインストーラ
- 一般アプリ一式
- 独自テーマ・ブランディング
- 外部リポジトリからテーマ等を取得するフック

### 既知の制限

- jgmenuの検索入力は英字検索のみ動作確認済みです。Fcitx5-Mozcを使用した日本語検索は
  現時点では正常に機能しません。日本語でのメニュー表示、およびカテゴリからのアプリ
  起動には影響しません。

## Live環境のログイン

MyPocketOSのLive環境は、通常起動時にlive-configの自動ログイン機能により
自動的にデスクトップへログインします（ユーザー操作は不要です）。

Openbox右クリックメニューの「ログアウト」を選択すると、LightDMのログイン画面へ
戻ります。ログイン画面から再ログインする場合の既定のユーザー名・パスワードは
次のとおりです。

- ユーザー名: `user`
- パスワード: `live`

これは `live-config`（`0030-live-debconfig_passwd` スクリプト、コメント
"Default password is: live"）が設定するDebian Live標準の既定値であり、
MyPocketOS独自の設定ではありません。また、将来実装予定の通常インストール環境
（Calamares等）で作成されるユーザーアカウントの認証情報とは別のものです。

VMでの動作確認により、Openbox右クリックメニューの「ログアウト」を実行して
LightDMのログイン画面へ正常に戻ること、および上記の既定値（`user` / `live`）で
LightDMから再ログインできることを確認済みです。再ログイン後は以下も確認済みです。

- `whoami` が `user` を返す
- `hostname` が `mypocketos` を返す
- Openboxが1プロセスのみ起動している（多重起動なし）
- Conkyが1プロセスのみ起動している（`-U`オプションによる多重起動防止が機能）
- tint2・PCManFM・Conkyが正常に再表示される
