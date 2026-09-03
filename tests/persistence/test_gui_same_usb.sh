#!/bin/sh
# tests/persistence/test_gui_same_usb.sh
#
# mypocketos-persistence-setup (GUI本体) の build_same_usb_candidate
# (Mode B: 起動元USBの末尾未使用領域) に対する非破壊モックテスト。
# production ファイルには一切書き込まない。実sudo・実helper・実lsblk・
# 実findmntはいずれも呼び出さない。
#
# Mode A (build_candidates) の既存挙動・既存テスト (test_gui.sh) は
# 一切変更していない。本ファイルはMode B候補検出・一覧表示上の区別・
# 確認ダイアログ (ERASE type-to-confirmを流用しないこと)・helper呼び出し
# (create-same-usb) に焦点を当てる。
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

# Mode Bの起動元USB (fakedisk) 用のsysツリー。check_usb_transport相当の
# 予備判定 (TRAN・sysfs実経路) が通過できるよう、USBバスを模したパスへの
# シンボリックリンクとして/sys/block/fakedisk/deviceを作る
# (test_helper_same_usb.sh のsetup_same_usb_sys_treeと同じ考え方だが、
# GUIは"/sys/block/<kname>/device" 側を物理デバイス根拠として使う点が
# helper "/sys/class/block/<KNAME>/device" とは異なる)。
setup_same_usb_sys_tree() {
    rm -rf "$SANDBOX/sys"
    mkdir -p "$SANDBOX/sys/class/block/fakedisk/holders"
    mkdir -p "$SANDBOX/sys/block/fakedisk"
    mkdir -p "$SANDBOX/sys/devices/fake-pci/usb1/1-1/1-1:1.0/host0/target0:0:0/0:0:0:0"
    ln -s "$SANDBOX/sys/devices/fake-pci/usb1/1-1/1-1:1.0/host0/target0:0:0/0:0:0:0" \
        "$SANDBOX/sys/block/fakedisk/device"
    ln -s "$SANDBOX/sys/devices/fake-pci/usb1/1-1/1-1:1.0/host0/target0:0:0/0:0:0:0" \
        "$SANDBOX/sys/class/block/fakedisk/device"
    : > "$SANDBOX/dev/fakedisk"
}

reset_scenario_state() {
    write_mocks "$SANDBOX"
    setup_same_usb_sys_tree
    rm -f "$SANDBOX/work/notice.log" "$SANDBOX/work/sudo-called" \
          "$SANDBOX/work/sudo-invocations" "$SANDBOX/work/sudo-args" \
          "$SANDBOX/work/progress-started" "$SANDBOX/work/progress-invocation" \
          "$SANDBOX/work/mount-state" \
          "$SANDBOX/work/yad-list-stdin.txt" "$SANDBOX/work/mock-kill-invocations"
    : > "$SANDBOX/work/notice.log"
}

use_fixture() {
    dest="$SANDBOX/work/rows-$2.txt"
    cp -- "$FIXTURES/$1" "$dest"
    printf '%s' "$dest"
}

sudo_called() { [ -e "$SANDBOX/work/sudo-called" ]; }
sudo_invocation_count() { wc -l < "$SANDBOX/work/sudo-invocations" 2>/dev/null || echo 0; }
sudo_args() { cat "$SANDBOX/work/sudo-args" 2>/dev/null || printf ''; }
notice_shows() { grep -qF -- "$1" "$SANDBOX/work/notice.log" 2>/dev/null; }
list_stdin_shows() { grep -qF -- "$1" "$SANDBOX/work/yad-list-stdin.txt" 2>/dev/null; }

# build_selection DISP_PATH DISP_SIZE DISP_MODEL DISP_SERIAL DISP_TRAN \
#                 REAL_DEVICE REAL_MAJMIN MODE
# yad --listの選択結果 (表示列5件 + 非表示HD列3件: 実DEVICE・実MAJMIN・
# mode種別) を模した\001区切り文字列を組み立てる。mock_command.shの
# yadモックはMOCK_LIST_SELECTIONを選択結果としてそのまま返すだけであり、
# 実yadのように行データから該当行を検索して返すわけではないため、
# テスト側がここで「選択された1行分の全フィールド」を正確に用意する
# 必要がある (表示列だけを与えると、production側が非表示HD列から読み取る
# DEVICE/MAJOR:MINOR/mode種別が空になり、実機で発覚した不具合を
# 再現できずに見逃してしまう)。
build_selection() {
    printf '%s\001%s\001%s\001%s\001%s\001%s\001%s\001%s' \
        "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8"
}

# 空のMode A候補セット (Mode B単独のシナリオ用)。実在するdisk行が
# 1件もない、既存fixtureのmount済み行を流用する (Mode A側は必ず
# 除外される)。
EMPTY_A_ROWS='gui-rows-mounted.txt'

DEFAULT_ANCESTOR_CHAIN_ROWS='KNAME="fakedisk1" TYPE="part"
KNAME="fakedisk" TYPE="disk"'
DEFAULT_DISK_ROW='NAME="fakedisk" KNAME="fakedisk" PATH="__SANDBOX_DEV__/fakedisk" MAJ:MIN="254:0" TYPE="disk" SIZE="8589934592" RO="0" MODEL="UDisk" SERIAL="ABC123" TRAN="usb"'
# 実機Hybrid ISO構造 (sda1 start=64,size=3492416セクタ / sda2
# start=540,size=6656セクタ、sda2はsda1にネスト) をSTART (常に512バイト
# セクタ単位) ・SIZE (-b指定によりバイト単位) で表現する。
DEFAULT_CHILD_ROWS='NAME="fakedisk1" TYPE="part" START="64" SIZE="1788116992" PKNAME="fakedisk"
NAME="fakedisk2" TYPE="part" START="540" SIZE="3407872" PKNAME="fakedisk"'

# run_same_usb_gui NAME EXPECTED_EXIT [env assignments...]
# 既定値はMode B候補が1件検出され、一覧をキャンセル (MOCK_LIST_RC=1) して
# 正常終了する構成。個々のシナリオは env assignments で上書きする。
run_same_usb_gui() {
    name="$1"; expected="$2"; shift 2
    reset_scenario_state
    all_rows="$(use_fixture "$EMPTY_A_ROWS" "$name")"
    disk_row="$(printf '%s' "$DEFAULT_DISK_ROW" | sed "s#__SANDBOX_DEV__#$SANDBOX/dev#g")"
    env -i PATH='/usr/bin:/bin' HOME="$HOME" SANDBOX="$SANDBOX" \
        XDG_RUNTIME_DIR="$SANDBOX/xdg-runtime" \
        MOCK_ALL_ROWS_FILE="$all_rows" \
        MOCK_SAME_USB_ANCESTOR_CHAIN_ROWS="$DEFAULT_ANCESTOR_CHAIN_ROWS" \
        MOCK_SAME_USB_DISK_ROW="$disk_row" \
        MOCK_SAME_USB_CHILD_ROWS="$DEFAULT_CHILD_ROWS" \
        MOCK_LIST_RC=1 \
        "$@" \
        "$COPY" > "$SANDBOX/work/stdout.$name" 2> "$SANDBOX/work/stderr.$name" && RC=0 || RC=$?
    log_result "$name" "$expected" "$RC"
}

echo "== GUI (same-usb): preparing sandbox and instrumented copy =="
sh -n "$COPY" && echo "sh -n: OK"
dash -n "$COPY" && echo "dash -n: OK"

echo "== GUI (same-usb): running scenarios =="

# ==============================================================================
# 正常系: Mode B候補が検出され、一覧に「MyPocketOS 起動USB」「空き容量」
# 表記で表示されること。
# ==============================================================================
run_same_usb_gui gui_same_usb_candidate_shown 0
if list_stdin_shows 'MyPocketOS 起動USB' && list_stdin_shows '空き容量 約6.3 GiB'; then
    log_bool 'gui_same_usb_candidate_shown_display_text' 1
else
    log_bool 'gui_same_usb_candidate_shown_display_text' 0
fi
if notice_shows '対象デバイスが見つかりません'; then
    log_bool 'gui_same_usb_candidate_shown_not_empty' 0
else
    log_bool 'gui_same_usb_candidate_shown_not_empty' 1
fi

# ==============================================================================
# 正常系: Mode B候補を選択し確認ダイアログを承認すると、sudoが
# create-same-usb DEVICE MAJMINで正確に1回だけ呼ばれること。
# ERASE type-to-confirmは使われない (--entry呼び出しが発生しない) こと。
# ==============================================================================
reset_scenario_state
all_rows="$(use_fixture "$EMPTY_A_ROWS" gui_same_usb_confirm_dispatch)"
disk_row="$(printf '%s' "$DEFAULT_DISK_ROW" | sed "s#__SANDBOX_DEV__#$SANDBOX/dev#g")"
env -i PATH='/usr/bin:/bin' HOME="$HOME" SANDBOX="$SANDBOX" \
    XDG_RUNTIME_DIR="$SANDBOX/xdg-runtime" \
    MOCK_ALL_ROWS_FILE="$all_rows" \
    MOCK_SAME_USB_ANCESTOR_CHAIN_ROWS="$DEFAULT_ANCESTOR_CHAIN_ROWS" \
    MOCK_SAME_USB_DISK_ROW="$disk_row" \
    MOCK_SAME_USB_CHILD_ROWS="$DEFAULT_CHILD_ROWS" \
    MOCK_LIST_SELECTION="$(build_selection 'MyPocketOS 起動USB' '空き容量 約6.3 GiB (USB全体 8.0 GiB)' 'UDisk' 'ABC123' 'usb' "$SANDBOX/dev/fakedisk" '254:0' 'B')" \
    MOCK_NOTICE_RC=0 MOCK_HELPER_RC=0 \
    "$COPY" > "$SANDBOX/work/stdout.dispatch" 2> "$SANDBOX/work/stderr.dispatch" && RC=0 || RC=$?
log_result 'gui_same_usb_confirm_dispatch_exit0' 0 "$RC"
count="$(sudo_invocation_count)"
if sudo_called && [ "$count" -eq 1 ]; then
    log_bool 'gui_same_usb_confirm_dispatch_sudo_once' 1
else
    log_bool 'gui_same_usb_confirm_dispatch_sudo_once' 0
fi
if printf '%s' "$(sudo_args)" | grep -qF -- "create-same-usb $SANDBOX/dev/fakedisk 254:0"; then
    log_bool 'gui_same_usb_confirm_dispatch_correct_op' 1
else
    log_bool 'gui_same_usb_confirm_dispatch_correct_op' 0
fi
if notice_shows 'ERASE'; then
    log_bool 'gui_same_usb_confirm_dispatch_no_erase_wording' 0
else
    log_bool 'gui_same_usb_confirm_dispatch_no_erase_wording' 1
fi
if notice_shows 'MyPocketOSの起動領域'; then
    log_bool 'gui_same_usb_confirm_dispatch_shows_no_erase_of_boot_area' 1
else
    log_bool 'gui_same_usb_confirm_dispatch_shows_no_erase_of_boot_area' 0
fi

# 進捗ダイアログが、数値パーセンテージではなく不定進捗 (pulsate) +
# 固定の処理中メッセージで表示されていること (実機で確認された「0%の
# まま停止しているように見える」UX問題の回帰防止、Mode B側)。
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
    log_bool 'gui_same_usb_progress_indeterminate_not_percentage' 1
else
    log_bool 'gui_same_usb_progress_indeterminate_not_percentage' 0
fi

# ==============================================================================
# 確認ダイアログでキャンセルすると、sudoは一切呼ばれないこと。
# ==============================================================================
reset_scenario_state
all_rows="$(use_fixture "$EMPTY_A_ROWS" gui_same_usb_confirm_cancel)"
disk_row="$(printf '%s' "$DEFAULT_DISK_ROW" | sed "s#__SANDBOX_DEV__#$SANDBOX/dev#g")"
env -i PATH='/usr/bin:/bin' HOME="$HOME" SANDBOX="$SANDBOX" \
    XDG_RUNTIME_DIR="$SANDBOX/xdg-runtime" \
    MOCK_ALL_ROWS_FILE="$all_rows" \
    MOCK_SAME_USB_ANCESTOR_CHAIN_ROWS="$DEFAULT_ANCESTOR_CHAIN_ROWS" \
    MOCK_SAME_USB_DISK_ROW="$disk_row" \
    MOCK_SAME_USB_CHILD_ROWS="$DEFAULT_CHILD_ROWS" \
    MOCK_LIST_SELECTION="$(build_selection 'MyPocketOS 起動USB' '空き容量 約6.3 GiB (USB全体 8.0 GiB)' 'UDisk' 'ABC123' 'usb' "$SANDBOX/dev/fakedisk" '254:0' 'B')" \
    MOCK_NOTICE_RC=1 \
    "$COPY" > "$SANDBOX/work/stdout.cancel" 2> "$SANDBOX/work/stderr.cancel" && RC=0 || RC=$?
log_result 'gui_same_usb_confirm_cancel_exit0' 0 "$RC"
if sudo_called; then
    log_bool 'gui_same_usb_confirm_cancel_no_sudo' 0
else
    log_bool 'gui_same_usb_confirm_cancel_no_sudo' 1
fi

# ==============================================================================
# 拒否系: USB接続として確認できない (TRAN不一致) -> Mode B候補が出ない。
# ==============================================================================
run_same_usb_gui gui_same_usb_not_usb_tran_empty 0 \
    MOCK_SAME_USB_DISK_ROW="$(printf '%s' "$DEFAULT_DISK_ROW" | sed "s#__SANDBOX_DEV__#$SANDBOX/dev#g;s/TRAN=\"usb\"/TRAN=\"ata\"/")"
if notice_shows '対象デバイスが見つかりません'; then
    log_bool 'gui_same_usb_not_usb_tran_empty_check' 1
else
    log_bool 'gui_same_usb_not_usb_tran_empty_check' 0
fi

# ==============================================================================
# 拒否系: 祖先チェーンにTYPE=diskが複数/0件 -> Mode B候補が出ない。
# ==============================================================================
run_same_usb_gui gui_same_usb_ambiguous_ancestor_empty 0 \
    MOCK_SAME_USB_ANCESTOR_CHAIN_ROWS='KNAME="fakedisk" TYPE="disk"
KNAME="otherdisk" TYPE="disk"'
if notice_shows '対象デバイスが見つかりません'; then
    log_bool 'gui_same_usb_ambiguous_ancestor_empty_check' 1
else
    log_bool 'gui_same_usb_ambiguous_ancestor_empty_check' 0
fi

# ==============================================================================
# 拒否系: 末尾未使用領域が予備判定の最小サイズ (1GiB) 未満 -> 候補が
# 出ない。ディスク総サイズを縮小する (既存partition終端はそのまま)。
# ==============================================================================
run_same_usb_gui gui_same_usb_insufficient_space_empty 0 \
    MOCK_SAME_USB_DISK_ROW="$(printf '%s' "$DEFAULT_DISK_ROW" | sed "s#__SANDBOX_DEV__#$SANDBOX/dev#g;s/SIZE=\"8589934592\"/SIZE=\"2000000000\"/")"
if notice_shows '対象デバイスが見つかりません'; then
    log_bool 'gui_same_usb_insufficient_space_empty_check' 1
else
    log_bool 'gui_same_usb_insufficient_space_empty_check' 0
fi

# ==============================================================================
# Mode AとMode Bが同時に候補として表示され、それぞれ独立して機能する
# こと (Mode B追加によるMode A回帰がないことの直接確認)。
# ==============================================================================
reset_scenario_state
mixed_rows="$SANDBOX/work/rows-mixed-ab.txt"
cat > "$mixed_rows" <<ROWS_EOF
NAME="otherdisk" KNAME="otherdisk" PATH="$SANDBOX/dev/otherdisk" MAJ:MIN="259:0" TYPE="disk" SIZE="17179869184" RO="0" RM="1" HOTPLUG="1" MOUNTPOINTS="" FSTYPE="" PTTYPE="" LABEL="" PARTLABEL="" PKNAME="" MODEL="Other Disk" SERIAL="OTHER456" TRAN="usb"
ROWS_EOF
: > "$SANDBOX/dev/otherdisk"
mkdir -p "$SANDBOX/sys/block/otherdisk" "$SANDBOX/sys/class/block/otherdisk/holders"
: > "$SANDBOX/sys/block/otherdisk/device"
disk_row="$(printf '%s' "$DEFAULT_DISK_ROW" | sed "s#__SANDBOX_DEV__#$SANDBOX/dev#g")"
env -i PATH='/usr/bin:/bin' HOME="$HOME" SANDBOX="$SANDBOX" \
    XDG_RUNTIME_DIR="$SANDBOX/xdg-runtime" \
    MOCK_ALL_ROWS_FILE="$mixed_rows" \
    MOCK_ANCESTOR_KNAME='fakedisk' \
    MOCK_SAME_USB_ANCESTOR_CHAIN_ROWS="$DEFAULT_ANCESTOR_CHAIN_ROWS" \
    MOCK_SAME_USB_DISK_ROW="$disk_row" \
    MOCK_SAME_USB_CHILD_ROWS="$DEFAULT_CHILD_ROWS" \
    MOCK_LIST_RC=1 \
    "$COPY" > "$SANDBOX/work/stdout.mixed_ab" 2> "$SANDBOX/work/stderr.mixed_ab" && RC=0 || RC=$?
log_result 'gui_same_usb_and_mode_a_both_shown_exit0' 0 "$RC"
if list_stdin_shows "$SANDBOX/dev/otherdisk" && list_stdin_shows 'MyPocketOS 起動USB'; then
    log_bool 'gui_same_usb_and_mode_a_both_shown_check' 1
else
    log_bool 'gui_same_usb_and_mode_a_both_shown_check' 0
fi

# Mode A側 (otherdisk) を選択した場合、引き続きERASE type-to-confirmの
# 既存フローが使われ、create (Mode A) が呼ばれること。
reset_scenario_state
: > "$SANDBOX/dev/otherdisk"
mkdir -p "$SANDBOX/sys/block/otherdisk" "$SANDBOX/sys/class/block/otherdisk/holders"
: > "$SANDBOX/sys/block/otherdisk/device"
disk_row="$(printf '%s' "$DEFAULT_DISK_ROW" | sed "s#__SANDBOX_DEV__#$SANDBOX/dev#g")"
env -i PATH='/usr/bin:/bin' HOME="$HOME" SANDBOX="$SANDBOX" \
    XDG_RUNTIME_DIR="$SANDBOX/xdg-runtime" \
    MOCK_ALL_ROWS_FILE="$mixed_rows" \
    MOCK_ANCESTOR_KNAME='fakedisk' \
    MOCK_SAME_USB_ANCESTOR_CHAIN_ROWS="$DEFAULT_ANCESTOR_CHAIN_ROWS" \
    MOCK_SAME_USB_DISK_ROW="$disk_row" \
    MOCK_SAME_USB_CHILD_ROWS="$DEFAULT_CHILD_ROWS" \
    MOCK_LIST_SELECTION="$(build_selection "$SANDBOX/dev/otherdisk" '16.0 GiB' 'Other Disk' 'OTHER456' 'usb' "$SANDBOX/dev/otherdisk" '259:0' 'A')" \
    MOCK_ENTRY_TEXT="ERASE $SANDBOX/dev/otherdisk" MOCK_HELPER_RC=0 \
    "$COPY" > "$SANDBOX/work/stdout.mixed_a_dispatch" 2> "$SANDBOX/work/stderr.mixed_a_dispatch" \
    && RC=0 || RC=$?
log_result 'gui_same_usb_mode_a_still_uses_erase_flow_exit0' 0 "$RC"
if printf '%s' "$(sudo_args)" | grep -qF -- "create $SANDBOX/dev/otherdisk 259:0"; then
    log_bool 'gui_same_usb_mode_a_still_uses_erase_flow_correct_op' 1
else
    log_bool 'gui_same_usb_mode_a_still_uses_erase_flow_correct_op' 0
fi

# ==============================================================================
# logical sector size = 4096 相当のディスクでも、候補判定・1GiB最小空き
# 容量・表示する空き容量が正しく計算されること。
#
# lsblkのSTART列は、対象diskの実際のlogical sector sizeによらず常に
# 512バイトセクタ単位で報告される (production側のコメント、および本
# ファイル冒頭の検証結果を参照)。そのため、GUI側の計算式自体は
# sector-size分岐を持たない。本テストは、その前提のもとで「実際に
# logical sector size=4096のUSBに対応する、512バイト単位表記のSTART値」
# を使った場合でも、helperのtest_helper_same_usb.sh (sector-size=4096
# テスト) と同じ実機Hybrid ISO構造・同じ最終バイトオフセットで正しく
# 計算されることを確認する。
#
# 手計算 (helperの4096テストと対応させた値):
#   sda1: 実sfdisk表記 start=16 (4096Bセクタ) -> 512B単位では 16*8=128、
#         size=100000 (4096Bセクタ) -> バイト換算 100000*4096=409,600,000
#   sda2: 実sfdisk表記 start=50 (4096Bセクタ) -> 512B単位では 50*8=400、
#         size=1024  (4096Bセクタ) -> バイト換算 1024*4096=4,194,304
#   sda1終端 = 128*512 + 409,600,000 = 409,665,536 (バイト)
#   sda2終端 = 400*512 + 4,194,304   =   4,399,104 (バイト)
#   max_end = 409,665,536 (helperのtest_helper_same_usb.shと同じ実機
#             構造から導出した値と一致する)
#   ディスク総サイズ 8,589,934,592 バイト (8GiB) のとき
#     空き容量 = 8,589,934,592 - 409,665,536 = 8,180,269,056 バイト
#              (約7.6 GiB、1GiB以上のため候補になる)
# ==============================================================================
SECTOR4096_CHILD_ROWS='NAME="fakedisk1" TYPE="part" START="128" SIZE="409600000" PKNAME="fakedisk"
NAME="fakedisk2" TYPE="part" START="400" SIZE="4194304" PKNAME="fakedisk"'

run_same_usb_gui gui_same_usb_sector4096_candidate_shown 0 \
    MOCK_SAME_USB_CHILD_ROWS="$SECTOR4096_CHILD_ROWS"
if list_stdin_shows 'MyPocketOS 起動USB' && list_stdin_shows '空き容量 約7.6 GiB (USB全体 8.0 GiB)'; then
    log_bool 'gui_same_usb_sector4096_display_correct' 1
else
    log_bool 'gui_same_usb_sector4096_display_correct' 0
fi

# ---- logical sector size=4096相当でも、1GiB未満の空きは候補にならない ----
# ディスク総サイズを縮小し、空き容量が約700MB (<1GiB) になるようにする
# (max_end=409,665,536 + 700,000,000 = 1,109,665,536)。
run_same_usb_gui gui_same_usb_sector4096_insufficient_space_empty 0 \
    MOCK_SAME_USB_CHILD_ROWS="$SECTOR4096_CHILD_ROWS" \
    MOCK_SAME_USB_DISK_ROW="$(printf '%s' "$DEFAULT_DISK_ROW" | sed "s#__SANDBOX_DEV__#$SANDBOX/dev#g;s/SIZE=\"8589934592\"/SIZE=\"1109665536\"/")"
if notice_shows '対象デバイスが見つかりません'; then
    log_bool 'gui_same_usb_sector4096_insufficient_space_empty_check' 1
else
    log_bool 'gui_same_usb_sector4096_insufficient_space_empty_check' 0
fi

echo
echo "== GUI (same-usb) summary =="
printf '%s' "$RESULTS"
echo "PASS=$PASS FAIL=$FAIL"

if [ "$FAIL" -eq 0 ]; then
    exit 0
else
    exit 1
fi
