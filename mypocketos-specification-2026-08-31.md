# MyPocketOS 最新統合仕様書

- 文書バージョン：1.2-draft
- 最終更新：2026-08-31
- 対象リポジトリ：`PC-FREEDOM/mypocket_os`
- 対象ブランチ：`main`
- 基準コミット：`0af37c0f3fbaaa11b0bc1d7aa75a4b48ebb2569f`（PR #18 merge commit）
- 対象リリース：初回公開候補（Base／Standard）
- 文書の目的：2026-08-30時点の全体仕様を正本として、PR #18「同一起動USBの未使用領域Persistence」を統合し、初回公開前の残作業と追加仕上げ候補を一つの基準文書に整理する

> 重要：仕様上の意図は本書、実際のコード状態は`main`を正とする。数値・バージョン・検証結果は実測・実行結果のみを記載し、未確認値を推測で補わない。

---

## 0. 状態表記

| 状態 | 意味 |
|---|---|
| 確定 | 初回公開版の仕様として採用する |
| 実装済み | `main`へ取り込み済み |
| 検証済み | 自動テスト、実ビルド、VM、実機等で確認済み |
| 要検証 | 実装済みだが、公開前に追加確認が必要 |
| 追加候補 | 初回公開までに追加したいが、未実装・未確定 |
| 将来候補 | 初回公開版には含めず、後続版で検討する |

---

# 1. 製品概要

## 1.1 名称

製品名は **MyPocketOS** とする。

## 1.2 コンセプト

> USBメモリから持ち運べて、古いPCでも軽快に使える、自分用の日本語作業環境。

MyPocketOSはDebian StableとOpenboxを基盤にした軽量ポータブルLinuxである。USB Liveとして試用・救援・日常作業に利用でき、必要に応じてユーザーデータと設定を永続保存できる。

## 1.3 参照する考え方

| 参照元 | 取り入れる要素 | 取り入れない要素 |
|---|---|---|
| Tails | USB Live、通常起動と永続起動の分離、クリーンな初期状態 | 匿名化OSとしての保証、Tor通信の強制、痕跡を残さないという保証 |
| CrunchBang++ | Debian＋Openboxの軽快さ、簡潔な画面構成 | 構成・ブランド資産の単純複製 |
| BunsenLabs | Openbox周辺の丁寧な調整、使い始めやすい初期設定 | 独自ツール・ブランド資産の無断流用 |

## 1.4 主な利用場面

- USBで持ち運ぶ個人用の作業環境
- 古いPC・低スペックPCの再利用
- PC故障時のファイル確認や救援作業
- LinuxやMyPocketOSの試用
- 必要に応じた内蔵ストレージへの通常インストール

## 1.5 初回公開版の対象外

- Tailsと同等の匿名性・反追跡性・フォレンジック耐性
- 独自カーネルや独自パッケージ管理システム
- 32bit対応
- LUKS暗号化Persistence
- システム全体を保存する`/ union`
- 追加インストールしたアプリ本体の永続化
- Creator版

---

# 2. 設計原則

| 原則 | 仕様 |
|---|---|
| Debian準拠 | Debian公式パッケージと標準機構を優先する |
| 軽量性 | Openboxを中心に常駐処理と依存関係を必要最小限にする |
| 安全側に失敗 | 判定不能・矛盾・不明状態は処理を拒否、または`Unknown`とする |
| 状態の明示 | Normal Live／Persistenceをデスクトップ上で確認可能にする |
| 再現可能性 | Git管理された設定とスクリプトから生成し、手作業ISO加工を正式工程に含めない |
| オフラインビルド | 収録済み外部資産はビルド時・Live起動時にネットワーク取得しない |
| 上流との分離 | upstream資産とMyPocketOS独自差分を明確に分離する |
| edition非破壊 | Base／Standardの一方をビルドしても他方の既存ISOを削除・更新しない |
| 回帰防止 | 検証済みproductionファイルを無関係な変更で書き換えない |
| 破壊範囲最小化 | Persistence操作は必要な領域だけを変更し、既存領域を極力不変に保つ |

---

# 3. 対象環境

| 項目 | 仕様 | 状態 |
|---|---|---|
| ベースOS | Debian 13 Stable（Trixie） | 確定 |
| アーキテクチャ | amd64／x86_64 | 確定 |
| ビルド基盤 | `live-build 20250505+deb13u1`系 | 実装済み |
| イメージ形式 | ISO Hybrid | 実装済み |
| Legacy BIOS | 対応 | 実USB検証済み |
| 64-bit UEFI | 対応予定 | VM確認済み、実USB要検証 |
| Secure Boot | 対応可否を公開前に実機確認し明記 | 要検証 |
| ロケール | `ja_JP.UTF-8` | 実装済み |
| タイムゾーン | `Asia/Tokyo` | 実装済み |
| キーボード | 日本語配列 | 実装済み |
| 日本語入力 | IBus＋Mozc | 実装済み |
| 最小USB容量 | 16GB | 暫定確定 |
| 推奨USB容量 | 32GB以上 | 推奨値 |
| 内蔵インストール容量 | 8GB以上 | 暫定推奨 |
| 最低RAM | 固定条件で実測後に確定 | 未確定 |

注：同一USB Persistenceの実機E2Eには7.5GB USBを使用して成功しているが、公開時の最小USB容量表記は現時点では16GBのままとする。

---

# 4. エディション

## 4.1 構成原則

```text
Base
  = common

Standard
  = common + standard

将来のCreator
  = common + standard + creator
```

package-listの正本は`config/package-lists.d/`に置く。`config/package-lists/`はlive-build向けの一時配置先とし、build終了・失敗・SIGINT時にcleanupする。

## 4.2 Base

正本：

```text
config/package-lists.d/mypocketos-common.list.chroot
```

正式ビルド：

```bash
./scripts/build.sh base
```

生成物：

```text
mypocketos-base-amd64.hybrid.iso
```

2026-08-30実測：

```text
1,428,750,336 bytes
約1.33 GiB
```

Standard専用のFirefox、LibreOffice、Drawing、Mousepad、Galculatorは含めない。

## 4.3 Standard

正本：

```text
config/package-lists.d/mypocketos-standard.list.chroot
```

追加パッケージ：

| 分類 | パッケージ |
|---|---|
| Webブラウザー | `firefox-esr`、`firefox-esr-l10n-ja` |
| オフィス | `libreoffice-writer`、`libreoffice-calc`、`libreoffice-impress`、`libreoffice-draw` |
| LibreOffice統合・日本語 | `libreoffice-gtk3`、`libreoffice-l10n-ja`、`libreoffice-help-ja` |
| 簡易描画 | `drawing` |
| テキスト編集 | `mousepad` |
| 電卓 | `galculator` |

正式ビルド：

```bash
./scripts/build.sh standard
```

生成物：

```text
mypocketos-standard-amd64.hybrid.iso
```

2026-08-30実測：

```text
1,788,149,760 bytes
約1.67 GiB
```

Baseとの差：

```text
359,399,424 bytes
約343 MiB
```

## 4.4 edition分離の検証済み事項

- Baseビルド時に既存Standard ISOのsize・SHA-256・mtimeが不変
- Standardビルド時に既存Base ISOのsize・SHA-256・mtimeが不変
- BaseではStandard専用12パッケージが不在
- StandardではStandard専用12パッケージがインストール済み
- edition一時package-listがbuild後に残留しない
- ISO名はedition別
- buildによるGit管理対象の汚染なし

---

# 5. デスクトップ仕様

| 役割 | 採用 | 状態 |
|---|---|---|
| ウィンドウマネージャー | Openbox | 実装済み |
| パネル | tint2 | 実装済み |
| アプリメニュー | jgmenu | 実装済み |
| ファイル管理 | PCManFM | 実装済み |
| 端末 | LXTerminal | 実装済み |
| システム情報 | Conky（conky-std） | 実装済み |
| ログイン | LightDM | 実装済み |
| ネットワーク | NetworkManager | 実装済み |
| 音声 | PipeWire／WirePlumber＋pasystray | 実装済み |
| パッケージ管理 | APT（CLI。Synaptic等GUIフロントエンドは未搭載） | 実装済み |
| 追加アプリ導入 | Flatpak（`flatpak --user`推奨） | 実装済み |

## 5.1 UI原則

- 右クリックだけに依存せず、tint2メニューボタンからアプリへ到達可能にする
- 黒系パネル上のトレイアイコンは22px前後でも状態を判別できること
- アイコン調整のためGTK/Openboxテーマを不要に変更しない
- ユーザーが後から別アイコンテーマへ変更できる標準構成を維持する
- 見た目より文字と状態の判読性を優先する

## 5.2 初回公開前の追加UX候補

消音アイコンの「スピーカー＋×」化（PR #31）・tint2電源管理／バッテリー％
表示（PR #32）・最初に表示される画面のDebian表記のMyPocketOS化（PR #30、
7.3節参照）は、いずれも実装済みのためこの候補一覧から除外した。

### 優先度高
- Openboxのウィンドウスナップ
  - `Super + Left`：左半分
  - `Super + Right`：右半分
  - `Super + Up`：最大化
  - `Super + Down`：最大化解除

### 優先度中
- Persistence領域が存在する場合、起動メニューでPersistenceを既定選択にできるか検討

---

# 6. アイコンテーマ

## 6.1 継承

```text
MyPocketOS
  └─ MyPocketOS-Fluent-yellow
       └─ Adwaita
            └─ hicolor
```

`MyPocketOS/index.theme`：

```ini
Inherits=MyPocketOS-Fluent-yellow,Adwaita,hicolor
```

GTK2/GTK3双方で`MyPocketOS`を既定アイコンテーマとする。

## 6.2 Fluent派生サブセット

| 項目 | 仕様 |
|---|---|
| upstream | `vinceliuice/Fluent-icon-theme` |
| タグ | `2026-07-27` |
| コミット | `c70c2441bcf2ab8bbc267e55635c76d69f659a8b` |
| 取得時tarball SHA-256 | `7fdd60faa543b297ef2d4f3d083d8b382e59a9b0933cbb1dfc042539d45036e2` |
| Git収録archive SHA-256 | `7cbeced29d1e3377ddba6cd59e2b12ef0adc7cc15c368ecafdd256bcad327a38` |
| ライセンス | GPL-3.0 |
| 派生テーマ | `MyPocketOS-Fluent-yellow` |

## 6.3 pasystray音量アイコン

- `audio-volume-muted`
- `audio-volume-low`
- `audio-volume-medium`
- `audio-volume-high`

非symbolic名を要求するpasystrayへ対応済み。

`audio-volume-muted`は、スピーカー形状＋交差する2本の直線による「×」表現へ
変更済み（PR #31）。

---

# 7. 起動仕様

## 7.1 起動項目

| 表示名 | カーネルパラメーター | 用途 |
|---|---|---|
| `MyPocketOS Live` | `nopersistence` | 保存しない通常Live |
| `MyPocketOS Live (Persistence)` | `persistence` | Persistence利用Live |
| `MyPocketOS Live (Fail-safe)` | Fail-safe設定 | 互換性問題時 |

Normal LiveとPersistenceは明示的に分離する。

## 7.2 Conkyの起動モード

- `Normal Live`
- `Persistence`
- `Unknown`

`/proc/cmdline`を完全一致トークンで判定し、曖昧・重複・不明は`Unknown`へ倒す。

## 7.3 ブランド表示の残課題(対応済み)

PR #30（`auto/config`の`--iso-volume`／`--iso-application`／
`--iso-publisher`／`--hdd-label`をMyPocketOS表記へ変更）で対応済み。
実際にビルドしたISOファイルのPrimary Volume Descriptorで
`Volume Id: MyPocketOS ...`となることを実機確認済み（詳細はPR #30本文・
README.mdの該当節を参照）。

- ✅ ISO/USB Volume IDをMyPocketOS表記へ変更
- ✅ 起動直後の最初のブート画面に残るDebian表記をMyPocketOS表記へ変更
  （PR #30調査時点で、ブートローダーメニュー(GRUB/Syslinux)は既に
  `MyPocketOS Live`表記であることを確認済みであり、Debian表記が残って
  いた唯一の箇所はISO Volume ID（BIOS/UEFIの起動デバイス選択画面等で
  表示され得る）だったため、上記の対応で解消したと判断する）

---

# 8. Live永続化

## 8.1 共通Persistenceモデル

| 項目 | 仕様 |
|---|---|
| 基盤 | Debian live-boot persistence |
| ファイルシステム | ext4 |
| ラベル | `persistence` |
| 設定ファイル | パーティションルートの`persistence.conf` |
| 現行設定 | `/home`と`/etc/NetworkManager/system-connections`の2行 (いずれもオプションなしのデフォルトbindマウント、独立したcustom mount) |
| 現行保存対象 | `/home`配下のユーザーデータ・一般アプリ設定、およびNetworkManagerのWi-Fi接続プロファイル (SSID・PSK等) |
| 非保存 | 追加アプリ本体、APTキャッシュ、カーネル、基本システム |
| 暗号化 | 初回公開版ではなし |
| `/ union` | 採用しない |

Wi-Fi／NetworkManager設定のPersistenceは実装済み。2026-09-02、Mode B(同一起動USB)・実機・Legacy/UEFI未特定の環境で、Persistence起動時のWi-Fi再起動後自動接続・`/etc/NetworkManager/system-connections`のPersistenceマウント・接続プロファイルの`root:root`/`0600`・Normal Liveでの非表示・`/home`保持への非回帰を確認済み(詳細は17節)。Mode A・USB persistence IMG経由、UEFI環境、Secure Boot環境、複数Wi-Fiプロファイルでの動作は未確認のまま残っている。認証情報が無暗号化のまま保存される点の注意は14節を参照。

## 8.2 Persistence Setup

GUI：

```text
/usr/local/bin/mypocketos-persistence-setup
```

root helper：

```text
/usr/local/libexec/mypocketos-persistence-setup-helper
```

GUIは一般ユーザー権限で予備選別し、破壊的操作直前にroot helperが独立再検証する。

## 8.3 Mode A：別の完全未使用ディスク全体

既存方式。

対象：
- 完全に未使用の別ディスク全体

主な除外：
- Live起動元
- `/home`提供元
- 既存partitionあり
- mount中／swap中
- read-only
- loop / mapper / RAID / 不明デバイス
- 既存`LABEL=persistence`または`PARTLABEL=persistence`

処理：
1. GPT作成
2. 全領域partition作成
3. ext4
4. `LABEL=persistence`
5. `persistence.conf`
6. sync
7. unmount

clean BIOS VMでE2E検証済み。

## 8.4 Mode B：MyPocketOS起動USB自身の末尾未使用領域

PR #18で`main`へ実装済み。

目的：

> ISOを書き込んだ1本のUSBだけで、MyPocketOS起動領域を維持したまま残りの空き領域をPersistenceとして利用する。

### 対象条件

- MyPocketOS Liveの起動元USBそのもの
- USB transportを安全に確認可能
- DOS/MBR Hybrid ISOとして解析可能
- 既存partition構成を厳格に取得可能
- ディスク末尾に連続した未使用領域が存在
- 最低1GiB以上の末尾空き
- primary partitionスロットが利用可能
- 既存Persistence label/partlabelが存在しない
- read-onlyでない
- 判定不能は拒否

GPT Hybrid等へ無理に一般化しない。

### 未使用領域

- 既存partition間の穴は使わない
- 既存partitionを縮小・移動しない
- 全既存partitionの最大終端より後ろだけを使う
- 1MiB alignment
- 1GiB未満は拒否
- 2GiB以上を推奨

### 実機Hybrid ISO構造

```text
/dev/sda1 start=64  size=3492416  type=0  bootable
/dev/sda2 start=540 size=6656     type=ef
```

`sda2`は数値上`sda1`内部に重なるHybrid ISO特有の構造。

### partition table更新

```text
sfdisk
  --lock=yes
  --backup
  -O <temp>
  --no-reread
  --no-tell-kernel
  --append
      ↓
disk上の既存partition不変性確認
      ↓
新規partition番号をdump差分から特定
      ↓
partx --add --nr N DEVICE
      ↓
udevadm settle
      ↓
lsblkで新規partition出現確認
      ↓
geometry再確認
      ↓
mkfs.ext4
      ↓
LABEL=persistence
      ↓
persistence.conf
      ↓
sync / unmount
```

`--force`は使用しない。Mode Bでは`partprobe`による全partition再読込を行わない。

### 安全要件

- GUI判定をhelperが信用せず再検証
- DEVICE＋MAJOR:MINOR再照合
- partition table、disk size、未使用領域を破壊直前に再確認
- `sfdisk --append`前後で既存partitionを比較
- 新partition geometryをmkfs前に検証
- partx/udevadm/lsblk確認を通過するまでmkfsしない
- 自動ロールバックしない
- sfdisk失敗時はdisk stateを`unchanged`/`changed`/`unknown`として診断
- disk更新済みだがkernel登録失敗時はmkfsせず停止し、再起動後に状態確認を案内

### GUI

Mode AとMode Bを明確に区別する。

Mode B例：

```text
MyPocketOS 起動USB
空き容量 約5.8GiB
```

表示用列と内部識別値を分離し、yad hidden columnで実DEVICE／実MAJ:MIN／mode種別を保持する。

## 8.5 Mode B Legacy BIOS実機E2E

2026-08-31、VAIO実機でStandard版を検証。

```text
VAIO VJPG11C11N
Intel Core i5-8250U
RAM 約7.7GiB
Intel UHD Graphics 620
Qualcomm Atheros QCA6174 Wi-Fi
Realtek Ethernet
```

検証結果：
- Legacy BIOS実USB起動：PASS
- 起動メニュー3項目：PASS
- Normal Live：PASS
- 同一起動USB候補検出：PASS
- 内蔵NVMe除外：PASS
- 約5.8GiB末尾未使用領域検出：PASS
- sda3追加：PASS
- sda1/sda2不変：PASS
- ext4：PASS
- `LABEL=persistence`：PASS
- `persistence.conf=/home`：PASS
- `root:root` / `0600`：PASS
- Persistence起動：PASS
- `/home`保存：PASS
- Persistence再起動後保持：PASS
- Normal Liveでは非表示：PASS
- 再Persistenceで再表示：PASS
- Conky Normal Live／Persistence表示：PASS
- 正常シャットダウン：PASS

**Mode BはLegacy BIOS実機E2Eまで検証済み。**

UEFIでのMode B作成後起動は未検証。

## 8.6 USB persistence IMG生成

`scripts/build-usb-persistence-image.sh`により単一IMGを生成できる。

- 元ISOを変更しない
- block device / symlink / FIFOを入出力にしない
- 暗黙上書きしない
- 一時領域で生成・検証し成功後だけ最終名へ移動
- sudo / loop mount / 実デバイス書込み不要
- 生成物はGit管理しない
- 公開用Persistence容量は2GiBを第一候補

## 8.7 将来候補

- LUKS暗号化
- 既存Persistence領域管理
- 選択式Persistence
- 追加アプリ再導入

「起動USBの未使用領域利用」はPR #18で実装済みのため将来候補から除外する。

---

# 9. メニュー仕様

## 9.1 tint2
既存`jgmenu_run`を維持。

## 9.2 デスクトップ右クリック

```text
jgmenu_run apps | jgmenu --at-pointer --simple
```

Base／Standard VM確認済み。

---

# 10. 通常インストール

初回公開版ではDebian Installerのlive導入経路を基準とする。

- Liveセッション一時変更を暗黙コピーしない
- Persistence内ユーザーデータを暗黙コピーしない

Calamaresは将来候補。

通常インストールを公開機能として明記する場合、リリース前に最終E2Eを実施する。

---

# 11. ビルド仕様

## 11.1 基本

- `live-build`
- `--mode debian`
- amd64
- Trixie
- `debian-installer live`
- 設定/package-list/includes/hooks/testsをGit管理
- ISO手作業再加工は正式工程に含めない
- ISO/IMG/binary/build log/VM diskはGit管理しない

## 11.2 edition選択

```bash
./scripts/build.sh base
./scripts/build.sh standard
```

## 11.3 `lb clean`

```text
lb config --image-name mypocketos-${EDITION}
sudo lb clean
lb config --image-name mypocketos-${EDITION}
sudo lb build
```

他edition ISOには触れない。

## 11.4 テストISO更新

```bash
./scripts/update-test-iso.sh base
./scripts/update-test-iso.sh standard
```

## 11.5 VM作成

```bash
./scripts/create-test-vm.sh base
./scripts/create-test-vm.sh standard
./scripts/create-test-vm.sh --firmware uefi base
./scripts/create-test-vm.sh --firmware uefi standard
```

---

# 12. テスト仕様

## 12.1 継続対象

| テスト群 | 対象 |
|---|---|
| edition-build | package-list分離、build順序、LB_IMAGE_NAME、ISO非破壊等 |
| desktop-polish | 起動モード、メニュー、アイコン、Standardパッケージ等 |
| persistence | Mode A／Mode B GUI・helper、安全判定、失敗行列、回帰 |
| USB persistence IMG | 引数、安全条件、生成・検証、production不変 |
| static checks | shell/XML/実行bit/trailing whitespace等 |

## 12.2 2026-08-30基準

```text
edition-build           136/136 PASS
desktop-polish          137/137 PASS
persistence             310/310 PASS
usb-persistence-image    94/94 PASS
```

## 12.3 PR #18 merge時の最新報告(再検証済み・最終値)

```text
edition-build           136/136 PASS
desktop-polish          137/137 PASS
usb-persistence-image    94/94 PASS
Mode B helper same-usb   97/97 PASS
Mode B GUI same-usb      24/24 PASS
Mode A                   全PASS
git diff --check         PASS
static checks            PASS
```

以前の101/101、65/65という報告は、ログをtailで切り詰めたことによる
報告上の集計ミスであり、テストケースの削除・減少・回帰はなかった。

---

# 13. 回帰防止対象

PR #18 merge後：

| ファイル | SHA-256 |
|---|---|
| `config/includes.chroot/usr/local/bin/mypocketos-persistence-setup` | `4a1215c7900783819499e2e4323f75721032bf74b3a5def54a02689180fb3597` |
| `config/includes.chroot/usr/local/libexec/mypocketos-persistence-setup-helper` | `8cdbfeb7228f7098c7568e8a046d5535c24f17ae58e87a15b2cb676552b11154` |
| `scripts/build-usb-persistence-image.sh` | `401a33eacaf9bb34bae0ec9ab62cc50a77aff4a354f9d97e6b9d54a9096ff88d` |

Fluent archive：

```text
7cbeced29d1e3377ddba6cd59e2b12ef0adc7cc15c368ecafdd256bcad327a38
```

---

# 14. ライセンスと配布表現

- Debianおよび収録パッケージのライセンスに従う
- Fluent派生はGPL-3.0本文と変更記録を同梱
- MyPocketOS独自資産とupstream資産を区別
- 「匿名OS」「痕跡を残さない」「Tailsと同等に安全」と表現しない
- Liveでも内蔵ストレージを手動mountすれば書込みが起こり得る
- Persistenceは初回版では暗号化されない
- Persistence USBを紛失・盗難された場合、`/home`の内容に加えて
  `/etc/NetworkManager/system-connections`配下に保存されたWi-Fi接続の
  認証情報 (PSK等) も無暗号化のまま読み取られ得ることを利用者へ明示する
  (8.1節)
- 保存範囲を実装済み仕様に合わせて正確に説明
- ISO／IMGへSHA-256を提供
- 未実施の確認を「確認済み」と記載しない

---

# 15. 現在の基準状態

```text
repository: PC-FREEDOM/mypocket_os
branch:     main
commit:     0af37c0f3fbaaa11b0bc1d7aa75a4b48ebb2569f
```

主な成立済み要素：
- Debian 13 Stable＋Openbox
- Base／Standard
- edition別ISO
- Normal Live／Persistence／Fail-safe
- `/home` Persistence
- Wi-Fi／NetworkManager設定のPersistence (Mode B実機確認済み、他経路は確認前)
- Mode A
- Mode B
- USB persistence IMG
- MyPocketOS icon theme
- pasystray独自音量SVG
- Conky起動モード
- tint2＋jgmenu
- Root右クリックjgmenu
- Standard日常アプリ
- edition対応スクリプト
- 自動回帰テスト

---

# 16. 初回公開前の残作業

## 16.1 実装・仕上げ候補

ミュートアイコン（PR #31）・tint2電源管理／バッテリー％表示（PR #32）・
ISO/USB Volume ID（PR #30）・最初のブート画面のDebian表記（PR #30、
7.3節参照）は、いずれも実装済みのためこの候補一覧から除外した。

1. Openbox `Super + 矢印` ウィンドウスナップ
2. Persistence存在時の起動既定選択を検討

原則1機能1feature branch。

## 16.2 実機・互換性

- UEFI実USB起動
- Persistence作成済みUSBでUEFI起動
- UEFI起動メニュー3項目
- Secure Boot
- 最低RAM
- 必要に応じDebian Installer E2E
- Wi-Fi／NetworkManager設定のPersistence VM/実機動作確認 (Mode Bは2026-09-02に実機確認済み。Mode A／USB persistence IMG経由、UEFI環境、Secure Boot環境、複数Wi-Fiプロファイルは未確認のまま、8.1節参照)

## 16.3 配布仕様

- Persistence IMG容量最終決定
- 最小／推奨USB容量
- 最終ISO容量
- Release Notes
- Known Issues
- ライセンス／third-party attribution
- USB書き込み手順
- Persistence説明
- 最終ISO/IMG SHA-256

---

# 17. 初回公開版の完了条件

| 条件 | 状態 |
|---|---|
| Base／Standardビルド成功 | ✅ |
| edition切替で他ISO非破壊 | ✅ |
| Base／Standard package差 | ✅ |
| 自動テストFAIL=0 | ✅ 現行報告上 |
| GitHub CI PASS | ✅ PR #18時点 |
| Normal Live／Persistence VM | ✅ |
| Base／Standard VM E2E | ✅ |
| 実USB Legacy BIOS | ✅ |
| 実USB Mode B Persistence | ✅ |
| Persistence再起動後 `/home`保持 | ✅ |
| Normal Liveとの分離 | ✅ |
| Persistence再起動後Wi-Fi設定保持 (VM/実機) | ✅ Mode B実機、2026-09-02時点(Mode A／USB persistence IMG／UEFI／Secure Boot未確認) |
| 実USB UEFI | ⬜ |
| Persistence作成済みUSBのUEFI | ⬜ |
| Secure Boot | ⬜ |
| 最低RAM | ⬜ |
| ISO／IMG容量・USB要件 | ⬜ |
| 通常インストール最終確認 | ⬜ 必要に応じて |
| License / Known Issues / Release Notes | ⬜ |
| 最終SHA-256 | ⬜ |

---

# 18. ロードマップ

## Phase 1
- Debian 13＋Openbox
- Base／Standard
- Normal Live／Persistence／Fail-safe
- `/home` Persistence
- Wi-Fi／NetworkManager設定のPersistence
- Mode A／Mode B
- USB persistence IMG
- 日本語環境
- デスクトップ仕上げ
- Flatpak標準搭載（`flatpak --user`を追加アプリ導入の推奨方式とする。
  Flathub等remoteの自動登録は行わず、ユーザー自身が追加する）
- 実機検証
- リリース整備

## Phase 2
- LUKS
- Persistence領域管理
- 選択式Persistence
- APTパッケージ本体の永続化・再導入を含む、より高度な追加アプリ管理機能
  （Flatpak `--user`によるアプリ導入はPhase 1で実装済み。ここでの
  「再導入」は、APTで追加したパッケージ本体の永続化・システム全体への
  インストールなど、Phase 1のFlatpak方式では扱わない範囲を指す）

## Phase 3
- Calamares
- Live／Persistenceから通常インストールへの安全な移行
- インストール後Live専用機能整理

## Phase 4
- Creator版アプリ選定

---

# 19. 変更管理

仕様変更時は原則同時更新：
1. 本仕様書
2. README
3. 設定／package-list／スクリプト
4. 自動テスト
5. VM・実機確認項目
6. 必要に応じライセンス／変更記録

大きな機能はfeature branch＋PRで完結させる。PRを閉じる際はGitHub上で`MERGED`を確認後branchを削除する。

---

# 20. 基準点

## 2026-08-30

PR #17 merge commit：

```text
91625c5
```

Base／Standard基本版成立。

## 2026-08-31

PR #18 merge commit：

```text
0af37c0f3fbaaa11b0bc1d7aa75a4b48ebb2569f
```

同一起動USBの末尾未使用領域をPersistenceとして利用するMode Bをmainへ統合。

Legacy BIOS実機で、

```text
Persistence → 保存
Persistence再起動 → 保持
Normal Live → 非表示
Persistence再起動 → 再表示
```

までE2E確認した。

このcommitを初回リリース前仕上げフェーズの新しい基準点とする。
