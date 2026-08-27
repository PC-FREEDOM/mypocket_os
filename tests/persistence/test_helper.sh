#!/bin/sh
# tests/persistence/test_helper.sh
#
# mypocketos-persistence-setup-helper (特権ヘルパー) の非破壊モックテスト。
# production ファイルには一切書き込まない。実sudo (helperはsudoを使わない
# 前提だが念のため) ・実parted・実mkfs.ext4・実mount・実umount・実syncは
# いずれも呼び出さない。
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

setup_default_sys_tree() {
    rm -rf "$SANDBOX/sys"
    # helperのvalidate_device_arg/reverify_deviceは "/sys/class/block/
    # <kname>/device" (GUIの "/sys/block/<kname>/device" とは異なる) を
    # 物理デバイスの根拠として確認する。
    mkdir -p "$SANDBOX/sys/class/block/fakedisk/holders"
    : > "$SANDBOX/sys/class/block/fakedisk/device"
}

reset_scenario_state() {
    write_mocks "$SANDBOX"
    setup_default_sys_tree
    rm -rf "$SANDBOX/run/lock"
    mkdir -p "$SANDBOX/run/lock"
    rm -f "$SANDBOX/work/parted-called" "$SANDBOX/work/parted-invocations" \
          "$SANDBOX/work/mkfs-called" "$SANDBOX/work/mount-state" \
          "$SANDBOX/work/partprobe-called" "$SANDBOX/work/udevadm-called" \
          "$SANDBOX/work/mount-called" "$SANDBOX/work/umount-called" \
          "$SANDBOX/work/sync-called" "$SANDBOX/work/persistence.conf.snapshot"
    : > "$FAKE_DEVICE"
}

# use_fixture NAME SUFFIX [SUBST_FROM SUBST_TO]
# fixtures/ (sandbox外) のファイルをsandbox内へコピーしてそのパスを返す。
# モックのcat/lsblk等はsandbox外のパスを拒否するため、MOCK_*_FILE系の
# 値は常にsandbox内のコピーを指す必要がある。
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

# run_helper_case NAME EXPECTED_EXIT DEVICE_ARG MAJMIN_ARG [env assignments...]
run_helper_case() {
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
}

echo "== helper: preparing sandbox and instrumented copy =="
sh -n "$COPY" && echo "sh -n: OK"
dash -n "$COPY" && echo "dash -n: OK"

echo "== helper: running scenarios =="

# ---------- 14: 正しいMAJOR:MINOR (-r利用) で誤って拒否されない ----------
# ロックを先取りしておき、exit 11 (ロック取得失敗) になることをもって
# validate_majminを通過したことを確認する (誤って13になっていないこと)。
reset_scenario_state
mkdir -p "$SANDBOX/run/lock/mypocketos-persistence-setup-helper.lock"
run_helper_case helper_majmin_match_lock_held_exit11 11 "$FAKE_DEVICE" "$DEFAULT_MAJMIN"
if parted_called || mkfs_called; then
    log_bool 'helper_majmin_match_lock_held_no_destructive' 0
else
    log_bool 'helper_majmin_match_lock_held_no_destructive' 1
fi
if stderr_shows helper_majmin_match_lock_held_exit11 'MAJOR:MINOR'; then
    log_bool 'helper_majmin_match_lock_held_not_majmin_message' 0
else
    log_bool 'helper_majmin_match_lock_held_not_majmin_message' 1
fi

# ---------- 15: 不正MAJOR:MINORはexit13、破壊的モック未到達 ----------
reset_scenario_state
run_helper_case helper_majmin_mismatch_exit13_no_destructive 13 "$FAKE_DEVICE" '999:9'
if parted_called || mkfs_called; then
    log_bool 'helper_majmin_mismatch_no_destructive' 0
else
    log_bool 'helper_majmin_mismatch_no_destructive' 1
fi

# ---------- 16: 既存LABEL=persistence検出、exit16、破壊的モック未到達 ----------
reset_scenario_state
run_helper_case helper_existing_label_exit16_no_destructive 16 "$FAKE_DEVICE" "$DEFAULT_MAJMIN" \
    MOCK_LABEL_ROWS='LABEL="persistence"'
if parted_called || mkfs_called; then
    log_bool 'helper_existing_label_no_destructive' 0
else
    log_bool 'helper_existing_label_no_destructive' 1
fi
if stderr_shows helper_existing_label_exit16_no_destructive 'LABEL=persistence'; then
    log_bool 'helper_existing_label_message_shown' 1
else
    log_bool 'helper_existing_label_message_shown' 0
fi

# ---------- 17: 既存PARTLABEL=persistence検出、exit16、破壊的モック未到達 ----------
reset_scenario_state
run_helper_case helper_existing_partlabel_exit16_no_destructive 16 "$FAKE_DEVICE" "$DEFAULT_MAJMIN" \
    MOCK_PARTLABEL_ROWS='PARTLABEL="persistence"'
if parted_called || mkfs_called; then
    log_bool 'helper_existing_partlabel_no_destructive' 0
else
    log_bool 'helper_existing_partlabel_no_destructive' 1
fi
if stderr_shows helper_existing_partlabel_exit16_no_destructive 'PARTLABEL=persistence'; then
    log_bool 'helper_existing_partlabel_message_shown' 1
else
    log_bool 'helper_existing_partlabel_message_shown' 0
fi

# ---------- 18: findmntのraw+pairs併用回帰 (check_not_home_source、動的) ----------
# 併用されていれば check_not_home_source 自身がexit14で拒否するはずだが、
# 正しくは併用されないため、後続のcheck_no_existing_labelまで到達し
# exit16になる。終了コードが14ではなく16であること自体が識別点。
reset_scenario_state
run_helper_case helper_home_findmnt_no_raw_pairs_reaches_label_check_exit16 16 \
    "$FAKE_DEVICE" "$DEFAULT_MAJMIN" \
    MOCK_LABEL_ROWS='LABEL="persistence"'
if parted_called || mkfs_called; then
    log_bool 'helper_home_findmnt_no_raw_pairs_no_destructive' 0
else
    log_bool 'helper_home_findmnt_no_raw_pairs_no_destructive' 1
fi
if stderr_shows helper_home_findmnt_no_raw_pairs_reaches_label_check_exit16 'LABEL=persistence'; then
    log_bool 'helper_home_findmnt_no_raw_pairs_message_shown' 1
else
    log_bool 'helper_home_findmnt_no_raw_pairs_message_shown' 0
fi

# ---------- 19: /dev配下制約がsandbox化後も機能する ----------
reset_scenario_state
outside_file="$SANDBOX/work/outside-sandbox-dev-file"
: > "$outside_file"
run_helper_case helper_dev_prefix_constraint_rejects_outside_sandbox 12 \
    "$outside_file" "$DEFAULT_MAJMIN"
if parted_called || mkfs_called; then
    log_bool 'helper_dev_prefix_constraint_no_destructive' 0
else
    log_bool 'helper_dev_prefix_constraint_no_destructive' 1
fi
if stderr_shows helper_dev_prefix_constraint_rejects_outside_sandbox '/dev以下の絶対パス'; then
    log_bool 'helper_dev_prefix_constraint_message_shown' 1
else
    log_bool 'helper_dev_prefix_constraint_message_shown' 0
fi

# ---------- 20: 成功経路でも実parted/mkfs/mount/partprobe/udevadm/
#               sync/umountは呼ばない ----------
reset_scenario_state
: > "$FAKE_PART_PATH"
part_rows="$(use_fixture helper-part-rows-created.txt part-rows-20 __FAKE_PART_PATH__ "$FAKE_PART_PATH")"
disk_rows_20="$(use_fixture helper-disk-rows-clean.txt disk-rows-20)"
env -i PATH='/usr/bin:/bin' SANDBOX="$SANDBOX" \
    FAKE_DEVICE="$FAKE_DEVICE" \
    MOCK_UID=0 MOCK_LIVE_MEDIUM_MOUNTED=0 \
    MOCK_LSBLK_KNAME='fakedisk' MOCK_LSBLK_TYPE=disk MOCK_LSBLK_RO=0 \
    MOCK_LSBLK_MAJMIN="$DEFAULT_MAJMIN" MOCK_LSBLK_PTTYPE='' \
    MOCK_DISK_ROWS_FILE="$disk_rows_20" \
    MOCK_PART_ROWS_FILE="$part_rows" \
    MOCK_PART_TYPE=part MOCK_PART_RO=0 MOCK_PART_MAJMIN='259:1' \
    MOCK_LSBLK_PKNAME='fakedisk' MOCK_PART_PATH_FIELD="$FAKE_PART_PATH" \
    "$COPY" create "$FAKE_DEVICE" "$DEFAULT_MAJMIN" \
    > "$SANDBOX/work/stdout.20" 2> "$SANDBOX/work/stderr.20" && RC=0 || RC=$?
log_result 'helper_happy_path_no_real_binaries' 0 "$RC"

if parted_called && mkfs_called && partprobe_called && udevadm_called \
    && mount_called && umount_called && sync_called; then
    log_bool 'helper_happy_path_used_mocks' 1
else
    log_bool 'helper_happy_path_used_mocks' 0
fi

# parted は mklabel gpt (GPT作成) と mkpart (persistenceパーティション
# 作成) の2回だけ呼ばれることを検証する (件数不一致・余分な呼び出しが
# ないことの確認)。
mklabel_count="$(grep -cF 'mklabel gpt' "$SANDBOX/work/parted-invocations" 2>/dev/null)" || mklabel_count=0
mkpart_count="$(grep -cF 'mkpart' "$SANDBOX/work/parted-invocations" 2>/dev/null)" || mkpart_count=0
total_parted_count="$(wc -l < "$SANDBOX/work/parted-invocations" 2>/dev/null)" || total_parted_count=0
if [ "$mklabel_count" -eq 1 ] && [ "$mkpart_count" -eq 1 ] && [ "$total_parted_count" -eq 2 ]; then
    log_bool 'helper_happy_path_parted_called_exactly_mklabel_and_mkpart' 1
else
    log_bool 'helper_happy_path_parted_called_exactly_mklabel_and_mkpart' 0
fi

if [ -e "$SANDBOX/run/lock/mypocketos-persistence-setup-helper.lock" ]; then
    log_bool 'helper_happy_path_lock_removed' 0
else
    log_bool 'helper_happy_path_lock_removed' 1
fi
if find "$SANDBOX/run" -maxdepth 1 -name 'mypocketos-persistence-setup-helper.*' 2>/dev/null | grep -q .; then
    log_bool 'helper_happy_path_mnt_dir_removed' 0
else
    log_bool 'helper_happy_path_mnt_dir_removed' 1
fi

# persistence.conf はumount (アンマウント) 実行前にモックがsandbox/work
# へ退避しているので、その内容 (/home + 改行、6バイト) を確認する。
snapshot="$SANDBOX/work/persistence.conf.snapshot"
if [ -e "$snapshot" ]; then
    snapshot_size="$(wc -c < "$snapshot")"
    snapshot_content="$(cat -- "$snapshot")"
    if [ "$snapshot_size" -eq 6 ] && [ "$snapshot_content" = '/home' ]; then
        log_bool 'helper_happy_path_persistence_conf_content' 1
    else
        log_bool 'helper_happy_path_persistence_conf_content' 0
    fi
else
    log_bool 'helper_happy_path_persistence_conf_content' 0
fi

# 終了後、mount-stateが空 (アンマウント済み) であることを確認する。
if [ ! -s "$SANDBOX/work/mount-state" ]; then
    log_bool 'helper_happy_path_mount_state_empty' 1
else
    log_bool 'helper_happy_path_mount_state_empty' 0
fi

echo
echo "== helper summary =="
printf '%s' "$RESULTS"
echo "PASS=$PASS FAIL=$FAIL"

if [ "$FAIL" -eq 0 ]; then
    exit 0
else
    exit 1
fi
