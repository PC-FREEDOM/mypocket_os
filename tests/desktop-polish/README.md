# 配布前デスクトップ調整 静的/軽量テスト

音量アイコン視認性・Conky起動モード表示・右クリックメニュー・
アイコンテーマ(MyPocketOS-Fluent-yellow、単一tar.gzアーカイブ方式)・
Mousepad/Galculator追加、それぞれに対する軽量なテストハーネス。
`tests/persistence/`のような、破壊的な特権操作をモックする本格的な
sandbox基盤は必要ないため採用していない(対象がいずれも読み取り専用
ヘルパー・静的設定ファイル・アーカイブのエントリ一覧であるため)。

## 実行方法

```sh
tests/desktop-polish/run.sh
```

一般ユーザー権限のみで完結する。`sudo`・実`jgmenu`・実tar展開・実
gtk-update-icon-cache・実VM/ISO操作は一切必要ない。

個別に実行する場合:

```sh
tests/desktop-polish/test_boot_mode.sh
tests/desktop-polish/test_menu.sh
tests/desktop-polish/test_icon_theme.sh
tests/desktop-polish/test_fluent_archive.sh
tests/desktop-polish/test_battery.sh
tests/desktop-polish/test_touchpad.sh
tests/desktop-polish/test_conky_display.sh
tests/desktop-polish/test_conky_network_restart.sh
```

## 内容

- `test_boot_mode.sh`: `mypocketos-boot-mode`の判定ロジック
  (persistence/nopersistence/両方/両方なし/重複/部分一致/空/読み取り不可、
  計10シナリオ)。productionスクリプト自身がテスト用にcmdlineファイルを
  引数で差し替えられる設計のため、instrument/mockは不要で直接実行する。
- `test_menu.sh`: tint2側の`jgmenu_run`が変更されていないこと、右クリック
  用ラッパー(`mypocketos-jgmenu-at-pointer`)が`--at-pointer`を渡すこと、
  `append.csv`の必須項目、`menu.xml`が削除されず主要機能を保持している
  ことを静的に確認したうえで、`$PATH`へ配置したモック`jgmenu`(実バイナリ
  を一切起動しない)でラッパーが渡す引数を検証する。
- `test_icon_theme.sh`: **MyPocketOS側**の設定を確認する。`MyPocketOS`
  テーマの継承順(`MyPocketOS-Fluent-yellow,Adwaita,hicolor`)、GTK2/GTK3
  設定が`MyPocketOS`を参照し`gtk-theme-name`は変更していないこと、
  pasystray起動行にのみ`GTK_THEME=Adwaita:dark`が付与され`export`等で
  グローバル化されていないこと、非symbolic独自音量SVGがまだ追加されて
  いないこと(今回のスコープ外)、`mousepad`/`galculator`を含む
  Standard版パッケージリストの重複なしを確認する。
- `test_fluent_archive.sh`: **Fluent派生サブセット本体(アーカイブ)**を
  確認する。`MyPocketOS-Fluent-yellow.tar.gz`の存在・gzip整合性、
  live-build hook (`config/hooks/normal/mypocketos-fluent-icon-theme.hook.chroot`)
  に記載のSHA-256とアーカイブの実SHA-256が一致すること、`tar -tzf`の
  読み取り専用一覧から絶対パス・`..`・想定外のトップレベルディレクトリが
  無いこと、`COPYING`・`MODIFICATIONS.md`・`index.theme`・symbolic音量
  4種が含まれること、ファイル名が不正な3件
  (`cinnamon-virtual-keyboard`拡張子なし等。同名の正規`.svg`ファイルは
  別途存在してよい)・旧トップディレクトリ`Fluent-yellow/`・固定サイズ
  /HiDPIディレクトリ・`icon-theme.cache`が含まれないことを確認する。
  実展開・実sudo・実chroot操作は一切行わない。
- `test_battery.sh`: パネルのバッテリー残量%表示(tint2標準Battery機能)を
  確認する。`panel_items`に既存のP/T/S/Cを維持したまま`B`が1つだけ
  追加されていること、`bat1_format = %p`(残量%のみ)・`bat2_format`が
  空(2行表示にしない)であること、`battery_hide = never`・
  `battery_tooltip_enabled = 1`等の設定値、`battery_font_color`・
  `battery_padding`・`battery_background_id`が既存`clock_*`と統一されて
  いること、グラフィカルなアイコン(MyPocketOSテーマへの`battery`関連
  SVG追加)を採用していないこと、upower/acpi/cbatticon等の外部
  パッケージ・常駐daemonを追加していないことを静的に確認する。tint2は
  `/sys/class/power_supply`を直接読み取り、バッテリー非搭載機では
  tint2自身がBattery項目を自動非表示にする設計のため、実バッテリーの
  有無に依存する動作そのものは実機/VM側での確認が必要(本テストの対象外)。
- `test_touchpad.sh`: タッチパッド既定動作
  (`/etc/X11/xorg.conf.d/51-mypocketos-touchpad.conf`)を確認する。
  `MatchIsTouchpad "on"`を持つInputClassセクションが1つだけ存在し、その
  セクション内で`Tapping`/`TappingButtonMap`/`TappingDrag`/`ScrollMethod`
  が期待値どおり設定されていること、`MatchProduct`/`MatchVendor`/
  `MatchUSBID`等のデバイス名・vendor IDのハードコードが無いこと、
  `MatchIsPointer`/`MatchIsTouchscreen`/`MatchIsTablet`を持つ別セクション
  には同じOptionを適用していないこと、`xserver-xorg-input-all`
  (`xserver-xorg-input-libinput`への依存元)が既に共通パッケージリストに
  含まれていることを静的に確認する。実Xorg・実libinput・実タッチパッドは
  一切使用しない。
- `test_conky_display.sh`: Conkyシステム情報パネル
  (`~/.config/conky/conky.conf`)の表示内容を確認する。既存表示項目
  (MyPocketOS見出し・ホスト名・カーネル・稼働時間・起動モード・
  CPU使用率とバー・メモリとバー・ルートFSとバー・既存ショートカット
  5項目)がいずれも削除・置換されていないこと、ネットワーク表示
  (`${if_match "${gw_iface}" != "none"}`とその入れ子による接続判定、
  `${downspeed ${gw_iface}}`/`${upspeed ${gw_iface}}`によるDown/Up速度。
  2026-09-07時点の実装、詳細は後述)が特定インターフェース名
  (`wlan0`/`eth0`等)をハードコードしていないこと、`${exec`系変数
  (exec/execi)が追加されていないこと、過去2回の不具合版の実装
  (引数なし`${downspeed}`/`${upspeed}`、および廃止した
  `mypocketos-network.lua`経由のLua実装)に戻っていないこと、新規追加
  したウィンドウスナップ表示4項目(Super+Left/Right/Up/Down)が既存
  ショートカットの後に区切り線・見出し付きで追加されていること、
  ネットワーク監視用の新規パッケージ依存が追加されていないことを
  静的に確認する。実Conky・実Xは一切使用しない。
- `test_conky_network_restart.sh`: NetworkManager dispatcher
  (`config/includes.chroot/etc/NetworkManager/dispatcher.d/
  01-mypocketos-conky-restart`)を確認する。`action=up`(接続確立)の
  場合にのみ動作すること、対象ユーザー(固定のLiveユーザー`user`)の
  既存Conkyプロセスを`pgrep`で見つけること、DISPLAY/XAUTHORITYを
  そのConky自身の`/proc/<pid>/environ`から読み取り(ハードコードしない
  こと)、旧プロセスの終了を待ってから(無期限ループではない、上限付き
  ループで)`runuser`経由で同じユーザー・同じ環境で再起動すること、
  特定インターフェース名を判定に使っていないこと、毎秒のポーリング・
  常駐watchdog・新規systemdサービス/cronを追加していないことを静的に
  確認したうえで、モック`pgrep`/`runuser`と実プロセス・実
  `/proc/<pid>/environ`を使って、次を機能的に検証する:
  (1) 接続確立時に対象プロセスがkillされ、`runuser`が recovered
  DISPLAY/XAUTHORITY/HOMEと`conky -p 0 -U`(2026-09-11、Wi-Fi接続時の
  再表示遅延短縮のため`-p 3`→`-p 1`→`-p 0`と段階的に変更。実機確認で
  `-p 1`でも体感上の空白時間が残ったため`-p 0`へ再調整した。autostart側
  の`-p 3`は維持)で正しく1回呼ばれること、
  (2) 切断時 (`action=down`) は何もしないこと、(3) 対象プロセスが
  存在しない場合は何もしないこと、(4) DISPLAYを取得できない場合は
  fail-closeで再起動を試みず、既存プロセスにも触れないこと。実root権限・
  実conky・実NetworkManagerは一切使用しない。

### ネットワーク表示の実装経緯 (2026-09-06〜2026-09-07)

1. **2026-09-06導入**: 引数なし`${downspeed}`/`${upspeed}`(Conky内部の
   デバイス自動選択に委ねる方式)+`${if_gw}`。→実機で、Wi-Fi通信中でも
   Down/Upが常に0Bのままになる不具合が判明(Conkyの自動選択がdefault
   route interfaceと異なるデバイスを選んでいた)。
2. **2026-09-07 1st fix**: `mypocketos-network.lua`を追加し、Conky公式
   Lua API `conky_parse()`で`${gw_iface}`を取得してから
   `${downspeed IFACE}`/`${upspeed IFACE}`を組み立てる方式。→実機で
   `attempt to call a nil value`というLua実行時エラーが発生し、ラベル
   だけ表示され値が空欄になる不具合が判明(`${lua ...}`から呼ばれる
   Lua関数内で`conky_parse()`を再帰的に呼ぶことが、Conkyのネットワーク
   統計の内部状態と競合することが、実際のconky-std 1.22.1バイナリでの
   検証により判明した)。
3. **2026-09-07 2nd fix**: `mypocketos-network.lua`を廃止し、
   `${downspeed ${gw_iface}}`/`${upspeed ${gw_iface}}`という、Conky変数
   の引数へ別のConky変数を直接ネストさせる記法のみで実装。この記法は
   Conky公式ドキュメントには明記されていないが、実際にビルド済み
   conky-std 1.22.1バイナリ(`chroot/usr/bin/conky`、
   `out_to_x=false`・`out_to_console=true`の一時設定、複数回の更新
   サイクル)で、`${downspeed ${gw_iface}}`が固定インターフェース名を
   指定した場合と常に同一の値を返し、実際の通信量の増減を正しく反映
   することを確認した。→取得ロジック自体は解決したが、実機の再確認で
   別の症状(起動直後・Wi-Fi接続後・通信中でもDown/Upが0Bのまま)が
   判明した。
4. **2026-09-07 3rd fix (現行)**: 実機での追加切り分けにより、
   `${gw_iface}`/`${downspeed ${gw_iface}}`/`${upspeed ${gw_iface}}`は
   単体では実機でも正常動作すること、しかし**Conkyがネットワーク接続
   確立前に起動していると、そのConkyプロセスの生存中はネットワーク
   デバイスの内部状態が更新されず、後から接続してもDown/Upが0Bのまま
   変化しない**ことが実機で確認された(稼働中のConkyを完全終了させて
   から再起動すると正しく動作することも確認済み)。ネットワーク取得
   ロジック自体(`conky.conf`)はこれ以上変更せず、NetworkManagerの
   接続確立イベント(`up`)のたびにConkyを再起動する
   `config/includes.chroot/etc/NetworkManager/dispatcher.d/
   01-mypocketos-conky-restart`を新規追加した。詳細は
   `test_conky_network_restart.sh`の項を参照。

### `optional_conky_runtime_smoke.sh` (オプション、非必須)

上記2回の不具合はいずれも「静的テストはPASSしていたが、実際にConkyの
プロセス内で実行すると失敗する」という種類の問題だった。この種の
問題を可能な範囲で機械的に検出するため、実conkyバイナリを一時
HOME・一時設定(`out_to_x=false`・`out_to_console=true`・
`total_run_times=3`)でヘッドレスに実行し、Lua実行時エラー
(`attempt to call a nil value`等)が出ていないこと、既存表示項目・
ネットワーク表示・ウィンドウスナップ表示が実際にレンダリングされる
こと、Down:/Up:のラベルの後に値が空欄のまま残っていないこと(または
「未接続」表示になっていること)を確認するオプションスクリプトを
追加した。

- **4つの必須ローカルテストスイートには含まれていない**
  (`tests/persistence`・`tests/edition-build`・`tests/desktop-polish`
  ・`tests/usb-persistence-image`のいずれでもない)。
- `tests/desktop-polish/run.sh`からは呼び出されない。CI
  (`.github/workflows/`)からも実行されない。
- 実conkyバイナリが必要。CI環境や素の`git checkout`直後には
  `chroot/`(ビルド生成物、Git管理外)が存在しないため、その場合は
  何もエラーにせず`SKIP`して終了する(exit 0)。
- ローカルで`./scripts/build.sh`を実行済みの場合、
  `chroot/usr/bin/conky`と、不足する共有ライブラリ
  (`liblua5.3-0`・`libimlib2t64`)を`cache/packages.chroot/`(同じく
  Git管理外のパッケージキャッシュ)の.debから一時ディレクトリへ
  展開して(`dpkg-deb -x`、システムへのインストール・sudoは一切
  使わない)実行を試みる。
- **3回目の不具合(Conkyの起動タイミング/初期化問題、後述)の再現・
  検出はこのスクリプトには含めていない。** 実際のNetworkManager接続
  状態遷移(未接続→接続確立)を必要とし、ヘッドレスな一時プロセス実行
  だけでは安全に再現できないため。この不具合への対応
  (`01-mypocketos-conky-restart`)自体の検証は
  `test_conky_network_restart.sh`(モック`pgrep`/`runuser` + 実プロセス/
  実`/proc/<pid>/environ`)で行っている。

手動実行方法:

```sh
tests/desktop-polish/optional_conky_runtime_smoke.sh
```

## production整合性への影響

このディレクトリのテストは、`config/includes.chroot/usr/local/bin/
mypocketos-persistence-setup`・`.../mypocketos-persistence-setup-helper`・
`scripts/build-usb-persistence-image.sh`のいずれにも触れない
(読み込みもしない)。既存の`tests/persistence/`・
`tests/usb-persistence-image/`とは完全に独立している。
