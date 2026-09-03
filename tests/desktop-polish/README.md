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

## production整合性への影響

このディレクトリのテストは、`config/includes.chroot/usr/local/bin/
mypocketos-persistence-setup`・`.../mypocketos-persistence-setup-helper`・
`scripts/build-usb-persistence-image.sh`のいずれにも触れない
(読み込みもしない)。既存の`tests/persistence/`・
`tests/usb-persistence-image/`とは完全に独立している。
