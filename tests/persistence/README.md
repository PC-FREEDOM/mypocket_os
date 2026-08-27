# 永続領域作成GUI/helper 非破壊モックテストハーネス

`mypocketos-persistence-setup` (GUI本体) と
`mypocketos-persistence-setup-helper` (特権ヘルパー) を対象とした、
コミット可能な非破壊モックテストハーネス。

## 実行方法

```sh
tests/persistence/run.sh
```

一般ユーザー権限のみで完結する。実行に `sudo`・実`parted`・実`mkfs.ext4`・
実`mount`・実`umount`・実`sync`・VM/ISO/qcow2操作は一切必要ない。

GUI本体・helper (既存回帰)・helper失敗マトリクスをそれぞれ単体で実行する場合:

```sh
tests/persistence/test_gui.sh
tests/persistence/test_helper.sh
tests/persistence/test_helper_failure_matrix.sh
```

## 安全上の前提

- production ファイル
  (`config/includes.chroot/usr/local/bin/mypocketos-persistence-setup`,
  `config/includes.chroot/usr/local/libexec/mypocketos-persistence-setup-helper`)
  には一切書き込まない。`instrument_gui.sh`/`instrument_helper.sh` は
  常に `sed ... SRC > DEST` の形でsandbox内へ新規出力するだけであり、
  `sed -i` は使わない。
- `run.sh`・`test_gui.sh`・`test_helper.sh` はいずれも、実行前後で
  production 2ファイルの SHA-256 を比較し、不一致ならテスト結果に関わらず
  異常終了する (`common.sh` の `on_common_exit` EXIT trap)。
- 実ブロックデバイス・実`/dev`・実`/sys`・実`/proc/swaps` には一切作用
  しない。疑似`dev`/`sys`/`proc`/`run`ツリーは、`mktemp -d`でリポジトリ外に
  作成したsandboxの内側にのみ存在し、実行終了時に必ず削除される。
- `/dev/null`は出力破棄 (`>/dev/null`、`2>/dev/null`) にのみ使用する。
  疑似DEVICEとして実ホストの`/dev/null`を借用することはしない (疑似
  デバイスは常に`$SANDBOX/dev`配下の通常ファイルを使う)。
- `parted`・`mkfs.ext4`・`mount`・`umount`・`partprobe`・`udevadm`・
  `wipefs`・`sudo`・`sync`は、`mock_command.sh`が生成するモックの中で
  実バイナリへ委譲する分岐を一切持たない (完全モック)。

## ディレクトリ構成

```
tests/persistence/
  README.md              このファイル
  common.sh               共通ユーティリティ (sandbox作成、count_matches、
                           apply_rule、EXIT trapによるproduction整合性確認)
  instrument_gui.sh        GUI本体をsandbox化したコピーを生成する
  instrument_helper.sh     helperをsandbox化したコピーを生成する
  mock_command.sh          $SANDBOX/bin へ全モックコマンドを書き出す
  test_gui.sh              GUI本体のシナリオ (13件)
  test_helper.sh           helperの既存回帰シナリオ (7件、既存20シナリオ・
                           52アサーションの一部として変更しない)
  test_helper_failure_matrix.sh
                           helperの公開終了コード
                           (2, 10, 14, 15, 20〜25, 70, 71) に対する
                           決定論的な失敗マトリクス (51シナリオ・
                           258アサーション。数値はファイル自身の
                           実行結果 `SCENARIOS=`/`PASS=` 行が正とする)
  run.sh                   単一エントリポイント (GUI + helper + 失敗
                           マトリクス + 整合性確認)
  fixtures/                lsblk -P 形式の固定データセット (sandbox外、
                           コミット対象)
```

## instrument方式

`instrument_gui.sh`/`instrument_helper.sh`は、production ファイルの
コピーに対して次の2段階で置換を行う。

1. **段階1 (`apply_rule`/`apply_rule_next_line`)**: productionのリテラルを
   固定トークン (`@@SANDBOX_BIN@@`等) へ置換する。適用前に必ず
   `grep -cE`で一致件数を確認し、期待件数と一致しない場合は
   即座に失敗する ("REFUSING TO PATCH")。同一テキストが複数関数に
   出現し単純な文字列一致では一意に特定できない箇所 (`/dev/*) ;;`等) は、
   直前の一意な行をアンカーにして「次の行だけ」を置換する
   (`apply_rule_next_line`)。
2. **段階2 (`resolve_token`)**: 固定トークンを、そのテスト実行で
   実際に`mktemp -d`が生成したsandbox実パスへ解決する。

置換後、各instrumentスクリプトは次の不変条件を検証する
(いずれか1つでも満たさなければ失敗する)。

- 未解決の `@@...@@` トークンが0件。
- helperの `CMD_*` 定義が正確に19件、かつ全てsandbox bin配下。
- GUI/helperの固定PATHがsandbox binのみを指している。
- GUIの`HELPER`変数がsandbox配下を指している。
- 実システム絶対パス (`/usr/`, `/sbin/`) がコメント・shebang行以外に
  残っていない。
- メイン処理の抑止 (後続PR向け、今回は未使用) に使うマーカーコメントが
  正確に1件。

## grep終了コードの扱い

`grep -c`は「0=1件以上一致」「1=0件一致 (正常)」「2以上=grep自体の異常」
を返す。本ハーネスは`grep -cE ... || actual=0`のように一律で握り潰さず、
`count_matches`が2以上を明示的に異常終了として扱う。`set -e`下で
`grep`の失敗を正しく捕捉するため、`n="$(grep ...)" && rc=0 || rc=$?`の
形を用いる (バラの代入文は`set -e`下で失敗時に`rc=$?`へ到達できないため)。

## モックコマンドの3分類

`mock_command.sh`が`$SANDBOX/bin`へ書き出すコマンドは3分類される。

1. **読み取り専用パススルー**: `awk grep sed cut ls tail sleep`。
   実バイナリを無条件でexecする。
2. **sandbox制限ラッパー**: `mkdir rmdir rm cat mktemp`。対象パスが
   sandbox配下であることを確認したうえで実バイナリへ委譲する。
   sandbox外を指す場合は`exit 99`で拒否する。`mktemp`は戻り値も
   sandbox配下であることを再確認する。
3. **完全モック**: `lsblk findmnt id stat parted mkfs.ext4 mount umount
   partprobe udevadm wipefs sudo yad sync`。実バイナリを一切execしない。
   `id`/`stat`は既知の引数形式にのみ応答し、未知の形式は`exit 98`で
   拒否する。

失敗マトリクス (`test_helper_failure_matrix.sh`) 向けに、`rmdir`
(`MOCK_FAIL_RMDIR_LOCK`/`MOCK_FAIL_RMDIR_MNT`)・`mount`
(`MOCK_CONF_PATH_IS_DIR`)・`cat`
(`MOCK_FAKE_CONF_CONTENT`、対象は`persistence.conf`のみ) に、
既定値が未設定/0のopt-in環境変数によるフックを追加している。いずれも
未設定時の挙動は変更前と同一であり、既存20シナリオ・52アサーションには
影響しない。`MOCK_CONF_PATH_IS_DIR`は、persistence.confの書き込み失敗
(終了コード24) を再現するために、CONF_PATHの位置へ`mount`モックが
事前に空ディレクトリを作る (helper側の書き込みをchmodではなくEISDIRで
確実に失敗させる。実UID rootでの実行下でも、パーミッションに関係なく
カーネルが返すエラーのため決定論的に失敗する)。`umount`モック側は、
このディレクトリを`rmdir`で安全に取り除いてから後始末する。

`kill`は初回PRのsandbox binに意図的に配置していない。GUI本体の`kill`
呼び出し (進捗ダイアログの後始末) はいずれも`2>/dev/null || :`で
保護されており、コマンド不在 (`exit 127`) も許容される設計であることを
productionソースで確認済みである。テストドライバ自身がシグナル同期の
ために`kill`を使う手法 (HUP/INT/TERM待機テスト) は後続PRで導入する。

## fixtures/ と sandbox パスの関係

`fixtures/`配下のファイルはリポジトリ内 (sandbox外) にコミットされる
静的データである。モックコマンド (`cat`等) はsandbox外のパスを拒否する
制限ラッパーであるため、各テストシナリオは`use_fixture`でfixtureを
sandbox内へコピーしてから、そのsandbox内パスをモックの環境変数
(`MOCK_ALL_ROWS_FILE`等) へ渡す。

## 対応範囲

初回PRのシナリオはGUI 13件・helper 7件、既存・信頼済みの回帰観点に
限定していた (`test_gui.sh`/`test_helper.sh`、計20シナリオ・
52アサーション、以後変更しない)。

`test_helper_failure_matrix.sh` (後続PR) は、helperの公開終了コード
2, 10, 14, 15, 20〜25, 70, 71 に対する決定論的な失敗マトリクスを追加する
(11・12・13・16は`test_helper.sh`で既に回帰済みのため対象外)。
51シナリオ・258アサーションで構成される (この数値は手作業の数え上げ
ではなく、`test_helper_failure_matrix.sh`自身の実行結果の末尾
`SCENARIOS=51 PASS=258 FAIL=0`行に基づく。シナリオ数はスクリプト内の
自己申告カウンタ`SCENARIO_COUNT`が実際の呼び出し回数を集計したもので
あり、実行環境 [root/非root等] に依存する分岐は持たない)。各ケースで
終了コード・対応する日本語stderr・破壊的モックへの到達/未到達・lock/
mount/一時ディレクトリの後始末・cleanup失敗が既存の終了コードを上書き
しないことを検証する。シグナル (129/130/143) およびTOCTOU窓別の実時間
競合テストは対象外とする (決定論的なモックだけでは再現できないため)。
一部のfail()分岐 (production上defensiveで他の分岐と独立に再現できない
ものなど) はテストファイル冒頭のコメントに理由とともに明記したうえで
意図的に省略している。

`extract_field`のエッジケース単体テスト等は今後の課題とする。

## CIへの組み込み

`.github/workflows/persistence-mock-tests.yml` が本ハーネスを実行する。
既存の `.github/workflows/static-checks.yml` とは別ファイル・別ジョブ
であり、環境を共有しないため、必要なコマンドの確認は
`persistence-mock-tests.yml` 自身の中で完結させている。
