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
今後生成されません)。出力ISOおよび live-build の作業生成物 (`binary/`
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

以下は、上記の初回構成時点では未実装でした。その後の実装状況は
以下のとおりです (最新の詳細は本README内の該当節、または
`mypocketos-specification-2026-08-31.md`を参照)。

- 永続化 (persistence): 実装済み。「Live永続化基盤」節を参照
- Calamaresによるインストーラ: 未実装のまま (Phase 3、仕様書18節参照)
- 一般アプリ一式: Standard版の追加アプリ (「Standard版の追加アプリ」節)、
  および`flatpak --user`によるユーザー追加アプリ (「ユーザーによる追加
  アプリ導入 (Flatpak)」節) で対応済み
- 独自テーマ・ブランディング: 実装済み。「アイコンテーマ
  (MyPocketOS-Fluent-yellow)」節、およびISO/USBメディア名のMyPocketOS化
  (`auto/config`の`--iso-volume`等) を参照
- 外部リポジトリからテーマ等を取得するフック: 未実装のまま (アイコン
  テーマはオフライン同梱のtar.gzアーカイブ+検証hookで展開する設計を
  採用しており、外部リポジトリからの取得は意図的に行っていません)

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

### ユーザーによる追加アプリ導入 (Flatpak)

Base版・Standard版のいずれにも`flatpak`コマンドを標準搭載しています
(`config/package-lists.d/mypocketos-common.list.chroot`)。あらかじめ用意
した以外のアプリをユーザーが後から追加したい場合は、`flatpak --user`での
導入を正式な方法として推奨します。

- Flathub等のremoteは、MyPocketOS側では自動登録していません。必要な場合は
  ユーザー自身で`flatpak --user remote-add`を実行してください(例:
  `flatpak --user remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo`)。
- gnome-software等のGUIソフトウェアセンターは含めていません。
- `flatpak --user`でインストールしたアプリ・ランタイム・remote設定・
  ユーザーデータ(`~/.var/app/`)は、いずれも`/home`配下に保存されるため、
  既存のPersistence(`/home`)機能でそのまま永続化されます。**実機E2Eで
  確認済み**(下記「Flatpak Persistence 実機/VM E2E確認」節を参照)。
- APTで追加したパッケージ本体そのものの永続化は、初回版では対象外です
  (Live起動のたびにリセットされます)。

#### Flatpak Persistence 実機/VM E2E確認

VM・実機いずれのNormal Live環境でも`flatpak --version`(Flatpak 1.16.6)・
`flatpak --user remotes`(空)を確認し、Flathub等のremoteが自動登録されて
いないことを確認した。

実機のMode B Persistence環境で、次を確認した。

- Wi-Fi接続後、
  `flatpak --user remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo`
  でFlathubをユーザーremoteとして登録できること。
- `flatpak --user install --assumeyes flathub io.mpv.Mpv`でmpvを
  インストールでき、jgmenuに表示され、GUIから起動できること。
- Persistenceモードで再起動した後もmpvが起動でき、`flatpak --user list`
  でmpv本体とランタイムが確認できること。
- Normal Liveへ切り替えると、`flatpak --user list`が空になり、
  `~/.local/share/flatpak`・`~/.var/app`がいずれも存在しないこと
  (Persistenceへの非依存が保たれていることの確認)。
- 再度Persistenceへ戻すと、mpv本体・ランタイムが再表示され、起動できる
  こと。

以上により、`flatpak --user`でインストールしたアプリ本体・ランタイム・
remote設定・アプリ設定/データが、いずれも`/home` Persistenceで保持
されることを実機E2Eで確認済みである。

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

**注**: 上記はFlatpak標準搭載 (前述「ユーザーによる追加アプリ導入
(Flatpak)」節参照) 追加前の実測値であり、現在は`flatpak`本体および
その依存パッケージ (bubblewrap・xdg-desktop-portal等) の分だけ実際の
ISOサイズが増加しています。再測定は今後別途実施予定です。

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

### Conkyシステム情報パネル (ネットワーク表示・Window Snap表示追加, 2026-09-10)

設定ファイル: `/home/<user>/.config/conky/conky.conf`
(`config/includes.chroot/etc/skel/.config/conky/conky.conf`としてスケルトン
から配置。Base/Standard共通)。

既存のシステム情報表示(MyPocketOS見出し・ホスト名・カーネル・稼働時間・
起動モード・CPU使用率とバー・メモリとバー・ルートFSとバー・
ショートカット5項目)は維持したうえで、以下を追加した。

- **ネットワーク使用状況(Down/Up)**: `${gw_iface}`でdefault route
  interfaceを取得し、`${downspeed ${gw_iface}}`/`${upspeed ${gw_iface}}`
  でその速度を表示する。特定インターフェース名(`wlan0`/`eth0`等)は
  ハードコードしていない。未接続時は「ネットワーク: 未接続」を表示する。
- **NetworkManager dispatcherによるConky再起動**:
  Conkyがネットワーク接続確立前に起動していると、Conkyプロセス内部の
  ネットワークデバイス状態が更新されず、後から接続してもDown/Upが
  0Bのまま変化しない問題があったため、
  `config/includes.chroot/etc/NetworkManager/dispatcher.d/01-mypocketos-conky-restart`
  で、接続確立イベント(`action=up`)のたびに既存Conkyプロセスを終了して
  再起動する。再起動時は元プロセスの`/proc/<pid>/environ`から
  `DISPLAY`・`XAUTHORITY`・`LANG`・`XDG_RUNTIME_DIR`等を引き継ぎ、
  日本語表示・起動モード表示が再起動後も崩れないようにしている。
- **Window Snapショートカット表示**: 既存ショートカット5項目の後に
  区切り線・見出し付きで、`Super+Left`(左半分)・`Super+Right`(右半分)・
  `Super+Up`(最大化)・`Super+Down`(最大化解除)を追加した。

表示レイアウトは、ウィンドウ全体を`minimum_width`/`maximum_width`とも
`262`(px)の固定幅とし、値の桁数変化でウィンドウが伸縮しないようにして
いる。ホスト名・カーネル・稼働時間・起動モード・CPU使用率・メモリ・
ルートFSのシステム情報7行は1行表示(ラベル+`${alignr}`右寄せ値)、
ネットワークのみDown/Upを含め縦方向3行で表示する。日本語表示・
起動モード(`Normal Live`等)表示は従来どおり正常に機能する。

`tests/desktop-polish/test_conky_display.sh`・
`tests/desktop-polish/test_conky_network_restart.sh`で静的/機能テスト
済み(実Xorg・実Conky・実NetworkManagerは使用しない)。

### タッチパッド既定動作 (2026-09-06)

ノートPCで起動した直後から、一般的なタッチパッド操作を機種やタッチパッド
製品名に依存せず使えるようにするため、libinputドライバ向けのXorg
`InputClass`設定を追加しています。

- 設定ファイル: `/etc/X11/xorg.conf.d/51-mypocketos-touchpad.conf`
  (`config/includes.chroot/etc/X11/xorg.conf.d/51-mypocketos-touchpad.conf`
  としてリポジトリに収録)。
- 標準動作:
  - 1本指タップ = 左クリック
  - 2本指タップ = 右クリック
  - 3本指タップ = libinput既定の`TappingButtonMap`(`lrm`)どおり中クリック
  - 2本指スクロール
  - タップ&ドラッグ(1本指タップ後そのまま指を置き続けるとドラッグ)
  - 物理クリック(ボタン)は従来どおり使用可能
- 設定したlibinputオプション: `Tapping "on"`・`TappingButtonMap "lrm"`・
  `TappingDrag "on"`・`ScrollMethod "twofinger"`・`NaturalScrolling "on"`
  (2本指スクロールの方向。詳細は下記「タッチパッド 2本指スクロール方向
  (2026-09-10)」節参照)。
- `InputClass`セクションは`MatchIsTouchpad "on"`(デバイス名・vendor ID
  等のハードコードなし)でlibinputがタッチパッドと分類したデバイスにのみ
  適用され、マウス・トラックポイント(pointing stick)・タッチスクリーン
  には影響しません。
- 既存の`xserver-xorg-input-all`パッケージ(`xserver-xorg-input-libinput`
  への依存元、既存の共通パッケージリストに元々含まれている)をそのまま
  利用しており、新規パッケージの追加は不要です。
- xinputコマンドをOpenbox autostart等でログイン後に大量実行する方式では
  なく、Xorg起動時に読み込まれる標準の`xorg.conf.d`スニペットのみで実現
  しています。Openbox autostart (`~/.config/openbox/autostart`) 側の変更
  はありません。
- ファイル名は`51-`とし、`xserver-xorg-input-libinput`パッケージが提供する
  既定の`/usr/share/X11/xorg.conf.d/40-libinput.conf`(`40-`)より後に
  読み込まれるようにしています(Xorgは`xorg.conf.d`配下をファイル名順に
  読み込み、後から読み込まれた`InputClass`の`Option`が同じデバイスに対して
  優先されます)。
- `tests/desktop-polish/test_touchpad.sh`で、上記オプションの値・
  タッチパッド限定であること・デバイス名やvendor ID等のハードコードが
  無いこと・他デバイスクラス(マウス等)へ誤適用されていないことを静的に
  確認しています。

**実機E2E検証 (2026-09-06)**: branch `feat/touchpad-defaults`
(commit `23c946519b91e141de4bac46e7ef4e7b01a1ccc8`) のStandard版ISO
(`mypocketos-standard-amd64.hybrid.iso`、SHA-256
`07617844477ef74841d201392904b93f2ca60778d8a2e0a0bd5ac9ced704d8c9`、
Volume ID `MyPocketOS 20260906-21:04`) を用いて、実機で1本指タップ
(左クリック)・2本指タップ(右クリック)・2本指スクロール・タップ&ドラッグ・
物理クリックがいずれも正常に動作することを確認しました。`/proc/bus/input/devices`
では、対象タッチパッドが`ETPS/2 Elantech Touchpad`・`ELAN0902:00 04F3:3051
Touchpad`としてカーネルに認識されていることを確認しました。また、USBマウス
接続時の左クリック・右クリック・ホイールスクロールが正常であり、
`MatchIsTouchpad "on"`による明らかなマウス側の副作用は確認されませんでした。
一方、トラックポイント搭載機・Bluetoothマウスでの確認、`xinput
list-props`によるlibinputプロパティの直接確認(`xinput`コマンド自体が
MyPocketOSに未搭載のため今回未実施)は、いずれも未確認のまま残っています
(詳細は「タッチパッド 実機E2E検証 (2026-09-06)」節を参照)。

### タッチパッド 実機E2E検証 (2026-09-06)

branch `feat/touchpad-defaults` (commit
`23c946519b91e141de4bac46e7ef4e7b01a1ccc8`) のStandard版ISOを用いて、
上記「タッチパッド既定動作」の実機E2Eを実施した。

**検証対象ISO**

- file: `mypocketos-standard-amd64.hybrid.iso`
- size: 1,793,409,024 bytes
- SHA-256: `07617844477ef74841d201392904b93f2ca60778d8a2e0a0bd5ac9ced704d8c9`
- Volume ID: `MyPocketOS 20260906-21:04`

**実機確認済み項目**

- 1本指タップ → 左クリック: 正常。
- 2本指タップ → 右クリック: 正常。
- 2本指スクロール: 正常。
- タップ&ドラッグ: 正常。
- 物理クリック: 正常。
- `/proc/bus/input/devices`で、対象タッチパッドが`ETPS/2 Elantech
  Touchpad`・`ELAN0902:00 04F3:3051 Touchpad`としていずれも
  input deviceとしてカーネルに認識されていることを確認した。
- USBマウスを接続し、左クリック・右クリック・ホイールスクロールが
  正常であることを確認した。`MatchIsTouchpad "on"`による明らかな
  マウス側の副作用は確認されなかった。

**この検証で確認していない事項 / 注意**

- `xinput`コマンド自体がMyPocketOSに含まれておらず、実機での実行が
  できなかった。今回の設定実装は`xinput`依存ではない(Xorg起動時に
  読み込まれる`xorg.conf.d`スニペットのみで完結する)ため、これは
  今回の実装の不具合ではない。評価は実機での操作確認と
  `/proc/bus/input/devices`によるカーネル側認識確認によって行った。
  `xinput list-props`によるlibinputプロパティ(`libinput Tapping
  Enabled`等)の直接確認は未実施のまま残っている。
- トラックポイント(pointing stick)搭載機での確認は今回実施していない。

### タッチパッド 2本指スクロール方向 (2026-09-10)

branch `feat/touchpad-natural-scrolling`で、`51-mypocketos-touchpad.conf`
に`NaturalScrolling "on"`を追加した。

**背景**: PR #41 (branch `feat/touchpad-defaults`) の実機確認時点では
`NaturalScrolling`は未設定であり、libinputドライバの既定(無効)が
適用されていた。この状態では、指を下へ動かすとスクロールバーを下げる
のと同じ向き、すなわち表示内容が上へ動く「従来型」スクロールになる。
ユーザーからのフィードバックで、指を下へ動かしたときに表示内容も下へ
動く(タッチスクリーンの操作感に近い)挙動を希望する旨があったため、
`man 4 libinput`(実機`xserver-xorg-input-libinput`パッケージ付属の
man page)の`Option "NaturalScrolling" "bool"`(`Enables or disables
natural scrolling behavior.`)の定義を確認したうえで、`NaturalScrolling
"on"`を明示的に設定した。

`MatchIsTouchpad "on"`セクション内のみへの適用のため、USBマウスの
ホイール方向には影響しない設計(既存のマウス副作用なしの設計を維持)。

`tests/desktop-polish/test_touchpad.sh`に`NaturalScrolling "on"`の
アサーションを追加し、静的/モック確認済み。実機での2本指スクロール
方向の確認、およびUSBマウスホイール方向に副作用がないことの確認は、
本ドキュメント作成時点では**未実施**(実機検証待ち)。
- Bluetoothマウスでの確認は今回実施していない。
- 実機テスト中、一度動作が重くなった後の再起動時に、systemd-journaldの
  `Failed to send WATCHDOG=1 notification message: Transport endpoint
  is not connected`というメッセージが繰り返し表示され、再起動が停止する
  事象が発生した。**この事象とタッチパッド設定との因果関係は今回
  確認しておらず、本PRの不具合として断定しない。** 別件の調査項目として
  記録するにとどめる。

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

### 正式なVM運用構成

MyPocketOSの開発では、以下の2台を恒久的なVMとして維持します。
Persistence専用・USB persistence IMG検証専用といった追加の恒久VMは
作らない方針です (詳細は後述)。

| VM名 | 役割 |
|---|---|
| `mypocketos-test` | BIOS/Legacy確認用。日常的なLive起動・UI・Persistence確認に使用する |
| `mypocketos-uefi-test` | UEFI/Secure Boot系確認用 |

**ISO更新時の方針**: ISOを再ビルドするたびにVMを作り直す必要はありません。
両VMは`MyPocketOS-dev.iso`を共有しており、ISO再ビルド後は
`scripts/update-test-iso.sh`で共有ISOのみを更新します (手順は後述の
「ISO再ビルド後の更新手順」節を参照)。

**Persistence VMの方針**: Persistence専用の恒久3台目VMは作りません。
Mode A等の確認が必要な場合は、`mypocketos-test`に接続済みの
`mypocketos-test-persistence-scratch.qcow2`を必要に応じて利用します。

**USB persistence IMG等の特殊検証の方針**: このような検証のためだけに
恒久VMを増やすことはしません。必要なときだけ一時的な検証VMを作成し、
検証結果を本READMEや仕様書へ記録したら、不要になったVM・専用ディスクは
整理します (整理手順は後述の「VMの削除について」節を参照)。

**2026-09-04の整理結果**: 過去の個別検証で作成し役目を終えていたVM7台
(GUI永続化領域作成検証・試作USB persistence IMG検証・Standard版USB
persistence IMG検証それぞれのBIOS/UEFI版、および用途未確認の1台) を
整理し、古いraw IMG・一時ファイルもあわせて整理しました。この結果、
恒久VMは現在上記の2台のみとなり、開発ホストの空き容量は約14GiBから
約29GiBへ回復しました。

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
実装していません (削除の一括自動化はscriptsへ追加しない方針です)。

現在、恒久的に維持し削除しないものは次のとおりです。

- `MyPocketOS-dev.iso` (BIOS版・UEFI版共有のCD-ROM)
- `mypocketos-test.qcow2`
- `mypocketos-test-persistence-scratch.qcow2`
- `mypocketos-uefi-test.qcow2`

「USB persistence IMG等の特殊検証の方針」節のとおり一時的に作成した
検証用VM・専用ディスクが不要になった場合は、virt-manager等で対象VM名を
目視確認したうえで、VM定義の削除 (`virsh undefine`) と仮想ディスクの
削除 (`virsh vol-delete`) を分けて手動で行ってください。
`virsh undefine --remove-all-storage` のような一括削除コマンドは、
共有ISO (`MyPocketOS-dev.iso`) を巻き込んで削除してしまう危険があるため
推奨しません。誤削除防止のため、本READMEでは具体的な削除コマンド例は
案内しません。

## Live永続化基盤

- 起動メニューは、通常Liveと永続Liveで分かれています
  (BIOS/Syslinux: `MyPocketOS Live` / `MyPocketOS Live (Persistence)` /
  `MyPocketOS Live (Fail-safe)` の3ラベル。UEFI/GRUB も同名の3項目)。
- 通常Liveには `nopersistence`、永続Liveには `persistence` の起動
  パラメータが付きます。
- 現段階で永続化の対象となるのは `/home` と
  `/etc/NetworkManager/system-connections` (Wi-Fi等の接続プロファイル) の
  2箇所です。
- 永続化には、ext4でフォーマットしラベルを `persistence` にした
  パーティションと、そのルートに置く `persistence.conf` (中身は
  `/home` と `/etc/NetworkManager/system-connections` の2行、いずれも
  live-boot標準のオプションなしデフォルトbindマウント) が必要です。
- 暗号化 (LUKS等) は未実装です。Wi-Fi接続の認証情報 (PSK等) も含めて、
  Persistence領域は無暗号化のまま保存されます。Persistence USBの紛失・
  盗難時にはこれらの認証情報も読み取られ得る点に注意してください。
- GUIによるパーティション作成は実装済みであり、2026-08-26に専用の
  BIOS版・UEFI版の双方の使い捨てテストVMで、GUIから実際に新規
  persistence領域を作成できることを確認済みです (詳細は「GUIによる
  永続領域作成 (実装仕様)」節の「動作確認」を参照)。
- `/home` 配下の一般アプリ設定・ユーザーデータ、および
  NetworkManagerのWi-Fi接続プロファイルは保存対象です。
- 追加インストールしたアプリ本体、パッケージ一覧、APTキャッシュの永続化は
  未実装です。

### `/` unionを採用しない理由

- `/` unionはシステム全体の変更を保存する方式であり、カーネルやLive基盤を
  ISO更新によって提供するという方針と衝突します。
- 今回はユーザーデータとホームディレクトリ配下の設定、およびWi-Fi接続
  設定 (`/etc/NetworkManager/system-connections`) といった限定された
  パスだけを永続化の対象とします。
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

5. `persistence.conf` を作成する (中身は `/home` と
   `/etc/NetworkManager/system-connections` の2行)。シェルの
   リダイレクトでは書き込み権限の問題が起きうるため、`tee` を使う。
   作成後は内容を確認する。

   ```sh
   printf '/home\n/etc/NetworkManager/system-connections\n' | sudo tee /mnt/persistence/persistence.conf >/dev/null
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
  実機試験は未確認です。ただし、既存partitionを持つ外付けUSBを対象と
  したMode A許可パス全体 (候補表示→内蔵ディスク除外→既存データ消去
  警告→ERASE確認→既存partition/signature消去→作成→Persistence起動) は
  2026-09-06に実機で確認済みです (詳細は「Mode A 既存partitionあり
  外付けUSB 実機E2E検証 (2026-09-06)」節を参照)。
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
  ただし、既存partitionを持つ外付けUSBを対象としたMode A許可パス全体
  (候補表示から作成・Persistence起動までの一連の流れ) は2026-09-06に
  実機で確認済みである (詳細は「Mode A 既存partitionあり外付けUSB
  実機E2E検証 (2026-09-06)」節を参照。個々の拒否条件を実ブロック
  デバイスで個別に確認する実機試験は引き続き未実施)。
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
  **パーティションテーブルや既存partitionが存在すること自体は、単独では
  除外理由にしない**(2026-09-06修正。Debian ISOや他OSのインストーラを
  書き込んだ、一般的な外付けUSBメモリが既存partitionを理由に候補から
  漏れていた実機不具合の修正)。完全に未使用なディスク (パーティション
  テーブルなし) は、既存方針どおり接続方式を問わず候補になりうる。
- 子パーティションを1つ以上持つ (既存パーティションテーブルがある)
  ディスクは、次の**全て**を満たす場合に限り候補にする。1つでも満たさ
  ない場合、または判定に必要な情報の取得・解析に失敗した場合は、安全に
  判定できないため候補から除外する (fail-closed)。
  - 対象ディスク自身が`TRAN=usb`であり、かつ`/sys/class/block/<name>/device`
    の実体パスがUSBコントローラ配下 (パス中に`usbN/`を含む) であることを
    sysfs上で確認できる (Mode B の起動USB確認と同じ判定方式。内蔵SATA/
    NVMeディスク等の既存OS等が入ったディスクを誤って候補にしないための
    確認であり、子パーティションを持たない完全未使用ディスクにはこの
    確認を課さない)。
  - 全ての子パーティションが未マウントであること。
  - 全ての子パーティションがスワップとして使用されていないこと。
  - 全ての子パーティションについて `/sys/class/block/<name>/holders/`
    が空であること。
  - **既知の制限**: GUI側のこの予備判定で確認するのは対象ディスクの
    直接の子パーティションのみである。MBR拡張パーティション配下の
    論理パーティション (親が拡張パーティションであるもの) はGUI側の
    この確認の対象に含まれない。ただし後述のヘルパー側の最終検証は
    lsblkの階層出力 (指定したディスクとその配下の全block-device子孫を
    まとめて返す) をそのまま用いるため、直接の子だけに限定されず、
    GUI側の予備判定より広い範囲を対象とする。
  - 2026-09-06実装: 上記の全条件を満たすディスクは、確認画面での
    type-to-confirm完了後、実際にヘルパーによって初期化される。ヘルパーは
    既存partition・署名を能動的に消去 (`wipefs -a`) したうえで、通常の
    Mode A手順 (GPT作成→単一partition作成→ext4フォーマット) を実行する。
    確認画面には、対象ディスクに既存データが検出された場合、その旨を
    明示する文言を表示する (後述「GUI操作フロー」節、「helper側の最終
    検証」節参照)。
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

- 対象ディスク・その配下の全block-device子孫 (指定したディスクを対象に
  lsblkを実行し、階層出力をそのまま用いる。直接の子パーティションだけで
  なく、MBR拡張パーティション配下の論理パーティションやLVM/LUKS等で
  さらにネストしたデバイスも含む) について、次を再検証する。
  - 対象ディスク・全子孫がいずれも未マウントであること。
  - 対象ディスク・全子孫がスワップとして使用されていないこと
    (`FSTYPE=swap`直接確認と、`/proc/swaps`によるアクティブなswapの
    両方を確認する)。
  - 対象ディスク・全子孫について `/sys/class/block/<name>/holders/`
    が空であること。
- Live起動元/`/home`のいずれの親diskとも一致しないこと、「既存の永続
  領域の検出範囲」節の検査 (システム全体のブロックデバイスを対象とした
  `LABEL=persistence`/`PARTLABEL=persistence`の再検索) の再実行。
- 2026-09-06修正: 対象ディスクに子孫デバイス (既存partition) が1件でも
  見つかった場合、以下のいずれかとなる。
  - 対象ディスクが`TRAN=usb`かつsysfs実体パスがUSBコントローラ配下で
    あることを確認できない場合は拒否する (exit 17。内蔵SATA/NVMe
    ディスク等の保護)。
  - 上記のUSB接続確認、および子孫の未マウント/非swap/holders空の確認を
    いずれも満たす場合は許可し、新規GPT作成の直前に、既存の各partition
    自身の署名、および対象ディスク自身の署名 (パーティションテーブル)
    を`wipefs -a`で能動的に消去したうえで (失敗時はexit 18)、通常の
    Mode A手順 (GPT作成→単一partition作成→ext4フォーマット) へ進む。
  子孫デバイスを持たない (完全に未使用な) ディスクについては、従来
  どおり`wipefs -n`(読み取り専用) による署名検出を含む
  **パーティションテーブルが一切存在しないこと**の確認 (`check_pttype_empty`・
  `check_no_signature`) を行い、いずれかでも検出された場合は拒否する
  (exit 15)。この許可条件は変更していない。

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
| 17 | 既存partition (子孫デバイス) を持つ対象ディスクが、USB接続として確認できない (2026-09-06追加。内蔵SATA/NVMeディスク等の保護) |
| 18 | 既存partition・対象ディスク自身の署名消去 (`wipefs -a`) に失敗 (2026-09-06追加) |
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
- 終了コード10〜17は、いずれも**破壊的操作 (`wipefs -a`/`parted`/`mkfs`)
  を開始する前の拒否**であり、対象ディスクには一切変更を加えない。対象
  デバイスの再検証 (`reverify_device`) は、ロック取得直後・`parted`実行
  直前の計2箇所で行われ、これらはいずれも`parted`実行より前であるため、
  `DEVICE`系の不一致は12、`MAJOR:MINOR`系の不一致は13を返す。
- 終了コード18・20〜25は、**破壊的操作 (`wipefs -a`による既存署名消去、
  または`parted`/`mkfs`) を開始した後の、段階別の失敗**であり、対象
  ディスクが途中状態 (既存署名の一部のみ消去済み、パーティションテーブル
  のみ作成済み、ファイルシステム未作成、`persistence.conf`未作成等) に
  なっている可能性があることを明示する。18は、既存partitionを持つ
  ディスクの初期化でのみ発生しうる (子孫を持たない完全未使用のディスク
  では`wipefs -a`による能動的な消去自体を行わないため発生しない)。
  `parted`によるGPT/パーティション作成・`partprobe`・`udevadm settle`・
  作成したパーティションの特定が完了した後、`mkfs.ext4`実行直前にも
  同じ`reverify_device`を再度呼び出すが、この時点では既に対象ディスクへ
  変更を加えているため、`DEVICE`系・`MAJOR:MINOR`系のいずれの不一致も
  21を返す (12/13は返さない)。
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
   2026-09-06追加: 対象ディスクに既存パーティションテーブルが検出された
   場合、「このディスクには既存のデータ・パーティションがあります。
   続行すると、それらはすべて消去されます。」という文言を警告文の先頭に
   追加する (`lsblk -dn -o PTTYPE`による表示目的の予備判定。取得に失敗
   した場合や不明な場合も、安全側の文言 (既存データがある可能性がある)
   を選ぶ)。type-to-confirm形式自体は変更・追加せず、既存の仕組みを
   そのまま使う。
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
   `persistence.conf`書き込み (`/home`と`/etc/NetworkManager/system-connections`
   の2行) → `sync` → アンマウント。
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
- `/home`と`/etc/NetworkManager/system-connections`以外 (`/`全体等) の
  永続化。
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
  既存partitionを持つ外付けUSBを対象としたMode A許可パス全体について
  のみ、下記「Mode A 既存partitionあり外付けUSB 実機E2E検証
  (2026-09-06)」節で別途実機確認済みである。
- 専用UEFI VMでのSecure Boot有効状態 (`mokutil`未搭載のため未確認。
  UEFI起動自体は確認済み)。
- LUKSによる暗号化、部分的な空き領域を利用した永続化、既存永続領域の
  変更、複数の永続領域の作成・切り替え、`/home`以外の永続化、追加
  インストールしたアプリ本体の永続化 (いずれも「初版のスコープ外」節
  参照)。

#### Mode A 既存partitionあり外付けUSB 実機E2E検証 (2026-09-06)

branch `fix/mode-a-existing-partition-candidates`
(commit `29cfcd825bc5073bd51f5abe5d206b16df4478dc`) のStandard版ISOを
用いて、既存partition/signatureを持つ外付けUSBに対するMode A新設
許可パスの実機E2Eを実施した。

**検証対象ISO**

- file: `mypocketos-standard-amd64.hybrid.iso`
- size: 1,793,409,024 bytes
- SHA-256: `92941882720b5e5dba927adcee8aecd12bdd70b0301d29cbfa5c89a4cb7b3158`
- Volume ID: `MyPocketOS 20260906-19:28`

**実機構成**

- MyPocketOS起動USB: MODEL `USB DISK 2.0`、SERIAL `071891876B260185`、
  7.2G。
- Mode A対象USB: MODEL `USB Flash Disk`、SERIAL `07080A7474AB4873`、
  7.4G。事前状態としてDebian trixie ISOを書き込み済みで、
  iso9660+vfatの既存partitionがある状態。
- 内蔵ディスク: KLEVV NVMe、238.5G (Mode A対象にしてはならないもの)。

**確認した内容**

1. MyPocketOS Liveを通常起動し、lsblkで起動USB (`MyPocketOS
   20260906-19:28`)・Mode A対象USB (Debian trixie既存partitionあり)・
   内蔵NVMeの構成を確認した。
2. Persistence GUIの候補一覧に、`/dev/sdb` (USB Flash Disk、
   SERIAL `07080A7474AB4873`、7.4 GiB) がMode A候補として表示された。
   MyPocketOS起動USBは既存の特別項目として表示され、内蔵NVMeは候補
   一覧に表示されなかった。
3. `/dev/sdb`を選択して次へ進むと、「このディスクには既存のデータ・
   パーティションがあります。続行すると、それらはすべて消去されます。」
   相当の明確な破壊確認が表示された。
4. type-to-confirm欄に`ERASE /dev/sdb`を正確に入力した。
5. GUIで「永続領域の作成に成功しました。」を確認した。既存partitionを
   持つ外付けUSBからのMode A作成が実機で成功した。
6. MyPocketOS Live (Persistence)で再起動し、`findmnt --target /home`が
   `/dev/sda1[/home]` (ext4)、`findmnt --target
   /etc/NetworkManager/system-connections`が同一partition・ext4である
   ことを確認した。
7. `$HOME/mode-a-verify.txt`
   (内容: `MyPocketOS Mode A physical test 2026-09-06`、SHA-256
   `5177690d21b9ade0ffcb4dfae3dd4b539d5c8eca57e2f483ab617b472eaa0771`)
   を作成した。
8. Persistenceモードで再起動後、同一SHA-256であることを確認した
   (ファイル保持を確認)。
9. Normal Liveへ切替後、
   `test -e "$HOME/mode-a-verify.txt"; echo $?`が`1` (存在しない) で
   あることを確認した。
10. 再度Persistenceへ切替後、同一SHA-256でファイルが復活することを
    確認した。

以上により、既存partition/signatureを持つ外付けUSBからのMode A作成が、
候補表示・内蔵NVMeの候補除外・既存データ消去警告・ERASE確認・既存
partition/signature消去・GPT/partition/ext4によるPersistence作成・
Persistence起動・`/home` Persistence・NetworkManager設定Persistence・
Persistence再起動保持・Normal Liveでの非表示・再Persistenceでの復活
という一連の流れで動作することを、2026-09-06に実機E2Eで確認した。

**この検証で確認していない事項 / 注意**

- 実機でhelper内部の各コマンド (`wipefs`/`parted`/`mkfs.ext4`) を
  個別にトレースしたわけではない。GUIの成功表示と、最終的なMode A
  成果物・Persistence挙動から、処理全体としての成功を確認したもので
  ある。
- 署名・mount・swap・holders等、既存partition配下の個々の拒否条件
  (exit 14/17/18等) を実ブロックデバイスで個別に確認する実機試験は、
  引き続き未実施である (非破壊モックテストでは確認済み)。
- 今回の起動がBIOS/UEFIいずれのファームウェアモードによるものかは
  明示的に確認しておらず、推測では記載しない。
- 実機でのSecure Boot確認は行っていない。
- Mode A経由の実Wi-Fi SSID登録から再起動後の自動再接続までの確認、
  および複数Wi-Fiプロファイルの確認は、今回実施していない (「Mode B
  Wi-Fi Persistence 実機E2E検証 (2026-09-02)」・「USB persistence IMG
  経由の実Wi-Fi接続E2E検証 (2026-09-06)」節はMode B/USB persistence
  IMG経由の検証であり、本節の対象ではない)。
- UEFI / Secure Boot環境での、既存partitionを持つ外付けUSBに対する
  Mode Aの確認は未実施のままである。

#### Mode B Wi-Fi Persistence 実機E2E検証 (2026-09-02)

feature branch `feat/persistence-wifi-networkmanager` (commit
`38fc0fe1b884102c9c487abaa9c1652329f750ab`) のBase版ISOを実機のUSBメモリへ
書き込み、Mode B (同一起動USBの末尾未使用領域) でPersistence領域を作成した
うえで、Wi-Fi Persistenceの実機E2Eを実施した。

- 通常Liveから「永続領域を作成」を実行し、候補一覧の「MyPocketOS 起動USB」
  を選択、ERASE警告やtype-to-confirmが表示されないこと (Mode Bであること)
  を確認したうえで、永続領域の作成に成功した。
- Persistenceモードで再起動後、`findmnt`により`/home`・
  `/etc/NetworkManager/system-connections`の両方が、同一の`persistence`
  ラベルのext4パーティションからマウントされていることを確認した。
- GUI (nm-applet) からWi-Fiへ接続し、`/etc/NetworkManager/system-connections/`
  配下に接続プロファイル (`<SSID>.nmconnection`) が所有者`root:root`・
  パーミッション`600`で作成されることを確認した。
- 再起動しPersistenceモードで再度起動したところ、パスワード再入力なしで
  同じWi-Fiへ自動接続すること、接続プロファイルの所有者・パーミッションが
  維持されていることを確認した。
- `/home`側のテストファイルも、再起動後に保持されていることを確認した
  (既存の`/home` Persistenceへの回帰がないことの確認を兼ねる)。
- 通常Live (`nopersistence`) で起動すると、Wi-Fi接続・接続プロファイル・
  `/home`のテストファイルのいずれも見えないことを確認した。

**この検証で確認していない事項**

- 使用した実機のブート方式 (Legacy BIOS / UEFI) は記録されておらず未確認。
- Mode A (別ディスク全体) でのWi-Fi Persistence実機/VM確認。
- UEFI環境・Secure Boot環境でのWi-Fi Persistence確認。
- 複数のWi-Fiプロファイルを記憶させた場合の挙動。

**注記(2026-09-06追記)**: 「USB persistence IMG
(`build-usb-persistence-image.sh`) 経由でのWi-Fi Persistence実機確認」は、
2026-09-06に実施済みである(後述「USB persistence IMG経由の実Wi-Fi接続
E2E検証 (2026-09-06)」節を参照)。ただし、その検証時の実機起動方式
(BIOS/UEFI) も記録されておらず不明のままであり、Mode A・UEFI環境・
Secure Boot環境・複数Wi-Fiプロファイルでの確認は、USB persistence IMG
経由も含めて引き続き未確認のまま残っている。

検証中に、今回の検証対象とは別のUSBメモリでのI/Oエラー、および別の
USBメモリでの書き込み後起動失敗が確認されたが、いずれも本機能のコードとは
無関係なUSBハードウェア側の問題として切り分けており、上記の結果に影響
していない。

## USB persistence IMG生成 (試作)

`scripts/build-usb-persistence-image.sh` は、通常のedition別ISO
(`mypocketos-base-amd64.hybrid.iso` / `mypocketos-standard-amd64.hybrid.iso`)
とは**別成果物**として、単一のGPT/MBR/APM/El Toritoハイブリッド構造に
persistence用の第3パーティション (ext4, LABEL=`persistence`,
`persistence.conf`の内容は`/home`と
`/etc/NetworkManager/system-connections`の2行) をあらかじめ追加した
IMGファイルを、
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

- 実USBメモリへの書き込み。
- 実機BIOS/UEFI起動。
- 実際のWi-Fi無線接続・自動再接続 (後述「現行(2行版)persistence.confでの
  VM実地検証 (2026-09-06)」節を参照。VM上ではNetworkManagerプロファイルの
  永続化機構そのものは確認済みだが、実Wi-Fi電波での接続・自動再接続は
  未確認のまま)。
- 未署名バイナリ拒否によるSecure Boot enforcementの実証 (同節を参照)。

**注記(2026-09-06追記)**: 上記でかつて「未確認」としていた「現在の
正式スクリプトが生成した成果物そのものについてのVM実地検証」は、
2026-09-06に現行(2行版)`persistence.conf`の成果物に対して実施済みである
(後述「現行(2行版)persistence.confでのVM実地検証 (2026-09-06)」節を
参照)。本節の直後にあるプロトタイプIMG検証、および次節の2026-08-29の
検証は、いずれもこの2026-09-06検証より前の`persistence.conf`
(1行版、`/home`のみ) に対するものであり、現行の2行版とは版が異なる
点に注意する。

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

### 現行(2行版)persistence.confでのVM実地検証 (2026-09-06)

上記2026-08-29の検証は、`persistence.conf`が`/home`のみの1行版だった時期
のものである。その後commit `38fc0fe`(Wi-Fi/NetworkManager設定Persistence
追加)で`persistence.conf`の内容は現行の2行版
(`/home`と`/etc/NetworkManager/system-connections`)へ変更されたが、
この現行版を`scripts/build-usb-persistence-image.sh`で生成した成果物
そのものについては、2026-09-06まで一度もVM実地検証を行っていなかった。
本節はこの検証結果を記録する。

**検証対象**

- `main` HEAD: `df924d97b04e35738b286e43132a78324b34b239`
- Standard版ISO: `mypocketos-standard-amd64.hybrid.iso`
  (サイズ: 1,793,409,024 bytes、SHA-256:
  `04dd2ffee5991f8f8719cbd5f4b3445ea4f3788356bb5df9da3e0048d8999351`)
- persistence領域: 2GiB
- `persistence.conf`: `/home` と `/etc/NetworkManager/system-connections`
  の2行(現行版)

**訂正**: 実際のlive-buildの生成先ディレクトリは`binary/`である
(`config/binary/`ではない。「ビルド仕様」節参照)。
`build-usb-persistence-image.sh`には`--binary-dir "$(pwd)/binary"`を
指定して生成した。

**IMG生成結果**

BIOS検証用・UEFI検証用にそれぞれ個別のIMGを生成した(同一IMGファイルを
2台のVMで同時に使うと書込みが競合するため)。

| 用途 | パス(検証後に削除済み) | SHA-256 |
|---|---|---|
| BIOS検証用 | `/var/tmp/mypocketos-standard-usbimg-verify-bios-20260906.img` | `cbb923529cca3b079eec0bdb2bd2156834d522abd3cc7d887eaccdae94574c7f` |
| UEFI検証用 | `/var/tmp/mypocketos-standard-usbimg-verify-uefi-20260906.img` | `bd655c1943979cf403d8b1002dfb96f2ce64ec8bab8103b83393845da466d552` |

いずれも次を確認した。

- `build-usb-persistence-image.sh`がexit 0で成功。
- MBR/GPTの整合性確認PASS。
- El Torito BIOS/UEFI一致確認PASS。
- ISO9660の読み取りPASS。
- partition 3: ext4, `LABEL=persistence`, 2GiB。
- `persistence.conf`の内容が`/home`と
  `/etc/NetworkManager/system-connections`の2行であること、
  UID=0/GID=0/mode=0600であることを確認。
- `e2fsck -fn`で異常なし。
- 入力ISO・`binary/`の主要ファイルが実行前後で変化しないこと。

**BIOS VM実地検証** (一時VM `mypocketos-usbimg-verify-bios-test`)

- BIOSブートメニュー3項目の表示PASS。
- Normal Live起動PASS、`nopersistence`確認PASS。
- `sda1`/`sda2`/`sda3`の認識PASS。
- Persistence起動PASS。
- `/home`が`/dev/sda3[/home]`からマウントされることを確認。
- `/etc/NetworkManager/system-connections`が
  `/dev/sda3[/etc/NetworkManager/system-connections]`からマウントされる
  ことを確認(`/home`と同一partitionからの独立bind mount)。
- `sda3`: `LABEL=persistence`, ext4, 2GiB。
- `/home`に作成したテストファイルが再起動後も保持されることを確認
  (SHA-256: `e36c04c913afbe7bae394225acb23e4cb5fafdd0bea00ed70a68fe6f5c22411f`)。
- NetworkManagerのWi-Fi接続プロファイル(`persistence-verify-wifi.nmconnection`)
  を疑似作成し(VMには実Wi-Fiデバイスがないため、`nmcli`でWi-Fi種別の
  プロファイルファイルのみを作成。実接続は行っていない)、
  所有者`root:root`・パーミッション`0600`であることを確認。
- 上記プロファイルがPersistence再起動後も保持されることを確認。
- Normal Liveでは`/home`のテストファイル・NMプロファイルとも非表示に
  なることを確認。
- 再度Persistenceに戻すと、両方とも再表示されることを確認。

**UEFI VM実地検証** (一時VM `mypocketos-usbimg-verify-uefi-test`)

- GRUBブートメニューの表示PASS。
- libvirtのfirmware設定: `firmware='efi'`、`secure-boot enabled='yes'`、
  `enrolled-keys enabled='yes'`、loader `secure='yes'`
  (`/usr/share/OVMF/OVMF_CODE_4M.ms.fd`、NVRAMテンプレート
  `/usr/share/OVMF/OVMF_VARS_4M.ms.fd`)。
- ゲスト側で`/sys/firmware/efi`の存在を確認(UEFI起動)。
- ゲスト側でSecure BootのEFI変数の値が`1`であることを確認。
- 上記のSecure Boot有効なVM環境で、MyPocketOSデスクトップまで起動する
  ことを確認。**ただし「未署名バイナリが実際に拒否されること」自体は
  検証していない**(意図的に未署名のブートローダー/カーネルを用意して
  拒否されることを試す行為はリスクが高いため、本検証の範囲外とした)。
- Persistence起動PASS。
- `/home`が`/dev/sda3[/home]`からマウントされることを確認。
- `/etc/NetworkManager/system-connections`が
  `/dev/sda3[/etc/NetworkManager/system-connections]`からマウントされる
  ことを確認。
- `sda3`: `LABEL=persistence`, ext4, 2GiB。
- `/home`に作成したテストファイルが再起動後も保持されることを確認
  (SHA-256: `f26239e18b46fe57a5fc9b789b432b990be998402b3133245efca61d3b9a7b6f`)。
- NetworkManagerのWi-Fi接続プロファイル(`persistence-verify-wifi-uefi.nmconnection`、
  BIOS版と同様に疑似作成)について、所有者`root:root`・パーミッション
  `0600`であることを確認。
- 上記プロファイルがPersistence再起動後も保持されることを確認。
- Normal Liveでは`/home`のテストファイル・NMプロファイルとも非表示に
  なることを確認。
- 再度Persistenceに戻すと、両方とも再表示されることを確認。

**この検証で確認していない事項**

- 実USBメモリへのIMG書き込み。**2026-09-06に別途実施済み**(下記
  「実USB/実機E2E検証 (2026-09-06)」節を参照)。
- 実機でのUSB persistence IMG起動(BIOS/UEFIいずれも)。**基本的な`/home`
  Persistenceの実機起動は2026-09-06に確認済みだが、起動方式(BIOS/UEFI)
  は記録されておらず不明**(下記「実USB/実機E2E検証 (2026-09-06)」節を
  参照)。
- 実際のWi-Fi無線接続・自動再接続(VMには実Wi-Fiデバイスがないため、
  上記はいずれも`nmcli`によるプロファイルファイル作成のみの確認であり、
  NetworkManager設定パスのPersistence機構そのものの確認にとどまる)。
  2026-09-06の実USB/実機E2Eでも、NetworkManager設定パスが同一partitionから
  マウントされることは確認したが、実際のWi-Fi SSID/パスワード登録から
  再起動後の自動再接続までは未確認のまま(下記節を参照)。
- 実機でのSecure Boot確認。
- 未署名バイナリ拒否によるSecure Boot enforcementの実証。

**クリーンアップ**

検証後、一時VM定義(`mypocketos-usbimg-verify-bios-test`・
`mypocketos-usbimg-verify-uefi-test`)・UEFI版のNVRAM・BIOS/UEFI検証用
IMG 2本を削除済み。恒久VM(`mypocketos-test`・`mypocketos-uefi-test`)、
および共有ISO・両VMの永続化ディスクを含むKEEP対象ディスクには変更を
加えていない。

### 実USB/実機E2E検証 (2026-09-06)

上記VM実地検証に続き、同日2026-09-06に、実USBメモリへの書き込み・実機での
起動E2Eを実施した。

**検証対象**

- IMG: `/var/tmp/mypocketos-standard-usb-persistence-20260906.img`
  (検証後削除)
  - サイズ: 3,939,475,456 bytes
  - SHA-256: `cca50b545c94774e1938e397153117979773a6c1874098a5cece2977db0f27e0`
  - 元ISO SHA-256: `04dd2ffee5991f8f8719cbd5f4b3445ea4f3788356bb5df9da3e0048d8999351`
- 書き込み先実USB: MODEL `USB DISK 2.0`、SERIAL `071891876B260185`、
  容量7.2G、`/dev/sdb`
- 書き込みコマンド:
  ```sh
  sudo dd if=/var/tmp/mypocketos-standard-usb-persistence-20260906.img \
      of=/dev/sdb bs=4M status=progress conv=fsync
  ```
  書き込みバイト数(3,939,475,456 bytes)はIMGサイズと一致。
- 書き込み後のpartition構成: `sdb1` 1.7G iso9660(ボリュームラベル
  `MyPocketOS 20260906-08:10`)、`sdb2` 3.3M vfat、`sdb3` 2G ext4
  `persistence`。

**実機USB Persistence E2E結果**

- 実USBからMyPocketOSを起動し、`MyPocketOS Live (Persistence)`で起動。
- `/proc/cmdline`に`boot=live`・`persistence`を確認。
- `/home`が`/dev/sda3[/home]`(ext4)からマウントされることを確認。
- `/etc/NetworkManager/system-connections`が
  `/dev/sda3[/etc/NetworkManager/system-connections]`(ext4)から
  マウントされることを確認。
- `/home/user/usb-persistence-verify.txt`を作成し、
  SHA-256(`55f9f61bd660c30dab6d85df7850c96402c772e2848a0da03220ed8991dc`)を
  記録。
- Persistenceモードで再起動後、同一SHA-256であることを確認(ファイル
  保持を確認)。
- Normal Liveへ切替後、`test -e "$HOME/usb-persistence-verify.txt"; echo $?`
  が`1`(存在しない)であることを確認。
- 再度Persistenceで起動すると、同一SHA-256でファイルが復活することを
  確認。

以上により、実USBメモリ経由での`/home` Persistenceが、
Persistence → 再起動 → Normal Live → 再Persistenceという一連の流れで
動作することを実機E2Eで確認した。

**この検証で確認していない事項**

- 今回の起動が実機のBIOS/UEFIいずれのファームウェアモードによるものかは
  記録されておらず不明(推測で記載しない)。
- 実機でのSecure Boot確認、および未署名バイナリ拒否によるSecure Boot
  enforcementの実証(いずれも本検証の対象外)。

**注記(2026-09-06追記)**: NetworkManager設定パスがPersistence領域から
マウントされることを確認した上記の結果を踏まえ、同日別途、実際のWi-Fi
SSID/パスワードの登録から再起動後の自動再接続までを実機E2Eで確認した
(下記「USB persistence IMG経由の実Wi-Fi接続E2E検証 (2026-09-06)」節を
参照)。

### USB persistence IMG経由の実Wi-Fi接続E2E検証 (2026-09-06)

上記「実USB/実機E2E検証」に続き、同じ実USB環境(Intel UHD Graphics 620
搭載VAIO実機、GUI起動には下記「既知の実機互換性問題」節の回避策
`i915.enable_psr=0`を適用)で、`MyPocketOS Live (Persistence)`起動中に
実際のWi-Fi接続E2Eを実施した。

**確認結果**

- `nmcli device status`でWi-Fiデバイス`wlp2s0`(TYPE: `wifi`)を認識
  していることを確認。
- `nmcli device wifi list`で周辺の複数SSIDが正常に表示され、Wi-Fi
  スキャンが動作していることを確認。
- `nmcli --ask device wifi connect "<実SSID>"`(パスワードは端末内で
  入力、記録はしない)で実SSIDへの接続に成功したことを確認。
- `/etc/NetworkManager/system-connections/`に対象SSIDに対応する
  `.nmconnection`ファイルが所有者`root:root`・パーミッション`0600`で
  作成されることを確認(この保存先が`/dev/sda3[/etc/NetworkManager/system-connections]`
  としてPersistence領域からマウントされていることは、上記「実USB/実機
  E2E検証」節で既に確認済み)。
- Persistenceモードで再起動後、`nmcli device status`で`wlp2s0`が
  「接続済み」となり、CONNECTION欄に登録済みの実SSIDが表示されることを
  確認。
- 再起動後、パスワードの再入力や手動接続操作を行わずに自動的に再接続
  したことを確認。

以上により、USB persistence IMG経由の実機環境で、実SSIDへの接続・
Wi-Fiパスワードを含むNetworkManager接続プロファイルの作成・Persistence
領域への保存・再起動・自動再接続までを実機E2Eで確認した。

**この検証で確認していない事項**

- 今回の起動が実機のBIOS/UEFIいずれのファームウェアモードによるものかは、
  上記「実USB/実機E2E検証」節と同様に記録されておらず不明。
- 複数のWi-Fiプロファイルを記憶させた場合の挙動。
- Mode A(別ディスク全体)経由でのWi-Fi Persistence実機/VM確認。
- UEFI環境・Secure Boot環境でのWi-Fi Persistence確認、および未署名
  バイナリ拒否によるSecure Boot enforcementの実証。

### 既知の実機互換性問題: Intel UHD Graphics 620 (i915) + PSR (2026-09-06)

上記実USB検証と同じ機会に、VAIO実機(Intel UHD Graphics 620
`[8086:5917]`、`i915`ドライバ)で以下の表示問題を確認した。

- 通常起動では、OS起動途中から縦線・表示乱れが発生する。
- BIOS/UEFI設定画面自体は正常に表示される(ファームウェア・ディスプレイ
  ケーブル自体の問題ではないと考えられる)。
- カーネルパラメータ`nomodeset`を指定すると縦線は消えるが、GUIまでは
  正常に起動しない。
- カーネルパラメータ`i915.enable_psr=0`を追加すると、MyPocketOSおよび
  比較のため試したPeppermint OSの両方で正常なGUI起動を確認した。

以上から、この機種ではIntel UHD Graphics 620・`i915`ドライバ・内蔵液晶
パネルのPSR (Panel Self Refresh) の組み合わせによる互換性問題である
可能性が高いと考えている。回避策は次のとおり。

```
i915.enable_psr=0
```

**注意**:
- ハードウェア故障とは断定しない(同一実機のBIOS/UEFI画面は正常表示)。
- 全てのIntel内蔵グラフィックス機で発生するとは一般化しない(今回確認
  したのはこの1機種のみ)。
- 初回公開版において、この回避策を起動オプションへ恒久的に組み込むかは
  未決定であり、現時点では未実装(手動でカーネルパラメータを追加する
  必要がある)。
