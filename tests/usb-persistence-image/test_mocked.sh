#!/bin/sh
# tests/usb-persistence-image/test_mocked.sh
#
# build-usb-persistence-image.sh の、xorriso/mke2fs/e2fsck/debugfs/dfを
# 実際に呼び出す段階 (入力整合性検査以降) を、instrument_script.sh +
# mock_command.sh による完全モックで検証する。実xorriso・実mke2fs・
# 実e2fsck・実debugfsは一切execしない。
#
# 成功パス (exit 0) を含め、生成後自動検証 (exit 41〜50) の代表的な
# 失敗シナリオも、xorrisoモックが合成するMBR/GPT/El Torito報告を通じて
# 検証する。
#
set -eu

TESTS_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$TESTS_DIR/../.." && pwd)"
PROD_SCRIPT="$REPO_ROOT/scripts/build-usb-persistence-image.sh"

# shellcheck source=tests/usb-persistence-image/common.sh
. "$TESTS_DIR/common.sh"
# shellcheck source=tests/usb-persistence-image/instrument_script.sh
. "$TESTS_DIR/instrument_script.sh"
# shellcheck source=tests/usb-persistence-image/mock_command.sh
. "$TESTS_DIR/mock_command.sh"
trap on_common_exit EXIT

create_sandbox
write_mocks "$SANDBOX/bin" "$SANDBOX"

INSTRUMENTED="$SANDBOX/work/instrumented.sh"
instrument_script "$SANDBOX/bin" "$INSTRUMENTED"

# ---- フィクスチャ準備 --------------------------------------------------------
# ファイル名は "fake.iso" 固定 (mock_command.sh のxorrisoモックが
# basenameで入力ISO/生成物を区別するため)。mockのosirrox extractが返す
# デフォルト内容と一致させておくことで、入力整合性検査そのものは通過させる。
FAKE_ISO="$SANDBOX/input/fake.iso"
head -c 2000 /dev/zero > "$FAKE_ISO"

FAKE_BINARY_DIR="$SANDBOX/input/binary"
mkdir -p "$FAKE_BINARY_DIR/isolinux" "$FAKE_BINARY_DIR/boot/grub" "$FAKE_BINARY_DIR/live"
printf '' > "$FAKE_BINARY_DIR/isolinux/isolinux.bin"
printf 'mock-efi-content' > "$FAKE_BINARY_DIR/boot/grub/efi.img"
printf 'mock-squashfs-content' > "$FAKE_BINARY_DIR/live/filesystem.squashfs"

OUT_DIR="$SANDBOX/work/out"
mkdir -p "$OUT_DIR"

run_instrumented() {
    # run_instrumented OUTPUT_BASENAME の後、EXIT_CODE に終了コードを
    # 格納する。MOCK_* 環境変数は呼び出し元で事前にexportしておく。
    out="$OUT_DIR/$1"
    ( "$INSTRUMENTED" --iso "$FAKE_ISO" --binary-dir "$FAKE_BINARY_DIR" \
        --persistence-size 256M --output "$out" \
        >"$SANDBOX/work/stdout" 2>"$SANDBOX/work/stderr" ) && EXIT_CODE=0 || EXIT_CODE=$?
}

ALL_MOCK_VARS="
MOCK_XORRISO_FAIL_REPORT MOCK_XORRISO_BAD_VOLID MOCK_XORRISO_FAIL_EXTRACT
MOCK_CONTENT_EFI_IMG MOCK_CONTENT_SQUASHFS MOCK_CONTENT_ISOLINUX_BIN
MOCK_XORRISO_FAIL_GENERATE MOCK_MKE2FS_FAIL
MOCK_E2FSCK_FAIL_PRE MOCK_E2FSCK_FAIL_POST
MOCK_DEBUGFS_FAIL_WRITE
MOCK_DEBUGFS_BAD_STAT_PRE MOCK_DEBUGFS_BAD_STAT_POST
MOCK_DEBUGFS_BAD_CONTENT_PRE MOCK_DEBUGFS_BAD_CONTENT_POST
MOCK_XORRISO_FAIL_REPORT_INPUT_PLAIN MOCK_XORRISO_FAIL_REPORT_OUTPUT_PLAIN
MOCK_XORRISO_MBR_DROP MOCK_XORRISO_MBR_DUPLICATE
MOCK_XORRISO_GPT_DROP MOCK_XORRISO_GPT_DUPLICATE
MOCK_XORRISO_GPT2_MISMATCH MOCK_XORRISO_GPT3_MISMATCH
MOCK_XORRISO_BACKUP_LBA_WRONG MOCK_XORRISO_EL_TORITO_MISMATCH
MOCK_XORRISO_FIND_MISSING_PATH MOCK_XORRISO_PART3_CORRUPT
MOCK_TAMPER_TARGET_PATH MOCK_DF_AVAILABLE_BYTES MOCK_MKE2FS_SLEEP_SECONDS
MOCK_LN_PRECREATE_DEST
"

reset_mock_env() {
    # shellcheck disable=SC2086
    unset $ALL_MOCK_VARS 2>/dev/null || :
}

# ============================================================================
# 各wrapper/mockの自己テスト: sandbox外パスを渡すとexit 99になること
# ============================================================================
# instrumented productionを経由せず、$SANDBOX/bin配下の各コマンドを直接
# 呼び出す。対象パスはsandbox外の使い捨てディレクトリ (OUTSIDE_DIR) に
# 置き、実際に書き込み/削除が発生していないことも内容比較で確認する。
# OUTSIDE_DIRは、この時点で確定しているSANDBOXの「兄弟パス」として、
# 固定prefixのmktempテンプレート ("$SANDBOX.outside.XXXXXXXXXX") で
# 作る。sandbox本体 (SANDBOX配下) には置かない (sandbox外拒否の自己
# テストという性質上、意図的にsandbox外に置く必要があるため) が、
# common.shのon_common_exitがこの命名規約に一致するパスだけを安全に
# 削除できるようにするための識別子である。

OUTSIDE_DIR="$(mktemp -d "${SANDBOX}.outside.XXXXXXXXXX")"
OUTSIDE_FILE="$OUTSIDE_DIR/outside.txt"
OUTSIDE_MARKER='outside-untouched-marker'
printf '%s' "$OUTSIDE_MARKER" > "$OUTSIDE_FILE"

assert_sandbox_rejects() {
    # assert_sandbox_rejects NAME CMD ARGS...
    name="$1"; shift
    rc=0
    "$@" >/dev/null 2>&1 || rc=$?
    scenario_result "sandbox-reject:$name" 99 "$rc"
}

# --- 読み取り専用コマンド ---
assert_sandbox_rejects 'grep' "$SANDBOX/bin/grep" -q foo "$OUTSIDE_FILE"
assert_sandbox_rejects 'sed' "$SANDBOX/bin/sed" 's/a/b/' "$OUTSIDE_FILE"
assert_sandbox_rejects 'awk' "$SANDBOX/bin/awk" '{print}' "$OUTSIDE_FILE"
assert_sandbox_rejects 'stat' "$SANDBOX/bin/stat" "$OUTSIDE_FILE"
assert_sandbox_rejects 'cmp' "$SANDBOX/bin/cmp" "$OUTSIDE_FILE" "$OUTSIDE_FILE"
assert_sandbox_rejects 'sha256sum' "$SANDBOX/bin/sha256sum" "$OUTSIDE_FILE"
assert_sandbox_rejects 'realpath' "$SANDBOX/bin/realpath" "$OUTSIDE_FILE"
assert_sandbox_rejects 'dirname' "$SANDBOX/bin/dirname" "$OUTSIDE_FILE"
assert_sandbox_rejects 'cat' "$SANDBOX/bin/cat" "$OUTSIDE_FILE"
assert_sandbox_rejects 'diff' "$SANDBOX/bin/diff" "$OUTSIDE_FILE" "$OUTSIDE_FILE"

# --- sandbox内限定の書き込みコマンド ---
assert_sandbox_rejects 'rm' "$SANDBOX/bin/rm" -f "$OUTSIDE_FILE"
assert_sandbox_rejects 'mkdir' "$SANDBOX/bin/mkdir" "$OUTSIDE_DIR/newdir"
assert_sandbox_rejects 'mktemp' "$SANDBOX/bin/mktemp" -d "$OUTSIDE_DIR/tmpl.XXXXXX"
assert_sandbox_rejects 'dd-of' "$SANDBOX/bin/dd" "if=$FAKE_ISO" "of=$OUTSIDE_FILE"
assert_sandbox_rejects 'dd-if' "$SANDBOX/bin/dd" "if=$OUTSIDE_FILE" "of=$SANDBOX/work/dd-if-selftest.out"
assert_sandbox_rejects 'ln' "$SANDBOX/bin/ln" -- "$FAKE_ISO" "$OUTSIDE_FILE.link"
assert_sandbox_rejects 'mv' "$SANDBOX/bin/mv" "$OUTSIDE_FILE" "$OUTSIDE_FILE.moved"
assert_sandbox_rejects 'df' "$SANDBOX/bin/df" -P -B1 -- "$OUTSIDE_DIR"

# --- 完全モック (mke2fs/e2fsck/debugfs/xorriso) の内部sandbox検査 ---
assert_sandbox_rejects 'mke2fs' "$SANDBOX/bin/mke2fs" -F -t ext4 -L persistence \
    -d "$SANDBOX/input" "$OUTSIDE_FILE.img" 256M

assert_sandbox_rejects 'e2fsck' "$SANDBOX/bin/e2fsck" -fn -- "$OUTSIDE_FILE"

assert_sandbox_rejects 'debugfs-write' "$SANDBOX/bin/debugfs" -w -f "$FAKE_ISO" -- "$OUTSIDE_FILE"

printf 'dummy-persist-content' > "$SANDBOX/work/dummy_persist.img"
assert_sandbox_rejects 'xorriso-extract' "$SANDBOX/bin/xorriso" \
    -indev "$FAKE_ISO" -osirrox on -extract /isolinux/isolinux.bin "$OUTSIDE_FILE.extract"
assert_sandbox_rejects 'xorriso-generate' "$SANDBOX/bin/xorriso" -as mkisofs \
    -append_partition 3 0FC63DAF-8483-4772-8E79-3D69D8477DE4 "$SANDBOX/work/dummy_persist.img" \
    -o "$OUTSIDE_FILE.generate" "$FAKE_BINARY_DIR"

# mke2fsの出力IMG自体はsandbox内だが、tamperフック先 (通常は
# 実行中の入力変化シナリオが使う) がsandbox外を指す場合も拒否すること。
# 出力IMGは自己テスト専用の使い捨てパスとし、既存シナリオの
# フィクスチャには一切影響しない。
MOCK_TAMPER_TARGET_PATH="$OUTSIDE_FILE"
export MOCK_TAMPER_TARGET_PATH
assert_sandbox_rejects 'mke2fs-tamper-target-outside-sandbox' "$SANDBOX/bin/mke2fs" \
    -F -t ext4 -L persistence -d "$SANDBOX/input" "$SANDBOX/work/mke2fs-tamper-selftest.img" 256M
unset MOCK_TAMPER_TARGET_PATH

# 上記いずれも、sandbox外へ実際には一切書き込み・作成していないことを
# まとめて確認する (1アサーション)。OUTSIDE_FILE自体の内容不変に加え、
# 各wrapper/mockが (拒否せず通っていれば) 作成したはずの副産物
# (新規ディレクトリ・symlink・生成物ファイル) が一切存在しないことを
# 検出する。通常ファイルだけでなくsymlink (壊れているものを含む) も
# [ -e ] || [ -L ] で検出する。
outside_content_after="$(cat -- "$OUTSIDE_FILE" 2>/dev/null || echo MISSING)"
outside_leftover=0
[ "$outside_content_after" = "$OUTSIDE_MARKER" ] || outside_leftover=1
for p in \
    "$OUTSIDE_DIR/newdir" \
    "$OUTSIDE_FILE.link" \
    "$OUTSIDE_FILE.moved" \
    "$OUTSIDE_FILE.img" \
    "$OUTSIDE_FILE.extract" \
    "$OUTSIDE_FILE.generate"
do
    if [ -e "$p" ] || [ -L "$p" ]; then
        outside_leftover=1
        echo "unexpected artifact outside sandbox: $p" >&2
    fi
done
for p in "$OUTSIDE_DIR"/tmpl.*; do
    if [ -e "$p" ] || [ -L "$p" ]; then
        outside_leftover=1
        echo "unexpected artifact outside sandbox: $p" >&2
    fi
done
scenario_bool 'sandbox-reject-no-actual-write-occurred' \
    "$([ "$outside_leftover" -eq 0 ] && echo 1 || echo 0)"

rm -rf -- "$OUTSIDE_DIR"
OUTSIDE_DIR=''

# ============================================================================
# 生成前段階の失敗シナリオ (exit 21, 22, 30〜32, 40)
# ============================================================================

reset_mock_env
MOCK_XORRISO_FAIL_EXTRACT=1
export MOCK_XORRISO_FAIL_EXTRACT
run_instrumented 'scenario01.img'
scenario_result 'extract-command-fails' 21 "$EXIT_CODE"

reset_mock_env
MOCK_CONTENT_EFI_IMG='different-content-than-fixture'
export MOCK_CONTENT_EFI_IMG
run_instrumented 'scenario02.img'
scenario_result 'efi-img-content-mismatch' 21 "$EXIT_CODE"

reset_mock_env
MOCK_XORRISO_BAD_VOLID=1
export MOCK_XORRISO_BAD_VOLID
run_instrumented 'scenario03.img'
scenario_result 'volid-line-malformed' 22 "$EXIT_CODE"

reset_mock_env
MOCK_XORRISO_FAIL_REPORT=1
export MOCK_XORRISO_FAIL_REPORT
run_instrumented 'scenario04.img'
scenario_result 'report-system-area-fails' 22 "$EXIT_CODE"

reset_mock_env
MOCK_MKE2FS_FAIL=1
export MOCK_MKE2FS_FAIL
run_instrumented 'scenario05.img'
scenario_result 'mke2fs-fails' 30 "$EXIT_CODE"

reset_mock_env
MOCK_DEBUGFS_FAIL_WRITE=1
export MOCK_DEBUGFS_FAIL_WRITE
run_instrumented 'scenario06.img'
scenario_result 'debugfs-write-fails' 31 "$EXIT_CODE"

reset_mock_env
MOCK_E2FSCK_FAIL_PRE=1
export MOCK_E2FSCK_FAIL_PRE
run_instrumented 'scenario07.img'
scenario_result 'e2fsck-pre-fails' 32 "$EXIT_CODE"

reset_mock_env
MOCK_DEBUGFS_BAD_STAT_PRE=1
export MOCK_DEBUGFS_BAD_STAT_PRE
run_instrumented 'scenario08.img'
scenario_result 'persistence-conf-stat-mismatch-pre' 32 "$EXIT_CODE"

reset_mock_env
MOCK_DEBUGFS_BAD_CONTENT_PRE=1
export MOCK_DEBUGFS_BAD_CONTENT_PRE
run_instrumented 'scenario09.img'
scenario_result 'persistence-conf-content-mismatch-pre' 32 "$EXIT_CODE"

reset_mock_env
MOCK_XORRISO_FAIL_GENERATE=1
export MOCK_XORRISO_FAIL_GENERATE
run_instrumented 'scenario10.img'
scenario_result 'xorriso-generate-fails' 40 "$EXIT_CODE"

# ============================================================================
# 成功パス (exit 0)
# ============================================================================

# 「成功パス」は1シナリオ (1回の実行) につき複数のアサーション
# (exit code・出力が1個だけ作られたこと・work directoryが残らないこと)
# を持つ。begin_scenarioは1回だけ呼び、個々のチェックはlog_result/
# log_boolを直接呼んでアサーションとしてのみ計上する。
reset_mock_env
begin_scenario
run_instrumented 'success.img'
log_result 'mocked-success-path' 0 "$EXIT_CODE"

log_bool 'success-output-created-exactly-once' \
    "$([ -f "$OUT_DIR/success.img" ] && echo 1 || echo 0)"

# work directory残存の有無は、個々のシナリオごとにチェックせず、末尾で
# $OUT_DIR配下を一括走査する ("work directory残存0の確認" 節を参照)。
# ここでは成功パス直後の時点でのworkdir有無だけ、単発でも確認しておく。
success_workdir_leftover=0
for d in "$OUT_DIR"/.success.img.work.*; do
    [ -e "$d" ] || [ -L "$d" ] || continue
    success_workdir_leftover=1
done
log_bool 'success-workdir-removed' \
    "$([ "$success_workdir_leftover" -eq 0 ] && echo 1 || echo 0)"

# ---- ln (hard link) がsandbox制限ラッパー越しでも、出力先が既に存在する
#      場合には -f なしで正しく失敗すること (exit 60が依拠する下位機構の
#      単体確認。正常系フローでは "--output は既に存在します" (exit 13) が
#      先に検出するため、full scriptを通した exit 60 到達は構造上の
#      TOCTOU窓でのみ起こる。ここではlnモック自体の拒否動作を直接確認する)
DUMMY_SRC="$SANDBOX/work/dummy_src"
printf 'x' > "$DUMMY_SRC"
ln_rc=0
"$SANDBOX/bin/ln" -- "$DUMMY_SRC" "$OUT_DIR/success.img" >/dev/null 2>&1 || ln_rc=$?
scenario_bool 'ln-refuses-to-overwrite-existing-destination' \
    "$([ "$ln_rc" -ne 0 ] && echo 1 || echo 0)"

# ---- production全体を通した公開直前競合 (exit 60) --------------------------
# MOCK_LN_PRECREATE_DESTにより、production自身のlnモック呼び出しの
# 直前に「別プロセスが既に公開先を作成していた」状態を再現する。
# productionのTOCTOU防止 (ln、-fなし) がexit 60を正しく返すこと、
# 競合相手 (先に存在していたファイル) の内容が変化しないこと、
# work directoryが残存しないことを確認する。
reset_mock_env
begin_scenario
MOCK_LN_PRECREATE_DEST='publish-conflict-marker'
export MOCK_LN_PRECREATE_DEST
run_instrumented 'publish-conflict.img'
log_result 'publish-conflict-exit-60' 60 "$EXIT_CODE"

conflict_content="$(cat -- "$OUT_DIR/publish-conflict.img" 2>/dev/null || echo MISSING)"
log_bool 'publish-conflict-collider-content-unchanged' \
    "$([ "$conflict_content" = 'publish-conflict-marker' ] && echo 1 || echo 0)"

# ============================================================================
# 生成後自動検証の失敗シナリオ (exit 41〜50)
# ============================================================================

reset_mock_env
MOCK_XORRISO_FAIL_REPORT_OUTPUT_PLAIN=1
export MOCK_XORRISO_FAIL_REPORT_OUTPUT_PLAIN
run_instrumented 'scenario11.img'
scenario_result 'post-system-area-report-fails' 41 "$EXIT_CODE"

reset_mock_env
MOCK_XORRISO_MBR_DROP=1
export MOCK_XORRISO_MBR_DROP
run_instrumented 'scenario12.img'
scenario_result 'mbr-entry-missing' 41 "$EXIT_CODE"

reset_mock_env
MOCK_XORRISO_MBR_DUPLICATE=1
export MOCK_XORRISO_MBR_DUPLICATE
run_instrumented 'scenario13.img'
scenario_result 'mbr-entry-duplicate' 41 "$EXIT_CODE"

reset_mock_env
MOCK_XORRISO_GPT_DROP=1
export MOCK_XORRISO_GPT_DROP
run_instrumented 'scenario14.img'
scenario_result 'gpt-entry-missing' 42 "$EXIT_CODE"

reset_mock_env
MOCK_XORRISO_GPT_DUPLICATE=1
export MOCK_XORRISO_GPT_DUPLICATE
run_instrumented 'scenario15.img'
scenario_result 'gpt-entry-duplicate' 42 "$EXIT_CODE"

reset_mock_env
MOCK_XORRISO_GPT2_MISMATCH=1
export MOCK_XORRISO_GPT2_MISMATCH
run_instrumented 'scenario16.img'
scenario_result 'gpt-entry2-mismatch' 42 "$EXIT_CODE"

reset_mock_env
MOCK_XORRISO_GPT3_MISMATCH=1
export MOCK_XORRISO_GPT3_MISMATCH
run_instrumented 'scenario17.img'
scenario_result 'gpt-entry3-mismatch' 42 "$EXIT_CODE"

reset_mock_env
MOCK_XORRISO_BACKUP_LBA_WRONG=1
export MOCK_XORRISO_BACKUP_LBA_WRONG
run_instrumented 'scenario18.img'
scenario_result 'gpt-backup-header-mismatch' 43 "$EXIT_CODE"

reset_mock_env
MOCK_XORRISO_EL_TORITO_MISMATCH=1
export MOCK_XORRISO_EL_TORITO_MISMATCH
run_instrumented 'scenario19.img'
scenario_result 'el-torito-mismatch' 44 "$EXIT_CODE"

reset_mock_env
MOCK_XORRISO_FIND_MISSING_PATH='/live/vmlinuz'
export MOCK_XORRISO_FIND_MISSING_PATH
run_instrumented 'scenario20.img'
scenario_result 'iso9660-missing-file' 45 "$EXIT_CODE"

reset_mock_env
MOCK_XORRISO_PART3_CORRUPT=1
export MOCK_XORRISO_PART3_CORRUPT
run_instrumented 'scenario21.img'
scenario_result 'partition3-cmp-mismatch' 46 "$EXIT_CODE"

reset_mock_env
MOCK_E2FSCK_FAIL_POST=1
export MOCK_E2FSCK_FAIL_POST
run_instrumented 'scenario22.img'
scenario_result 'e2fsck-post-fails' 47 "$EXIT_CODE"

reset_mock_env
MOCK_DEBUGFS_BAD_STAT_POST=1
export MOCK_DEBUGFS_BAD_STAT_POST
run_instrumented 'scenario23.img'
scenario_result 'persistence-conf-stat-mismatch-post' 48 "$EXIT_CODE"

reset_mock_env
MOCK_DEBUGFS_BAD_CONTENT_POST=1
export MOCK_DEBUGFS_BAD_CONTENT_POST
run_instrumented 'scenario24.img'
scenario_result 'persistence-conf-content-mismatch-post' 48 "$EXIT_CODE"

reset_mock_env
MOCK_TAMPER_TARGET_PATH="$FAKE_ISO"
export MOCK_TAMPER_TARGET_PATH
run_instrumented 'scenario25.img'
scenario_result 'input-iso-sha256-changes-mid-run' 49 "$EXIT_CODE"
# フィクスチャを正しいサイズへ戻す (以降のシナリオへ影響させない)
head -c 2000 /dev/zero > "$FAKE_ISO"

reset_mock_env
MOCK_TAMPER_TARGET_PATH="$FAKE_BINARY_DIR/boot/grub/efi.img"
export MOCK_TAMPER_TARGET_PATH
run_instrumented 'scenario26.img'
scenario_result 'binary-file-sha256-changes-mid-run' 50 "$EXIT_CODE"
# フィクスチャを元へ戻す
printf 'mock-efi-content' > "$FAKE_BINARY_DIR/boot/grub/efi.img"

# ============================================================================
# シグナル (item 4): シグナル終了がexit 0として扱われないこと
# ============================================================================
# mke2fsモックは通常一瞬で終わるため、シグナル送出のための猶予を作る
# 目的でMOCK_MKE2FS_SLEEP_SECONDSを与える (instrumented scriptの
# on_int/on_term/on_hupトラップが実際に発火し、期待どおりの終了コード
# (130/143/129) を返すことを確認する)。
#
# 送出には `cmd & ; kill -SIG $pid` ではなく `timeout --preserve-status
# --signal=SIG` を使う。POSIXシェルにはジョブ制御が無効な状態で
# バックグラウンド起動された非同期コマンドのSIGINT/SIGQUITを既定で無視
# する仕様があり (POSIX Shell & Utilities、bashのmanにも "signals ignored
# upon entry to the shell cannot be trapped or reset" と明記)、本ドライバ
# (test_mocked.sh、/bin/shで実行) から `cmd &` した子はSIGINTが構造的に
# 無視されてしまう (実機・実際のインタラクティブ実行では起こらない、この
# テスト方式固有の問題であることを、最小再現で individually 確認済み)。
# `timeout` は対象コマンドをジョブ制御を介さず直接fork/execしたうえで
# シグナルを送るため、この問題を回避できる。
test_signal() {
    # test_signal NAME SIGNAL EXPECTED_EXIT
    # 1シグナルにつき1シナリオ (exit code・出力が残らないことの2アサー
    # ション) として計上する。
    name="$1"; sig="$2"; expected="$3"
    reset_mock_env
    begin_scenario
    MOCK_MKE2FS_SLEEP_SECONDS=10
    export MOCK_MKE2FS_SLEEP_SECONDS
    out="$OUT_DIR/signal-$name.img"
    timeout --preserve-status --signal="$sig" 2 \
        "$INSTRUMENTED" --iso "$FAKE_ISO" --binary-dir "$FAKE_BINARY_DIR" \
        --persistence-size 256M --output "$out" \
        >"$SANDBOX/work/stdout" 2>"$SANDBOX/work/stderr" && sig_rc=0 || sig_rc=$?
    log_result "signal-$name-exit-code" "$expected" "$sig_rc"
    log_bool "signal-$name-no-output-left" \
        "$([ ! -e "$out" ] && echo 1 || echo 0)"
}

test_signal 'int' INT 130
test_signal 'term' TERM 143
test_signal 'hup' HUP 129

reset_mock_env

# ============================================================================
# 不完全出力の未残存確認 (全失敗シナリオを対象とする集約チェック)
# ============================================================================
leftover=0
for f in "$OUT_DIR"/scenario*.img; do
    [ -e "$f" ] || continue
    leftover=1
    echo "unexpected leftover output file: $f" >&2
done
scenario_bool 'no-incomplete-output-left-behind' \
    "$([ "$leftover" -eq 0 ] && echo 1 || echo 0)"

# ---- private work directory残存の未残存確認 (成功・全失敗・シグナルの
#      全経路を対象とする集約チェック) ----------------------------------------
# $OUT_DIR配下に生成されるprivate work directoryは、常に
# "$OUT_DIR/.<basename>.work.XXXXXXXX" という命名規則を持つ (productionの
# mktemp -dテンプレートに基づく)。単純な文字列比較 (glob非展開時の
# リテラル一致) では常にfalseとなり検査が無意味になるため、実在する
# エントリをforループで走査する (glob展開後、存在確認する標準的な
# イディオム)。成功パス・全失敗シナリオ・INT/TERM/HUP・公開直前競合
# のいずれについても、この時点でwork directoryが1件も残っていないこと
# を、まとめて確認する。
workdir_leftover=0
for d in "$OUT_DIR"/.*.work.*; do
    [ -e "$d" ] || [ -L "$d" ] || continue
    workdir_leftover=1
    echo "unexpected leftover work directory: $d" >&2
done
scenario_bool 'no-workdir-left-behind-across-all-paths' \
    "$([ "$workdir_leftover" -eq 0 ] && echo 1 || echo 0)"

# ---- 結果表示 (構造検査より先に表示し、失敗時も内訳を確認できるようにする) --
printf '%s' "$RESULTS"
echo "SCENARIOS=$SCENARIO_COUNT PASS=$PASS FAIL=$FAIL"

# ---- 構造検査: シナリオ数・アサーション数の期待値一致 -----------------------
check_scenario_totals 59 65

[ "$FAIL" -eq 0 ]
