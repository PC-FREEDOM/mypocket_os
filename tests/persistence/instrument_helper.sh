#!/bin/sh
# tests/persistence/instrument_helper.sh
#
# mypocketos-persistence-setup-helper (特権ヘルパー) の production ファイルを
# 読み取り、サンドボックス化された実行コピーを生成する。production ファイル
# は一切変更しない (常に "sed ... SRC > DEST" で新規ファイルへ出力し、
# sed -i は使わない)。段階1/段階2の方式は instrument_gui.sh と同じ。
#
# 使い方: instrument_helper.sh SANDBOX_DIR DEST_PATH
#
# 各ルールの一致件数は、事前に `grep -cE` で本体ファイルに対して直接
# 確認済みの値である。CMD_* が24件 (create-same-usb関連のCMD_SFDISK/
# CMD_BLOCKDEV/CMD_READLINK/CMD_PARTX/CMD_RMを含む)、その他が24件 (同じく
# create-same-usb追加分を含む: sysfsパス1件・mktempテンプレート1件・
# identify_new_partition_since_baseline用の/dev制約2件・-b緩和1件) の
# 合計48ルール。
set -eu

TESTS_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$TESTS_DIR/../.." && pwd)"
PROD_GUI="$REPO_ROOT/config/includes.chroot/usr/local/bin/mypocketos-persistence-setup"
PROD_HELPER="$REPO_ROOT/config/includes.chroot/usr/local/libexec/mypocketos-persistence-setup-helper"
. "$TESTS_DIR/common.sh"

instrument_helper() {
    # instrument_helper SANDBOX DEST
    sandbox="$1"; dest="$2"

    cp -- "$PROD_HELPER" "$dest"

    # ---- 段階1a: CMD_* 絶対パス (19件、各期待件数1) ----------------------
    apply_rule helper-cmd-lsblk     'CMD_LSBLK=/usr/bin/lsblk'                'CMD_LSBLK=@@SANDBOX_BIN@@/lsblk'         1 "$dest"
    apply_rule helper-cmd-findmnt   'CMD_FINDMNT=/usr/bin/findmnt'            'CMD_FINDMNT=@@SANDBOX_BIN@@/findmnt'     1 "$dest"
    apply_rule helper-cmd-wipefs    'CMD_WIPEFS=/usr/sbin/wipefs'             'CMD_WIPEFS=@@SANDBOX_BIN@@/wipefs'       1 "$dest"
    apply_rule helper-cmd-parted    'CMD_PARTED=/usr/sbin/parted'             'CMD_PARTED=@@SANDBOX_BIN@@/parted'       1 "$dest"
    apply_rule helper-cmd-partprobe 'CMD_PARTPROBE=/usr/sbin/partprobe'       'CMD_PARTPROBE=@@SANDBOX_BIN@@/partprobe' 1 "$dest"
    apply_rule helper-cmd-udevadm   'CMD_UDEVADM=/usr/bin/udevadm'            'CMD_UDEVADM=@@SANDBOX_BIN@@/udevadm'     1 "$dest"
    apply_rule helper-cmd-mkfs-ext4 'CMD_MKFS_EXT4=/usr/sbin/mkfs\.ext4'      'CMD_MKFS_EXT4=@@SANDBOX_BIN@@/mkfs.ext4' 1 "$dest"
    apply_rule helper-cmd-mount     'CMD_MOUNT=/usr/bin/mount'                'CMD_MOUNT=@@SANDBOX_BIN@@/mount'         1 "$dest"
    apply_rule helper-cmd-umount    'CMD_UMOUNT=/usr/bin/umount'              'CMD_UMOUNT=@@SANDBOX_BIN@@/umount'       1 "$dest"
    apply_rule helper-cmd-mktemp    'CMD_MKTEMP=/usr/bin/mktemp'              'CMD_MKTEMP=@@SANDBOX_BIN@@/mktemp'       1 "$dest"
    apply_rule helper-cmd-stat      'CMD_STAT=/usr/bin/stat'                  'CMD_STAT=@@SANDBOX_BIN@@/stat'           1 "$dest"
    apply_rule helper-cmd-id        'CMD_ID=/usr/bin/id'                      'CMD_ID=@@SANDBOX_BIN@@/id'               1 "$dest"
    apply_rule helper-cmd-cat       'CMD_CAT=/usr/bin/cat'                    'CMD_CAT=@@SANDBOX_BIN@@/cat'             1 "$dest"
    apply_rule helper-cmd-sync      'CMD_SYNC=/usr/bin/sync'                  'CMD_SYNC=@@SANDBOX_BIN@@/sync'           1 "$dest"
    apply_rule helper-cmd-mkdir     'CMD_MKDIR=/usr/bin/mkdir'                'CMD_MKDIR=@@SANDBOX_BIN@@/mkdir'         1 "$dest"
    apply_rule helper-cmd-rmdir     'CMD_RMDIR=/usr/bin/rmdir'                'CMD_RMDIR=@@SANDBOX_BIN@@/rmdir'         1 "$dest"
    apply_rule helper-cmd-awk       'CMD_AWK=/usr/bin/awk'                    'CMD_AWK=@@SANDBOX_BIN@@/awk'             1 "$dest"
    apply_rule helper-cmd-grep      'CMD_GREP=/usr/bin/grep'                  'CMD_GREP=@@SANDBOX_BIN@@/grep'           1 "$dest"
    apply_rule helper-cmd-ls        'CMD_LS=/usr/bin/ls'                      'CMD_LS=@@SANDBOX_BIN@@/ls'               1 "$dest"
    apply_rule helper-cmd-sfdisk    'CMD_SFDISK=/usr/sbin/sfdisk'             'CMD_SFDISK=@@SANDBOX_BIN@@/sfdisk'       1 "$dest"
    apply_rule helper-cmd-blockdev  'CMD_BLOCKDEV=/usr/sbin/blockdev'         'CMD_BLOCKDEV=@@SANDBOX_BIN@@/blockdev'   1 "$dest"
    apply_rule helper-cmd-readlink  'CMD_READLINK=/usr/bin/readlink'          'CMD_READLINK=@@SANDBOX_BIN@@/readlink'   1 "$dest"
    apply_rule helper-cmd-partx     'CMD_PARTX=/usr/bin/partx'                'CMD_PARTX=@@SANDBOX_BIN@@/partx'         1 "$dest"
    apply_rule helper-cmd-rm        'CMD_RM=/usr/bin/rm'                      'CMD_RM=@@SANDBOX_BIN@@/rm'               1 "$dest"

    # ---- 段階1b: その他 (19件) -------------------------------------------
    apply_rule helper-fixed-path \
        "PATH='/usr/sbin:/usr/bin:/sbin:/bin'" \
        "PATH='@@SANDBOX_BIN@@'" \
        1 "$dest"

    apply_rule helper-lock-dir \
        "LOCK_DIR='/run/lock/mypocketos-persistence-setup-helper\.lock'" \
        "LOCK_DIR='@@SANDBOX_RUN@@/lock/mypocketos-persistence-setup-helper.lock'" \
        1 "$dest"

    # validate_device_argの物理デバイス根拠チェックと、対応する
    # エラーメッセージ本文の計2箇所に同一リテラルが出現する。
    apply_rule helper-sys-device-check \
        '/sys/class/block/\$kname/device' \
        '@@SANDBOX_SYS@@/class/block/$kname/device' \
        2 "$dest"

    apply_rule helper-sys-holders-dir \
        '/sys/class/block/\$DEVICE_KNAME/holders' \
        '@@SANDBOX_SYS@@/class/block/$DEVICE_KNAME/holders' \
        1 "$dest"

    # check_usb_transport (create-same-usb専用) が使う実デバイスパス。
    apply_rule helper-sys-device-check-same-usb \
        '/sys/class/block/\$DEVICE_KNAME/device' \
        '@@SANDBOX_SYS@@/class/block/$DEVICE_KNAME/device' \
        1 "$dest"

    apply_rule helper-proc-cmdline \
        '"\$CMD_CAT" /proc/cmdline' \
        '"$CMD_CAT" @@SANDBOX_PROC_CMDLINE@@' \
        1 "$dest"

    apply_rule helper-proc-swaps \
        '"\$CMD_CAT" /proc/swaps' \
        '"$CMD_CAT" @@SANDBOX_PROC_SWAPS@@' \
        1 "$dest"

    # check_live_envの判定文・エラーメッセージ・check_not_live_source
    # (Mode A) ・check_is_live_boot_disk (Mode B create-same-usb) の
    # findmnt --target の計4箇所に同一リテラルが出現する。
    apply_rule helper-run-live-medium \
        '/run/live/medium' \
        '@@SANDBOX_RUN@@/live/medium' \
        4 "$dest"

    apply_rule helper-mktemp-template \
        '/run/mypocketos-persistence-setup-helper\.XXXXXX' \
        '@@SANDBOX_RUN@@/mypocketos-persistence-setup-helper.XXXXXX' \
        1 "$dest"

    # create-same-usb (Mode B) のsfdiskバックアップ用一時ディレクトリの
    # mktempテンプレート。
    apply_rule helper-mktemp-template-sfdisk-backup \
        '/run/mypocketos-persistence-setup-helper\.sfdisk-backup\.XXXXXX' \
        '@@SANDBOX_RUN@@/mypocketos-persistence-setup-helper.sfdisk-backup.XXXXXX' \
        1 "$dest"

    # ---- /dev配下制約 (無効化せず、sandbox/devを指すよう置換する) --------
    # "/dev/*) ;;" は4関数で同一テキストのため、直前の一意な
    # "case ... in" 行をアンカーにして「その次の行だけ」を置換する。
    apply_rule_next_line helper-dev-prefix-device-arg \
        'case "\$device" in' 1 \
        '/dev/\*' '@@SANDBOX_DEV@@/*' \
        "$dest"

    apply_rule helper-dev-parent-device-arg \
        'if \[ "\$parent" != '"'"'/dev'"'"' \]' \
        'if [ "$parent" != '"'"'@@SANDBOX_DEV@@'"'"' ]' \
        1 "$dest"

    apply_rule_next_line helper-dev-prefix-ancestor \
        'case "\$src" in' 1 \
        '/dev/\*' '@@SANDBOX_DEV@@/*' \
        "$dest"

    apply_rule_next_line helper-dev-prefix-home-source \
        'case "\$home_source" in' 1 \
        '/dev/\*' '@@SANDBOX_DEV@@/*' \
        "$dest"

    apply_rule_next_line helper-dev-prefix-identify-part \
        'case "\$part_path" in' 1 \
        '/dev/\*' '@@SANDBOX_DEV@@/*' \
        "$dest"

    apply_rule helper-dev-parent-identify-part \
        'if \[ "\$part_parent" != '"'"'/dev'"'"' \]' \
        'if [ "$part_parent" != '"'"'@@SANDBOX_DEV@@'"'"' ]' \
        1 "$dest"

    # identify_new_partition_since_baseline (create-same-usb専用、Mode Aの
    # identify_created_partitionとは変数名を別にしているため、上記2ルール
    # とは別に必要)。
    apply_rule_next_line helper-dev-prefix-identify-new-part \
        'case "\$new_part_path" in' 1 \
        '/dev/\*' '@@SANDBOX_DEV@@/*' \
        "$dest"

    apply_rule helper-dev-parent-identify-new-part \
        'if \[ "\$new_part_parent" != '"'"'/dev'"'"' \]' \
        'if [ "$new_part_parent" != '"'"'@@SANDBOX_DEV@@'"'"' ]' \
        1 "$dest"

    # ---- -b -> -e 緩和 (root/mknod無しで実block deviceを用意できないため) --
    apply_rule helper-b-device-arg \
        '\[ ! -b "\$device" \]' '[ ! -e "$device" ]' 1 "$dest"
    apply_rule helper-b-reverify-device \
        '\[ ! -b "\$DEVICE" \]' '[ ! -e "$DEVICE" ]' 1 "$dest"
    apply_rule helper-b-ancestor-chain \
        '\[ ! -b "\$src" \]' '[ ! -e "$src" ]' 1 "$dest"
    apply_rule helper-b-identify-part \
        '\[ ! -b "\$part_path" \]' '[ ! -e "$part_path" ]' 1 "$dest"
    apply_rule helper-b-reverify-part \
        '\[ ! -b "\$CREATED_PART_PATH" \]' '[ ! -e "$CREATED_PART_PATH" ]' 1 "$dest"
    apply_rule helper-b-identify-new-part \
        '\[ ! -b "\$new_part_path" \]' '[ ! -e "$new_part_path" ]' 1 "$dest"

    # ---- 段階2: 固定トークン -> 実サンドボックスパス ---------------------
    resolve_token '@@SANDBOX_BIN@@' "$sandbox/bin" "$dest"
    resolve_token '@@SANDBOX_SYS@@' "$sandbox/sys" "$dest"
    resolve_token '@@SANDBOX_PROC_CMDLINE@@' "$sandbox/proc/cmdline" "$dest"
    resolve_token '@@SANDBOX_PROC_SWAPS@@' "$sandbox/proc/swaps" "$dest"
    resolve_token '@@SANDBOX_RUN@@' "$sandbox/run" "$dest"
    resolve_token '@@SANDBOX_DEV@@' "$sandbox/dev" "$dest"

    chmod +x "$dest"

    verify_helper_invariants "$sandbox" "$dest"
}

verify_helper_invariants() {
    sandbox="$1"; dest="$2"
    sandbox_esc="$(escape_ere "$sandbox")"

    # 未解決トークンが0件であること。
    assert_count 'helper-invariant-no-unresolved-tokens' '@@[A-Z_]+@@' "$dest" 0

    # CMD_* が正確に24件であること。
    assert_count 'helper-invariant-cmd-star-count' '^CMD_[A-Za-z0-9_]+=' "$dest" 24

    # その24件全てがsandbox bin配下を指していること。
    assert_count 'helper-invariant-cmd-star-all-sandboxed' \
        "^CMD_[A-Za-z0-9_]+=${sandbox_esc}/bin/" "$dest" 24

    # 固定PATHがsandbox binのみを指していること。
    assert_count 'helper-invariant-path-is-sandbox-bin' \
        "PATH='${sandbox_esc}/bin'" "$dest" 1

    # 実システム絶対パス (/usr/, /sbin/) がコメント・shebang行以外に
    # 残っていないこと。
    real_path_lines="$(grep -nE '(^|[^#].*)(/usr/|/sbin/)' "$dest" \
        | grep -vE '^1:#!/bin/sh$' \
        | grep -vE '^[0-9]+:[[:space:]]*#' || true)"
    if [ -n "$real_path_lines" ]; then
        echo "[helper-invariant-no-real-system-paths] REFUSING: found real system path(s):" >&2
        printf '%s\n' "$real_path_lines" >&2
        exit 93
    fi

    # メイン抑止方式 (後続PR向け、未使用) のためのマーカーコメントが
    # 正確に1件であることを、今のうちから保証しておく。
    assert_count 'helper-invariant-main-marker-count' \
        '# ---- メイン処理 ' "$dest" 1
}

instrument_helper "$1" "$2"
