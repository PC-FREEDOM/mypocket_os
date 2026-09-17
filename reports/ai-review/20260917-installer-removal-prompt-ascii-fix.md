# インストールメディア取り外し案内の文字化け修正 (2026-09-17)

対象branch: `feat/calamares-install-spike`

## 1. 原因(実地確認、確認済みとして受領)

実機VMでUEFI Live起動→Calamaresインストール成功→「今すぐ再起動」→
`mypocketos-installer-reboot`→marker作成→shutdown hook発火→Enter待ち
→boot orderによるInstalled system起動、という一連の機能動作は全て
正常であることを確認済み。

問題は表示のみ: shutdown最終段階のLinux consoleに表示される案内文の
うち、日本語部分が「♦」等に文字化けしていた。英数字部分
(`MyPocketOS`・`Enter`等)は正常表示されていた。この段階のconsoleには
CJKフォントが読み込まれていないことが原因と判断された。

## 2. 変更ファイル

- `config/includes.chroot/usr/lib/systemd/system-shutdown/
  mypocketos-install-media-removal`(案内文`_MSG`のみ変更、
  変更理由を説明するヘッダーコメントを追加)
- `tests/desktop-polish/test_installer_media_removal.sh`
  (ASCII文面確認テストを追加)

marker作成ロジック・reboot-only guard・device detection・USB判定・
eject処理・Plymouth判定ロジック・Enter待ちロジックはいずれも無変更
(`git diff`で確認済み、後述6章)。`finished.conf`・
`mypocketos-installer-reboot`・`shellprocess-livepurge.conf`・
`auto/config`・boot order・`scripts/create-test-vm.sh`・Persistence
production・package listもすべて無変更。

## 3. 変更前文面

```
MyPocketOS のインストールが完了しました。

インストールメディアを取り外してください。
取り外したら Enter キーを押してください。
```

## 4. 変更後文面

```
MyPocketOS installation is complete.

Please remove the installation media.
Then press Enter to continue.
```

Plymouth分岐・console fallback分岐とも同一の`_MSG`変数を参照している
ため(変更前から共通、今回もこの構造は維持)、両分岐で同じ英語文面が
使われる。

## 5. ロジック無変更確認(確認済み、`git diff`で直接確認)

`config/includes.chroot/usr/lib/systemd/system-shutdown/
mypocketos-install-media-removal`の差分は以下の2箇所のみ:

1. ヘッダーコメントへの追記(今回の変更理由の説明、実コードへの影響なし)
2. `_MSG='...'`の文字列リテラル部分のみ

`set -u`以降の実行コード(`[ "${1:-}" = "reboot" ]`のガード、marker
存在確認、`findmnt`によるデバイス特定、`sd*`+usbサブシステム判定、
`eject -p -m`呼び出し、`plymouth`/`console`分岐の条件式、
`read -r`によるEnter待ち、`wait`)は1文字も変更していない。

## 6. test結果(確認済み、本AI実施)

`tests/desktop-polish/test_installer_media_removal.sh`に以下を追加
(34→40シナリオ):

- production script側`_MSG`リテラルが期待する英語文面
  (`MyPocketOS installation is complete.`)を含むこと(静的grep)。
- production scriptのコメント行を除いた実コード部分(=案内文を含む)が
  ASCII文字のみであること(コメント自体は説明用に日本語のまま維持して
  よいため、コメント行を除外した上で確認)。
- 実際にshutdown hookを実行して得られたconsole出力(scenario G:
  reboot+marker+デバイス解決成功時)に、期待する3行の英語文面が
  そのまま含まれること、かつASCII以外の文字が一切含まれないこと。

```
$ ./tests/desktop-polish/test_installer_media_removal.sh
SCENARIOS=40 PASS=40 FAIL=0

$ sh tests/desktop-polish/run.sh
(14サブスイート全PASS、既存シナリオに回帰なし)

$ sh tests/persistence/run.sh
GUI suite exit=0 / helper suite exit=0 / failure-matrix suite exit=0 /
helper same-usb suite exit=0 / GUI same-usb suite exit=0 / overall=0
(production GUI/helper SHA-256: unchanged)

$ sh tests/edition-build/run.sh
package_lists=0 media_label=0 build=0 update_iso=0 create_vm=0 overall=0
(scripts SHA-256: unchanged)

$ sh tests/usb-persistence-image/run.sh
direct suite exit=0 / mocked suite exit=0 / overall=0
(production build-usb-persistence-image.sh SHA-256: unchanged)

$ git diff --check
(exit=0、出力なし)
```

いずれも失敗なし。

## 7. Persistence無変更確認(確認済み)

`git status -sb`で変更ファイル一覧を確認したところ、Persistence関連
ファイルは一覧に現れない(意図しないdiffなし)。加えて
`tests/persistence/run.sh`自身の「production integrity (post-run)」
SHA-256照合もPASS。

## 8. commit hash

`7679d96`(`fix: use ascii installer removal prompt`)

## 9. push結果

成功(`7ea7d44..7679d96 feat/calamares-install-spike ->
feat/calamares-install-spike`)。main mergeなし。

## 10. 人間によるVM実地確認結果 (2026-09-17)

### 10.1 UEFI VM確認

2026-09-17、人間側でStandard ISO(`mypocketos-standard-amd64.hybrid.iso`)
を再ビルドし、QEMU/KVMのUEFIテストVM(`mypocketos-uefi-test`、
[20260916-test-vm-boot-order-fix.md](20260916-test-vm-boot-order-fix.md)
で導入した新boot order: vda=boot.order 1、CD-ROM=boot.order 2で
作成済み)を用いて、以下の一連の流れをエンドツーエンドで実地確認した。

1. UEFI VMでLive ISO起動。
2. 空のvdaがboot.order=1であっても起動不能のためCD-ROMへ自動
   フォールバックし、MyPocketOS Liveが正常起動。
3. Calamaresを起動。
4. インストール正常完了。
5. finished画面で「今すぐ再起動」をONのまま実行。
6. `mypocketos-installer-reboot`が動作。
7. volatile marker(`/run/mypocketos/install-complete-reboot`)を使う
   設計のshutdown hookが発火。
8. shutdown最終段階でインストールメディア取り外し案内が表示。
9. (本reportで修正した)ASCII英語版の案内文が、文字化けせず正常表示
   されることを確認。画面上で確認した実際の文面:
   ```
   MyPocketOS installation is complete.

   Please remove the installation media.
   Then press Enter to continue.
   ```
10. Enter入力待ちが正常に動作。
11. Enter入力後に再起動。
12. ISOが仮想CD-ROM側に残っている状態でも、boot orderによりvdaが
    優先され、Installed systemが正常起動。
13. Installed側のログイン画面まで正常到達。

**UEFI VMで確認済みとして記録する項目:**

- ASCII英語案内が文字化けせず表示される。
- shutdown hookがCalamares完了後(「今すぐ再起動」実行時)に発火する。
- Enter待ちが機能する。
- Enter後に再起動する。
- boot order変更(vda=1/CD-ROM=2)によりInstalled systemへ正常起動する。
- ISOが仮想CD-ROMに残っていてもLiveへ戻らない。
- UEFI VMでのエンドツーエンド成功(Live起動→インストール→
  「今すぐ再起動」→marker→shutdown hook→ASCII英語案内→Enter→
  reboot→Installed system起動→ログイン画面到達)。

### 10.2 BIOS VM確認 (2026-09-17追記)

同日、人間側でQEMU/KVMのBIOSテストVM(`mypocketos-test`、firmware:
BIOS、新boot order: vda=boot.order 1、CD-ROM=boot.order 2で新規作成)を
用いて、UEFI VMと同一のエンドツーエンド確認を実施した。使用ISOは
UEFI確認と同じ`mypocketos-standard-amd64.hybrid.iso`。

1. BIOS VMを新規作成。
2. 生成されたVM XMLで vda=boot.order 1、CD-ROM=boot.order 2を確認。
3. 空のvdaがboot.order=1でも起動不能のため、CD-ROMへフォールバック。
4. MyPocketOS LiveのBIOS boot menuが正常表示。
5. Normal Live起動。
6. Calamaresを起動。
7. 自動パーティショニングでインストール実行。
8. インストール正常完了。
9. finished画面で「今すぐ再起動」をONのまま実行。
10. `mypocketos-installer-reboot`が動作。
11. shutdown hookが発火。
12. shutdown最終段階でASCII英語案内が文字化けせず正常表示
    (UEFI確認時と同一文面)。
13. Enter入力待ちが正常に機能。
14. Enter入力後に再起動。
15. ISOが仮想CD-ROM側に残っている状態でも、boot orderによりvdaが
    優先起動。
16. Installed systemが正常起動。
17. Installed側のログイン画面まで正常到達。
18. ログイン後、Conkyの起動モード表示が`Installed`となることを確認。
19. Installed側のjgmenu「システム」カテゴリに、Calamares関連の
    インストール項目が表示されないことも確認。

**BIOS VMで新たに確認済みとして記録する項目:**

- BIOS VMで空vda→CD-ROMフォールバック成功。
- BIOS VMでLive ISO起動成功。
- BIOS VMでCalamares install成功。
- Calamares完了後のshutdown hook発火。
- ASCII英語案内の正常表示。
- Enter待ち。
- Enter後reboot。
- boot orderによるInstalled system優先起動。
- Installed systemのログイン画面到達。
- ログイン後の起動モード`Installed`。
- Installed側でCalamaresメニュー項目が非表示
  (2026-09-16の`mypocketos-installer-menu-state`修正の効果を
  BIOS VMでも確認)。

### 10.3 VM総合結果(UEFI + BIOS)

UEFI VM(10.1節)・BIOS VM(10.2節)の両方でエンドツーエンド確認が
成功した。QEMU/KVM VMでは以下のとおり整理してよい。

| firmware | 結果 |
|---|---|
| UEFI | エンドツーエンド成功 |
| BIOS | エンドツーエンド成功 |

両firmwareに共通して確認済みの流れ:

```
Live起動 → Calamares install → 今すぐ再起動 → marker →
shutdown hook → ASCII英語案内 → Enter → reboot → Installed system起動
```

### QEMU/KVMのejectについて(重要な精査結果、UEFI/BIOS共通)

UEFI VMでの切り分けにより、以下の事実を確認した(BIOS VMでも同じ
boot order制御の仕組みで動作しており、この整理に変更はない)。

- ゲスト内のLiveメディアは`/dev/sr0`。
- `findmnt -Un -o SOURCE /run/live/medium`で`/dev/sr0`を確認。
- `eject -v -n /dev/sr0`はCD-ROMとして正常に認識した。
- **しかし、libvirt側のドメインXMLではISO sourceが割り当てられたまま
  残っていた。** すなわち、ゲスト内からのeject操作だけでは、
  libvirt/QEMU側の仮想CD-ROMドライブからISOイメージの割り当て自体を
  解除する(ドライブを空にする)ことは、今回のv1では達成できていない。

したがって、正確には**「ejectが完全に成功した」とは言えない**。
正しい記録は次のとおり:

**ISO割り当て自体はlibvirt側に残ったままだが、boot order変更
(vda=1/CD-ROM=2)によって、Installed systemが優先起動することを
実地確認した(UEFI・BIOS両方)。** 今回のInstalled system起動は、
eject成功によるものではなく、boot order変更による優先度制御の効果
である。

### 10.4 物理USB実機確認 (2026-09-17追記)

同日、人間側で物理実機を用いた物理USBメディアでのエンドツーエンド
確認を実施した。

**使用実機:**
- Fujitsu FMVU1400MP
- Intel Core i5-7300U
- RAM 12GB
- Intel HD Graphics 620

**使用メディア:** 物理USBメモリ、MyPocketOS Standard ISO。

確認した流れ:

1. 物理USBからMyPocketOS Liveを起動。
2. Calamaresでインストールを実行。
3. インストールが正常完了。
4. finished画面で「今すぐ再起動」をONのまま実行。
5. shutdown処理へ移行。
6. 物理実機のLinux consoleで、以下のASCII英語案内が文字化けせず表示
   された(UEFI/BIOS VMと同一文面)。
   ```
   MyPocketOS installation is complete.

   Please remove the installation media.
   Then press Enter to continue.
   ```
7. USBメモリを物理的に取り外した。
8. console上でUSB disconnectが確認できた。
9. Enterキーを押した。
10. 再起動が正常に進行した。
11. USBメモリを外した状態で、内蔵SSD上のInstalled systemが正常起動
    した。
12. デスクトップ到達後、Conkyの起動モード表示が`Installed`である
    ことを確認した。

**物理USB実機で新たに確認済みとして記録する項目:**

- 物理USB実機でのremove-media案内の表示(文字化けなし)。
- USB取り外し後のEnter入力→Installed system起動。

正確な流れとして記録する:

```
Live起動 → Calamares install → 今すぐ再起動 → shutdown hook →
ASCII英語案内 → 物理USB取り外し → Enter → reboot →
Installed system起動 → Conky "Installed"
```

これにより、これまでVM(QEMU/KVM、10.1〜10.3節)でのみ確認されて
いたremove-media UXの核心部分(marker駆動のshutdown hook発火・ASCII
英語案内の正常表示・Enter待ち・reboot後のInstalled system起動)が、
初めて物理実機・物理USBメディアの組み合わせでも実地確認された。

**観測事項(原因断定・修正は今回行わない):**

shutdown処理中、以下のようなsystemd-shutdown関連メッセージが複数回
表示された。

- `Failed to unmount ... Device or resource busy`
- `Could not stop ...`
- loop device関連の停止処理メッセージ

これらのメッセージは表示されたものの、今回の実地結果では
remove-media案内の表示・USB取り外し検知・Enter待ち・再起動・
Installed system起動のいずれも正常に完了しており、**現時点では
実動作を阻害する不具合としては確認されていない**。これらのメッセージ
自体がLive環境のoverlay/squashfs構成に起因する一般的なshutdown時の
ログ(本機能追加以前から発生していた可能性を含む)なのか、本機能
(marker駆動のshutdown hook)に起因するものなのかは、今回切り分けて
おらず**未確認**。原因調査・対応は本reportのスコープ外とし、今後の
課題として記録するに留める。

## 11. 依然として未確認のもの

UEFI VM(10.1節)・BIOS VM(10.2節)・物理USB実機(10.4節)の実地確認
により、以下2項目は確認済みへ移った(削除):

- ~~物理USB実機でのremove-media案内の表示~~ → 10.4節で確認済み。
- ~~物理USBでのEnter入力後のInstalled system起動~~ →
  10.4節で確認済み。

以下は今回もその対象外であり、引き続き未確認のまま残っている。

- 物理光学ドライブでの動作。
- 90秒のsystemd-shutdown安全タイムアウトを超過した場合の挙動。
- Plymouthが実際に有効な環境(本確認では該当せず、console fallback
  経路のみを確認)での表示。
- v1.1(デバイス種別によるverbose抑制、QEMU/KVMでの完全自動eject)。
- libvirt側のISO source自体を自動的に解除する仕組み(上記のとおり
  今回のv1では未達成であり、boot order変更による代替策で実用上の
  目的を達成している)。

## 12. ISO / VM(今回のreport更新時点での状況)

本AI(このセッション)自身によるISO build・VM操作・sudoの実行は、
本reportのどの更新時点においても一貫して**未実施**。

一方、**人間側でのISO再ビルド・QEMU/KVM VMでの実地検証(UEFI・BIOS
両方)、および物理実機(Fujitsu FMVU1400MP)・物理USBメディアでの
実地検証は2026-09-17に実施済みであり、10章のとおりいずれも成功を
確認している。** 本節を含め、本reportの過去の版にあった
「ISO/VM未実施」という記述は、あくまで本AIによる作業範囲についての
記述であり、人間側の実地検証の有無とは別軸であることに注意(11章
記載の項目は、人間側でもまだ未実施・未確認)。

## 13. 次に人間が確認すべき内容

- 物理光学ドライブでの動作。
- 90秒タイムアウト超過時の実際の挙動。
- Plymouthが実際に有効な環境での表示確認。
- v1.1(完全自動eject、libvirt側ISO source自動解除)へ進むかどうかの
  製品判断。
