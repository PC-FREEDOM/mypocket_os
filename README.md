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
- 電源・セッション操作 (ログアウト・再起動・電源オフ)
- ファームウェア設定への再起動
- GUI確認ダイアログ (yad)

電源・セッション操作について:

- ログアウト・再起動・電源オフ・ファームウェア設定はすべて
  `/usr/local/bin/mypocketos-power` に集約されており、jgmenu (アプリメニュー内
  「電源・セッション」) とOpenbox右クリックメニュー (「電源・セッション」
  サブメニュー) の両方から同じ確認ダイアログ経由で呼び出されます。
- sudoは使用せず、systemd-logind (`systemctl`) とPolicyKit (`lxpolkit`) の
  組み合わせに委ねています。
- ファームウェア設定画面への再起動は、UEFIおよび機器 (ファームウェア) 側の
  対応が必要です。対応可否は `systemd-logind` の
  `CanRebootToFirmwareSetup()` (D-Bus) で都度判定し、非対応と判定された
  場合は再起動を行わず、日本語のGUIメッセージで理由を表示します。

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

Openbox右クリックメニューの「電源・セッション」→「ログアウト」(またはjgmenuの
同項目) を選択すると、LightDMのログイン画面へ戻ります。ログイン画面から
再ログインする場合の既定のユーザー名・パスワードは次のとおりです。

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

## Live環境の再起動

Live環境の起動パラメータ (`auto/config` の `--bootappend-live`) に
`noeject` を指定しています。これは、Live環境の再起動時にメディアの取り外し
待ちにならないようにするためのものです。Liveメディアを接続したまま
再起動できるようにする設定であり、通常インストール環境の再起動には
影響しません (live-boot(7) 参照)。

今回のテスト結果は次のとおりです。

- 「電源・セッション」→「再起動」(`mypocketos-power`) から `systemctl reboot`
  が実行され、`noeject` によりメディアの取り外し待ちが表示されないことを
  確認しました。
- 永続VM `mypocketos-test` で、同じISOを接続したままLive環境へ再起動できる
  ことを確認しました。
- 再起動後、`hostname` が `mypocketos` を返すこと、稼働時間がリセットされて
  いること、`/proc/cmdline` 内に `noeject` が1件だけ含まれていることを
  確認しました。

## QEMU/KVM検証環境

`scripts/create-test-vm.sh` と `scripts/update-test-iso.sh` は、
**MyPocketOSのISO内ではなく、開発ホスト (Debianで virt-install/virsh/QEMU/KVM
がセットアップ済みの環境) で実行するスクリプト**です。ビルドしたISOを
QEMU/KVM上のVMで手軽に確認するためのものであり、MyPocketOS自体には含まれません。

前提として、`qemu:///system` が使えること (libvirtの `default` ネットワークが
active であること)、および `sudo` が使えることが必要です。

### 初回作成

```sh
./scripts/build.sh                 # ISOをビルド (未実施の場合)
./scripts/create-test-vm.sh
```

`live-image-amd64.hybrid.iso` を `/var/lib/libvirt/images/MyPocketOS-dev.iso`
へコピーし (コピー後にSHA-256を照合)、`mypocketos-test` という名前の永続VMを
`qemu:///system` に作成して起動します。VMはこのISOから直接Live起動します
(`--import` によりインストーラは起動しません)。

VMには16GiBのqcow2仮想ディスクも接続されますが、**これは将来のインストーラ
検証用であり、現時点のLive起動には使用しません**(起動順序はCD-ROMが先、
仮想ディスクが後です)。

### ISO再ビルド後の更新手順

```sh
virsh --connect qemu:///system shutdown mypocketos-test   # VMを停止
./scripts/build.sh                                        # ISOを再ビルド
./scripts/update-test-iso.sh                               # ISOのみを更新
virsh --connect qemu:///system start mypocketos-test       # VMを起動
```

`update-test-iso.sh` は、`mypocketos-test` が存在しない場合や、状態が厳密に
「停止 (shut off)」でない場合 (実行中・一時停止中・状態取得失敗などを含む)は
何もせず失敗します。VM定義や仮想ディスクには一切触れず、ISOファイルのみを
更新します。

### 動作確認

実機でのテストにより、次を確認済みです。

- `create-test-vm.sh` で永続VM `mypocketos-test` を作成できたこと
- CD-ROMが `boot.order=1`、仮想ディスクが `boot.order=2` であること
- SPICE・クリップボード共有・spice-vdagentが動作すること
- VM実行中に `update-test-iso.sh` を実行するとISO交換が拒否されること
- VM停止後は、ISOの更新とSHA-256の一致確認に成功すること
- 更新後、同じVMからMyPocketOSをLive起動できること

### virt-managerで開く

virt-managerを起動し、`QEMU/KVM` (qemu:///system) の接続の下に
`mypocketos-test` が表示されます。ダブルクリックするとSPICE経由で画面に
接続できます (`listen=127.0.0.1` のためホスト上でのみ接続可能です)。

### VMの削除について

これらのスクリプトは、VM・仮想ディスク・ISOを削除する機能を意図的に
実装していません。不要になった場合は、virt-managerで対象のVM名が
`mypocketos-test` であることを確認したうえで、手動で管理してください
(誤削除防止のため、本READMEでは削除コマンドは案内しません)。
