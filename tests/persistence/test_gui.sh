#!/bin/sh
# tests/persistence/test_gui.sh
#
# mypocketos-persistence-setup (GUI本体) の非破壊モックテスト。
# production ファイルには一切書き込まない。実sudo・実helper・実parted・
# 実mkfs・実mount・実umountはいずれも呼び出さない。
set -eu

TESTS_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$TESTS_DIR/../.." && pwd)"
PROD_GUI="$REPO_ROOT/config/includes.chroot/usr/local/bin/mypocketos-persistence-setup"
PROD_HELPER="$REPO_ROOT/config/includes.chroot/usr/local/libexec/mypocketos-persistence-setup-helper"
. "$TESTS_DIR/common.sh"
. "$TESTS_DIR/mock_command.sh"

create_sandbox
trap on_common_exit EXIT

COPY="$SANDBOX/work/gui-copy"
sh "$TESTS_DIR/instrument_gui.sh" "$SANDBOX" "$COPY"

FIXTURES="$TESTS_DIR/fixtures"

# fakedisk が「完全に未使用のwhole disk」として通過するために必要な
# sandbox sys ツリーの既定状態 (物理デバイス根拠 + 空holders)。
setup_default_sys_tree() {
    rm -rf "$SANDBOX/sys"
    mkdir -p "$SANDBOX/sys/block/fakedisk" "$SANDBOX/sys/class/block/fakedisk/holders"
    : > "$SANDBOX/sys/block/fakedisk/device"

    # findmntモックのMOCK_LIVE_SOURCE既定値 ("$SANDBOX/dev/fakedisk") が
    # 実体を持つようにする。ancestor_knames_of_sourceは "-e" で実在を
    # 確認するため、既定状態でこのファイルが無いと (何も指定しなかった
    # だけの) 通常のシナリオまでLive起動元祖先追跡が失敗し、fail-closed
    # で候補0件になってしまう。既定のMOCK_ANCESTOR_KNAME ("unrelated-disk")
    # はfakedisk自身とは異なる値であるため、これ自体はfakedisk除外には
    # ならない。
    : > "$SANDBOX/dev/fakedisk"
}

reset_scenario_state() {
    write_mocks "$SANDBOX"
    setup_default_sys_tree
    rm -f "$SANDBOX/work/notice.log" "$SANDBOX/work/sudo-called" \
          "$SANDBOX/work/sudo-invocations" "$SANDBOX/work/progress-started" \
          "$SANDBOX/work/progress-invocation" \
          "$SANDBOX/work/mount-state" "$SANDBOX/work/yad-list-stdin.txt" \
          "$SANDBOX/work/mock-kill-invocations"
    : > "$SANDBOX/work/notice.log"
}

# use_fixture NAME
# fixtures/ 配下 (リポジトリ内、sandbox外) のファイルを、sandbox内の
# 作業ファイルへコピーしてそのパスを返す。モックコマンド (cat 等) は
# sandbox外のパスを拒否する制限ラッパーであるため、MOCK_ALL_ROWS_FILE等に
# fixtures/ のパスを直接渡すことはできない (コピー先はシナリオごとに
# 別名にし、直後の reset_scenario_state 等で上書きされないようにする)。
use_fixture() {
    dest="$SANDBOX/work/rows-$2.txt"
    cp -- "$FIXTURES/$1" "$dest"
    printf '%s' "$dest"
}

# run_gui / 各シナリオとも、GUIコピーの呼び出しは必ず
# "cmd && RC=0 || RC=$?" で終了コードを捕捉する ("cmd; rc=$?" は set -e 下
# で cmd 失敗時に rc=$? へ到達できない、このプロジェクトで既出の欠陥
# パターンのため)。
run_gui() {
    # run_gui NAME EXPECTED_EXIT ROWS_FIXTURE [env assignments...]
    name="$1"; expected="$2"; fixture="$3"; shift 3
    reset_scenario_state
    rows_file="$(use_fixture "$fixture" "$name")"
    env -i PATH='/usr/bin:/bin' HOME="$HOME" SANDBOX="$SANDBOX" \
        XDG_RUNTIME_DIR="$SANDBOX/xdg-runtime" \
        MOCK_ALL_ROWS_FILE="$rows_file" \
        "$@" \
        "$COPY" > "$SANDBOX/work/stdout.$name" 2> "$SANDBOX/work/stderr.$name" && RC=0 || RC=$?
    log_result "$name" "$expected" "$RC"
}

sudo_called() { [ -e "$SANDBOX/work/sudo-called" ]; }
sudo_invocation_count() { wc -l < "$SANDBOX/work/sudo-invocations" 2>/dev/null || echo 0; }
notice_shows() { grep -qF -- "$1" "$SANDBOX/work/notice.log" 2>/dev/null; }
lock_left_behind() { [ -e "$SANDBOX/xdg-runtime/mypocketos-persistence-setup.lock" ]; }

echo "== GUI: preparing sandbox and instrumented copy =="
sh -n "$COPY" && echo "sh -n: OK"
dash -n "$COPY" && echo "dash -n: OK"

echo "== GUI: running scenarios =="

# ---------- 1: boot=live未検出 ----------
reset_scenario_state
env -i PATH='/usr/bin:/bin' HOME="$HOME" SANDBOX="$SANDBOX" \
    XDG_RUNTIME_DIR="$SANDBOX/xdg-runtime" \
    MOCK_CMDLINE='BOOT_IMAGE=/vmlinuz quiet' \
    "$COPY" > /dev/null 2> "$SANDBOX/work/stderr.1" && RC=0 || RC=$?
log_result 'gui_live_env_missing_boot_live' 1 "$RC"
if lock_left_behind; then
    log_bool 'gui_live_env_missing_boot_live_no_lock' 0
else
    log_bool 'gui_live_env_missing_boot_live_no_lock' 1
fi

# ---------- 2: XDG_RUNTIME_DIR不正 (未設定) ----------
reset_scenario_state
env -i PATH='/usr/bin:/bin' HOME="$HOME" SANDBOX="$SANDBOX" \
    "$COPY" > /dev/null 2> "$SANDBOX/work/stderr.2" && RC=0 || RC=$?
log_result 'gui_xdg_runtime_dir_invalid' 1 "$RC"
if lock_left_behind; then
    log_bool 'gui_xdg_runtime_dir_invalid_no_lock' 0
else
    log_bool 'gui_xdg_runtime_dir_invalid_no_lock' 1
fi

# ---------- 3: clean diskのみ候補化 (混在データセット) ----------
reset_scenario_state
rows_file="$(use_fixture gui-rows-mixed.txt 3)"
env -i PATH='/usr/bin:/bin' HOME="$HOME" SANDBOX="$SANDBOX" \
    XDG_RUNTIME_DIR="$SANDBOX/xdg-runtime" \
    MOCK_ALL_ROWS_FILE="$rows_file" MOCK_LIST_RC=1 \
    "$COPY" > /dev/null 2> "$SANDBOX/work/stderr.3" && RC=0 || RC=$?
log_result 'gui_candidate_clean_disk_only' 0 "$RC"
if notice_shows '対象デバイスが見つかりません'; then
    log_bool 'gui_candidate_clean_disk_only_not_empty' 0
else
    log_bool 'gui_candidate_clean_disk_only_not_empty' 1
fi

# yad --list へ実際に渡された候補データ (yadモックがstdinをそのまま
# 保存したもの) を検証する。「見つかりません」が表示されないことだけを
# もって「clean diskのみ」を確認したことにはならない (除外対象が紛れて
# いても検出できない偽陽性になりうる) ため、渡されたパス列を直接確認する。
list_stdin="$SANDBOX/work/yad-list-stdin.txt"
if [ -e "$list_stdin" ]; then
    # yad_dataは末尾のフィールド (接続方式) の後ろに改行を持たない
    # (コマンド置換が末尾改行を取り除くため、これはproductionの正常な
    # 挙動である)。"wc -l" は改行文字の個数を数えるため、この最終行を
    # 1件少なく数えてしまう。"awk 'END{print NR}'" は末尾に改行のない
    # 最終行も1行として数えるため、こちらを使う。
    # 1候補あたり8行 (表示列5 + 非表示HD列3: 実DEVICE・実MAJMIN・
    # mode種別)。この候補セットには1件のみ含まれるはずなので8行となる。
    line_count="$(awk 'END { print NR }' "$list_stdin")"
    has_fakedisk=0
    grep -qxF '/dev/fakedisk' "$list_stdin" && has_fakedisk=1
    has_excluded=0
    grep -qxF '/dev/sda' "$list_stdin" && has_excluded=1
    grep -qxF '/dev/sda1' "$list_stdin" && has_excluded=1
    if [ "$line_count" -eq 8 ] && [ "$has_fakedisk" -eq 1 ] && [ "$has_excluded" -eq 0 ]; then
        log_bool 'gui_candidate_clean_disk_only_exact_candidate_list' 1
    else
        log_bool 'gui_candidate_clean_disk_only_exact_candidate_list' 0
    fi
else
    log_bool 'gui_candidate_clean_disk_only_exact_candidate_list' 0
fi

# ---------- 4: mount済み除外 ----------
run_gui gui_candidate_mount_excluded 0 gui-rows-mounted.txt
if notice_shows '対象デバイスが見つかりません'; then
    log_bool 'gui_candidate_mount_excluded_empty' 1
else
    log_bool 'gui_candidate_mount_excluded_empty' 0
fi

# ---------- 5: swap祖先除外 ----------
reset_scenario_state
rows_file="$(use_fixture gui-rows-clean-disk.txt 5)"
: > "$SANDBOX/dev/fake-swap-part"
env -i PATH='/usr/bin:/bin' HOME="$HOME" SANDBOX="$SANDBOX" \
    XDG_RUNTIME_DIR="$SANDBOX/xdg-runtime" \
    MOCK_ALL_ROWS_FILE="$rows_file" \
    MOCK_SWAP_LINE="$SANDBOX/dev/fake-swap-part partition 1048572 0 -2" \
    MOCK_ANCESTOR_KNAME='fakedisk' \
    "$COPY" > /dev/null 2> "$SANDBOX/work/stderr.5" && RC=0 || RC=$?
log_result 'gui_candidate_swap_excluded_via_ancestor' 0 "$RC"
if notice_shows '対象デバイスが見つかりません'; then
    log_bool 'gui_candidate_swap_excluded_empty' 1
else
    log_bool 'gui_candidate_swap_excluded_empty' 0
fi

# ---------- 6: holders除外 ----------
reset_scenario_state
rows_file="$(use_fixture gui-rows-clean-disk.txt 6)"
: > "$SANDBOX/sys/class/block/fakedisk/holders/dm-0"
env -i PATH='/usr/bin:/bin' HOME="$HOME" SANDBOX="$SANDBOX" \
    XDG_RUNTIME_DIR="$SANDBOX/xdg-runtime" \
    MOCK_ALL_ROWS_FILE="$rows_file" \
    "$COPY" > /dev/null 2> "$SANDBOX/work/stderr.6" && RC=0 || RC=$?
log_result 'gui_candidate_holders_excluded' 0 "$RC"
if notice_shows '対象デバイスが見つかりません'; then
    log_bool 'gui_candidate_holders_excluded_empty' 1
else
    log_bool 'gui_candidate_holders_excluded_empty' 0
fi

# ---------- 7: Live起動元除外 ----------
reset_scenario_state
rows_file="$(use_fixture gui-rows-clean-disk.txt 7)"
: > "$SANDBOX/dev/fake-live-source"
env -i PATH='/usr/bin:/bin' HOME="$HOME" SANDBOX="$SANDBOX" \
    XDG_RUNTIME_DIR="$SANDBOX/xdg-runtime" \
    MOCK_ALL_ROWS_FILE="$rows_file" \
    MOCK_LIVE_SOURCE="$SANDBOX/dev/fake-live-source" MOCK_ANCESTOR_KNAME='fakedisk' \
    "$COPY" > /dev/null 2> "$SANDBOX/work/stderr.7" && RC=0 || RC=$?
log_result 'gui_candidate_live_source_excluded' 0 "$RC"
if notice_shows '対象デバイスが見つかりません'; then
    log_bool 'gui_candidate_live_source_excluded_empty' 1
else
    log_bool 'gui_candidate_live_source_excluded_empty' 0
fi

# ---------- 8: home提供元除外 ----------
reset_scenario_state
rows_file="$(use_fixture gui-rows-clean-disk.txt 8)"
: > "$SANDBOX/dev/fake-home-source"
env -i PATH='/usr/bin:/bin' HOME="$HOME" SANDBOX="$SANDBOX" \
    XDG_RUNTIME_DIR="$SANDBOX/xdg-runtime" \
    MOCK_ALL_ROWS_FILE="$rows_file" \
    MOCK_HOME_SOURCE="$SANDBOX/dev/fake-home-source" MOCK_HOME_FSTYPE='ext4' \
    MOCK_ANCESTOR_KNAME='fakedisk' \
    "$COPY" > /dev/null 2> "$SANDBOX/work/stderr.8" && RC=0 || RC=$?
log_result 'gui_candidate_home_source_excluded' 0 "$RC"
if notice_shows '対象デバイスが見つかりません'; then
    log_bool 'gui_candidate_home_source_excluded_empty' 1
else
    log_bool 'gui_candidate_home_source_excluded_empty' 0
fi

# ---------- 9: /home findmnt失敗によるfail-closed ----------
run_gui gui_candidate_home_findmnt_failure_fail_closed 0 gui-rows-clean-disk.txt \
    MOCK_FAIL_HOME_SOURCE=1
if notice_shows '対象デバイスが見つかりません'; then
    log_bool 'gui_candidate_home_findmnt_failure_empty' 1
else
    log_bool 'gui_candidate_home_findmnt_failure_empty' 0
fi

# ---------- 10: findmntのraw+pairs併用回帰 (動的) ----------
# 候補が見つかったことだけを確認したいので、一覧表示後は
# キャンセル(MOCK_LIST_RC=1)で正常終了させる (シナリオ3と同じ形)。
run_gui gui_findmnt_raw_pairs_rejected_success 0 gui-rows-clean-disk.txt MOCK_LIST_RC=1
if notice_shows '対象デバイスが見つかりません'; then
    log_bool 'gui_findmnt_raw_pairs_rejected_success_not_empty' 0
else
    log_bool 'gui_findmnt_raw_pairs_rejected_success_not_empty' 1
fi

# ---------- 11: 一覧キャンセルでsudo未到達 ----------
run_gui gui_list_cancel_no_sudo 0 gui-rows-clean-disk.txt MOCK_LIST_RC=1
if sudo_called; then
    log_bool 'gui_list_cancel_no_sudo_check' 0
else
    log_bool 'gui_list_cancel_no_sudo_check' 1
fi

# ---------- 12: 確認不一致でsudo未到達 ----------
# yadの選択結果 (表示列5件+非表示HD列3件) の詳細はシナリオ13のコメントを
# 参照。
run_gui gui_confirm_mismatch_no_sudo 0 gui-rows-clean-disk.txt \
    MOCK_LIST_SELECTION='/dev/fakedisk'"$(printf '\001')"'16.0 GiB'"$(printf '\001')"'Fake Disk'"$(printf '\001')"'FAKE123'"$(printf '\001')"'usb'"$(printf '\001')"'/dev/fakedisk'"$(printf '\001')"'259:0'"$(printf '\001')"'A' \
    MOCK_ENTRY_TEXT='ERASE /dev/wrong'
if sudo_called; then
    log_bool 'gui_confirm_mismatch_no_sudo_check' 0
else
    log_bool 'gui_confirm_mismatch_no_sudo_check' 1
fi
if notice_shows '確認文字列が一致しなかった'; then
    log_bool 'gui_confirm_mismatch_message_shown' 1
else
    log_bool 'gui_confirm_mismatch_message_shown' 0
fi

# ---------- 13: 正しい確認文字列でsudoが正確に1回 ----------
# yadの選択結果は、表示列 (パス・サイズ・モデル・シリアル番号・接続方式)
# に続けて、内部識別専用の非表示 (HD) 列 (実DEVICE・実MAJMIN・mode種別)
# を含む8フィールドの\001区切り文字列として返る (実機で発覚した不具合の
# 修正により、表示列と内部識別値が別々になった。gui-rows-clean-disk.txt
# のfakedisk行: SIZE=17179869184 バイト = 16.0 GiB, MODEL="Fake Disk",
# SERIAL="FAKE123", TRAN="usb", MAJ:MIN="259:0")。
run_gui gui_confirm_correct_sudo_called_once 0 gui-rows-clean-disk.txt \
    MOCK_LIST_SELECTION='/dev/fakedisk'"$(printf '\001')"'16.0 GiB'"$(printf '\001')"'Fake Disk'"$(printf '\001')"'FAKE123'"$(printf '\001')"'usb'"$(printf '\001')"'/dev/fakedisk'"$(printf '\001')"'259:0'"$(printf '\001')"'A' \
    MOCK_ENTRY_TEXT='ERASE /dev/fakedisk' MOCK_HELPER_RC=0
count="$(sudo_invocation_count)"
if sudo_called && [ "$count" -eq 1 ]; then
    log_bool 'gui_confirm_correct_sudo_called_once_check' 1
else
    log_bool 'gui_confirm_correct_sudo_called_once_check' 0
fi

# 進捗ダイアログが、数値パーセンテージではなく不定進捗 (pulsate) +
# 固定の処理中メッセージで表示されていること (実機で確認された「0%の
# まま停止しているように見える」UX問題の回帰防止)。
progress_invocation="$SANDBOX/work/progress-invocation"
progress_text_value=''
if [ -e "$progress_invocation" ]; then
    progress_text_value="$(grep -oE -- '--progress-text=[^ ]*' "$progress_invocation" | head -n1 | sed 's/^--progress-text=//')"
fi
if [ -e "$progress_invocation" ] \
    && grep -qF -- '--pulsate' "$progress_invocation" \
    && [ -n "$progress_text_value" ] \
    && ! printf '%s' "$progress_text_value" | grep -qE '^[0-9]+%?$' \
    && ! grep -qF -- '--percentage=' "$progress_invocation"; then
    log_bool 'gui_progress_indeterminate_not_percentage' 1
else
    log_bool 'gui_progress_indeterminate_not_percentage' 0
fi

echo
echo "== GUI summary =="
printf '%s' "$RESULTS"
echo "PASS=$PASS FAIL=$FAIL"

if [ "$FAIL" -eq 0 ]; then
    exit 0
else
    exit 1
fi
