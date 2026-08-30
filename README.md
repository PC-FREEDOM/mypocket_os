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

edition (`base` または `standard`) の指定が必須です。省略時や不正な値は
デフォルトを推測せず、usageを表示して終了します。

```sh
./scripts/build.sh base
./scripts/build.sh standard
```

`scripts/build.sh` は以下の順に実行します。

1. edition引数の検証
2. 選択したeditionに必要なpackage-list (`config/package-lists.d/` が正本)
   だけを`config/package-lists/`へ一時的に配置 (詳細は
   「Base版 / Standard版のedition分離ビルド」節を参照)
3. `sudo lb clean` — 前回のビルド生成物 (chroot・binary・各段階の生成物) を削除。パッケージキャッシュは再利用のため残す
4. `lb config --image-name mypocketos-${EDITION}` — `auto/config` (`lb config noauto ...`) を実行し、`config/` 以下の設定を生成
5. `sudo lb build` — chrootの構築とISOイメージの生成
6. 一時配置したpackage-listの削除 (成功・失敗・SIGINT等いずれでも行う)

実行ログは `build.log` に保存されます。

ビルドに成功すると、プロジェクトルート直下に `mypocketos-base-amd64.hybrid.iso`
または`mypocketos-standard-amd64.hybrid.iso`が生成されます (`--image-name`は
live-buildの正規オプション。旧来の`live-image-amd64.hybrid.iso`という名前は
今後生成されません)。出力ISOおよび live-build の作業生成物 (`config/binary`
などの生成済み設定、`chroot/`、`cache/`、`local/`、`.build/` 等) はGit管理
対象外です。

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

### Base版 / Standard版のedition分離ビルド

`config/package-lists.d/`を正本とし、Base版とStandard版を明示的に選んで
別々にビルドできます。

```
Base     = mypocketos-common.list.chroot
Standard = mypocketos-common.list.chroot + mypocketos-standard.list.chroot
```

live-build (`chroot_package-lists`) は `config/package-lists/*.list.chroot`
に一致する全ファイルを無条件に取り込む仕様であり、edition単位で選択的に
取り込む機能自体は持っていません。そのため正本を`config/package-lists.d/`
(live-buildの読み込み対象外) に置き、`scripts/build.sh`がビルド中のみ
選択されたeditionに必要なファイルだけを`config/package-lists/`へ一時的に
配置し、ビルド終了後 (成功・失敗・SIGINT等いずれでも) 削除します。

出力ISO名は、live-build標準の`--image-name`オプションで
`mypocketos-base-amd64.hybrid.iso` / `mypocketos-standard-amd64.hybrid.iso`
となります (ビルド後に`mv`等で改名する処理は行いません)。

将来Creator版を追加する場合も、`mypocketos-creator.list.chroot`を
`config/package-lists.d/`へ追加するだけで済み、common/standardの重複管理は
発生しません (`Creator = common + standard + creator`という積み上げ式)。

### Standard版の追加アプリ

Base版の構成に加えて、Standard版では次のアプリを追加します。

- Firefox ESR (日本語UI)
- LibreOffice Writer / Calc / Impress / Draw (GTK3統合、日本語UI・日本語ヘルプ付き)
- GNOME Drawing (描画ツール)
- Mousepad (テキストエディタ)
- Galculator (電卓)

パッケージ定義は `config/package-lists.d/mypocketos-standard.list.chroot` に
まとめています。Firefox・LibreOffice・Drawing・Mousepad・GalculatorはいずれもDebian 13 (trixie)
のパッケージを使用しています。

GIMP・Inkscape・動画編集・音楽制作・Blenderは、今回のStandard版には
含めていません。将来のCreator系構成の候補です。

**実測ISOサイズ**

`./scripts/build.sh base` / `./scripts/build.sh standard` でそれぞれ実際に
ビルドし、確認した値です。

| edition | ISO | サイズ |
|---|---|---|
| Base | `mypocketos-base-amd64.hybrid.iso` | 約1.33 GiB (1,428,750,336 bytes) |
| Standard | `mypocketos-standard-amd64.hybrid.iso` | 約1.67 GiB (1,788,149,760 bytes) |

差は約343 MiB (359,399,424 bytes、StandardはBaseより約25.15%大きく、
BaseはStandardより約20.10%小さい) です。ISOのSHA-256はビルドごとに
変わる (タイムスタンプ等を含むため) ため、ここには記載しません。

### アイコンテーマ (MyPocketOS-Fluent-yellow)

既定のGTKアイコンテーマは、`MyPocketOS`という薄い継承テーマ
(`/usr/share/icons/MyPocketOS/index.theme`、
`Inherits=MyPocketOS-Fluent-yellow,Adwaita,hicolor`) を介して選択して
います (`~/.config/gtk-3.0/settings.ini`・`~/.gtkrc-2.0`の
`gtk-icon-theme-name`)。**`MyPocketOS-Fluent-yellow`は、upstream
「Fluent Icon Theme」の完全版ではなく、MyPocketOS向けに固定サイズ・
HiDPI等を除いた派生サブセットです。** MyPocketOS独自のアイコンを
追加する場合は、この派生サブセット本体を直接改変せず、`MyPocketOS`
テーマ側にのみ追加する方針です。Adwaitaへ戻す場合は、上記2ファイルの
`gtk-icon-theme-name`を`Adwaita`へ書き換えるだけで戻せます。GTKテーマ・
ウィンドウ装飾・Openboxテーマは変更していません。

**Git管理方式 (単一tar.gzアーカイブ + live-build hookでのオフライン展開)**

`MyPocketOS-Fluent-yellow`は、12,000ファイル超を展開した状態でGit管理
するのではなく、単一の再現可能な`tar.gz`として
`config/includes.chroot/usr/share/mypocketos/icon-themes/MyPocketOS-Fluent-yellow.tar.gz`
にコミットしています。ビルド時、live-build hook
(`config/hooks/normal/mypocketos-fluent-icon-theme.hook.chroot`)
が以下を行います。

1. アーカイブの存在確認
2. SHA-256検証 (hook内に埋め込んだ固定値と一致することを確認。不一致なら
   非0で終了しビルドを止める)
3. アーカイブ内の全エントリが安全なパス (絶対パスでない、`..`を含まない、
   想定するトップディレクトリ`MyPocketOS-Fluent-yellow/`以下のみ) である
   ことの検証。1つでも満たさなければ展開せず終了する
4. `/usr/share/icons/`へ展開
5. `index.theme`・`COPYING`・`MODIFICATIONS.md`・symbolic音量アイコン4種
   の存在確認
6. 元の`tar.gz`をイメージ内から削除 (最終ISOにアーカイブ自体は残らない)

この一連の処理はネットワークアクセスを一切行いません (アーカイブは
ビルド開始前にリポジトリから`config/includes.chroot`経由で既にchroot内へ
配置されているため)。live-buildのchrootステージ順序
(`chroot_includes_after_packages` → `chroot_hooks`、
`/usr/lib/live/build/chroot`で確認済み) により、本hook実行時点でアーカイブは
必ず存在します。

**アーカイブの再生成**

```sh
./scripts/rebuild-fluent-yellow-subset.sh /path/to/fluent-icon-theme-2026-07-27.tar.gz
```

このスクリプト自体もネットワークアクセスを一切行いません。入力として
受け付けるのは、下記SHA-256と一致する指定タグのtarballのみです (一致
しない場合は処理を中断します)。処理の概要は、tarball展開 → 同梱の
`install.sh`をローカル実行 (yellowカラーの標準明度のみ) → シンボリック
リンクの実体化 → 固定サイズ/HiDPI/不正ファイル名3件の削除 → `MyPocketOS-Fluent-yellow`
への改名 → `index.theme`書き換え → `MODIFICATIONS.md`生成 → 再現可能な
`tar.gz`生成、です。**アーカイブを再生成した場合は、
`config/hooks/normal/mypocketos-fluent-icon-theme.hook.chroot`内の
`EXPECTED_ARCHIVE_SHA256`も新しいアーカイブのSHA-256へ必ず更新してください**
(更新を忘れるとhookがSHA-256不一致でビルドを止めます)。

**取得元・ライセンス**

- upstream: Fluent Icon Theme (https://github.com/vinceliuice/Fluent-icon-theme)
- 取得タグ: `2026-07-27` (コミット `c70c2441bcf2ab8bbc267e55635c76d69f659a8b`)
- upstream入力tarballのSHA-256: `7fdd60faa543b297ef2d4f3d083d8b382e59a9b0933cbb1dfc042539d45036e2`
- ライセンス: GPL-3.0。upstream原文のまま無改変の`COPYING`をアーカイブ内
  (`MyPocketOS-Fluent-yellow/COPYING`) に同梱しています
- 変更内容の詳細は、アーカイブ内`MyPocketOS-Fluent-yellow/MODIFICATIONS.md`
  に記録しています (upstream情報・生成日・変更点・削除したディレクトリ・
  除外したファイルの一覧)
- upstreamの`install.sh`は、curl/wget/apt等のネットワークアクセスを一切
  含まないことをソース確認済みです。ビルド時・Live起動時に`install.sh`を
  ネットワーク経由で取得することはありません (アーカイブ生成は開発者が
  事前に手元で1回だけ行い、その結果だけをリポジトリへコミットします)

**主な変更点 (詳細は`MODIFICATIONS.md`参照)**

- テーマ名を`Fluent-yellow`から`MyPocketOS-Fluent-yellow`へ変更
  (upstream完全版と誤認されないようにするため)
- `index.theme`を書き換え、実際に収録する`scalable/`・`symbolic/`配下の
  ディレクトリのみを参照するようにした (固定サイズ`16`/`22`/`24`/`32`/
  `256`とHiDPI`@2x`/`@3x`は削除。`scalable`/`symbolic`は`Type=Scalable`
  のため任意の解像度で描画できる)
- 生成過程で作られる`icon-theme.cache`を削除
- ファイル名が不正 (拡張子欠落・破損) で実質的に無効な3ファイル
  (`cinnamon-virtual-keyboard`・`org.gnome.Weather.Application.svg}`・
  `page.kramo.Cartridges`) を除外 (upstream生成結果の時点で既にこの名前
  であり、MyPocketOSが破損させたものではない。同名の正しい`.svg`拡張子
  ファイルは別途存在する)
- 色共通アイコンを指すシンボリックリンクを実ファイルへ実体化し、単体で
  自己完結する構成にした
- `scalable/`・`symbolic/`配下のSVGファイル自体の内容は、上記除外3件を
  除きupstream生成結果と無改変

アーカイブは12,220ファイル・約57MB相当を単一tar.gzに圧縮したもので、
リポジトリへのコミットサイズは展開状態より大幅に小さくなります。

## Live環境のログイン

MyPocketOSのLive環境は、通常起動時にlive-configの自動ログイン機能により
自動的にデスクトップへログインします（ユーザー操作は不要です）。

デスクトップ背景を右クリックしてjgmenuを開き、「電源・セッション」→
「ログアウト」を選択すると、LightDMのログイン画面へ戻ります。ログイン画面から
再ログインする場合の既定のユーザー名・パスワードは次のとおりです。

- ユーザー名: `user`
- パスワード: `live`

これは `live-config`（`0030-live-debconfig_passwd` スクリプト、コメント
"Default password is: live"）が設定するDebian Live標準の既定値であり、
MyPocketOS独自の設定ではありません。また、将来実装予定の通常インストール環境
（Calamares等）で作成されるユーザーアカウントの認証情報とは別のものです。

VMでの動作確認により、デスクトップ右クリックのjgmenuから「ログアウト」を
実行してLightDMのログイン画面へ正常に戻ること、および上記の既定値（`user` / `live`）で
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

`create-test-vm.sh`・`update-test-iso.sh`とも、editionの指定 (`base` または
`standard`) が必須です。省略時や不正な値はデフォルトを推測せず、usageを
表示して終了します。

BIOS版VMを作成します (`--firmware`省略時はBIOS)。

```sh
./scripts/build.sh standard        # ISOをビルド (未実施の場合)
./scripts/create-test-vm.sh standard
```

UEFI版VMを作成する場合:

```sh
./scripts/create-test-vm.sh --firmware uefi standard
```

いずれも、指定したeditionに対応するISO
(`mypocketos-base-amd64.hybrid.iso` / `mypocketos-standard-amd64.hybrid.iso`)
を`/var/lib/libvirt/images/MyPocketOS-dev.iso`へコピーし (コピー後にSHA-256を
照合)、`qemu:///system` に永続VMを作成して起動します。VMはこのISOから直接
Live起動します (`--import` によりインストーラは起動しません)。

BIOS版とUEFI版の違いは次のとおりです。

| | BIOS (既定) | UEFI |
|---|---|---|
| VM名 | `mypocketos-test` | `mypocketos-uefi-test` |
| 仮想ディスク | `mypocketos-test.qcow2` | `mypocketos-uefi-test.qcow2` |
| ファームウェア | レガシーBIOS | OVMF (UEFI) |
| TPM | なし | `--tpm none` (TPMデバイスなし) |

RAM 2048MiB・vCPU 2・16GiBのqcow2仮想ディスク・CD-ROM (`boot.order=1`)・
仮想ディスク (`boot.order=2`)・SPICE (クリップボード共有あり)・spicevmc・
virtioビデオ・ich9サウンド・自動起動なしは、BIOS版・UEFI版で共通です。

**両VMは同じ `MyPocketOS-dev.iso` を共有します。** VMには16GiBのqcow2仮想
ディスクも接続されており、起動順序はCD-ROMが先、仮想ディスクが後です。
作成直後のこのqcow2は空です。「Live永続化基盤」の手動テスト手順では、
このディスクをpersistenceパーティションとして初期化して使用します。
将来的にはインストーラ検証にも利用する予定です。

### ISO再ビルド後の更新手順

`MyPocketOS-dev.iso` はBIOS版・UEFI版の両方から共有されるため、更新前には
**このISOを参照している全てのVMを停止しておく必要があります**。

```sh
virsh --connect qemu:///system shutdown mypocketos-test        # BIOS版を停止
virsh --connect qemu:///system shutdown mypocketos-uefi-test   # UEFI版を停止
./scripts/build.sh standard                                     # ISOを再ビルド (ビルド済みのVMと同じeditionを指定)
./scripts/update-test-iso.sh standard                           # ISOのみを更新 (同上)
```

`update-test-iso.sh` は、固定のドメイン名をハードコードせず、このISOを
実際に参照している全ドメインを毎回動的に検査します。参照しているVMが
1件も無ければ「更新対象のVMが見つからない」として失敗し、1件以上ある
場合は、それら全てのVMの状態が厳密に「停止 (shut off)」であるときのみ
更新を行います (実行中・一時停止中・状態取得失敗などが1件でもあれば、
何もせず失敗します)。VM定義や仮想ディスクには一切触れず、ISOファイルの
みを更新します。更新に成功すると、検出した各VMの起動コマンドを表示します。

### 動作確認

実機でのテストにより、次を確認済みです。BIOS版とUEFI版で確認済みの範囲が
異なるため、分けて記載します。

- BIOS版は `create-test-vm.sh` で実際に作成済みです。
- UEFI版は、`create-test-vm.sh` のUEFI対応より前に、同等構成の
  `virt-install` コマンドを手動で実行して作成・起動し、`/home` の
  永続化検証まで実施済みです。
- UEFI対応後の `create-test-vm.sh --firmware uefi` 自体は、
  `--print-xml --dry-run` によるXML生成と、libvirtスキーマ
  (`virt-xml-validate`) による検証までを行っています。この更新後
  スクリプトによるUEFI VMの実際の作成そのものは、今回未実施です。
- CD-ROMが `boot.order=1`、仮想ディスクが `boot.order=2` であることは
  BIOS版・UEFI版とも確認済みです。
- SPICE・クリップボード共有・spice-vdagentが動作すること (BIOS版で確認)。
- VM実行中に `update-test-iso.sh` を実行するとISO交換が拒否されること。
- VM停止後は、ISOの更新とSHA-256の一致確認に成功すること。
- 更新後、同じVMからMyPocketOSをLive起動できること。

### virt-managerで開く

virt-managerを起動し、`QEMU/KVM` (qemu:///system) の接続の下に、
BIOS版は `mypocketos-test`、UEFI版は `mypocketos-uefi-test` という名前で
表示されます。ダブルクリックするとSPICE経由で画面に接続できます
(`listen=127.0.0.1` のためホスト上でのみ接続可能です)。

### VMの削除について

これらのスクリプトは、VM・仮想ディスク・ISOを削除する機能を意図的に
実装していません。不要になった場合は、virt-managerで対象のVM名が
`mypocketos-test` または `mypocketos-uefi-test` であることを確認したうえで、
手動で管理してください (誤削除防止のため、本READMEでは削除コマンドは
案内しません)。

## Live永続化基盤

- 起動メニューは、通常Liveと永続Liveで分かれています
  (BIOS/Syslinux: `MyPocketOS Live` / `MyPocketOS Live (Persistence)` /
  `MyPocketOS Live (Fail-safe)` の3ラベル。UEFI/GRUB も同名の3項目)。
- 通常Liveには `nopersistence`、永続Liveには `persistence` の起動
  パラメータが付きます。
- 現段階で永続化の対象となるのは `/home` のみです。
- 永続化には、ext4でフォーマットしラベルを `persistence` にした
  パーティションと、そのルートに置く `persistence.conf` (中身は
  `/home` の1行だけ) が必要です。
- 暗号化 (LUKS等) は未実装です。
- GUIによるパーティション作成は実装済みであり、2026-08-26に専用の
  BIOS版・UEFI版の双方の使い捨てテストVMで、GUIから実際に新規
  persistence領域を作成できることを確認済みです (詳細は「GUIによる
  永続領域作成 (実装仕様)」節の「動作確認」を参照)。
- `/home` 配下の一般アプリ設定・ユーザーデータは保存対象です。
- 追加インストールしたアプリ本体、パッケージ一覧、APTキャッシュの永続化は
  未実装です。

### `/` unionを採用しない理由

- `/` unionはシステム全体の変更を保存する方式であり、カーネルやLive基盤を
  ISO更新によって提供するという方針と衝突します。
- 今回はユーザーデータとホームディレクトリ配下の設定だけを永続化の対象と
  します。
- 一般アプリの永続化は、将来的にパッケージ一覧とAPTキャッシュを使う
  別機能として実装する予定です。

### 手動テスト手順 (開発用VM専用)

**警告**

- この手順は開発用VM `mypocketos-test` 専用です。
- 対象デバイス (`/dev/vda`) の内容はすべて失われます。
- 実機やUSBメモリでは実行しないでください。
- デバイスが `/dev/vda` であることを確認できない場合は中止してください。
- 実際のデバイス名は環境により異なるため、この手順の `/dev/vda` は
  製品利用者向けの一般化された手順ではありません。

手順:

1. VM `mypocketos-test` 上のLive環境で、`lsblk` を実行し、`/dev/vda` が
   16GiBの空ディスク (CD-ROMではない) であることを確認する。

   ```sh
   lsblk
   ```

2. `parted` でGPTと、ext4用のパーティション `/dev/vda1` を作成し、
   カーネルにパーティション情報を再読込させてから、`/dev/vda1` が
   実際に存在することを確認する。**ここで `/dev/vda1` の存在を
   確認できない場合は、以降の手順に進まず中止する。**

   ```sh
   sudo parted -s /dev/vda -- mklabel gpt
   sudo parted -s /dev/vda -- mkpart persistence ext4 1MiB 100%
   sudo partprobe /dev/vda
   sudo udevadm settle
   lsblk -f /dev/vda
   ```

3. `/dev/vda1` をext4でフォーマットし、ラベルを `persistence` にする。

   ```sh
   sudo mkfs.ext4 -L persistence /dev/vda1
   ```

4. 一時的にマウントする。

   ```sh
   sudo mkdir -p /mnt/persistence
   sudo mount /dev/vda1 /mnt/persistence
   ```

5. `persistence.conf` を作成する (中身は `/home` の1行のみ)。シェルの
   リダイレクトでは書き込み権限の問題が起きうるため、`tee` を使う。
   作成後は内容を確認する。

   ```sh
   printf '/home\n' | sudo tee /mnt/persistence/persistence.conf >/dev/null
   cat /mnt/persistence/persistence.conf
   ```

6. 同期してアンマウントする。

   ```sh
   sync
   sudo umount /mnt/persistence
   ```

7. VMを再起動し、ブートメニューから「MyPocketOS Live (Persistence)」を
   選択する。

8. 永続Liveで起動した直後、テストファイルを作成する前に、永続化が
   実際に有効になっていることを確認する。`/home` がラベル `persistence`
   の `/dev/vda1` から提供されていることを確認できてから次に進む。

   ```sh
   findmnt --target /home
   lsblk -f
   ```

9. `/home/user` にテストファイルを作成する (例: `touch ~/persistence-test`)。

10. 永続Liveで再起動し、テストファイルが残っていることを確認する。

11. 通常Live (`MyPocketOS Live`) で起動し、同じファイルが見えないことを
    確認する。

12. 再び永続Liveで起動し、テストファイルが見えることを確認する。

### 動作確認

以下は、開発用QEMU/KVM VM (BIOS版 `mypocketos-test` およびUEFI版
`mypocketos-uefi-test`) 上で、BIOS/SyslinuxとUEFI/GRUBの両方の起動経路で
実際に確認した内容です。検証環境は、16GiBの空の `/dev/vda` に対して
`/dev/vda1` をext4で作成し、ファイルシステムラベルを `persistence`、
`persistence.conf` の内容を `/home` の1行としたものです。

**BIOS/Syslinuxでの確認内容**

1. BIOS/Syslinuxの起動メニューに、次の3項目が表示されることを確認しました。
   - `MyPocketOS Live`
   - `MyPocketOS Live (Persistence)`
   - `MyPocketOS Live (Fail-safe)`

2. 通常Live (`MyPocketOS Live`) では次を確認しました。
   - カーネルコマンドラインに `nopersistence` が1件、`persistence` が
     0件であること
   - `/home` がLive環境のoverlayであること
   - `/dev/vda1` がマウントされないこと
   - 永続領域内に作成したテストファイルが表示されないこと

3. Persistenceモード (`MyPocketOS Live (Persistence)`) では次を確認しました。
   - カーネルコマンドラインに `persistence` が1件、`nopersistence` が
     0件であること
   - `/home` が `/dev/vda1[/home]` としてマウントされていること
   - `/home/user` が `user:user` 所有、パーミッション `0700` で
     作成されていること

4. `/home/user/persistence-test` を作成し、Persistenceモードで再起動した
   後も、内容と所有者が維持されていることを確認しました。

5. 通常Liveへ切り替えるとテストファイルは表示されず、再びPersistenceモード
   へ戻ると同じ内容で再表示されることを確認しました。

6. 各再起動でカーネルの `boot_id` が変化していることを確認しており、
   同一セッション内の見かけ上の確認ではないことを確認しています。

**UEFI/GRUBでの確認内容**

UEFI版VM (`mypocketos-uefi-test`, OVMFによる64-bit UEFI起動) でも、同様に
次を確認しました。

1. GRUBの起動メニューに、次の3項目が表示されることを確認しました。
   - `MyPocketOS Live`
   - `MyPocketOS Live (Persistence)`
   - `MyPocketOS Live (Fail-safe)`

2. 通常Live (`MyPocketOS Live`) では、カーネルコマンドラインに
   `nopersistence` が1件・`persistence` が0件であること、`/dev/vda1` が
   マウントされず永続領域内のテストファイルが見えないことを確認しました。

3. Persistenceモードでは、カーネルコマンドラインに `persistence` が
   1件・`nopersistence` が0件であること、`/home` が `/dev/vda1[/home]`
   としてext4でマウントされ、`/home/user` が `user:user` 所有・
   パーミッション `0700` で作成されていることを確認しました。

4. 再起動後もテストファイルの内容・所有者・パーミッションが維持され、
   通常Liveへ切り替えると非表示に、Persistenceへ戻すと再表示されること、
   および再起動ごとにカーネルの `boot_id` が変化することを確認しました。

**この手順で確認していない事項**

- GUIによる永続領域作成は、本手順 (GUIを介さず`parted`/`mkfs.ext4`/
  `mount`/`tee`を直接実行するBIOS/UEFI手動永続化テスト) の対象には
  含まれていません。GUI経由の新規作成は、本手順とは別に、専用のBIOS版・
  UEFI版の双方の使い捨てテストVMを用いて確認済みです (詳細は「GUIに
  よる永続領域作成 (実装仕様)」節の「動作確認」を参照)。署名・mount・
  swap・holders等の各拒否条件を個別の実ブロックデバイスで確認する
  実機試験は未確認です。
- LUKSによる暗号化は未実装です。
- 追加インストールしたアプリ本体、パッケージ一覧、APTキャッシュの
  永続化は未実装です。

上記のとおり、BIOS/SyslinuxとUEFI/GRUBの両方で `/home` の永続化を
確認済みです (GUI経由のBIOS版・UEFI版新規作成も別途確認済みです)。
暗号化、アプリ本体の永続化といった、本手順の対象外または未実装の
機能については、確認済みとはみなしていません。

### GUIによる永続領域作成 (実装仕様)

GUI本体 (`/usr/local/bin/mypocketos-persistence-setup`)・特権ヘルパー
(`/usr/local/libexec/mypocketos-persistence-setup-helper`)・jgmenu
(`append.csv`) およびOpenbox右クリックメニュー (`menu.xml`) への統合は、
いずれもソース上で実装済みである。`sh -n`/`dash -n`によるPOSIX sh構文
検査、`xmllint --noout`によるOpenboxメニューXMLの整形式検査、および
実sudo・実helper・実parted/mkfs/mountを一切使わない非破壊モックテスト
(GUI・helper双方) による検証を行っている。

2026-08-26には、この変更を含むISOを実際に再ビルドし、専用のBIOS版
使い捨てテストVM `mypocketos-persistence-gui-test`、および専用の
UEFI版使い捨てテストVM `mypocketos-persistence-gui-uefi-test`
(いずれも共有ISO `MyPocketOS-dev.iso`と新規の空16GiB qcow2ディスクの
みを接続) 上で、GUI経由の実際の新規persistence領域作成まで確認した
(詳細は後述の「動作確認」節を参照)。**GUI経由の実動作は、専用BIOS VM
と専用UEFI VMの双方で確認済みである。** 同じくBIOS版使い捨てVM上で、
既存の永続領域を持つディスクに対してGUI・helperが実際に新規作成を
拒否することも確認した。

一方、次の項目は未確認である。

- 署名・mount・swap・holders等、各拒否条件を個別の実ブロックデバイスを
  追加して確認する実機試験 (これらは非破壊モックテストでは確認済み)。
- 専用UEFI VMでのSecure Boot有効状態 (`mokutil`未搭載のため未確認。
  UEFI起動自体は確認済み)。

これらは、上記「手動テスト手順」節のBIOS/UEFI手動永続化テスト (GUIを
介さず`parted`/`mkfs.ext4`/`mount`/`tee`を直接実行して確認したもの) とは
別の検証範囲である。両者を混同しない。以下は、この実装が従う仕様を
まとめたものである。

#### 初版のスコープ

- 初版が対象とするのは、**完全に未使用のwhole disk (ディスク全体)** のみと
  する。ディスクの一部に空き領域があるだけのケース (既存パーティションと
  未使用領域が混在する状態) は対象外とする。「whole diskが丸ごと空である
  こと」を確認できた場合のみ候補とする。
- 既存の永続領域の検出範囲は、選択したディスク1台に限らず、**接続されて
  いる全ブロックデバイスを対象とする** (詳細は「既存の永続領域の検出範囲」
  節を参照)。検出した場合は上書き・再作成を行わず、新規作成そのものを
  拒否する。既存の永続領域を扱うUI (更新・再フォーマット等) は初版の
  スコープに含めない。

#### GUI側の予備的な候補除外 (一般ユーザー権限)

GUI (`mypocketos-persistence-setup`) は一般ユーザー権限で動作するため、
このGUIによる候補除外は、一般ユーザーが読み取れる範囲の情報
(`lsblk`・`findmnt`・sysfs) のみを用いた**予備的な絞り込み**に留める。
`wipefs -n` によるブロックデバイスの署名検査など、対象デバイスへの
読み取り権限が一般ユーザーには無い (または保証されない) 検査は、GUI側では
行わず、後述のヘルパーが破壊的操作の直前に実行する。

**GUIの候補一覧に表示されたこと自体は安全性の保証ではない。** 最終的な
安全判定は、必ずヘルパー側の最終検証で行う。GUI側の予備的除外は、
明らかに対象外のデバイスをユーザーに提示しないための利便性目的であり、
セキュリティ境界ではない。

デバイス列挙には `lsblk` の既定の表形式出力を解析せず、列を明示した
`lsblk -b -P -o NAME,KNAME,PATH,MAJ:MIN,TYPE,SIZE,RO,RM,HOTPLUG,MOUNTPOINTS,FSTYPE,PTTYPE,LABEL,PARTLABEL,PKNAME,MODEL,SERIAL,TRAN`
(`--pairs`、または同等の `--json`) を用いる。`PTTYPE`はパーティション
テーブルの有無、`LABEL`/`PARTLABEL`は既存永続領域の予備検出、`TRAN`は
GUI上で対象ディスクを識別する情報として用いる。`--json`を用いる場合も
同じ列を明示して取得し、既定列に依存しない。取得した情報をもとに、次の
いずれかに該当するデバイスは候補から予備的に除外する。

- `PATH`・`TYPE`・`SIZE`・`RO`・`MAJ:MIN`など、判定に必要な基本属性が
  取得できないデバイス。判定不能なものは安全側に倒して候補から外す。
  **一方、パーティションテーブルが存在しないこと自体は除外理由にしない。**
  完全に未使用なディスクではパーティションテーブルが存在しないことが
  正常な条件であり、むしろ初版の許可条件である。逆に、パーティション
  テーブルが存在する (子パーティションを1つ以上持つ、または `lsblk` から
  既知のパーティションテーブル種別が読み取れる) デバイスは候補から除外
  する。
- `TYPE` が `disk` ではないもの。ただし **`TYPE=disk` であること単体を
  「安全」の根拠にはしない。** `loop` / `zram` / device mapper
  (`dm-*` および `/dev/mapper/*`) など、環境によっては `disk` として
  見えうる仮想ブロックデバイスも、デバイス名パターンおよび
  `/sys/block/<name>` 配下の実体 (物理デバイスへの `device` シンボリック
  リンクの有無等) から個別に除外する。
- `RO=1` (読み取り専用) のデバイス。
- `MOUNTPOINTS` が空でない、または子パーティションのいずれかがマウント
  されているデバイス。
- スワップとして使用中のデバイス (`FSTYPE=swap` または `/proc/swaps` に
  現れるもの)。
- `/sys/class/block/<name>/holders/` が空でないデバイス (device mapper /
  LVM / RAID等の下位デバイスとして使用中であることを示す)。
- Live起動元のデバイス。`/run/live/medium` の `SOURCE`
  (`findmnt -no SOURCE /run/live/medium`) を起点に、loopデバイスや
  device mapperを介している場合も `lsblk -s` (`--inverse`) による祖先
  追跡をたどって最終的な親diskを特定し、除外する。overlayの `/`
  (upperdir) のデバイスだけを見て判定しない。BIOS/UEFI問わず同じ
  ロジックを用いる。
- `/home` を現在提供しているデバイス。同様に `findmnt -no SOURCE /home`
  を起点に親diskまでたどって除外する (Live起動元と`/home`のSOURCEが
  異なる場合があるため、両方を個別に追跡する)。
- 「既存の永続領域の検出範囲」節の検査により、システム全体のいずれかの
  ブロックデバイスに既存の永続領域が見つかった場合、新規作成の候補一覧
  そのものを空にする。

候補が0件の場合は「対象デバイスが見つかりません」という日本語メッセージを
表示して終了する (手順を進めない)。

#### 既存の永続領域の検出範囲

既存の永続領域の有無は、**選択しようとしているディスクだけでなく、接続
されている全ブロックデバイスを対象に**検査する。`LABEL=persistence` または
`PARTLABEL=persistence` を持つパーティションが、システム全体のどこかに
1件でも存在した場合、新規作成そのものを拒否する (対象がそのディスク自身か
別のディスクかを問わない)。

これは、複数の`persistence`ラベル領域が存在する状態を作った場合、
live-bootがどちらを永続領域として選択するかが曖昧になることを避けるため
である。この検査はGUI側の予備的除外と、ヘルパー側の最終検証の両方で
行う (GUI側は一般ユーザー権限で読み取れる範囲、ヘルパー側は最終確認として
再実行する)。

#### GUI起動時の実行環境確認

GUIは、デバイス列挙や確認ダイアログの表示に先立ち、次の実行環境を確認する。
いずれか1つでも満たさない場合は、日本語のエラーメッセージを標準エラーへ
出力し、可能であればyadでも表示したうえで、ヘルパーを一切呼び出さずに
0以外の終了コードで終了する。

- `/proc/cmdline` に、部分一致ではなく**独立したパラメータとして**
  `boot=live` が含まれること (空白区切りでトークン化し、トークン全体が
  `boot=live`と一致することを確認する。他のパラメータの一部分に
  `boot=live`という文字列が含まれるだけの誤検知を避けるため)。
- `/run/live/medium` が実際にマウントされていること。
- `XDG_RUNTIME_DIR` が設定されていること。
- `XDG_RUNTIME_DIR` がシンボリックリンクではないこと。
- `XDG_RUNTIME_DIR` が実在するディレクトリであること。
- `XDG_RUNTIME_DIR` の所有者が現在のUIDと一致すること。
- `XDG_RUNTIME_DIR` に現在のユーザーが書き込み可能であること。

これらは`mypocketos-power`の`check_runtime_dir()`と同じ検証内容・同じ
安全側判定方針 (満たさない場合はそのディレクトリへ一切手を加えない) を
踏襲する。

GUIの多重起動防止には、検証済みの`XDG_RUNTIME_DIR`内に`mkdir`で
排他的にロックディレクトリを作成する方式を用いる (例:
`$XDG_RUNTIME_DIR/mypocketos-persistence-setup.lock`)。既に存在する場合は
何もせず終了する。`mypocketos-power`のロック処理と同じ考え方である。

#### 特権昇格方式 (MVPとしてのsudo利用)

- 本READMEの「手動テスト手順」により、**現在のMyPocketOS Liveイメージに
  おいて、Liveユーザー`user`が`sudo parted` / `sudo mkfs.ext4` /
  `sudo mount` / `sudo tee`を追加のパスワード入力なしで実行できることを
  開発用VM上で確認済み**である。初版はこの開発用VM上での確認結果を
  根拠に`sudo`を用いる。live-configのどの設定ファイル・仕組みによって
  NOPASSWDが付与されているかは今回直接確認していないため、その特定の
  仕組みを断定しない。GUIは、`sudo -n`によってその時点での利用可否を
  判定する (利用できない場合はパスワード入力を待たずに失敗させる)。
  **これはMyPocketOSのLive環境固有の初版MVPであり、一般的な (Live環境
  以外の) インストール環境で同様のNOPASSWD sudoが保証されるという意味
  ではない。** 通常インストール環境向けの特権昇格方式は別途検討が必要な
  課題として残す。
- 電源・セッション操作 (`mypocketos-power`) はsystemd-logindとPolicyKitの
  組み合わせで完結しており`sudo`を使用しない。パーティション作成・
  フォーマットについては、udisks2のD-Bus API (`org.freedesktop.UDisks2`)
  や専用のPolicyKitアクション+ヘルパーという方式も将来的な選択肢として
  あり得る。ここでは **「PolicyKitでは完結できない」と断定するのではなく**、
  初版はsudoによるMVPとし、専用policy+helperへの置き換えは今後の検討課題
  とする。
- GUI本体 (`/usr/local/bin/mypocketos-persistence-setup`、一般ユーザー
  権限) は、候補デバイスの列挙・選択・確認 (type-to-confirm)・進捗表示・
  結果通知を担当し、破壊的操作は一切行わない。**候補列挙や予備的除外の
  ためにヘルパーを事前に`sudo`実行することはしない。** `sudo`による
  ヘルパー呼び出しは、ユーザーが確認画面を完了した後の1回だけに限定する。
- 実際のパーティション操作は、専用の特権ヘルパー
  (`/usr/local/libexec/mypocketos-persistence-setup-helper`) に閉じ込め、
  GUI側から次の形で1回だけ呼び出す。

  ```sh
  sudo -n -- /usr/local/libexec/mypocketos-persistence-setup-helper \
      create "$DEVICE" "$MAJ_MIN"
  ```

  `-n` (non-interactive) を指定し、何らかの理由でパスワード入力が必要に
  なった場合は待機せず失敗させる (想定外の昇格プロンプトを表示しない)。
- ヘルパーの引数は `create DEVICE MAJOR:MINOR` の形式に固定する。
  `MAJOR:MINOR` を併せて渡すのは、GUI側がデバイスを列挙してからヘルパーが
  実際に処理するまでの間にデバイス構成が変化する余地 (TOCTOU) を減らす
  ためである。任意の文字列は`eval`しない。
- `MAJOR:MINOR`は、GUI側では列を明示した`lsblk -P`出力の
  `MAJ:MIN`フィールドから取得する。ヘルパー側では、列幅調整による末尾
  空白を含めないよう、`lsblk -dnr -o MAJ:MIN -- "$DEVICE"`で現在値を
  取得する。GUIが渡した値とヘルパーが取得した値を、10進表現の文字列として
  厳密に比較する。GNU `stat`の`%t:%T`等は16進表現になる場合があるため、
  表現形式が異なる値同士を比較する実装にはしない。

#### helper側の最終検証 (root権限、破壊的操作の直前)

ヘルパーは、GUI側の予備的除外の結果を一切信用せず、`parted`/`mkfs`を
実行する直前に、次を含む全条件を自分自身で読み取り専用の手段により
再取得・再検証する。**この最終検証に1つでも失敗した場合、対象デバイスには
一切変更を加えず、処理を拒否して終了する。**

- 「GUI側の予備的な候補除外」に列挙した全条件 (whole diskであること、
  基本属性が取得できること、パーティションテーブルが存在しないこと、
  マウントなし、スワップでないこと、holdersが空であること、Live起動元/
  `/home`のいずれの親diskとも一致しないこと等) の再検証。
- `wipefs -n` (読み取り専用。対象デバイスを一切変更しない) による署名
  検出。パーティションテーブル (GPT/MBR等)・ファイルシステム署名・LUKS
  (`crypto_LUKS`)・LVM (`LVM2_member`)・RAID (`linux_raid_member`) を
  含め、何らかの署名が検出された場合は拒否する。
- 「既存の永続領域の検出範囲」節の検査 (システム全体のブロックデバイスを
  対象とした`LABEL=persistence`/`PARTLABEL=persistence`の再検索) の
  再実行。

GUI起動からヘルパー実行までの間に状態が変化している可能性を前提とした
多層防御であり、GUI側の判定はあくまで予備的なものと位置付ける。

#### helperのロック・後始末

- ヘルパーは処理開始時に、root側の排他ロックを取得する。ロック方式は
  `mypocketos-power`と同じ`mkdir`による排他的作成とする (例:
  `/run/lock/mypocketos-persistence-setup-helper.lock`)。`flock`は用いない。
- `mkdir`によるロックディレクトリの作成に成功したプロセスだけが以降の
  処理を行う。作成に失敗した場合 (既にロックが存在する場合) は、
  **既存のロックディレクトリを削除するなどの回復操作は一切行わず**、
  何もせずに失敗として終了する。
- ロック取得に成功したプロセスは、`trap`により、**自身が作成したロック
  ディレクトリのみ**を終了時に削除する。他プロセスが作成したロックには
  一切干渉しない。
- 一時マウントポイントの作成・マウント・アンマウントも同様に`trap`で
  後始末を行い、途中で失敗した場合でも一時マウントやロックディレクトリが
  残らないようにする。

#### helperの設置・実行条件

- 設置パス: `/usr/local/libexec/mypocketos-persistence-setup-helper`。
- 所有者は`root:root`、パーミッションは`0755`とし、一般ユーザーからの
  書き換えを不能にする。
- POSIX sh (dash) で実装し、`set -eu`を用いる。
- `PATH`は固定した安全な値を明示的に設定するか、`parted`/`mkfs.ext4`/
  `partprobe`/`udevadm`/`wipefs`/`mount`/`umount`等の特権コマンドを
  絶対パスで呼び出す。
- `umask 077`を設定してから一時ファイル・マウントポイントを作成する。
- `eval`は使用しない。
- `DEVICE`引数は、`/dev`以下に実在するブロックデバイスであることを
  確認する。
- `DEVICE`がシンボリックリンクである場合は拒否する。
- `MAJOR:MINOR`引数は、`DEVICE`に対して`lsblk -dnr -o MAJ:MIN --`で改めて
  取得した値と文字列として厳密に一致しない場合は拒否する。
- whole disk以外 (パーティション、loop、device mapper等) は拒否する。

#### helperの終了コード

ヘルパーの終了コードは次のとおり定義する。

| 終了コード | 意味 |
|---|---|
| 0 | 永続領域の作成に成功 |
| 2 | 引数不正、usage |
| 10 | MyPocketOS Live環境ではない、または実行環境の検証失敗 |
| 11 | root側の排他ロックを取得できない |
| 12 | `DEVICE`が不正 (`/dev`以下ではない、存在しない、block deviceではない、シンボリックリンク、whole diskではない等) |
| 13 | GUIから渡された`MAJOR:MINOR`と現在値が一致しない |
| 14 | 対象ディスクが使用中 (mount、swap、holders、Live起動元、`/home`提供元等) |
| 15 | 対象ディスクが未使用ではない (パーティションテーブル、子パーティション、filesystem、LUKS、LVM、RAID等の署名が存在) |
| 16 | システム内に既存の`LABEL=persistence`または`PARTLABEL=persistence`が存在 |
| 20 | GPTパーティションテーブルの作成失敗 |
| 21 | persistenceパーティションの作成・再読込・特定、またはGPT/パーティション作成後の再検証に失敗 |
| 22 | ext4ファイルシステムの作成失敗 |
| 23 | 一時マウントの作成またはmountに失敗 |
| 24 | `persistence.conf`の書き込みまたは内容確認に失敗 |
| 25 | syncまたはumountに失敗 |
| 70 | 必要なコマンドがないなど、内部実行環境の不備 |
| 71 | 上記へ分類できない内部エラー |

- ヘルパーは、上記いずれの終了コードの場合も、日本語の詳細エラーを
  標準エラーへ出力する。
- GUIは終了コードを日本語ダイアログへ対応付けて表示するが、ヘルパーが
  標準エラーへ出力した内容をコマンドとして解釈・実行することはしない
  (あくまで表示用の文字列として扱う)。
- 終了コード10〜16は、いずれも**破壊的操作 (`parted`/`mkfs`) を開始する
  前の拒否**であり、対象ディスクには一切変更を加えない。対象デバイスの
  再検証 (`reverify_device`) は、ロック取得直後・`parted`実行直前の
  計2箇所で行われ、これらはいずれも`parted`実行より前であるため、
  `DEVICE`系の不一致は12、`MAJOR:MINOR`系の不一致は13を返す。
- 終了コード20〜25は、**破壊的操作 (`parted`/`mkfs`) を開始した後の、
  段階別の失敗**であり、対象ディスクが途中状態 (パーティションテーブル
  のみ作成済み、ファイルシステム未作成、`persistence.conf`未作成等) に
  なっている可能性があることを明示する。`parted`によるGPT/パーティション
  作成・`partprobe`・`udevadm settle`・作成したパーティションの特定が
  完了した後、`mkfs.ext4`実行直前にも同じ`reverify_device`を再度
  呼び出すが、この時点では既に対象ディスクへ変更を加えているため、
  `DEVICE`系・`MAJOR:MINOR`系のいずれの不一致も21を返す (12/13は
  返さない)。
- 終了コード70 (必要なコマンドがないなどの内部実行環境の不備) は、
  `check_required_commands`によって検出され、通常は破壊的操作を開始する
  より前に発生する。
- 終了コード71 (上記いずれにも分類できない内部エラー) は、未分類の
  エラーや、後始末 (アンマウント・一時ディレクトリ削除・ロック削除) 自体
  の失敗によっても発生し得るものであり、発生し得る段階 (破壊的操作の前か
  後か) を一律には断定しない。71が返された場合、対象ディスクが変更済み
  かどうかは終了コードだけからは判断できない。
- 終了コード20〜25で失敗した場合、ヘルパーは自動的な再フォーマット・
  再試行・ロールバックを一切行わない。
- `trap`によるアンマウント・一時ディレクトリの削除・自身のロック
  ディレクトリの削除といった後始末に失敗した場合、本来の失敗内容
  (上記いずれかの終了コードに対応するエラー) を隠さず、それに加えて
  後始末自体が失敗した旨も標準エラーへ追加で出力する。
- `SIGINT`・`SIGTERM`・`SIGHUP`を受けて終了した場合の終了コードは
  `128+シグナル番号`とする。シグナルは処理のどの段階でも受信し得るため、
  これらの終了コード (129/130/143) だけでは、対象ディスクが変更前・
  変更後のどちらの状態にあるかを断定しない。GUIはこれらの終了コードを
  検出した場合、「処理が中断されました」という日本語メッセージを表示
  する。
- GUIは、上記のいずれにも当てはまらない未知の終了コードを成功
  (終了コード0) として扱わない。そのような終了コードは「未分類の
  エラー」として表示する。

#### 作成したパーティションの特定方法

- 作成したパーティションのデバイス名は、対象diskのデバイス名に単純に
  `"1"`を連結して求めない (`/dev/nvme0n1`や`/dev/mmcblk0`等では
  `p1`が必要になるなど、命名規則がデバイス種別ごとに異なるため)。
- `partprobe`・`udevadm settle`の後、`lsblk`で対象diskの子パーティション
  (親子関係、`PKNAME`が対象diskと一致するもの) を再列挙し、新規作成した
  1個のパーティションを特定する。

#### GUI操作フロー

`mypocketos-power`と同じ体裁 (yad、`--center --on-top --skip-taskbar`) で
以下を行う。

1. 候補デバイスの一覧を表示する。表示する識別情報は、パス・サイズ・
   モデル名に加え、取得できる場合はシリアル番号 (`SERIAL`) と接続方式
   (`TRAN`) も含める。これらの値が空の場合は推測で補完せず「不明」と
   表示する。パス・サイズ等、対象を安全に区別するために必要な識別情報が
   不足しているデバイスは、「GUI側の予備的な候補除外」の方針に従い
   候補から除外する。
2. 選択後、対象デバイスパスとサイズを明示したうえで「この操作でデバイスの
   全内容が失われます」という警告を表示する。取り消し可能な操作ではない
   ため、確認文字列には対象デバイス名を含める (例: `ERASE /dev/vda` と
   入力させる) type-to-confirm形式とし、汎用的な「はい」等の入力や
   誤クリックでは通過しないようにする。**この確認画面までは、ユーザーは
   いつでもキャンセルできる。**
3. 確認後、`sudo -n --`経由でヘルパーを起動する。ヘルパーは
   `helper | yad --progress`のような単純なパイプでは実行しない
   (パイプ経由では正確な終了コードを失いやすいため)。GUI側でヘルパーを
   バックグラウンド実行してPIDを保持し、進捗ダイアログ (yadの
   pulsate表示等) を別途表示しながら`wait`で当該PIDの終了を待ち、正確な
   終了コードを取得する。
4. ヘルパーは次を順に実行する。
   `parted mklabel gpt` → `mkpart persistence ext4 1MiB 100%` →
   `partprobe` → `udevadm settle` → (作成したパーティションの特定) →
   `mkfs.ext4 -L persistence` → 一時マウント →
   `persistence.conf`書き込み (`/home`の1行) → `sync` → アンマウント。
   各コマンドの終了コードを確認し、失敗した時点で以降の手順を中断する。
5. **`parted`によるヘルパーの処理が開始された後は、GUIから処理を
   キャンセルしない。** 進捗ダイアログのウィンドウを閉じても、GUIは
   ヘルパーを強制終了させない。ダイアログの見た目上の状態に関わらず、
   GUIはヘルパーのPIDに対する`wait`を継続し、実際の終了状態を回収する。
6. 成功・失敗を、`wait`で取得した終了コードに基づき日本語メッセージで
   通知する。失敗時は、どの手順で失敗したかが分かるメッセージにする。
   永続化を有効にするには次回起動時に「MyPocketOS Live (Persistence)」を
   選ぶ必要がある旨も併せて案内する。

#### メニュー統合

jgmenuの`append.csv`が、tint2パネルの常駐jgmenuとデスクトップ背景右クリック
(`mypocketos-jgmenu-at-pointer`) の両方に共通する実体であり、ここへGUI本体
(`mypocketos-persistence-setup`) を起動する項目を実装している。表示名は
「永続領域を作成」である。特権ヘルパーはメニューやショートカットから直接
実行できるようにはしていない。「電源・セッション」用の区切り線 (`^sep()`)
より前に、「電源・セッション」とは独立した項目として配置している
(パーティション操作は電源・セッションとは性質が異なるため)。

`menu.xml`にも同名の項目をファイルとして残しているが、デスクトップ背景の
右クリックは現在jgmenuを表示するため、この導線では使用していない。

#### 初版のスコープ外

- 部分的な空き領域を利用した永続化 (対象はwhole diskのみ)。
- 既存永続領域の上書き・削除・サイズ変更・再フォーマット。
- 複数の永続領域の作成・切り替え。
- LUKSによる暗号化。
- `/home`以外 (`/`全体等) の永続化。
- 追加インストールしたアプリ本体・パッケージ一覧・APTキャッシュの永続化。

#### 動作確認

既存の開発用VM `mypocketos-test` / `mypocketos-uefi-test` の`/dev/vda`には、
「Live永続化基盤」の「動作確認」で既に検証済みの永続化パーティションと
テストデータが存在するため、**このディスクを空ディスクとして再利用・
再フォーマットするテストは行っていない。**

さらに、既存の永続領域検出はシステム全体の`LABEL=persistence`/
`PARTLABEL=persistence`を対象とする設計であるため (「既存の永続領域の
検出範囲」節参照)、既存の`mypocketos-test`または`mypocketos-uefi-test`に
未使用の空ディスクを追加接続しただけの構成では新規作成テストを実施
できない (接続済みのpersistenceパーティションが検出され、新規作成が
拒否されるため)。

そのため、GUIによる新規作成テストには、既存の永続化ディスクが一切
接続されていない、新規の専用・使い捨てテストVM
`mypocketos-persistence-gui-test` (BIOS版)、および
`mypocketos-persistence-gui-uefi-test` (UEFI版、OVMF・専用NVRAM使用、
TPMは接続なし) を用意して使用した。いずれのVMにも次のみを接続した。

- `MyPocketOS-dev.iso` (共有ISO、読み取りのみ)。
- 内容を失ってよいことを明示的に確認した、新規の空16GiB qcow2ディスク。

既存の`mypocketos-test`・`mypocketos-uefi-test`、およびそれらの
永続化ディスクは、この新規作成テストのために変更・再フォーマット・
取り外しのいずれも行っていない。

**ISO再ビルドとSquashFS内容の確認 (2026-08-26)**

- この変更 (GUI・helper・メニュー統合) を含むISOを`./scripts/build.sh`で
  再ビルドし、ビルドが成功することを確認した。
- 再ビルドしたISOのSquashFS内に含まれるGUI本体・helperが、リポジトリの
  ソースとSHA-256で一致することを確認した。

**実測中に検出・修正した事項**

- `findmnt`でraw (`-r`) とpairs (`-P`) を併用していたため、`/home`情報の
  取得に失敗し、GUI側の候補一覧が常に0件になっていた。GUI・helper双方の
  `/home`向け`findmnt`呼び出しから`-r`を削除し、pairs出力 (`-P`) のみを
  使用するよう修正した (raw/pairsは併用できない出力形式であるため)。
- helperの`lsblk -dn -o MAJ:MIN`が値の末尾に空白を含む出力を返すことが
  あり、GUIから渡された値との厳密な文字列比較に失敗してexit 13に
  なっていた。`lsblk -dnr -o MAJ:MIN`(`-r`=raw、列幅調整なし) へ修正した。
- 上記2件の修正を含むISOを再ビルドした後、以下の実作成テストに
  成功した。

**通常Live環境でのGUI起動・候補列挙**

- 通常Live (`nopersistence`) 起動後、メニューに追加された
  「永続領域を作成」からGUIを起動できることを確認した。
- 候補一覧には、接続された空のwhole disk `/dev/vda`のみが表示され、
  CD-ROM (`sr0`)・Live起動元デバイス・overlayの`/home`・zram swapは
  いずれも候補にならないことを確認した。

**キャンセル・確認文字列不一致の安全性**

- 候補選択後にキャンセルした場合、`/dev/vda`の内容は無変更のままであり、
  GUIロック・一時ファイルも残らないことを確認した。
- 誤った確認文字列 (対象と異なるデバイス名を含む`ERASE /dev/vdb`) を
  入力した場合は拒否され、対象ディスクは無変更のままであることを
  確認した。

**正しい確認文字列での新規作成**

- 正しい確認文字列 (`ERASE /dev/vda`) を入力し、GPTパーティション
  テーブルと`/dev/vda1`が作成されることを確認した。
- `/dev/vda1`はext4でフォーマットされ、LABEL・PARTLABELともに
  `persistence`であることを確認した。
- `persistence.conf`は所有者`root:root`、パーミッション`0600`、
  サイズ6バイトで、内容が`/home`+改行1つであることを確認した。
- `e2fsck -fn`でエラーが検出されないことを確認した。
- 処理終了後、helperのロック・GUIのロック・一時作業ディレクトリの
  いずれも残っていないことを確認した。

**Persistence起動での永続化確認**

- 作成したpersistence領域を用いてPersistenceモードで起動した場合、
  カーネルコマンドラインに`persistence`が1件、`nopersistence`が0件で
  あることを確認した。
- `/home`が`/dev/vda1[/home]`としてext4でread-writeマウントされる
  ことを確認した。
- `/home/user`が`user:user`所有、パーミッション`0700`で作成される
  ことを確認した。
- 作成したテストファイルが、Persistenceモードで再起動した後も内容・
  所有者・パーミッション (`0600`) を維持していることを確認した。
- 通常Liveに切り替えるとテストファイルが表示されず、`/dev/vda1`も
  マウントされないことを確認した。
- 再びPersistenceへ戻すと、同じテストファイルが再表示されることを
  確認した。
- 各再起動でカーネルの`boot_id`が変化していることを確認した。

**専用UEFI版使い捨てVMでの新規作成・永続化確認 (2026-08-26)**

専用のUEFI版使い捨てテストVM `mypocketos-persistence-gui-uefi-test`
(`firmware=efi`、OVMF・専用NVRAM使用、TPMは接続なし) 上で、BIOS版と
同様の手順により次を確認した。

- ゲスト内で`/sys/firmware/efi`の存在を確認し、UEFI起動であることを
  確認した。Secure Bootの状態は、Live環境に`mokutil`が含まれていない
  ため確認していない。
- 通常Live (`nopersistence`) 起動後、メニューに追加された「永続領域を
  作成」からGUIを起動し、候補一覧には接続された空のwhole disk
  `/dev/vda`のみが表示されることを確認した。
- GUIから正しい確認文字列を入力し、GPTパーティションテーブルと
  `/dev/vda1`が作成されることを確認した。
- `/dev/vda1`はext4でフォーマットされ、LABEL・PARTLABELともに
  `persistence`であることを確認した。
- `persistence.conf`は所有者`root:root`、パーミッション`0600`、
  サイズ6バイトで、内容が`/home`+改行1つであることを確認した。
- `e2fsck -fn`でエラーが検出されないことを確認した。
- 処理終了後、GUI・helperのロックおよび一時作業領域のいずれも
  残っていないことを確認した。
- 作成した領域を用いてUEFI Persistenceモードで起動した場合、
  カーネルコマンドラインに`persistence`が1件、`nopersistence`が0件で
  あることを確認した。
- `/home`が`/dev/vda1[/home]`としてext4でread-writeマウントされる
  ことを確認した。
- `/home/user`が`user:user`所有、パーミッション`0700`で作成される
  ことを確認した。
- 作成したテストファイルが、UEFI Persistenceモードで再起動した後も
  内容・所有者・パーミッション (`0600`) を維持していることを確認した。
- UEFI通常Liveに切り替えるとテストファイルが表示されず、`/dev/vda1`も
  マウントされないことを確認した。
- 各再起動でカーネルの`boot_id`が変化していることを確認した。
- 作成したパーティションのUUIDは`f99149e3-c88e-4f4b-a7b6-940f39c7e257`
  であった。

**既存persistence領域に対するGUI/helperの実機拒否確認 (2026-08-26)**

上記のBIOS版使い捨てテストVM `mypocketos-persistence-gui-test`上に、
新規作成テストにより既に作成済みのpersistence領域が存在する状態を
用いて、次を確認した。

- 通常LiveでGUIを起動すると、システム内の既存`LABEL=persistence`が
  検出され、候補一覧が0件になることを確認した。
- GUI終了後、プロセス・GUIロック・一時作業領域のいずれも残っていない
  ことを確認した。
- ヘルパーを、対象ディスク`/dev/vda`と正しい`MAJOR:MINOR`を指定して
  (GUI経由ではなく) 直接呼び出した場合、システム内の既存
  `LABEL=persistence`を検出し、exit 16で拒否されることを確認した。
- helper呼び出しの実行前後で、対象パーティションのUUID
  (`ca12dd1f-1738-4776-8d26-c1eda925c939`) が一致し、LABEL・PARTLABEL・
  ext4署名も維持されていることを確認した。
- helperのロックも残っていないことを確認した。
- 対象ディスクの内容は、上記いずれの試行によっても変更されていない
  ことを確認した。

上記のとおり、既存の`mypocketos-test`と`mypocketos-uefi-test`、および
両VMの永続化ディスクは、これらのGUI新規作成テスト・既存persistence
拒否確認のために変更・再フォーマット・取り外しのいずれも行っていない。

**この動作確認で確認していない事項**

- 署名・mount・swap・holders等、各拒否条件を個別の実ブロックデバイスを
  追加して確認する実機試験 (これらは非破壊モックテストでは確認済み)。
- 専用UEFI VMでのSecure Boot有効状態 (`mokutil`未搭載のため未確認。
  UEFI起動自体は確認済み)。
- LUKSによる暗号化、部分的な空き領域を利用した永続化、既存永続領域の
  変更、複数の永続領域の作成・切り替え、`/home`以外の永続化、追加
  インストールしたアプリ本体の永続化 (いずれも「初版のスコープ外」節
  参照)。

## USB persistence IMG生成 (試作)

`scripts/build-usb-persistence-image.sh` は、通常のedition別ISO
(`mypocketos-base-amd64.hybrid.iso` / `mypocketos-standard-amd64.hybrid.iso`)
とは**別成果物**として、単一のGPT/MBR/APM/El Toritoハイブリッド構造に
persistence用の第3パーティション (ext4, LABEL=`persistence`,
`persistence.conf`の内容は`/home`) をあらかじめ追加したIMGファイルを、
単一のxorriso生成処理で作る試作スクリプトである。「Live永続化基盤」
「GUIによる永続領域作成」節が前提とする、Live起動中にGUI/helperで
外部の別ディスクへ永続領域を作成する経路とは別に、**1本のUSBメモリだけで
起動と永続化を両立させる**ことを目的とする。

### 使い方

```sh
scripts/build-usb-persistence-image.sh \
    --iso mypocketos-standard-amd64.hybrid.iso \
    --binary-dir binary \
    --persistence-size 2G \
    --output MyPocketOS-usb-persistence.img
```

4引数はすべて必須であり、既定値は設けていない。`--persistence-size`は
`256M`/`2G`のような形式のみを許可し (K単位・小数・大文字M/G以外の単位は
不可)、**最小256M**とする。出力ファイルサイズの公開既定値はまだ決めて
いない。`--output`は既存パス (symlink含む) を一切上書きしない。

### 出力の公開方式 (競合安全性)

最終出力は、`--output`と同じディレクトリ内に作る**private work
directory** (`mktemp -d`、作成直後にmode 0700を検証) の中へ固定名で
生成し、生成後自動検証がすべて成功した場合にのみ、同一ファイルシステム
内の**hard link** (`ln`、`-f`なし) で公開する。`ln`は`--output`が既に
存在すれば失敗する (exit 60) ため、TOCTOU的な上書きが構造上起こらない。
公開成功後、work directory内の一時コピーは削除する (hard linkのため
公開済みファイルのデータには影響しない)。`mv`/`mv -f`/`mv -n`は最終公開に
使わない。

hard link方式であることから、**`--output`の親ファイルシステムは通常
ファイルのhard linkをサポートしている必要がある**(work directoryも同じ
親ディレクトリ内に作るため、同一ファイルシステム内hard linkとなる)。
FAT系等、hard linkをサポートしないファイルシステムを`--output`の親に
指定した場合、生成後自動検証まではすべて成功したうえで、**最終公開の
`ln`だけがexit 60で失敗する**(`--output`が既に存在する場合と同じ終了
コードを共有するが、原因はhard link非対応であり上書きではない)。
いずれの場合も、既存出力を上書きしない安全設計 (`ln`に`-f`を使わない)
は維持される。

### 空き容量検査

xorriso/mke2fs等の実行前に、`--output`の親ディレクトリのファイル
システムについて、次の合計が空き容量以内であることを検査する
(超過時はexit 19で拒否する)。

```
ISOサイズ + persistenceサイズ×3 (生成途中の最終IMG分・persistence.img分・
検証用抽出分) + binary/live/filesystem.squashfsのサイズ (入力整合性検査での
一時抽出分) + 安全余白 (16MiB)
```

この判定は、加算した合計を上限と比較するのではなく、上限から毎回減算
しながら判定する (`fits_within`)。極端に大きい値の組み合わせによる
整数演算のオーバーフローで、上限検査そのものが回避されることを防ぐ
ためである。合計サイズ上限 (8,000,000,000 bytes) の検査も同じ関数で
行う。

### 制限事項

- **8GB未満の保守的な上限**: 入力ISOサイズ + `--persistence-size` +
  安全余白 (8MiB) の合計が **8,000,000,000 bytes を超える指定は、
  xorriso実行前に拒否**する (exit 18)。これは現時点の暫定的な保守値
  であり、将来的な緩和を妨げるものではない。
- **現状は再現可能ビルドではない**: 生成されるIMGのGPT disk
  GUID・各パーティションGUID・ext4 UUID等は実行のたびに変化する
  (xorrisoが実行時刻や乱数を基に生成するため)。同一入力から常に
  バイト同一の出力を得られることは、現時点では保証していない。
- 入力ISOと`binary/`ソースツリーの整合性は、`isolinux/isolinux.bin`・
  `boot/grub/efi.img`・`live/filesystem.squashfs`の3ファイルについてのみ
  検証する。`isolinux.bin`は`-boot-info-table`によりbytes 8-63が
  意図的に書き換えられるため、この範囲を除いた完全一致を条件とする。

### 動作確認の範囲

実装過程で、実ISO・実`binary/`ツリーに対して本スクリプトを実際に実行し、
以下を確認済みである。

- xorriso単一生成が成功すること (exit 0)。
- 生成物のMBR partition 1 (status/type/start)・partition 2
  (status/type/start/blocksが入力ISOと完全一致)・partition 3
  (status/type/start/blocks、partition 1に連続・非重複)、GPT entry 1が
  MBR partition 1と整合、GPT entry 2 (start/size/type GUID/nameが入力ISO
  と完全一致)・entry 3 (start/size/type GUID/name)、GPT backup headerが
  出力ファイル末尾LBAにあり出力ファイルサイズが512の倍数であること、
  El Toritoが入力ISOと完全一致すること、ISO9660が読み取れることを確認。
- partition 3を抽出し、`persistence.img`とのcmp完全一致・`e2fsck -fn`の
  異常なし・`persistence.conf`のUID/GID/mode/size/内容が想定どおりで
  あることを、いずれも実xorriso・実e2fsprogsで確認済み。
- 入力ISO・`binary/`主要3ファイルが実行前後で変化しないこと。
- 出力先が既に存在する場合に上書きせず拒否すること (exit 13)、
  private work directoryが成功後に削除されること。
- `tests/usb-persistence-image/`のテスト (直接実行29シナリオ+モック59
  シナリオ=計88シナリオ・94アサーション、モック側は実xorriso/mke2fs/
  e2fsck/debugfsを呼ばない) で、各wrapper/mockのsandbox外パス拒否、
  生成後自動検証の代表的な失敗経路 (MBR/GPT欠落・重複、entry不一致、
  backup header不一致、El Torito不一致、ISO9660欠落、partition 3不一致、
  実行中の入力変化検出等)、公開直前競合 (exit 60、競合相手を上書き
  しないこと含む)、INT/TERM/HUPの各シグナルで確実に非0終了することを
  確認済み。

**プロトタイプIMGによるVM実地検証 (正式スクリプト完成前)**

以下は、正式スクリプト (`scripts/build-usb-persistence-image.sh`)
完成前に、同等の単一xorriso生成方式 (`-append_partition 3`を用いた
手動コマンド列) で作成した**試作IMG**を対象に、開発用QEMU/KVM VM上で
実施した検証結果である。**正式スクリプトが生成した最終成果物そのものを
VM起動して検証したものではない**ことに注意 (両者は同一の生成方式に
基づくが、別の実行・別の生成物である)。

- BIOS VMで、通常Live・Persistenceの両方の起動に成功した。
- BIOS Persistenceでは、`/home`が`/dev/vda3[/home]`からマウントされる
  ことを確認した。
- BIOS Persistenceで作成したファイルは、再起動後も保持されることを
  確認した。
- BIOS通常Live (Persistenceでない) では、永続化したファイルが表示され
  ず、partition 3がマウントされないことを確認した。
- UEFI VMで起動に成功した。
- UEFI環境でSecure Boot関連のEFI変数の値が1であることを確認した。
- UEFI Persistenceでは、`/home`が`/dev/vda3[/home]`からマウントされる
  ことを確認した。
- UEFI Secure Boot環境で、再起動後もファイルが保持されることを確認した。
- UEFI通常Live (Persistenceでない) では、永続化したファイルが表示され
  ず、partition 3がマウントされないことを確認した。

**次の項目は未確認である。**

- 現在の正式スクリプトが生成した成果物そのものについての、上記と同様の
  VM実地検証 (未実施)。
- 実USBメモリへの書き込み。
- 実機BIOS/UEFI起動。

上記「Live永続化基盤」節で行ったVM実地検証 (GUI/helperによる外部ディスク
永続化) とは対象が異なり、混同しないこと。

### Standard版アプリ搭載イメージでのUSB persistence検証 (2026-08-29)

Standard版パッケージ (Firefox ESR・LibreOffice・Drawing) を含むISOから、
`--persistence-size 2G` を指定してUSB persistence IMGを生成し、開発用
QEMU/KVM VM上で次を確認しました。

- IMGサイズ: 3,930,710,016 bytes (persistence領域2GiB)。
- BIOS起動に成功。
- UEFI Secure Boot環境での起動に成功。
- LibreOffice Writerで作成した文書が、再起動後もSHA-256完全一致で
  保持されることを確認。
- 通常Live (`nopersistence`) では永続化したファイルが表示されず、
  persistenceパーティションもマウントされないことを確認。

上記の検証結果を踏まえ、この構成 (Standard版 + USB persistence 2GiB) の
配布媒体には、**8GB以上のUSBメモリを推奨**します。
