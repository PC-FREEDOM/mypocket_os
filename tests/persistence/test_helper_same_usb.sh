#!/bin/sh
# tests/persistence/test_helper_same_usb.sh
#
# mypocketos-persistence-setup-helper の create-same-usb (Mode B: 起動元USB
# の末尾未使用領域へのpersistence追加) に対する非破壊モックテスト。
# production ファイルには一切書き込まない。実sfdisk・実blockdev・実mkfs.ext4・
# 実mount・実umount・実syncはいずれも呼び出さない (sfdisk/blockdevは
# mock_command.shのstatefulモックへ差し替える)。
#
# 正常系のパーティション構成は、実機で確認された MyPocketOS Hybrid ISO
# 特有の重複構造 (partition 2がpartition 1の範囲に数値上ネストされている:
# sda1 start=64,size=3492416 / sda2 start=540,size=6656) を必ず再現する
# (仕様レビューで確定した要件)。一般的な非重複構成だけを正常系にしない。
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
DEFAULT_MAJMIN='254:0'
# 実機のHybrid ISO構造と一致するよう、8GiB (実機検証と同じ7.5GiB級USB相当)
# を既定のディスク総サイズとする。
DEFAULT_DISK_BYTES=8589934592

# ---- USB起動元媒体としてのsysfsツリー -------------------------------------
# check_usb_transport は "/sys/class/block/<kname>/device" をreadlink -fで
# 解決し、経路にUSBバスのセグメント (usbN/) が含まれることを要求する。
# Mode Aのsetup_default_sys_tree (test_helper.sh) はこのdeviceを空の通常
# ファイルとして作るため (物理デバイスの根拠確認のみが目的)、Mode B用には
# 別途、実際にUSBバスを模したパスへのシンボリックリンクとして作り直す。
setup_same_usb_sys_tree() {
    rm -rf "$SANDBOX/sys"
    mkdir -p "$SANDBOX/sys/class/block/fakedisk/holders"
    mkdir -p "$SANDBOX/sys/devices/fake-pci/usb1/1-1/1-1:1.0/host0/target0:0:0/0:0:0:0"
    ln -s "$SANDBOX/sys/devices/fake-pci/usb1/1-1/1-1:1.0/host0/target0:0:0/0:0:0:0" \
        "$SANDBOX/sys/class/block/fakedisk/device"
}

# ---- 通常のsysfsツリー (USBバス経路を含まない、check_usb_transportの ------
# ---- sysfs経路チェック単体で拒否させるためのバリエーション) --------------
setup_non_usb_sys_tree() {
    rm -rf "$SANDBOX/sys"
    mkdir -p "$SANDBOX/sys/class/block/fakedisk/holders"
    mkdir -p "$SANDBOX/sys/devices/fake-pci/ata1/1-1/1-1:1.0/host0/target0:0:0/0:0:0:0"
    ln -s "$SANDBOX/sys/devices/fake-pci/ata1/1-1/1-1:1.0/host0/target0:0:0/0:0:0:0" \
        "$SANDBOX/sys/class/block/fakedisk/device"
}

use_fixture() {
    # use_fixture NAME SUFFIX [SUBST_FROM SUBST_TO]
    dest="$SANDBOX/work/$2.txt"
    if [ "$#" -ge 4 ]; then
        sed "s#$3#$4#g" "$FIXTURES/$1" > "$dest"
    else
        cp -- "$FIXTURES/$1" "$dest"
    fi
    printf '%s' "$dest"
}

reset_scenario_state() {
    write_mocks "$SANDBOX"
    setup_same_usb_sys_tree
    rm -rf "$SANDBOX/run/lock"
    mkdir -p "$SANDBOX/run/lock"
    # 前のシナリオが意図的に残した可能性のあるsfdiskバックアップ用一時
    # ディレクトリ (例: MOCK_FAIL_RM_SFDISK_BACKUP=1のcleanup失敗シナリオ)
    # を、次のシナリオへ持ち越さないよう明示的に除去する。
    find "$SANDBOX/run" -maxdepth 1 -name 'mypocketos-persistence-setup-helper.*' -exec rm -rf -- {} +
    rm -f "$SANDBOX"/work/sfdisk-called "$SANDBOX"/work/sfdisk-invocations \
          "$SANDBOX"/work/mkfs-called "$SANDBOX"/work/mount-state \
          "$SANDBOX"/work/partprobe-called "$SANDBOX"/work/udevadm-called \
          "$SANDBOX"/work/partx-called "$SANDBOX"/work/partx-invocations \
          "$SANDBOX"/work/mount-called "$SANDBOX"/work/umount-called \
          "$SANDBOX"/work/sync-called "$SANDBOX"/work/persistence.conf.snapshot
    : > "$FAKE_DEVICE"
    : > "${FAKE_DEVICE}1"
    : > "${FAKE_DEVICE}2"
    : > "${FAKE_DEVICE}3"
}

sfdisk_called() { [ -e "$SANDBOX/work/sfdisk-called" ]; }
append_invoked() { grep -qF -- '--append' "$SANDBOX/work/sfdisk-invocations" 2>/dev/null; }
mkfs_called() { [ -e "$SANDBOX/work/mkfs-called" ]; }
partprobe_called() { [ -e "$SANDBOX/work/partprobe-called" ]; }
partx_called() { [ -e "$SANDBOX/work/partx-called" ]; }
stderr_shows() { grep -qF -- "$2" "$SANDBOX/work/stderr.$1" 2>/dev/null; }

# new_sfdisk_state: 実機Hybrid ISO構造のsfdisk --dump状態ファイルを
# sandbox内に新規作成し、そのパスを返す (呼び出しごとに独立させる。
# --appendでmutateされるため使い回さない)。
new_sfdisk_state() {
    suffix="$1"
    use_fixture helper-sfdisk-dump-hybrid.txt "sfdisk-state-$suffix" __FAKE_DEVICE__ "$FAKE_DEVICE"
}

# 実機 (LC_ALL=C sudo sfdisk --dump /dev/sda) の生出力をそのまま採取した
# fixture。start=/size=の値が桁揃えのため右詰め・可変長スペースで出力
# されている点を、テストの入力データとして必ず再現する
# (fetch_partition_tableの解析ロジックがこの桁揃えを許容できず、実機で
# exit 32になっていた不具合の回帰テスト)。
new_sfdisk_state_real_padded() {
    suffix="$1"
    use_fixture helper-sfdisk-dump-hybrid-real-padded.txt "sfdisk-state-real-padded-$suffix" __FAKE_DEVICE__ "$FAKE_DEVICE"
}

PART_ROWS_AFTER="$(use_fixture helper-part-rows-same-usb-after-append.txt part-rows-same-usb-after __FAKE_DEVICE__ "$FAKE_DEVICE")"

# run_same_usb_case NAME EXPECTED_EXIT [env assignments...]
run_same_usb_case() {
    name="$1"; expected="$2"; shift 2
    sfdisk_state="$(new_sfdisk_state "$name")"
    env -i PATH='/usr/bin:/bin' SANDBOX="$SANDBOX" \
        FAKE_DEVICE="$FAKE_DEVICE" \
        MOCK_UID=0 MOCK_LIVE_MEDIUM_MOUNTED=0 \
        MOCK_LSBLK_KNAME='fakedisk' MOCK_LSBLK_TYPE=disk MOCK_LSBLK_RO=0 \
        MOCK_LSBLK_MAJMIN="$DEFAULT_MAJMIN" MOCK_LSBLK_TRAN='usb' \
        MOCK_ANCESTOR_CHAIN='fakedisk' \
        MOCK_LABEL_ROWS='LABEL=""' MOCK_PARTLABEL_ROWS='PARTLABEL=""' \
        MOCK_SFDISK_DUMP_STATE_FILE="$sfdisk_state" \
        MOCK_BLOCKDEV_GETSZ=$((DEFAULT_DISK_BYTES / 512)) \
        MOCK_PART_ROWS_FILE="$PART_ROWS_AFTER" \
        MOCK_PART_TYPE=part MOCK_PART_RO=0 MOCK_PART_MAJMIN='259:3' \
        "$@" \
        "$COPY" create-same-usb "$FAKE_DEVICE" "$DEFAULT_MAJMIN" \
        > "$SANDBOX/work/stdout.$name" 2> "$SANDBOX/work/stderr.$name" && RC=0 || RC=$?
    log_result "$name" "$expected" "$RC"
}

echo "== helper (same-usb): preparing sandbox and instrumented copy =="
sh -n "$COPY" && echo "sh -n: OK"
dash -n "$COPY" && echo "dash -n: OK"

echo "== helper (same-usb): running scenarios =="

# ==============================================================================
# 引数受理: create-same-usbが有効なOPとして受理されること
# ==============================================================================
reset_scenario_state
env -i PATH='/usr/bin:/bin' SANDBOX="$SANDBOX" "$COPY" >/dev/null 2>"$SANDBOX/work/stderr.usage" && RC=0 || RC=$?
log_result 'same_usb_usage_mentions_both_ops' 2 "$RC"
if stderr_shows usage 'create-same-usb'; then
    log_bool 'same_usb_usage_lists_create_same_usb' 1
else
    log_bool 'same_usb_usage_lists_create_same_usb' 0
fi

# ==============================================================================
# 正常系: 実機Hybrid ISO構造 (重複partition) からの新規作成成功
# ==============================================================================
reset_scenario_state
run_same_usb_case same_usb_happy_path 0
if sfdisk_called && append_invoked && mkfs_called; then
    log_bool 'same_usb_happy_path_used_mocks' 1
else
    log_bool 'same_usb_happy_path_used_mocks' 0
fi
if [ -e "$SANDBOX/run/lock/mypocketos-persistence-setup-helper.lock" ]; then
    log_bool 'same_usb_happy_path_lock_removed' 0
else
    log_bool 'same_usb_happy_path_lock_removed' 1
fi
snapshot="$SANDBOX/work/persistence.conf.snapshot"
if [ -e "$snapshot" ]; then
    snapshot_size="$(wc -c < "$snapshot")"
    snapshot_content="$(cat -- "$snapshot")"
    if [ "$snapshot_size" -eq 6 ] && [ "$snapshot_content" = '/home' ]; then
        log_bool 'same_usb_happy_path_persistence_conf_content' 1
    else
        log_bool 'same_usb_happy_path_persistence_conf_content' 0
    fi
else
    log_bool 'same_usb_happy_path_persistence_conf_content' 0
fi
# --append呼び出しが正確に1回だけであること (重複実行がないこと)。
append_count="$(grep -cF -- '--append' "$SANDBOX/work/sfdisk-invocations" 2>/dev/null)" || append_count=0
if [ "$append_count" -eq 1 ]; then
    log_bool 'same_usb_happy_path_append_called_once' 1
else
    log_bool 'same_usb_happy_path_append_called_once' 0
fi

# ==============================================================================
# 最重要回帰: 追加操作後、既存partition (sda1/sda2相当) の内容がsfdisk
# --dumpから見て変化していないこと
# ==============================================================================
reset_scenario_state
happy_state="$(new_sfdisk_state same_usb_happy_existing_unchanged)"
env -i PATH='/usr/bin:/bin' SANDBOX="$SANDBOX" \
    FAKE_DEVICE="$FAKE_DEVICE" \
    MOCK_UID=0 MOCK_LIVE_MEDIUM_MOUNTED=0 \
    MOCK_LSBLK_KNAME='fakedisk' MOCK_LSBLK_TYPE=disk MOCK_LSBLK_RO=0 \
    MOCK_LSBLK_MAJMIN="$DEFAULT_MAJMIN" MOCK_LSBLK_TRAN='usb' \
    MOCK_ANCESTOR_CHAIN='fakedisk' \
    MOCK_LABEL_ROWS='LABEL=""' MOCK_PARTLABEL_ROWS='PARTLABEL=""' \
    MOCK_SFDISK_DUMP_STATE_FILE="$happy_state" \
    MOCK_BLOCKDEV_GETSZ=$((DEFAULT_DISK_BYTES / 512)) \
    MOCK_PART_ROWS_FILE="$PART_ROWS_AFTER" \
    MOCK_PART_TYPE=part MOCK_PART_RO=0 MOCK_PART_MAJMIN='259:3' \
    "$COPY" create-same-usb "$FAKE_DEVICE" "$DEFAULT_MAJMIN" \
    > "$SANDBOX/work/stdout.existing_unchanged" 2> "$SANDBOX/work/stderr.existing_unchanged" \
    && RC=0 || RC=$?
log_result 'same_usb_existing_partitions_call_succeeds' 0 "$RC"
if grep -qF 'start=64, size=3492416, type=0, bootable' "$happy_state" \
    && grep -qF 'start=540, size=6656, type=ef' "$happy_state"; then
    log_bool 'same_usb_existing_partitions_content_unchanged_after_append' 1
else
    log_bool 'same_usb_existing_partitions_content_unchanged_after_append' 0
fi

# ==============================================================================
# 最重要回帰 (サーキットブレーカー): 追加操作後に既存partitionが変化して
# いることを検出した場合、exit 37でそれ以上の処理 (mkfs等) へ進まないこと。
# 「書き込みを未然に防ぐ」のではなく「検出して停止する」ことを確認する。
# ==============================================================================
reset_scenario_state
run_same_usb_case same_usb_existing_changed_detected_exit37 37 \
    MOCK_SFDISK_APPEND_CORRUPT_EXISTING=1
if mkfs_called; then
    log_bool 'same_usb_existing_changed_no_mkfs_after_detection' 0
else
    log_bool 'same_usb_existing_changed_no_mkfs_after_detection' 1
fi
if stderr_shows same_usb_existing_changed_detected_exit37 '意図しない変化'; then
    log_bool 'same_usb_existing_changed_message_shown' 1
else
    log_bool 'same_usb_existing_changed_message_shown' 0
fi

# ==============================================================================
# 拒否系: USB接続として確認できない (TRAN不一致)
# ==============================================================================
reset_scenario_state
run_same_usb_case same_usb_not_usb_tran_exit30 30 MOCK_LSBLK_TRAN='ata'
if append_invoked; then
    log_bool 'same_usb_not_usb_tran_no_destructive' 0
else
    log_bool 'same_usb_not_usb_tran_no_destructive' 1
fi

# ---- USBバス経路を含まないsysfs (TRANは一致するが実経路が一致しない) ------
reset_scenario_state
setup_non_usb_sys_tree
run_same_usb_case same_usb_not_usb_syspath_exit30 30
if append_invoked; then
    log_bool 'same_usb_not_usb_syspath_no_destructive' 0
else
    log_bool 'same_usb_not_usb_syspath_no_destructive' 1
fi

# ==============================================================================
# 拒否系: 対象ディスクがMyPocketOS起動元USBと一致しない
# ==============================================================================
reset_scenario_state
run_same_usb_case same_usb_not_live_boot_disk_exit31 31 \
    MOCK_ANCESTOR_CHAIN='some-other-disk'
if append_invoked; then
    log_bool 'same_usb_not_live_boot_disk_no_destructive' 0
else
    log_bool 'same_usb_not_live_boot_disk_no_destructive' 1
fi

# ==============================================================================
# 拒否系: 既存LABEL=persistence検出 (Mode Aと同じ関数を再利用)
# ==============================================================================
reset_scenario_state
run_same_usb_case same_usb_existing_label_exit16 16 \
    MOCK_LABEL_ROWS='LABEL="persistence"'
if append_invoked; then
    log_bool 'same_usb_existing_label_no_destructive' 0
else
    log_bool 'same_usb_existing_label_no_destructive' 1
fi

# ==============================================================================
# 拒否系: パーティションテーブルがDOS/MBRではない (label=gpt)
# ==============================================================================
reset_scenario_state
gpt_state="$SANDBOX/work/sfdisk-state-gpt.txt"
cat > "$gpt_state" <<STATE_EOF
label: gpt
label-id: AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE
device: ${FAKE_DEVICE}
unit: sectors
first-lba: 34
last-lba: 100
sector-size: 512

${FAKE_DEVICE}1 : start=64, size=3492416, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4
STATE_EOF
env -i PATH='/usr/bin:/bin' SANDBOX="$SANDBOX" \
    FAKE_DEVICE="$FAKE_DEVICE" \
    MOCK_UID=0 MOCK_LIVE_MEDIUM_MOUNTED=0 \
    MOCK_LSBLK_KNAME='fakedisk' MOCK_LSBLK_TYPE=disk MOCK_LSBLK_RO=0 \
    MOCK_LSBLK_MAJMIN="$DEFAULT_MAJMIN" MOCK_LSBLK_TRAN='usb' \
    MOCK_ANCESTOR_CHAIN='fakedisk' \
    MOCK_LABEL_ROWS='LABEL=""' MOCK_PARTLABEL_ROWS='PARTLABEL=""' \
    MOCK_SFDISK_DUMP_STATE_FILE="$gpt_state" \
    MOCK_BLOCKDEV_GETSZ=$((DEFAULT_DISK_BYTES / 512)) \
    "$COPY" create-same-usb "$FAKE_DEVICE" "$DEFAULT_MAJMIN" \
    > "$SANDBOX/work/stdout.gpt" 2> "$SANDBOX/work/stderr.gpt" && RC=0 || RC=$?
log_result 'same_usb_non_dos_label_exit32' 32 "$RC"

# ==============================================================================
# 拒否系: MBR primaryパーティション枠 (4件) が既に使用済み
# ==============================================================================
reset_scenario_state
full_state="$SANDBOX/work/sfdisk-state-full.txt"
cat > "$full_state" <<STATE_EOF
label: dos
label-id: 0x61fae024
device: ${FAKE_DEVICE}
unit: sectors
sector-size: 512

${FAKE_DEVICE}1 : start=64, size=3492416, type=0, bootable
${FAKE_DEVICE}2 : start=540, size=6656, type=ef
${FAKE_DEVICE}3 : start=3493888, size=1048576, type=83
${FAKE_DEVICE}4 : start=4542464, size=1048576, type=83
STATE_EOF
env -i PATH='/usr/bin:/bin' SANDBOX="$SANDBOX" \
    FAKE_DEVICE="$FAKE_DEVICE" \
    MOCK_UID=0 MOCK_LIVE_MEDIUM_MOUNTED=0 \
    MOCK_LSBLK_KNAME='fakedisk' MOCK_LSBLK_TYPE=disk MOCK_LSBLK_RO=0 \
    MOCK_LSBLK_MAJMIN="$DEFAULT_MAJMIN" MOCK_LSBLK_TRAN='usb' \
    MOCK_ANCESTOR_CHAIN='fakedisk' \
    MOCK_LABEL_ROWS='LABEL=""' MOCK_PARTLABEL_ROWS='PARTLABEL=""' \
    MOCK_SFDISK_DUMP_STATE_FILE="$full_state" \
    MOCK_BLOCKDEV_GETSZ=$((DEFAULT_DISK_BYTES / 512)) \
    "$COPY" create-same-usb "$FAKE_DEVICE" "$DEFAULT_MAJMIN" \
    > "$SANDBOX/work/stdout.full" 2> "$SANDBOX/work/stderr.full" && RC=0 || RC=$?
log_result 'same_usb_primary_slots_exhausted_exit33' 33 "$RC"

# ==============================================================================
# 拒否系: 末尾未使用領域が最小サイズ (1GiB) 未満
# ==============================================================================
reset_scenario_state
# 2,831,155,200 bytes (5,529,600セクタ、2048の倍数) では、既存
# partition終端 (3,493,888) から算出される末尾空き領域が約993MiBとなり、
# 最小サイズ (1GiB) をわずかに下回る。
run_same_usb_case same_usb_insufficient_free_space_exit34 34 \
    MOCK_BLOCKDEV_GETSZ=5529600
if append_invoked; then
    log_bool 'same_usb_insufficient_free_space_no_destructive' 0
else
    log_bool 'same_usb_insufficient_free_space_no_destructive' 1
fi

# ==============================================================================
# 拒否系: ディスクの総サイズ取得自体に失敗 (blockdev --getsz失敗)。
# 「空き容量不足」(終了コード34) とは原因が異なるため、別の終了コード
# (39) で区別されることを確認する (実機で報告された不具合を踏まえた
# 要件)。
# ==============================================================================
reset_scenario_state
run_same_usb_case same_usb_disk_size_acquisition_fails_exit39 39 \
    MOCK_BLOCKDEV_GETSZ_EXIT=1
if append_invoked; then
    log_bool 'same_usb_disk_size_acquisition_fails_no_destructive' 0
else
    log_bool 'same_usb_disk_size_acquisition_fails_no_destructive' 1
fi
if stderr_shows same_usb_disk_size_acquisition_fails_exit39 'blockdev --getsz'; then
    log_bool 'same_usb_disk_size_acquisition_fails_message_distinct' 1
else
    log_bool 'same_usb_disk_size_acquisition_fails_message_distinct' 0
fi

# ==============================================================================
# 回帰: blockdev呼び出しに "--" (end-of-options) を付けていないこと。
#
# 実機のutil-linux 2.41.5 blockdevは、sfdiskと異なり "--" を
# end-of-optionsとして扱わず、`blockdev --getsz -- DEVICE`は
# "blockdev: Unknown command: --" (rc=1) で失敗する。この実機不具合の
# 再発を防ぐため、2つの方法で確認する。
#
# 1. 静的検査: production helperのソース中に、blockdev呼び出しの
#    直後に "--" を付ける記述が存在しないことを確認する。
# 2. 動的検査: mock_command.shのblockdevモックは、"--getsz DEVICE"
#    (正確に2引数、"--"なし) 以外の呼び出しを "unrecognized
#    invocation" として拒否するよう厳格化されている
#    (tests/persistence/mock_command.sh参照)。したがって、このファイル
#    内の他の全ての正常系シナリオ (exit0を期待するもの) が実際に
#    exit0へ到達していること自体が、production側が "--" なしで
#    blockdevを呼んでいることの動的な証明になっている。ここでは
#    そのうちの1つを明示的に名前付けし、意図を記録する。
# ==============================================================================
if grep -Eq -- '\$CMD_BLOCKDEV" --getsz -- ' "$PROD_HELPER"; then
    log_bool 'same_usb_blockdev_no_dashdash_static_check' 0
else
    log_bool 'same_usb_blockdev_no_dashdash_static_check' 1
fi
reset_scenario_state
run_same_usb_case same_usb_blockdev_no_dashdash_dynamic_check_exit0 0

# ==============================================================================
# 拒否系: sfdisk --append自体の失敗
# ==============================================================================
reset_scenario_state
run_same_usb_case same_usb_append_fails_exit36 36 MOCK_SFDISK_APPEND_EXIT=1
if mkfs_called; then
    log_bool 'same_usb_append_fails_no_mkfs' 0
else
    log_bool 'same_usb_append_fails_no_mkfs' 1
fi

# ==============================================================================
# 回帰: sfdisk --append失敗時、これまで捨てていたsfdiskの実際のstderr・
# 終了コード・stdin (start=/size=/type=) が、fail()経由でGUI表示用の
# 標準エラーへ含まれること (実USB E2Eでの原因調査のために追加した計装。
# 実機での実際のsfdiskエラー文言は本テスト作成時点では未確定のため、
# ここでは任意の文言を模擬してプラミング (捕捉→表示) 自体を確認する)。
# ==============================================================================
reset_scenario_state
run_same_usb_case same_usb_append_fails_stderr_captured 36 \
    MOCK_SFDISK_APPEND_EXIT=1 \
    MOCK_SFDISK_APPEND_STDERR='sfdisk: Re-reading the partition table failed.: Device or resource busy'
if stderr_shows same_usb_append_fails_stderr_captured 'Device or resource busy'; then
    log_bool 'same_usb_append_fails_stderr_message_included' 1
else
    log_bool 'same_usb_append_fails_stderr_message_included' 0
fi
if stderr_shows same_usb_append_fails_stderr_captured 'sfdisk終了コード: 1'; then
    log_bool 'same_usb_append_fails_exit_code_included' 1
else
    log_bool 'same_usb_append_fails_exit_code_included' 0
fi
if stderr_shows same_usb_append_fails_stderr_captured 'stdin: [start='; then
    log_bool 'same_usb_append_fails_stdin_included' 1
else
    log_bool 'same_usb_append_fails_stdin_included' 0
fi

# ==============================================================================
# 回帰: sfdisk --append自体が失敗した場合、「ディスクは変更されていない」
# とは断定しない。読み取り専用のsfdisk --dumpでbaselineと比較した診断
# (unchanged/changed/unknown) をstderrへ含めること (設計レビューでの
# item 1修正)。自動ロールバックは行わない。
# ==============================================================================

# unchanged: --append自体が (書込み前に) 失敗するため、disk上のbaselineは
# 変化しない。診断は "unchanged" になるはずである。
reset_scenario_state
run_same_usb_case same_usb_append_fails_diag_unchanged 36 MOCK_SFDISK_APPEND_EXIT=1
if stderr_shows same_usb_append_fails_diag_unchanged 'ディスク状態診断: unchanged'; then
    log_bool 'same_usb_append_fails_diag_reports_unchanged' 1
else
    log_bool 'same_usb_append_fails_diag_reports_unchanged' 0
fi

# changed: 「disk上の書込みは実際に発生したにもかかわらず、sfdisk自体は
# nonzeroで終了する」という状態を模擬する。診断は "changed" になるはず
# であり、この場合も自動ロールバックは行わない (mkfsに進まないことは
# 別途 same_usb_append_fails_no_mkfs 系で確認済み)。
reset_scenario_state
run_same_usb_case same_usb_append_fails_diag_changed 36 \
    MOCK_SFDISK_APPEND_EXIT=1 MOCK_SFDISK_APPEND_WRITE_THEN_FAIL=1
if stderr_shows same_usb_append_fails_diag_changed 'ディスク状態診断: changed'; then
    log_bool 'same_usb_append_fails_diag_reports_changed' 1
else
    log_bool 'same_usb_append_fails_diag_reports_changed' 0
fi
if mkfs_called; then
    log_bool 'same_usb_append_fails_diag_changed_no_mkfs' 0
else
    log_bool 'same_usb_append_fails_diag_changed_no_mkfs' 1
fi

# unknown: 診断用の (診断関数自身が発行する) sfdisk --dump再実行自体が
# 失敗する場合。診断は "unknown" になり、かつ診断関数自身の失敗が
# 元の失敗原因 (fail 36) を握りつぶさないことを確認する。
reset_scenario_state
run_same_usb_case same_usb_append_fails_diag_unknown 36 \
    MOCK_SFDISK_APPEND_EXIT=1 MOCK_SFDISK_DUMP_FAIL_AFTER_APPEND_ATTEMPT=1
if stderr_shows same_usb_append_fails_diag_unknown 'ディスク状態診断: unknown'; then
    log_bool 'same_usb_append_fails_diag_reports_unknown' 1
else
    log_bool 'same_usb_append_fails_diag_reports_unknown' 0
fi

# ==============================================================================
# 回帰: Mode Bのsfdisk --append呼び出しに --no-reread / --no-tell-kernel
# が含まれ、--force は含まれないこと (実機で「This disk is currently in
# use」により失敗した不具合の修正、および--forceを意図的に不採用とした
# 設計判断の回帰確認。設計レビュー参照)。
# ==============================================================================
reset_scenario_state
run_same_usb_case same_usb_sfdisk_flags_exit0 0
if grep -qF -- '--no-reread' "$SANDBOX/work/sfdisk-invocations" 2>/dev/null; then
    log_bool 'same_usb_sfdisk_invocation_has_no_reread' 1
else
    log_bool 'same_usb_sfdisk_invocation_has_no_reread' 0
fi
if grep -qF -- '--no-tell-kernel' "$SANDBOX/work/sfdisk-invocations" 2>/dev/null; then
    log_bool 'same_usb_sfdisk_invocation_has_no_tell_kernel' 1
else
    log_bool 'same_usb_sfdisk_invocation_has_no_tell_kernel' 0
fi
if grep -qF -- '--force' "$SANDBOX/work/sfdisk-invocations" 2>/dev/null; then
    log_bool 'same_usb_sfdisk_invocation_no_force' 0
else
    log_bool 'same_usb_sfdisk_invocation_no_force' 1
fi

# ==============================================================================
# 回帰: Mode Bはpartprobeを呼ばない (sda1がmount中のディスクに対する
# 全体再読込は、sfdiskの使用中チェックと同じ問題を起こしうるため、
# partx --add --nrによる個別カーネル登録へ置き換えた。設計レビュー参照)。
# ==============================================================================
reset_scenario_state
run_same_usb_case same_usb_no_partprobe_exit0 0
if partprobe_called; then
    log_bool 'same_usb_partprobe_not_called' 0
else
    log_bool 'same_usb_partprobe_not_called' 1
fi

# ==============================================================================
# 回帰: partx --add --nr N -- DEVICE の引数を厳格検証する (mock_command.sh
# のpartxモックは、この正確な5引数形式以外を "unrecognized invocation"
# として拒否する)。全ての正常系シナリオがこの厳格モックを通っていること
# 自体が動的な証明になっているが、ここでは意図を明示的に記録する。
# ==============================================================================
reset_scenario_state
run_same_usb_case same_usb_partx_add_args_strict_exit0 0
if partx_called; then
    log_bool 'same_usb_partx_add_invoked' 1
else
    log_bool 'same_usb_partx_add_invoked' 0
fi
if grep -qF -- '--add --nr 3 --' "$SANDBOX/work/partx-invocations" 2>/dev/null; then
    log_bool 'same_usb_partx_add_args_correct' 1
else
    log_bool 'same_usb_partx_add_args_correct' 0
fi

# ==============================================================================
# 拒否系: partx --add (新規パーティションのカーネル登録) 自体の失敗
# (終了コード40)。パーティションテーブルへの書込みは既に成功している
# ため、exit 36とは別の終了コードで区別する。mkfsへは進まない。
# ==============================================================================
reset_scenario_state
run_same_usb_case same_usb_partx_add_fails_exit40 40 MOCK_PARTX_ADD_EXIT=1
if mkfs_called; then
    log_bool 'same_usb_partx_add_fails_no_mkfs' 0
else
    log_bool 'same_usb_partx_add_fails_no_mkfs' 1
fi

reset_scenario_state
run_same_usb_case same_usb_partx_add_fails_stderr_captured 40 \
    MOCK_PARTX_ADD_EXIT=1 \
    MOCK_PARTX_ADD_STDERR='partx: /dev/sda: error adding partition 3'
if stderr_shows same_usb_partx_add_fails_stderr_captured 'error adding partition 3'; then
    log_bool 'same_usb_partx_add_fails_stderr_message_included' 1
else
    log_bool 'same_usb_partx_add_fails_stderr_message_included' 0
fi
if stderr_shows same_usb_partx_add_fails_stderr_captured 'partx終了コード: 1'; then
    log_bool 'same_usb_partx_add_fails_exit_code_included' 1
else
    log_bool 'same_usb_partx_add_fails_exit_code_included' 0
fi

# ==============================================================================
# 拒否系: partx --add成功後のudevadm settle (デバイスノード作成待ち) の
# 失敗 (終了コード40)。partxは実際に呼ばれたが、後続のudevadm settleで
# 失敗したことを確認する (partx成功後のみ次段階へ進むことの回帰確認)。
# ==============================================================================
reset_scenario_state
run_same_usb_case same_usb_partx_udevadm_settle_fails_exit40 40 MOCK_FAIL_UDEVADM=1
if partx_called; then
    log_bool 'same_usb_partx_udevadm_settle_fails_partx_was_called' 1
else
    log_bool 'same_usb_partx_udevadm_settle_fails_partx_was_called' 0
fi
if mkfs_called; then
    log_bool 'same_usb_partx_udevadm_settle_fails_no_mkfs' 0
else
    log_bool 'same_usb_partx_udevadm_settle_fails_no_mkfs' 1
fi

# ==============================================================================
# 回帰: partx --add・udevadm settleの両方が成功した場合のみ、lsblkによる
# 新規パーティション特定・geometry検証・mkfsへ進むこと (成功経路)。
# ==============================================================================
reset_scenario_state
run_same_usb_case same_usb_partx_then_mkfs_exit0 0
if sfdisk_called && append_invoked && partx_called && mkfs_called; then
    log_bool 'same_usb_partx_success_then_mkfs_reached' 1
else
    log_bool 'same_usb_partx_success_then_mkfs_reached' 0
fi

# ==============================================================================
# 拒否系: sfdiskが必要オプションに対応していない (内部実行環境の不備)
# ==============================================================================
reset_scenario_state
run_same_usb_case same_usb_sfdisk_missing_append_exit70 70 \
    MOCK_SFDISK_HELP_MISSING_APPEND=1
if sfdisk_called && append_invoked; then
    log_bool 'same_usb_sfdisk_missing_append_no_append_attempted' 0
else
    log_bool 'same_usb_sfdisk_missing_append_no_append_attempted' 1
fi

# ==============================================================================
# 拒否系: sfdiskが --no-reread / --no-tell-kernel に対応していない場合、
# 破壊的操作の前に拒否する (check_required_commands_same_usbの拡張分)。
# ==============================================================================
reset_scenario_state
run_same_usb_case same_usb_sfdisk_missing_noreread_exit70 70 \
    MOCK_SFDISK_HELP_MISSING_NOREREAD=1
if sfdisk_called && append_invoked; then
    log_bool 'same_usb_sfdisk_missing_noreread_no_append_attempted' 0
else
    log_bool 'same_usb_sfdisk_missing_noreread_no_append_attempted' 1
fi

reset_scenario_state
run_same_usb_case same_usb_sfdisk_missing_notellkernel_exit70 70 \
    MOCK_SFDISK_HELP_MISSING_NOTELLKERNEL=1
if sfdisk_called && append_invoked; then
    log_bool 'same_usb_sfdisk_missing_notellkernel_no_append_attempted' 0
else
    log_bool 'same_usb_sfdisk_missing_notellkernel_no_append_attempted' 1
fi

# ==============================================================================
# 拒否系: partxが --add / --nr に対応していない場合、破壊的操作の前に
# 拒否する。
# ==============================================================================
reset_scenario_state
run_same_usb_case same_usb_partx_missing_add_exit70 70 \
    MOCK_PARTX_HELP_MISSING_ADD=1
if sfdisk_called && append_invoked; then
    log_bool 'same_usb_partx_missing_add_no_append_attempted' 0
else
    log_bool 'same_usb_partx_missing_add_no_append_attempted' 1
fi

reset_scenario_state
run_same_usb_case same_usb_partx_missing_nr_exit70 70 \
    MOCK_PARTX_HELP_MISSING_NR=1
if sfdisk_called && append_invoked; then
    log_bool 'same_usb_partx_missing_nr_no_append_attempted' 0
else
    log_bool 'same_usb_partx_missing_nr_no_append_attempted' 1
fi

# ==============================================================================
# 項目1: logical sector size = 4096 でのalignment/最小空き容量/START・SIZE
# 計算の確認。実機Hybrid ISOのセクタ数をそのまま4096バイトセクタ単位に
# 読み替えた模擬構成 (sda1 start=16,size=100000 / sda2
# start=50,size=1024、sda2はsda1の範囲にネスト) を用いる。
#
# 手計算 (align_sectors = 1MiB/4096 = 256):
#   max_end = max(16+100000, 50+1024) = 100016
#   100016 % 256 = 176 (割り切れない) -> new_start = 100016 + (256-176)
#                                                  = 100096
#   total_sectors = 8589934592 / 4096 = 2097152
#   usable_end = floor(2097152/256)*256 - 256 = 2097152 - 256 = 2096896
#   new_size = 2096896 - 100096 = 1996800
#   free_bytes = 1996800 * 4096 = 8,178,892,800 (約7.62GiB、1GiB以上)
# ==============================================================================
reset_scenario_state
sector4096_state="$SANDBOX/work/sfdisk-state-4096.txt"
cat > "$sector4096_state" <<STATE_EOF
label: dos
label-id: 0x61fae024
device: ${FAKE_DEVICE}
unit: sectors
sector-size: 4096

${FAKE_DEVICE}1 : start=16, size=100000, type=0, bootable
${FAKE_DEVICE}2 : start=50, size=1024, type=ef
STATE_EOF
part_rows_4096="$(use_fixture helper-part-rows-same-usb-after-append.txt part-rows-4096 __FAKE_DEVICE__ "$FAKE_DEVICE")"
env -i PATH='/usr/bin:/bin' SANDBOX="$SANDBOX" \
    FAKE_DEVICE="$FAKE_DEVICE" \
    MOCK_UID=0 MOCK_LIVE_MEDIUM_MOUNTED=0 \
    MOCK_LSBLK_KNAME='fakedisk' MOCK_LSBLK_TYPE=disk MOCK_LSBLK_RO=0 \
    MOCK_LSBLK_MAJMIN="$DEFAULT_MAJMIN" MOCK_LSBLK_TRAN='usb' \
    MOCK_ANCESTOR_CHAIN='fakedisk' \
    MOCK_LABEL_ROWS='LABEL=""' MOCK_PARTLABEL_ROWS='PARTLABEL=""' \
    MOCK_SFDISK_DUMP_STATE_FILE="$sector4096_state" \
    MOCK_BLOCKDEV_GETSZ=$((DEFAULT_DISK_BYTES / 512)) \
    MOCK_PART_ROWS_FILE="$part_rows_4096" \
    MOCK_PART_TYPE=part MOCK_PART_RO=0 MOCK_PART_MAJMIN='259:3' \
    "$COPY" create-same-usb "$FAKE_DEVICE" "$DEFAULT_MAJMIN" \
    > "$SANDBOX/work/stdout.sector4096" 2> "$SANDBOX/work/stderr.sector4096" \
    && RC=0 || RC=$?
log_result 'same_usb_sector_4096_exit0' 0 "$RC"
# 実際にsfdiskへ渡された (=状態ファイルへ追記された) start/size/typeを
# 状態ファイル自体の最終行から確認する (sfdisk-invocationsにはコマンド
# 引数のみが記録され、標準入力経由のstart=/size=/type=仕様は含まれない)。
if grep -qF 'start=100096, size=1996800, type=83' "$sector4096_state" 2>/dev/null; then
    log_bool 'same_usb_sector_4096_start_size_computed_correctly' 1
else
    log_bool 'same_usb_sector_4096_start_size_computed_correctly' 0
fi

# ---- 項目1 (拒否系): sector-size=4096でも1GiB未満の末尾空きは拒否する ----
# usable_end - new_start (セクタ) * 4096 < 1GiB となるよう、diskを縮小する。
# new_start=100096は不変 (partition構成は同じ)。1GiBはセクタ換算で
# 262144セクタ (4096バイト単位)。それよりわずかに小さい200000セクタ分の
# 空きだけを残すよう、total_sectorsを 100096+200000=300096 の
# 256刻み切り上げに設定する: ceil(300096/256)*256 = 300288。
# usable_end = 300288-256=300032 (256刻みの端数調整により意図した値と
# 多少ずれるが、1GiB未満であることが本旨のため許容する)。
reset_scenario_state
insufficient4096_state="$SANDBOX/work/sfdisk-state-4096-insufficient.txt"
cat > "$insufficient4096_state" <<STATE_EOF
label: dos
label-id: 0x61fae024
device: ${FAKE_DEVICE}
unit: sectors
sector-size: 4096

${FAKE_DEVICE}1 : start=16, size=100000, type=0, bootable
${FAKE_DEVICE}2 : start=50, size=1024, type=ef
STATE_EOF
# blockdev --getszは対象diskの実際のlogical sector sizeによらず常に
# 512バイトセクタ単位で返るため (production側コメント参照)、
# 「total_bytes = 300288 * 4096 (4096バイトセクタ換算)」を512バイト
# セクタ単位に換算した値をMOCK_BLOCKDEV_GETSZへ渡す。
small_total_bytes=$((300288 * 4096))
small_total_getsz=$((small_total_bytes / 512))
env -i PATH='/usr/bin:/bin' SANDBOX="$SANDBOX" \
    FAKE_DEVICE="$FAKE_DEVICE" \
    MOCK_UID=0 MOCK_LIVE_MEDIUM_MOUNTED=0 \
    MOCK_LSBLK_KNAME='fakedisk' MOCK_LSBLK_TYPE=disk MOCK_LSBLK_RO=0 \
    MOCK_LSBLK_MAJMIN="$DEFAULT_MAJMIN" MOCK_LSBLK_TRAN='usb' \
    MOCK_ANCESTOR_CHAIN='fakedisk' \
    MOCK_LABEL_ROWS='LABEL=""' MOCK_PARTLABEL_ROWS='PARTLABEL=""' \
    MOCK_SFDISK_DUMP_STATE_FILE="$insufficient4096_state" \
    MOCK_BLOCKDEV_GETSZ="$small_total_getsz" \
    "$COPY" create-same-usb "$FAKE_DEVICE" "$DEFAULT_MAJMIN" \
    > "$SANDBOX/work/stdout.sector4096-insufficient" 2> "$SANDBOX/work/stderr.sector4096-insufficient" \
    && RC=0 || RC=$?
log_result 'same_usb_sector_4096_insufficient_space_exit34' 34 "$RC"

# ==============================================================================
# 項目2: sfdisk --backup が生成する一時ディレクトリのcleanup方針。
# 「MNT_DIR/LOCK_DIRと同じtrap経由で、成功・失敗・シグナル終了いずれの
# 場合も必ず削除する一時ファイル」として扱うことを確認する。
# ==============================================================================
no_leftover_helper_run_dirs() {
    ! find "$SANDBOX/run" -maxdepth 1 -name 'mypocketos-persistence-setup-helper.*' 2>/dev/null | grep -q .
}

# ---- 成功時 ----
reset_scenario_state
run_same_usb_case same_usb_cleanup_success_no_backup_dir_left 0
if no_leftover_helper_run_dirs; then
    log_bool 'same_usb_cleanup_success_backup_dir_removed' 1
else
    log_bool 'same_usb_cleanup_success_backup_dir_removed' 0
fi

# ---- エラー時 (sfdisk --append自体の失敗、backup作成"後") ----
reset_scenario_state
run_same_usb_case same_usb_cleanup_append_fail_no_backup_dir_left 36 \
    MOCK_SFDISK_APPEND_EXIT=1
if no_leftover_helper_run_dirs; then
    log_bool 'same_usb_cleanup_append_fail_backup_dir_removed' 1
else
    log_bool 'same_usb_cleanup_append_fail_backup_dir_removed' 0
fi

# ---- エラー時 (サーキットブレーカー、既存partition変化検出) ----
reset_scenario_state
run_same_usb_case same_usb_cleanup_existing_changed_no_backup_dir_left 37 \
    MOCK_SFDISK_APPEND_CORRUPT_EXISTING=1
if no_leftover_helper_run_dirs; then
    log_bool 'same_usb_cleanup_existing_changed_backup_dir_removed' 1
else
    log_bool 'same_usb_cleanup_existing_changed_backup_dir_removed' 0
fi

# ---- backup用ディレクトリ自体の削除に失敗した場合、成功予定(0)を71へ
#      正規化すること (MNT_DIR/LOCK_DIRと同じ既存パターンを踏襲) ----
reset_scenario_state
run_same_usb_case same_usb_cleanup_rm_failure_normalizes_to_71 71 \
    MOCK_FAIL_RM_SFDISK_BACKUP=1

# ---- シグナル終了時 (sfdisk --append実行中にSIGINTを受けても、backup用
#      ディレクトリ・lockディレクトリとも残らないこと) ----
reset_scenario_state
sig_state="$(new_sfdisk_state same_usb_signal)"
(
    env -i PATH='/usr/bin:/bin' SANDBOX="$SANDBOX" \
        FAKE_DEVICE="$FAKE_DEVICE" \
        MOCK_UID=0 MOCK_LIVE_MEDIUM_MOUNTED=0 \
        MOCK_LSBLK_KNAME='fakedisk' MOCK_LSBLK_TYPE=disk MOCK_LSBLK_RO=0 \
        MOCK_LSBLK_MAJMIN="$DEFAULT_MAJMIN" MOCK_LSBLK_TRAN='usb' \
        MOCK_ANCESTOR_CHAIN='fakedisk' \
        MOCK_LABEL_ROWS='LABEL=""' MOCK_PARTLABEL_ROWS='PARTLABEL=""' \
        MOCK_SFDISK_DUMP_STATE_FILE="$sig_state" \
        MOCK_BLOCKDEV_GETSZ=$((DEFAULT_DISK_BYTES / 512)) \
        MOCK_SFDISK_APPEND_SLEEP_SECONDS=10 \
        timeout --preserve-status --signal=INT 2 \
        "$COPY" create-same-usb "$FAKE_DEVICE" "$DEFAULT_MAJMIN"
) > "$SANDBOX/work/stdout.signal" 2> "$SANDBOX/work/stderr.signal" && RC=0 || RC=$?
# timeout --signal=INT はプロセスグループ全体にSIGINTを送るため、sleep中の
# モックsfdisk自身もその場で中断されうる。この場合、helper側の
# "if ! CMD; then fail N; fi" は (中断されたCMDの非0終了を検知して)
# 通常のCMD失敗経路 (このシナリオではsfdisk-append、終了コード36) を
# 通ることがあり、これはcheck_signalのチェックポイント間で保留シグナルを
# 検出して終了する129/130/143の経路とは別に、既存の全コード (Mode A含む)
# で最初から採用している設計である。そのため、ここでは終了コードの厳密な
# 一致は求めず、非0終了 (処理が正常完了していないこと) とcleanupの結果
# だけを確認する。
if [ "$RC" -ne 0 ]; then
    log_bool 'same_usb_signal_during_append_nonzero_exit' 1
else
    log_bool 'same_usb_signal_during_append_nonzero_exit' 0
fi
if no_leftover_helper_run_dirs; then
    log_bool 'same_usb_signal_during_append_backup_dir_removed' 1
else
    log_bool 'same_usb_signal_during_append_backup_dir_removed' 0
fi
if [ -e "$SANDBOX/run/lock/mypocketos-persistence-setup-helper.lock" ]; then
    log_bool 'same_usb_signal_during_append_lock_removed' 0
else
    log_bool 'same_usb_signal_during_append_lock_removed' 1
fi

# ==============================================================================
# 項目3: sfdisk --append後、mkfs実行前に実ジオメトリを検証すること。
# 不一致ならmkfsせず終了コード38で拒否する。
# ==============================================================================

# ---- actual start != calculated start ----
reset_scenario_state
run_same_usb_case same_usb_geometry_start_mismatch_exit38 38 \
    MOCK_SFDISK_APPEND_OVERRIDE_START=3500000
if mkfs_called; then
    log_bool 'same_usb_geometry_start_mismatch_no_mkfs' 0
else
    log_bool 'same_usb_geometry_start_mismatch_no_mkfs' 1
fi

# ---- actual size != calculated size ----
reset_scenario_state
run_same_usb_case same_usb_geometry_size_mismatch_exit38 38 \
    MOCK_SFDISK_APPEND_OVERRIDE_SIZE=1000000
if mkfs_called; then
    log_bool 'same_usb_geometry_size_mismatch_no_mkfs' 0
else
    log_bool 'same_usb_geometry_size_mismatch_no_mkfs' 1
fi

# ---- actual MBR type != 83 ----
reset_scenario_state
run_same_usb_case same_usb_geometry_type_mismatch_exit38 38 \
    MOCK_SFDISK_APPEND_OVERRIDE_TYPE=7
if mkfs_called; then
    log_bool 'same_usb_geometry_type_mismatch_no_mkfs' 0
else
    log_bool 'same_usb_geometry_type_mismatch_no_mkfs' 1
fi

# ---- actual start <= 既存partition終端の最大値 (重なり) ----
reset_scenario_state
run_same_usb_case same_usb_geometry_start_before_existing_end_exit38 38 \
    MOCK_SFDISK_APPEND_OVERRIDE_START=1000
if mkfs_called; then
    log_bool 'same_usb_geometry_start_before_existing_end_no_mkfs' 0
else
    log_bool 'same_usb_geometry_start_before_existing_end_no_mkfs' 1
fi

# ---- actual end (start+size) > ディスク総セクタ数 ----
reset_scenario_state
run_same_usb_case same_usb_geometry_end_beyond_disk_exit38 38 \
    MOCK_SFDISK_APPEND_OVERRIDE_SIZE=99999999999
if mkfs_called; then
    log_bool 'same_usb_geometry_end_beyond_disk_no_mkfs' 0
else
    log_bool 'same_usb_geometry_end_beyond_disk_no_mkfs' 1
fi

# ==============================================================================
# 実機dump桁揃え回帰: 実機のsfdisk --dump生出力 (start=/size=の値が
# 桁揃えのため右詰め・可変長スペースで出力されている) と、実機の
# blockdev --getsz実測値 (GETSZ=15730688、GETSS=512) の両方をそのまま
# 入力しても、SAME_USB_START/SAME_USB_SIZEが期待値どおりに計算され、
# create-same-usbがsfdisk --append段階まで正しく進むこと。
#
# 手計算 (align_sectors=2048、実機と同じ実dump構造からmax_end=3492480、
# ここまではDEFAULT_DISK_BYTES使用時と同じ):
#   total_sectors = 15730688 (実機のblockdev --getsz実測値、
#                   sector-size=512のためtotal_bytes/512と同じ)
#   usable_end = floor(15730688/2048)*2048 - 2048 = 15730688-2048
#              = 15728640 (15730688は2048の倍数)
#   new_start  = 3493888 (既存partition構成に依存、DEFAULT_DISK_BYTES
#                使用時と同一)
#   new_size   = 15728640 - 3493888 = 12234752
#
# GETSS (論理セクタサイズ) はproduction側で使用しない (blockdev --getsz
# は対象diskの実際のlogical sector sizeに依存せず常に512バイトセクタ
# 単位で報告されるため。GUI/helper双方のコメント参照)。実機確認済みの
# 値としてこのコメントに記録するに留める。
reset_scenario_state
real_padded_state="$(new_sfdisk_state_real_padded same_usb_real_padded)"
env -i PATH='/usr/bin:/bin' SANDBOX="$SANDBOX" \
    FAKE_DEVICE="$FAKE_DEVICE" \
    MOCK_UID=0 MOCK_LIVE_MEDIUM_MOUNTED=0 \
    MOCK_LSBLK_KNAME='fakedisk' MOCK_LSBLK_TYPE=disk MOCK_LSBLK_RO=0 \
    MOCK_LSBLK_MAJMIN="$DEFAULT_MAJMIN" MOCK_LSBLK_TRAN='usb' \
    MOCK_ANCESTOR_CHAIN='fakedisk' \
    MOCK_LABEL_ROWS='LABEL=""' MOCK_PARTLABEL_ROWS='PARTLABEL=""' \
    MOCK_SFDISK_DUMP_STATE_FILE="$real_padded_state" \
    MOCK_BLOCKDEV_GETSZ=15730688 \
    MOCK_PART_ROWS_FILE="$PART_ROWS_AFTER" \
    MOCK_PART_TYPE=part MOCK_PART_RO=0 MOCK_PART_MAJMIN='259:3' \
    "$COPY" create-same-usb "$FAKE_DEVICE" "$DEFAULT_MAJMIN" \
    > "$SANDBOX/work/stdout.real_padded" 2> "$SANDBOX/work/stderr.real_padded" \
    && RC=0 || RC=$?
log_result 'same_usb_real_padded_dump_exit0' 0 "$RC"
if grep -qF 'start=3493888, size=12234752, type=83' "$real_padded_state" 2>/dev/null; then
    log_bool 'same_usb_real_padded_dump_start_size_correct' 1
else
    log_bool 'same_usb_real_padded_dump_start_size_correct' 0
fi
# 既存のsda1/sda2エントリ (桁揃えつきの実機形式) が、追加操作後も内容の
# 上では変化していないこと (start/size自体は不変のはず。文字列としての
# 桁揃え表記が変わってもverify_existing_entries_unchangedは値ベースで
# 比較するため、正常に「変化なし」と判定されるはずである)。
if grep -qF 'start=          64, size=    3492416, type=0, bootable' "$real_padded_state" 2>/dev/null \
    && grep -qF 'start=         540, size=       6656, type=ef' "$real_padded_state" 2>/dev/null; then
    log_bool 'same_usb_real_padded_dump_existing_entries_untouched' 1
else
    log_bool 'same_usb_real_padded_dump_existing_entries_untouched' 0
fi

echo
echo "== helper (same-usb) summary =="
printf '%s' "$RESULTS"
echo "PASS=$PASS FAIL=$FAIL"

if [ "$FAIL" -eq 0 ]; then
    exit 0
else
    exit 1
fi
