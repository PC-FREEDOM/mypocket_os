#!/bin/sh
# tests/persistence/test_helper_failure_matrix.sh
#
# mypocketos-persistence-setup-helper (特権ヘルパー) の、公開終了コード
# 2, 10, 14, 15, 20〜25, 70, 71 に対する決定論的な失敗マトリクス。
#
# シナリオ数・アサーション数は手作業では数えない。末尾の
# "SCENARIOS=<N> PASS=<N> FAIL=<N>" 行が、実行結果に基づく唯一の正である
# (SCENARIO_COUNTは run_usage_case/run_matrix_case/run_success_track_case
# の実呼び出し回数をそのまま集計したもので、実行環境に依存する分岐を
# 一切持たない)。
#
# 対象外 (このファイルでは扱わない):
#   - 11・12・13・16: test_helper.sh で既に回帰済み (既存20シナリオ・
#     52アサーションには一切手を加えない)。
#   - 129・130・143: シグナル・実時間の競合窓に依存するため、決定論的
#     モックの対象外とする。
#   - 以下の fail() 分岐は、production の設計上このハーネスのモックだけ
#     では他の分岐と独立に再現できない (defensive/到達不能、または
#     再現に追加のタイミング制御機構を要する) ため、意図的に省略する。
#       * check_not_swap の NAME解析失敗・awk異常終了
#         (fetch_disk_rows が事前にNAME/TYPEの解析可能性を保証済みのため)
#       * check_no_children のTYPE解析失敗 (同上の理由)
#       * check_not_home_source のFSTYPE単独解析失敗
#         (SOURCE/FSTYPEは同一行を1回でパースするため、SOURCE解析失敗と
#         独立に再現できない)
#       * check_not_home_source の祖先チェーン一致
#         (check_not_live_sourceと同一のlsblk -sモック応答を共有しており、
#         現在のモックでは呼び出し元ごとに応答を変えられない)
#       * check_pttype_empty のlsblk取得失敗 (現在のモックはこの呼び出しを
#         常に成功させる設計であり、追加のモックフックを要する)
#       * reverify_device(21,21) のDEVICE側再検証ミスマッチ
#         (pre-partition再検証と共有のモック応答のため、呼び出し回数に
#         応じて応答を変える追加のモックが必要であり、事実上のタイミング
#         依存テストとなるため除外する)
#
# production ファイルには一切書き込まない。実sudo・実parted・実mkfs.ext4・
# 実mount・実umount・実sync・VM/ISO操作はいずれも呼び出さない
# (test_helper.sh と同じ前提)。
set -eu

TESTS_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$TESTS_DIR/../.." && pwd)"
PROD_GUI="$REPO_ROOT/config/includes.chroot/usr/local/bin/mypocketos-persistence-setup"
PROD_HELPER="$REPO_ROOT/config/includes.chroot/usr/local/libexec/mypocketos-persistence-setup-helper"
. "$TESTS_DIR/common.sh"
. "$TESTS_DIR/mock_command.sh"

create_sandbox
trap on_common_exit EXIT

COPY="$SANDBOX/work/helper-copy"
sh "$TESTS_DIR/instrument_helper.sh" "$SANDBOX" "$COPY"

FIXTURES="$TESTS_DIR/fixtures"
FAKE_DEVICE="$SANDBOX/dev/fakedisk"
FAKE_PART_PATH="$SANDBOX/dev/fakedisk1"
DEFAULT_MAJMIN='254:0'
LOCK_DIR_PATH="$SANDBOX/run/lock/mypocketos-persistence-setup-helper.lock"

# 実行されたシナリオ数の自己申告カウンタ。手作業の数え上げに頼らず、
# run_usage_case/run_matrix_case/run_success_track_caseの実呼び出し回数を
# そのまま集計する (各関数は1回の呼び出しにつき1シナリオ、必ず1回だけ
# log_resultを呼ぶ)。
SCENARIO_COUNT=0

# シナリオを追加・削除した場合は、この値も同じ変更の中で更新すること。
# ファイル末尾でSCENARIO_COUNTと突き合わせ、不一致なら (258アサーション
# とは別枠で) 失敗マトリクス全体を非0終了にする。条件分岐によるシナリオの
# 意図しないスキップ・二重実行を検出するための構造検査であり、258件の
# 既存アサーションには加算しない。
EXPECTED_SCENARIOS=51

setup_default_sys_tree() {
    rm -rf "$SANDBOX/sys"
    mkdir -p "$SANDBOX/sys/class/block/fakedisk/holders"
    : > "$SANDBOX/sys/class/block/fakedisk/device"
}

reset_scenario_state() {
    write_mocks "$SANDBOX"
    setup_default_sys_tree
    rm -rf "$SANDBOX/run/lock"
    mkdir -p "$SANDBOX/run/lock"
    for d in "$SANDBOX"/run/mypocketos-persistence-setup-helper.*; do
        [ -e "$d" ] || continue
        chmod -R u+rwx -- "$d" 2>/dev/null || :
        rm -rf -- "$d"
    done
    rm -f "$SANDBOX/work/parted-called" "$SANDBOX/work/parted-invocations" \
          "$SANDBOX/work/mkfs-called" "$SANDBOX/work/mount-state" \
          "$SANDBOX/work/partprobe-called" "$SANDBOX/work/udevadm-called" \
          "$SANDBOX/work/mount-called" "$SANDBOX/work/umount-called" \
          "$SANDBOX/work/sync-called" "$SANDBOX/work/persistence.conf.snapshot"
    : > "$FAKE_DEVICE"
    rm -f "$FAKE_PART_PATH"
    : > "$FAKE_PART_PATH"
}

# use_fixture NAME SUFFIX [SUBST_FROM SUBST_TO]
use_fixture() {
    dest="$SANDBOX/work/$2.txt"
    if [ "$#" -ge 4 ]; then
        sed "s#$3#$4#g" "$FIXTURES/$1" > "$dest"
    else
        cp -- "$FIXTURES/$1" "$dest"
    fi
    printf '%s' "$dest"
}

parted_called() { [ -e "$SANDBOX/work/parted-called" ]; }
mkfs_called() { [ -e "$SANDBOX/work/mkfs-called" ]; }
partprobe_called() { [ -e "$SANDBOX/work/partprobe-called" ]; }
udevadm_called() { [ -e "$SANDBOX/work/udevadm-called" ]; }
mount_called() { [ -e "$SANDBOX/work/mount-called" ]; }
umount_called() { [ -e "$SANDBOX/work/umount-called" ]; }
sync_called() { [ -e "$SANDBOX/work/sync-called" ]; }
stderr_shows() { grep -qF -- "$2" "$SANDBOX/work/stderr.$1" 2>/dev/null; }

# ---- 汎用実行ヘルパー -------------------------------------------------------

# run_usage_case NAME EXPECTED_EXIT ARG...
# 引数解析 (exit 2) 用。DEVICE/MAJMINの形を仮定しない生のargv呼び出し。
run_usage_case() {
    name="$1"; expected="$2"; shift 2
    env -i PATH='/usr/bin:/bin' SANDBOX="$SANDBOX" \
        "$COPY" "$@" \
        > "$SANDBOX/work/stdout.$name" 2> "$SANDBOX/work/stderr.$name" && RC=0 || RC=$?
    log_result "$name" "$expected" "$RC"
    SCENARIO_COUNT=$((SCENARIO_COUNT + 1))
}

# run_matrix_case NAME EXPECTED_EXIT DEVICE_ARG MAJMIN_ARG [env assignments...]
# 破壊的操作 (parted) より前で拒否される経路 (exit 2/10/14/15/70) 用。
run_matrix_case() {
    name="$1"; expected="$2"; device_arg="$3"; majmin_arg="$4"; shift 4
    disk_rows="$(use_fixture helper-disk-rows-clean.txt "disk-rows-$name")"
    env -i PATH='/usr/bin:/bin' SANDBOX="$SANDBOX" \
        FAKE_DEVICE="$FAKE_DEVICE" \
        MOCK_UID=0 MOCK_LIVE_MEDIUM_MOUNTED=0 \
        MOCK_LSBLK_KNAME='fakedisk' MOCK_LSBLK_TYPE=disk MOCK_LSBLK_RO=0 \
        MOCK_LSBLK_MAJMIN="$DEFAULT_MAJMIN" MOCK_LSBLK_PTTYPE='' \
        MOCK_DISK_ROWS_FILE="$disk_rows" \
        "$@" \
        "$COPY" create "$device_arg" "$majmin_arg" \
        > "$SANDBOX/work/stdout.$name" 2> "$SANDBOX/work/stderr.$name" && RC=0 || RC=$?
    log_result "$name" "$expected" "$RC"
    SCENARIO_COUNT=$((SCENARIO_COUNT + 1))
}

# run_success_track_case NAME EXPECTED_EXIT [env assignments...]
# final_verification・GPT作成まで到達する経路 (exit 20/21/22/23/24/25/71) 用。
# ベースラインはtest_helper.shのhappy-pathシナリオと同じ健全な既定値であり、
# 個々のシナリオは失敗させたい1箇所だけをMOCK_*で上書きする。
run_success_track_case() {
    name="$1"; expected="$2"; shift 2
    disk_rows="$(use_fixture helper-disk-rows-clean.txt "disk-rows-$name")"
    part_rows="$(use_fixture helper-part-rows-created.txt "part-rows-$name" __FAKE_PART_PATH__ "$FAKE_PART_PATH")"
    env -i PATH='/usr/bin:/bin' SANDBOX="$SANDBOX" \
        FAKE_DEVICE="$FAKE_DEVICE" \
        MOCK_UID=0 MOCK_LIVE_MEDIUM_MOUNTED=0 \
        MOCK_LSBLK_KNAME='fakedisk' MOCK_LSBLK_TYPE=disk MOCK_LSBLK_RO=0 \
        MOCK_LSBLK_MAJMIN="$DEFAULT_MAJMIN" MOCK_LSBLK_PTTYPE='' \
        MOCK_DISK_ROWS_FILE="$disk_rows" \
        MOCK_PART_ROWS_FILE="$part_rows" \
        MOCK_PART_TYPE=part MOCK_PART_RO=0 MOCK_PART_MAJMIN='259:1' \
        MOCK_LSBLK_PKNAME='fakedisk' MOCK_PART_PATH_FIELD="$FAKE_PART_PATH" \
        "$@" \
        "$COPY" create "$FAKE_DEVICE" "$DEFAULT_MAJMIN" \
        > "$SANDBOX/work/stdout.$name" 2> "$SANDBOX/work/stderr.$name" && RC=0 || RC=$?
    log_result "$name" "$expected" "$RC"
    SCENARIO_COUNT=$((SCENARIO_COUNT + 1))
}

# ---- アサーションヘルパー ---------------------------------------------------

# assert_stage_bounds NAME PARTED(yes/no) MKFS(yes/no) MOUNT(yes/no) SYNC(yes/no)
# 破壊的モック (parted/mkfs/mount/sync) への到達・未到達を、失敗地点として
# 想定される段階と厳密に一致させる (失敗地点より後の処理へ進んでいないこと、
# かつ想定される段階までは正しく進んでいることの両方を1回で確認する)。
assert_stage_bounds() {
    name="$1"; parted_exp="$2"; mkfs_exp="$3"; mount_exp="$4"; sync_exp="$5"
    ok=1
    parted_called && parted_now=yes || parted_now=no
    mkfs_called && mkfs_now=yes || mkfs_now=no
    mount_called && mount_now=yes || mount_now=no
    sync_called && sync_now=yes || sync_now=no
    [ "$parted_now" = "$parted_exp" ] || ok=0
    [ "$mkfs_now" = "$mkfs_exp" ] || ok=0
    [ "$mount_now" = "$mount_exp" ] || ok=0
    [ "$sync_now" = "$sync_exp" ] || ok=0
    log_bool "${name}_stage_bounds" "$ok"
}

assert_parted_invocation_count() {
    name="$1"; expected_mklabel="$2"; expected_mkpart="$3"
    mklabel_count="$(grep -cF 'mklabel gpt' "$SANDBOX/work/parted-invocations" 2>/dev/null)" || mklabel_count=0
    mkpart_count="$(grep -cF 'mkpart' "$SANDBOX/work/parted-invocations" 2>/dev/null)" || mkpart_count=0
    if [ "$mklabel_count" -eq "$expected_mklabel" ] && [ "$mkpart_count" -eq "$expected_mkpart" ]; then
        log_bool "${name}_parted_invocation_count" 1
    else
        log_bool "${name}_parted_invocation_count" 0
    fi
}

# LOCK_DIR (run/lock/...) の除去確認。MNT_DIR (run/ 直下のmktemp生成物) とは
# 親ディレクトリの深さが異なるため、find の対象と衝突しない。
assert_lock_released() {
    name="$1"
    if [ -e "$LOCK_DIR_PATH" ]; then
        log_bool "${name}_lock_released" 0
    else
        log_bool "${name}_lock_released" 1
    fi
}

assert_lock_residual() {
    name="$1"
    if [ -e "$LOCK_DIR_PATH" ]; then
        log_bool "${name}_lock_residual_as_expected" 1
    else
        log_bool "${name}_lock_residual_as_expected" 0
    fi
}

# MNT_DIR (一時マウントディレクトリ) の除去確認。
assert_run_clean() {
    name="$1"
    if find "$SANDBOX/run" -mindepth 1 -maxdepth 1 -name 'mypocketos-persistence-setup-helper.*' 2>/dev/null | grep -q .; then
        log_bool "${name}_mnt_dir_removed" 0
    else
        log_bool "${name}_mnt_dir_removed" 1
    fi
}

assert_run_residual() {
    name="$1"
    if find "$SANDBOX/run" -mindepth 1 -maxdepth 1 -name 'mypocketos-persistence-setup-helper.*' 2>/dev/null | grep -q .; then
        log_bool "${name}_mnt_dir_residual_as_expected" 1
    else
        log_bool "${name}_mnt_dir_residual_as_expected" 0
    fi
}

# assert_stderr NAME SUBSTR [LABEL]
assert_stderr() {
    name="$1"; substr="$2"; label="${3:-message_shown}"
    if stderr_shows "$name" "$substr"; then
        log_bool "${name}_${label}" 1
    else
        log_bool "${name}_${label}" 0
    fi
}

echo "== failure-matrix: preparing sandbox and instrumented copy =="
sh -n "$COPY" && echo "sh -n: OK"
dash -n "$COPY" && echo "dash -n: OK"

echo "== failure-matrix: running scenarios =="

# ---------- exit 2: 引数不正・usage ----------
reset_scenario_state
run_usage_case mx2_wrong_argc 2 create "$FAKE_DEVICE"
assert_stderr mx2_wrong_argc 'usage: mypocketos-persistence-setup-helper create DEVICE MAJOR:MINOR'
assert_stage_bounds mx2_wrong_argc no no no no
assert_lock_released mx2_wrong_argc
assert_run_clean mx2_wrong_argc

reset_scenario_state
run_usage_case mx2_bad_op 2 destroy "$FAKE_DEVICE" "$DEFAULT_MAJMIN"
assert_stderr mx2_bad_op 'usage: mypocketos-persistence-setup-helper create DEVICE MAJOR:MINOR'
assert_stage_bounds mx2_bad_op no no no no
assert_lock_released mx2_bad_op
assert_run_clean mx2_bad_op

# ---------- exit 70: 必要なコマンドの不在・実行不可 ----------
reset_scenario_state
chmod -x "$SANDBOX/bin/wipefs"
run_matrix_case mx70_missing_wipefs 70 "$FAKE_DEVICE" "$DEFAULT_MAJMIN"
assert_stderr mx70_missing_wipefs '必要なコマンドが見つからないか実行できません'
assert_stage_bounds mx70_missing_wipefs no no no no
assert_lock_released mx70_missing_wipefs
assert_run_clean mx70_missing_wipefs

reset_scenario_state
chmod -x "$SANDBOX/bin/ls"
run_matrix_case mx70_missing_ls 70 "$FAKE_DEVICE" "$DEFAULT_MAJMIN"
assert_stderr mx70_missing_ls '必要なコマンドが見つからないか実行できません'
assert_stage_bounds mx70_missing_ls no no no no
assert_lock_released mx70_missing_ls
assert_run_clean mx70_missing_ls

# ---------- exit 10: 実行環境検証 (root/Live環境/live medium) ----------
reset_scenario_state
run_matrix_case mx10_not_root 10 "$FAKE_DEVICE" "$DEFAULT_MAJMIN" MOCK_UID=1000
assert_stderr mx10_not_root 'root権限で実行される必要があります'
assert_stage_bounds mx10_not_root no no no no
assert_lock_released mx10_not_root
assert_run_clean mx10_not_root

reset_scenario_state
run_matrix_case mx10_no_boot_live 10 "$FAKE_DEVICE" "$DEFAULT_MAJMIN" \
    MOCK_CMDLINE='BOOT_IMAGE=/live/vmlinuz nopersistence quiet'
assert_stderr mx10_no_boot_live 'カーネルコマンドラインのboot=live'
assert_stage_bounds mx10_no_boot_live no no no no
assert_lock_released mx10_no_boot_live
assert_run_clean mx10_no_boot_live

reset_scenario_state
run_matrix_case mx10_live_medium_not_mounted 10 "$FAKE_DEVICE" "$DEFAULT_MAJMIN" \
    MOCK_LIVE_MEDIUM_MOUNTED=1
assert_stderr mx10_live_medium_not_mounted 'live/medium がマウントされていません'
assert_stage_bounds mx10_live_medium_not_mounted no no no no
assert_lock_released mx10_live_medium_not_mounted
assert_run_clean mx10_live_medium_not_mounted

# ---------- exit 14: 対象ディスク使用中・安全判定不能 ----------
reset_scenario_state
empty_rows="$SANDBOX/work/mx14-empty-rows.txt"
: > "$empty_rows"
run_matrix_case mx14_fetch_rows_empty 14 "$FAKE_DEVICE" "$DEFAULT_MAJMIN" \
    MOCK_DISK_ROWS_FILE="$empty_rows"
assert_stderr mx14_fetch_rows_empty '対象ディスクの情報を取得できませんでした'
assert_stage_bounds mx14_fetch_rows_empty no no no no
assert_lock_released mx14_fetch_rows_empty
assert_run_clean mx14_fetch_rows_empty

reset_scenario_state
bad_name_rows="$(use_fixture helper-disk-rows-empty-name.txt mx14-badname-rows)"
run_matrix_case mx14_fetch_rows_malformed 14 "$FAKE_DEVICE" "$DEFAULT_MAJMIN" \
    MOCK_DISK_ROWS_FILE="$bad_name_rows"
assert_stderr mx14_fetch_rows_malformed '一部フィールド'
assert_stage_bounds mx14_fetch_rows_malformed no no no no
assert_lock_released mx14_fetch_rows_malformed
assert_run_clean mx14_fetch_rows_malformed

reset_scenario_state
mounted_rows="$(use_fixture helper-disk-rows-mounted.txt mx14-mounted-rows)"
run_matrix_case mx14_already_mounted 14 "$FAKE_DEVICE" "$DEFAULT_MAJMIN" \
    MOCK_DISK_ROWS_FILE="$mounted_rows"
assert_stderr mx14_already_mounted '既にマウントされています'
assert_stage_bounds mx14_already_mounted no no no no
assert_lock_released mx14_already_mounted
assert_run_clean mx14_already_mounted

reset_scenario_state
run_matrix_case mx14_swaps_read_fail 14 "$FAKE_DEVICE" "$DEFAULT_MAJMIN" \
    MOCK_FAIL_SWAPS_READ=1
assert_stderr mx14_swaps_read_fail '/proc/swapsの読み取りに失敗しました'
assert_stage_bounds mx14_swaps_read_fail no no no no
assert_lock_released mx14_swaps_read_fail
assert_run_clean mx14_swaps_read_fail

reset_scenario_state
run_matrix_case mx14_swaps_empty 14 "$FAKE_DEVICE" "$DEFAULT_MAJMIN" \
    MOCK_EMPTY_SWAPS_FILE=1
assert_stderr mx14_swaps_empty '/proc/swapsの内容を取得できませんでした'
assert_stage_bounds mx14_swaps_empty no no no no
assert_lock_released mx14_swaps_empty
assert_run_clean mx14_swaps_empty

reset_scenario_state
run_matrix_case mx14_swap_match 14 "$FAKE_DEVICE" "$DEFAULT_MAJMIN" \
    MOCK_SWAP_LINE='/dev/fakeswap                          partition       1048572         0               -2' \
    MOCK_SWAP_KNAME='fakedisk'
assert_stderr mx14_swap_match 'スワップとして使用中です'
assert_stage_bounds mx14_swap_match no no no no
assert_lock_released mx14_swap_match
assert_run_clean mx14_swap_match

reset_scenario_state
rm -rf "$SANDBOX/sys"
mkdir -p "$SANDBOX/sys/class/block/fakedisk"
: > "$SANDBOX/sys/class/block/fakedisk/device"
run_matrix_case mx14_holders_dir_missing 14 "$FAKE_DEVICE" "$DEFAULT_MAJMIN"
assert_stderr mx14_holders_dir_missing 'holders情報を取得できませんでした'
assert_stage_bounds mx14_holders_dir_missing no no no no
assert_lock_released mx14_holders_dir_missing
assert_run_clean mx14_holders_dir_missing

reset_scenario_state
run_matrix_case mx14_holders_unreadable 14 "$FAKE_DEVICE" "$DEFAULT_MAJMIN" \
    MOCK_FAIL_LS_HOLDERS=1
assert_stderr mx14_holders_unreadable 'holders情報の取得に失敗しました'
assert_stage_bounds mx14_holders_unreadable no no no no
assert_lock_released mx14_holders_unreadable
assert_run_clean mx14_holders_unreadable

reset_scenario_state
: > "$SANDBOX/sys/class/block/fakedisk/holders/dm-0"
run_matrix_case mx14_holders_nonempty 14 "$FAKE_DEVICE" "$DEFAULT_MAJMIN"
assert_stderr mx14_holders_nonempty 'device mapper 等の下位デバイスとして使用中です'
assert_stage_bounds mx14_holders_nonempty no no no no
assert_lock_released mx14_holders_nonempty
assert_run_clean mx14_holders_nonempty

reset_scenario_state
run_matrix_case mx14_live_source_fetch_fail 14 "$FAKE_DEVICE" "$DEFAULT_MAJMIN" \
    MOCK_FAIL_LIVE_SOURCE=1
assert_stderr mx14_live_source_fetch_fail 'Live起動元デバイスのSOURCEを取得できませんでした'
assert_stage_bounds mx14_live_source_fetch_fail no no no no
assert_lock_released mx14_live_source_fetch_fail
assert_run_clean mx14_live_source_fetch_fail

reset_scenario_state
run_matrix_case mx14_live_source_match 14 "$FAKE_DEVICE" "$DEFAULT_MAJMIN" \
    MOCK_ANCESTOR_KNAME='fakedisk'
assert_stderr mx14_live_source_match 'Live起動元デバイスと同一'
assert_stage_bounds mx14_live_source_match no no no no
assert_lock_released mx14_live_source_match
assert_run_clean mx14_live_source_match

reset_scenario_state
run_matrix_case mx14_home_info_fetch_fail 14 "$FAKE_DEVICE" "$DEFAULT_MAJMIN" \
    MOCK_FAIL_HOME_SOURCE=1
assert_stderr mx14_home_info_fetch_fail '/home提供元の情報を取得できませんでした'
assert_stage_bounds mx14_home_info_fetch_fail no no no no
assert_lock_released mx14_home_info_fetch_fail
assert_run_clean mx14_home_info_fetch_fail

reset_scenario_state
run_matrix_case mx14_home_source_parse_fail 14 "$FAKE_DEVICE" "$DEFAULT_MAJMIN" \
    MOCK_HOME_SOURCE='bad"value'
assert_stderr mx14_home_source_parse_fail '/home提供元のSOURCEフィールドを解析できませんでした'
assert_stage_bounds mx14_home_source_parse_fail no no no no
assert_lock_released mx14_home_source_parse_fail
assert_run_clean mx14_home_source_parse_fail

reset_scenario_state
run_matrix_case mx14_home_source_unsafe 14 "$FAKE_DEVICE" "$DEFAULT_MAJMIN" \
    MOCK_HOME_SOURCE='tmpfs' MOCK_HOME_FSTYPE='tmpfs'
assert_stderr mx14_home_source_unsafe '/home提供元のSOURCEを安全に判定できません'
assert_stage_bounds mx14_home_source_unsafe no no no no
assert_lock_released mx14_home_source_unsafe
assert_run_clean mx14_home_source_unsafe
# ---------- exit 15: 対象ディスクが未使用ではない ----------
reset_scenario_state
child_rows="$(use_fixture helper-disk-rows-has-child.txt mx15-child-rows)"
run_matrix_case mx15_has_children 15 "$FAKE_DEVICE" "$DEFAULT_MAJMIN" \
    MOCK_DISK_ROWS_FILE="$child_rows"
assert_stderr mx15_has_children '既に子パーティションを持っています'
assert_stage_bounds mx15_has_children no no no no
assert_lock_released mx15_has_children
assert_run_clean mx15_has_children

reset_scenario_state
run_matrix_case mx15_pttype_nonempty 15 "$FAKE_DEVICE" "$DEFAULT_MAJMIN" \
    MOCK_LSBLK_PTTYPE='gpt'
assert_stderr mx15_pttype_nonempty '既にパーティションテーブル'
assert_stage_bounds mx15_pttype_nonempty no no no no
assert_lock_released mx15_pttype_nonempty
assert_run_clean mx15_pttype_nonempty

reset_scenario_state
run_matrix_case mx15_wipefs_device_fetch_fail 15 "$FAKE_DEVICE" "$DEFAULT_MAJMIN" \
    MOCK_FAIL_WIPEFS_DEVICE=1
assert_stderr mx15_wipefs_device_fetch_fail 'wipefsによる署名検査に失敗しました'
assert_stage_bounds mx15_wipefs_device_fetch_fail no no no no
assert_lock_released mx15_wipefs_device_fetch_fail
assert_run_clean mx15_wipefs_device_fetch_fail

reset_scenario_state
run_matrix_case mx15_signature_detected 15 "$FAKE_DEVICE" "$DEFAULT_MAJMIN" \
    MOCK_WIPEFS_SIG='ext4'
assert_stderr mx15_signature_detected '対象ディスクには既存の署名'
assert_stage_bounds mx15_signature_detected no no no no
assert_lock_released mx15_signature_detected
assert_run_clean mx15_signature_detected

# ---------- exit 20: GPTパーティションテーブルの作成失敗 ----------
reset_scenario_state
run_success_track_case mx20_gpt_fail 20 MOCK_FAIL_GPT=1
assert_stderr mx20_gpt_fail 'GPTパーティションテーブルの作成に失敗しました'
assert_stage_bounds mx20_gpt_fail yes no no no
assert_parted_invocation_count mx20_gpt_fail 1 0
assert_lock_released mx20_gpt_fail
assert_run_clean mx20_gpt_fail

# ---------- exit 21: パーティション作成後の途中失敗 ----------
reset_scenario_state
run_success_track_case mx21_mkpart_fail 21 MOCK_FAIL_MKPART=1
assert_stderr mx21_mkpart_fail 'persistenceパーティションの作成に失敗しました'
assert_stage_bounds mx21_mkpart_fail yes no no no
if partprobe_called; then log_bool 'mx21_mkpart_fail_partprobe_not_called' 0; else log_bool 'mx21_mkpart_fail_partprobe_not_called' 1; fi
assert_lock_released mx21_mkpart_fail
assert_run_clean mx21_mkpart_fail

reset_scenario_state
run_success_track_case mx21_partprobe_fail 21 MOCK_FAIL_PARTPROBE=1
assert_stderr mx21_partprobe_fail 'partprobeによるパーティション情報の再読込に失敗しました'
assert_stage_bounds mx21_partprobe_fail yes no no no
if udevadm_called; then log_bool 'mx21_partprobe_fail_udevadm_not_called' 0; else log_bool 'mx21_partprobe_fail_udevadm_not_called' 1; fi
assert_lock_released mx21_partprobe_fail
assert_run_clean mx21_partprobe_fail

reset_scenario_state
run_success_track_case mx21_udevadm_fail 21 MOCK_FAIL_UDEVADM=1
assert_stderr mx21_udevadm_fail 'udevadm settleに失敗しました'
assert_stage_bounds mx21_udevadm_fail yes no no no
assert_lock_released mx21_udevadm_fail
assert_run_clean mx21_udevadm_fail

reset_scenario_state
empty_part_rows="$SANDBOX/work/mx21-empty-part-rows.txt"
: > "$empty_part_rows"
run_success_track_case mx21_identify_rows_empty 21 MOCK_PART_ROWS_FILE="$empty_part_rows"
assert_stderr mx21_identify_rows_empty '作成されたパーティション情報を取得できませんでした'
assert_stage_bounds mx21_identify_rows_empty yes no no no
assert_lock_released mx21_identify_rows_empty
assert_run_clean mx21_identify_rows_empty

reset_scenario_state
malformed_part_rows="$(use_fixture helper-part-rows-malformed-key.txt mx21-malformed-rows __FAKE_PART_PATH__ "$FAKE_PART_PATH")"
run_success_track_case mx21_identify_malformed 21 MOCK_PART_ROWS_FILE="$malformed_part_rows"
assert_stderr mx21_identify_malformed '作成されたパーティション情報の解析に失敗しました'
assert_stage_bounds mx21_identify_malformed yes no no no
assert_lock_released mx21_identify_malformed
assert_run_clean mx21_identify_malformed

reset_scenario_state
zero_part_rows="$(use_fixture helper-part-rows-zero.txt mx21-zero-rows __FAKE_PART_PATH__ "$FAKE_PART_PATH")"
run_success_track_case mx21_identify_count_zero 21 MOCK_PART_ROWS_FILE="$zero_part_rows"
assert_stderr mx21_identify_count_zero '一意に特定できませんでした'
assert_stage_bounds mx21_identify_count_zero yes no no no
assert_lock_released mx21_identify_count_zero
assert_run_clean mx21_identify_count_zero

reset_scenario_state
two_part_rows="$(use_fixture helper-part-rows-two.txt mx21-two-rows __FAKE_PART_PATH__ "$FAKE_PART_PATH")"
run_success_track_case mx21_identify_count_two 21 MOCK_PART_ROWS_FILE="$two_part_rows"
assert_stderr mx21_identify_count_two '一意に特定できませんでした'
assert_stage_bounds mx21_identify_count_two yes no no no
assert_lock_released mx21_identify_count_two
assert_run_clean mx21_identify_count_two

reset_scenario_state
nested_part_rows="$(use_fixture helper-part-rows-nested.txt mx21-nested-rows __FAKE_PART_PATH__ "$FAKE_PART_PATH")"
run_success_track_case mx21_identify_nested_path 21 MOCK_PART_ROWS_FILE="$nested_part_rows"
assert_stderr mx21_identify_nested_path 'PATHが/dev直下ではありません'
assert_stage_bounds mx21_identify_nested_path yes no no no
assert_lock_released mx21_identify_nested_path
assert_run_clean mx21_identify_nested_path

reset_scenario_state
badpkname_part_rows="$(use_fixture helper-part-rows-badpkname.txt mx21-badpkname-rows __FAKE_PART_PATH__ "$FAKE_PART_PATH")"
run_success_track_case mx21_identify_badpkname 21 MOCK_PART_ROWS_FILE="$badpkname_part_rows"
assert_stderr mx21_identify_badpkname 'PKNAMEが対象ディスクと一致しません'
assert_stage_bounds mx21_identify_badpkname yes no no no
assert_lock_released mx21_identify_badpkname
assert_run_clean mx21_identify_badpkname

reset_scenario_state
run_success_track_case mx21_identify_ro 21 MOCK_PART_RO=1
assert_stderr mx21_identify_ro '作成されたパーティションが読み取り専用です'
assert_stage_bounds mx21_identify_ro yes no no no
assert_lock_released mx21_identify_ro
assert_run_clean mx21_identify_ro

reset_scenario_state
run_success_track_case mx21_reverify_type_mismatch 21 MOCK_PART_TYPE='disk'
assert_stderr mx21_reverify_type_mismatch 'TYPEがpartではなくなっています'
assert_stage_bounds mx21_reverify_type_mismatch yes no no no
assert_lock_released mx21_reverify_type_mismatch
assert_run_clean mx21_reverify_type_mismatch

reset_scenario_state
run_success_track_case mx21_wipefs_part_fetch_fail 21 MOCK_FAIL_WIPEFS_PART=1
assert_stderr mx21_wipefs_part_fetch_fail '署名検査 (wipefs) に失敗しました'
assert_stage_bounds mx21_wipefs_part_fetch_fail yes no no no
assert_lock_released mx21_wipefs_part_fetch_fail
assert_run_clean mx21_wipefs_part_fetch_fail

reset_scenario_state
run_success_track_case mx21_signature_detected_part 21 MOCK_PART_WIPEFS_SIG='ext4'
assert_stderr mx21_signature_detected_part '作成されたパーティションに既存の署名'
assert_stage_bounds mx21_signature_detected_part yes no no no
assert_lock_released mx21_signature_detected_part
assert_run_clean mx21_signature_detected_part
# ---------- exit 22: ext4ファイルシステムの作成失敗 ----------
reset_scenario_state
run_success_track_case mx22_mkfs_fail 22 MOCK_FAIL_MKFS=1
assert_stderr mx22_mkfs_fail 'ext4ファイルシステムの作成に失敗しました'
assert_stage_bounds mx22_mkfs_fail yes yes no no
assert_lock_released mx22_mkfs_fail
assert_run_clean mx22_mkfs_fail

# ---------- exit 23: 一時マウント準備失敗 ----------
reset_scenario_state
run_success_track_case mx23_mktemp_fail 23 MOCK_FAIL_MKTEMP=1
assert_stderr mx23_mktemp_fail '一時作業ディレクトリの作成に失敗しました'
assert_stage_bounds mx23_mktemp_fail yes yes no no
assert_lock_released mx23_mktemp_fail
assert_run_clean mx23_mktemp_fail

reset_scenario_state
run_success_track_case mx23_mount_fail 23 MOCK_FAIL_MOUNT=1
assert_stderr mx23_mount_fail '一時マウントに失敗しました'
assert_stage_bounds mx23_mount_fail yes yes yes no
assert_lock_released mx23_mount_fail
assert_run_clean mx23_mount_fail

# ---------- exit 24: persistence.confの書き込み・内容確認失敗 ----------
reset_scenario_state
run_success_track_case mx24_write_fail 24 MOCK_CONF_PATH_IS_DIR=1
assert_stderr mx24_write_fail 'persistence.confの書き込みに失敗しました'
assert_stage_bounds mx24_write_fail yes yes yes no
assert_lock_released mx24_write_fail
assert_run_clean mx24_write_fail

reset_scenario_state
run_success_track_case mx24_size_mismatch 24 MOCK_CONF_SIZE=0
assert_stderr mx24_size_mismatch '内容確認に失敗しました (サイズ'
assert_stage_bounds mx24_size_mismatch yes yes yes no
assert_lock_released mx24_size_mismatch
assert_run_clean mx24_size_mismatch

reset_scenario_state
run_success_track_case mx24_content_mismatch 24 MOCK_FAKE_CONF_CONTENT='/not-home'
assert_stderr mx24_content_mismatch '内容不一致'
assert_stage_bounds mx24_content_mismatch yes yes yes no
assert_lock_released mx24_content_mismatch
assert_run_clean mx24_content_mismatch

# ---------- exit 25: sync/umount失敗 ----------
reset_scenario_state
run_success_track_case mx25_sync_fail 25 MOCK_FAIL_SYNC=1
assert_stderr mx25_sync_fail 'syncに失敗しました'
assert_stage_bounds mx25_sync_fail yes yes yes yes
assert_lock_released mx25_sync_fail
assert_run_clean mx25_sync_fail

reset_scenario_state
run_success_track_case mx25_umount_fail 25 MOCK_FAIL_UMOUNT=1
assert_stderr mx25_umount_fail 'アンマウントに失敗しました:'
assert_stderr mx25_umount_fail '後始末に失敗しました' cleanup_message_shown
assert_stage_bounds mx25_umount_fail yes yes yes yes
assert_lock_released mx25_umount_fail
assert_run_residual mx25_umount_fail

# ---------- exit 71: cleanup失敗による正規化・既存終了コードの保護 ----------
reset_scenario_state
run_success_track_case mx71_success_mnt_rmdir_fail 71 MOCK_FAIL_RMDIR_MNT=1
assert_stderr mx71_success_mnt_rmdir_fail '一時ディレクトリ'
assert_stderr mx71_success_mnt_rmdir_fail 'の削除に失敗' mnt_rmdir_message_shown
assert_lock_released mx71_success_mnt_rmdir_fail
assert_run_residual mx71_success_mnt_rmdir_fail

reset_scenario_state
run_success_track_case mx71_success_lock_rmdir_fail 71 MOCK_FAIL_RMDIR_LOCK=1
assert_stderr mx71_success_lock_rmdir_fail 'ロックディレクトリ'
assert_stderr mx71_success_lock_rmdir_fail 'の削除に失敗' lock_rmdir_message_shown
assert_run_clean mx71_success_lock_rmdir_fail
assert_lock_residual mx71_success_lock_rmdir_fail

# override: 既に失敗している終了コード (22) は、後始末 (ロック
# ディレクトリ削除) が失敗しても71へ上書きされない。
reset_scenario_state
run_success_track_case mx71_override_mkfs_fail_plus_lock_rmdir_fail 22 \
    MOCK_FAIL_MKFS=1 MOCK_FAIL_RMDIR_LOCK=1
assert_stderr mx71_override_mkfs_fail_plus_lock_rmdir_fail 'ext4ファイルシステムの作成に失敗しました'
assert_stderr mx71_override_mkfs_fail_plus_lock_rmdir_fail 'ロックディレクトリ' override_cleanup_message_shown
assert_lock_residual mx71_override_mkfs_fail_plus_lock_rmdir_fail

# override: 既に失敗している終了コード (24) は、後始末 (アンマウント)
# が失敗しても71やその他の値へ上書きされない。
reset_scenario_state
run_success_track_case mx71_override_conf_write_fail_plus_umount_fail 24 \
    MOCK_CONF_PATH_IS_DIR=1 MOCK_FAIL_UMOUNT=1
assert_stderr mx71_override_conf_write_fail_plus_umount_fail 'persistence.confの書き込みに失敗しました'
assert_stderr mx71_override_conf_write_fail_plus_umount_fail '後始末に失敗しました' override_umount_cleanup_message_shown
assert_lock_released mx71_override_conf_write_fail_plus_umount_fail
assert_run_residual mx71_override_conf_write_fail_plus_umount_fail

echo
echo "== helper failure-matrix summary =="
printf '%s' "$RESULTS"
echo "SCENARIOS=$SCENARIO_COUNT PASS=$PASS FAIL=$FAIL"

# 構造検査 (258件のアサーションには含めない): 実行されたシナリオ数が
# 期待値と一致しない場合、意図しないシナリオの追加・削除・条件付き
# スキップ・二重実行が疑われるため、PASS/FAILの値に関わらず失敗マトリクス
# 全体を非0終了にする。
structure_rc=0
if [ "$SCENARIO_COUNT" -ne "$EXPECTED_SCENARIOS" ]; then
    printf 'test_helper_failure_matrix.sh: 構造検査失敗: 実行されたシナリオ数 (%s) が期待値 (%s) と一致しません。シナリオの追加・削除・条件付きスキップが意図せず発生していないか確認してください。\n' \
        "$SCENARIO_COUNT" "$EXPECTED_SCENARIOS" >&2
    structure_rc=1
fi

if [ "$FAIL" -eq 0 ] && [ "$structure_rc" -eq 0 ]; then
    exit 0
else
    exit 1
fi
