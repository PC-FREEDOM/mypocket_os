# USB persistence IMG生成 非破壊モックテストハーネス

`scripts/build-usb-persistence-image.sh` を対象とした、コミット可能な
非破壊モックテストハーネス。`tests/persistence/` と同じ設計思想 (sandbox化、
production整合性の二重防御、apply_ruleによる件数確認付き置換) を踏襲する。

## 実行方法

```sh
tests/usb-persistence-image/run.sh
```

一般ユーザー権限のみで完結する。実行に `sudo`・実`xorriso`(生成呼び出し)・
実`mke2fs`・実`e2fsck`・実`debugfs`・loop・mount・USB/block device操作は
一切必要ない (`test_direct.sh`の一部シナリオのみ、早期に失敗する経路として
実`xorriso`を軽量に呼び出すことがある。詳細は後述)。

直接実行スイート・モックスイートをそれぞれ単体で実行する場合:

```sh
tests/usb-persistence-image/test_direct.sh
tests/usb-persistence-image/test_mocked.sh
```

## 2つのスイートに分けている理由

`build-usb-persistence-image.sh` は、引数・パス・サイズの検証 (xorriso等を
一切呼び出さない段階) と、xorriso/mke2fs/e2fsck/debugfs/dfを実際に呼び出す
段階とに、明確な順序を持つ。

- **`test_direct.sh`**: 前者の段階を、production スクリプト本体を一切
  改変せず直接実行して検証する (exit 2, 11〜18)。この段階はstat/realpath/
  grep等の軽量な読み取り専用判定のみで完結し、xorriso等を一切呼び出さない
  ため、instrument/mockは不要かつ不適切 (実コードをそのまま検証できる
  利点を活かす)。**実xorriso・実mke2fs・実e2fsck・実debugfsによるIMG
  生成は一切行わない** (全シナリオが、それらへ到達する前に必ずexitする
  設計)。最小値境界を通過した後の挙動確認は`test_mocked.sh`側で行う。
- **`test_mocked.sh`**: 後者の段階を、`instrument_script.sh` +
  `mock_command.sh` による完全モックで検証する (exit 21, 22, 30〜32,
  40〜50、成功パス exit 0を含む)。実xorriso/mke2fs/e2fsck/debugfsは
  一切execしない。

## 安全上の前提

- production ファイル (`scripts/build-usb-persistence-image.sh`) には
  一切書き込まない。`instrument_script.sh` は常に `cp` してから
  `sed ... file > file.next && mv` の形でsandbox内へ新規出力するだけで
  あり、`sed -i` は使わない。
- 両スイートとも、実行前後でproduction ファイルのSHA-256を比較し、
  不一致ならテスト結果に関わらず異常終了する (`common.sh` の
  `on_common_exit` EXIT trap)。`run.sh` も同様の二重チェックを行う。
- 実xorriso (生成呼び出し)・実mke2fs・実e2fsck・実debugfsは、
  `mock_command.sh` が生成するモックの中で実バイナリへ委譲する分岐を
  一切持たない (完全モック)。
- 全ての作業ファイルは `mktemp -d` でリポジトリ外に作成し、実行終了時に
  必ず削除される。instrumented productionが自ら作るwork directoryも、
  sandbox内限定の書き込みコマンド (後述) が経路上のパスを検査するため、
  構造的にsandbox内に閉じる。
- `test_mocked.sh`のsandbox外拒否自己テストが使う`OUTSIDE_DIR`は、意図的
  にsandbox本体 (`$SANDBOX`配下) の外に置く使い捨てディレクトリである。
  `OUTSIDE_DIR`は`common.sh`で`SANDBOX`と同様に必ず空文字列へ初期化する
  (呼び出し元の環境から`OUTSIDE_DIR`をexportして継承していても無効化
  される)。`test_mocked.sh`は、この時点で確定している`$SANDBOX`の
  「兄弟パス」として、固定prefixのmktempテンプレート
  (`"$SANDBOX".outside.XXXXXXXXXX`) でのみ`OUTSIDE_DIR`を作る。
  `common.sh`の`on_common_exit` (EXIT trap) は、`OUTSIDE_DIR`の値が
  `"$SANDBOX".outside.*`という自分自身の命名規約に一致し、かつ`SANDBOX`
  自体が空でない場合だけ削除する (`case`文によるパターン一致。
  未定義・空文字列はもちろん、たまたま既存の無関係なディレクトリを
  指す`OUTSIDE_DIR`が呼び出し元から継承されていた場合でも、絶対に
  削除しない)。通常経路の末尾ではもちろん、途中終了・シグナル時にも
  同じ条件で確実に削除する。
- `mock_command.sh`内にevalは一切使わない (最後の引数・最後から2番目の
  引数の取得は、forループで位置をずらしながら安全に行う)。

## モックコマンドの3分類

`mock_command.sh` が `$SANDBOX/bin` へ書き出すコマンドは3分類される
(productionが使用する20コマンド全てを網羅する。`mv`はproduction側で
現在未使用だが、防御的に同水準のラッパーを用意している)。

1. **完全モック**: `xorriso mke2fs e2fsck debugfs df`。実バイナリを一切
   execしない。振る舞いは `MOCK_*` 環境変数で制御する。`df`は空き容量
   不足シナリオを決定論的に再現するために完全モックとする。`mke2fs`
   (書き込み先IMG・`MOCK_TAMPER_TARGET_PATH`)・`e2fsck`(最後の引数の
   filesystem image)・`debugfs`(最後の引数のfilesystem image、`-w`/
   `-R`いずれも)・`xorriso`(抽出先・生成先`-o`) も、実際の書き込み・
   追記・処理の前にsandbox内であることを検証し、sandbox外なら実処理へ
   到達する前にexit 99で拒否する (`SANDBOX`環境変数を`create_sandbox`が
   exportし、quoted heredocで生成するモックからも実行時に参照できる
   ようにしている)。
2. **読み取り専用コマンド**: `grep sed awk stat cmp sha256sum realpath
   dirname cat diff`。実バイナリへ委譲するが、絶対パス引数がsandbox外を
   指す場合はexit 99で拒否する (`/dev/fd/*`はプロセス置換の一時パイプ
   として例外的に許可する)。
3. **sandbox内限定の書き込みコマンド**: `rm mkdir mktemp dd ln mv`。
   書き込み (または新規作成) 対象パスがsandbox内であることを検査した
   うえで実バイナリへ委譲する。`mktemp`はtemplateと戻り値の両方、`dd`は
   `of=`の書き込み先に加え`if=`の読み取り元もsandbox内または明示
   allowlist (`MOCK_DD_IF_ALLOWLIST`) に限定、`ln`はsource/destinationの
   両方を検査する。`ln`にはさらに`MOCK_LN_PRECREATE_DEST`フックがあり、
   公開直前競合 (TOCTOU、exit 60) を再現できる。

## 対応範囲・対象外

`test_direct.sh` は exit 2, 11〜18 の全分岐 (29シナリオ・29アサーション、
シナリオとアサーションが1対1) を、実際の判定順序 (例: `--output` 既存
チェックが同一性検査より先に働くため `--iso == --output` は必ずexit 13
になる、等) を含めて検証する。

`test_mocked.sh` は59シナリオ・65アサーションである。シナリオとアサー
ションは分離しており、1回の実行に対して複数の観点を検証するシナリオ
(成功パス・公開直前競合・シグナル各種) は、1シナリオに複数アサーション
が対応する (`begin_scenario`を1回だけ呼び、個々のチェックは
`log_result`/`log_bool`で計上する。単一観点のシナリオは`scenario_result`/
`scenario_bool`で1シナリオ=1アサーションとする)。内訳:

- 各wrapper/mockのsandbox外パス拒否自己テスト、計24シナリオ・24
  アサーション。内訳は、読み取り専用コマンド10種 (`grep sed awk stat
  cmp sha256sum realpath dirname cat diff`)、sandbox内限定の書き込み
  コマンド8種 (`rm mkdir mktemp dd`の`of=`検査・`dd`の`if=`検査・
  `ln mv df`)、完全モック6件 (`mke2fs`の出力IMG検査・`e2fsck`・
  `debugfs -w`・`xorriso`のextract先・`xorriso`のgenerate先`-o`・
  `mke2fs`の`MOCK_TAMPER_TARGET_PATH`検査 [出力IMGはsandbox内、
  tamper先だけがsandbox外というケースを個別に検証])。加えて、
  上記いずれについてもsandbox外へ実際には一切書き込み・作成して
  いないこと (新規ディレクトリ・symlinkを含む) をまとめて確認する
  集約チェック (1シナリオ・1アサーション)。
- 生成前の失敗経路 (exit 21, 22, 30〜32, 40、10シナリオ・10アサーション)。
- 成功パス (1シナリオ・3アサーション: exit 0・完成名が1個だけ作られる
  こと・private work directoryが削除されること)。
- `ln`の下位機構単体確認 (出力先が既存なら`-f`なしで失敗すること、
  1シナリオ・1アサーション)。
- production全体を通した公開直前競合 (`MOCK_LN_PRECREATE_DEST`により
  再現、1シナリオ・2アサーション: exit 60になること・競合相手の内容が
  変化しないこと)。
- 生成後自動検証の失敗経路 (exit 41〜50: MBR/GPT entryの欠落・重複、
  GPT entry 2/3不一致、backup header不一致、El Torito不一致、ISO9660
  欠落、partition 3のcmp不一致、抽出後のe2fsck/persistence.conf不一致、
  実行中の入力SHA-256変化、16シナリオ・16アサーション)。
- シグナル (INT/TERM/HUPそれぞれ、1シグナル1シナリオ・2アサーション
  [exit code・出力が残らないこと]、計3シナリオ・6アサーション)。
- 不完全出力の未残存確認・work directory残存の未残存確認 (全経路対象の
  集約チェック、各1シナリオ・1アサーション。work directory側はsymlink
  [壊れているものを含む] も`[ -e ] || [ -L ]`で検出する)。

合計: `test_direct.sh` 29+29、`test_mocked.sh` 59+65 で、
**88シナリオ・94アサーション**。

シグナルテストは `cmd & ; kill -SIG $pid ; wait $pid` ではなく
`timeout --preserve-status --signal=SIG N cmd` を使う。POSIXシェルには、
ジョブ制御が無効な状態でバックグラウンド起動された非同期コマンドの
SIGINT/SIGQUITを既定で無視する仕様があり (bashのmanにも "signals
ignored upon entry to the shell cannot be trapped or reset" と明記)、
`/bin/sh`で実行するテストドライバから`cmd &`した子はSIGINTが構造的に
無視されてしまう (実機での対話的な実行や、他プロセスからの直接
`kill -INT`では起こらない、この種のテスト方式に固有の制約であることを
最小再現で個別に確認済み)。`timeout`は対象コマンドをジョブ制御を介さず
直接fork/execしたうえでシグナルを送るため、この制約を回避できる。

シナリオ数・アサーション数 (`SCENARIO_COUNT`・`PASS+FAIL`) は、各テスト
末尾の`check_scenario_totals`で期待値と突き合わせる。不一致の場合は
PASS/FAILへ加算せず、構造検査そのものの失敗として即座に終了する
(exit 93)。

## ディレクトリ構成

```
tests/usb-persistence-image/
  README.md              このファイル
  common.sh               共通ユーティリティ (sandbox作成、apply_rule、
                           シナリオ数/アサーション数の構造検査、
                           EXIT trapによるproduction整合性確認)
  instrument_script.sh    production scriptをsandbox化したコピーを生成する
  mock_command.sh         $SANDBOX/bin へ全モック/ラッパーを書き出す
  test_direct.sh          直接実行スイート (29シナリオ・29アサーション)
  test_mocked.sh          モックスイート (59シナリオ・65アサーション)
  run.sh                  単一エントリポイント
  fixtures/               (現時点では未使用。tests/persistence/の構成に
                           倣い予約)
```
