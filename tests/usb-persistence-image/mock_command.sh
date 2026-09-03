#!/bin/sh
# tests/usb-persistence-image/mock_command.sh
#
# write_mocks SANDBOX_BIN SANDBOX_ROOT
#
# $SANDBOX_BIN 配下へ、build-usb-persistence-image.sh (instrument後) が
# 呼び出す全20コマンドのモック/ラッパーを書き出す。3分類方式を実装する。
#
# 1. 完全モック (実バイナリを一切execしない): xorriso, mke2fs, e2fsck,
#    debugfs, df。重い処理 (実ISO生成・実ext4作成) をCIで一切走らせない
#    ための対象。df も、空き容量不足シナリオを決定論的に再現するため
#    完全モックとする。振る舞いは環境変数 (MOCK_*) で制御する。
# 2. 読み取り専用コマンド: grep, sed, awk, stat, cmp, sha256sum,
#    realpath, dirname, cat, diff。実バイナリへ委譲するが、絶対パス
#    引数がsandbox外を指す場合はexit 99で拒否する (読み取り専用でも
#    sandbox外を検査対象にしないことを自己検証する)。
# 3. sandbox内限定の書き込みコマンド: rm, mkdir, mktemp, dd, ln, mv。
#    書き込み (または新規作成) 対象パスがsandbox内であることを検査した
#    うえで実バイナリへ委譲する。sandbox外を指す場合はexit 99で拒否する。
#
# evalは一切使わない。最後の引数・最後から2番目の引数の取得は、
# forループで位置をずらしながら安全に求める。
#
# モックが書く先はいずれも $SANDBOX_BIN 配下のみであり、production
# ファイルには一切書き込まない。
set -eu

write_mocks() {
    bin="$1"; sandbox="$2"

    # ---- 読み取り専用コマンド (sandbox外の絶対パス引数は拒否) --------------
    for cmd in grep sed awk stat cmp sha256sum realpath dirname cat diff; do
        real="$(command -v "$cmd")"
        cat > "$bin/$cmd" <<WRAPEOF
#!/bin/sh
set -eu
sandbox='$sandbox'
for arg in "\$@"; do
    case "\$arg" in
        /dev/fd/*)
            # プロセス置換 (<(...)) が生成する一時パイプ。プロセス自身に
            # 閉じたfdであり、sandbox外のファイルシステムパスを指す
            # ものではないため許可する。
            ;;
        /*)
            case "\$arg" in
                "\$sandbox"/*|"\$sandbox") ;;
                *)
                    echo "mock $cmd: path outside sandbox: \$arg" >&2
                    exit 99
                    ;;
            esac
            ;;
    esac
done
exec "$real" "\$@"
WRAPEOF
        chmod 755 "$bin/$cmd"
    done

    # ---- sandbox内限定の書き込みコマンド ------------------------------------
    real_rm="$(command -v rm)"
    cat > "$bin/rm" <<WRAPEOF
#!/bin/sh
set -eu
sandbox='$sandbox'
for arg in "\$@"; do
    case "\$arg" in
        -*) continue ;;
    esac
    case "\$arg" in
        "\$sandbox"/*|"\$sandbox") ;;
        *)
            echo "mock rm: path outside sandbox: \$arg" >&2
            exit 99
            ;;
    esac
done
exec "$real_rm" "\$@"
WRAPEOF
    chmod 755 "$bin/rm"

    real_mkdir="$(command -v mkdir)"
    cat > "$bin/mkdir" <<WRAPEOF
#!/bin/sh
set -eu
sandbox='$sandbox'
for arg in "\$@"; do
    case "\$arg" in
        -*) continue ;;
    esac
    case "\$arg" in
        "\$sandbox"/*|"\$sandbox") ;;
        *)
            echo "mock mkdir: path outside sandbox: \$arg" >&2
            exit 99
            ;;
    esac
done
exec "$real_mkdir" "\$@"
WRAPEOF
    chmod 755 "$bin/mkdir"

    # production側は現在CMD_MVを定義していない (最終公開をhard link方式へ
    # 変更したため) が、防御的に同水準のsandbox制限ラッパーを用意しておく。
    real_mv="$(command -v mv)"
    cat > "$bin/mv" <<WRAPEOF
#!/bin/sh
set -eu
sandbox='$sandbox'
p1=''; p2=''; n=0
for arg in "\$@"; do
    case "\$arg" in
        -*) continue ;;
    esac
    n=\$((n + 1))
    if [ "\$n" -eq 1 ]; then p1="\$arg"; fi
    p2="\$arg"
done
if [ "\$n" -lt 2 ]; then
    echo "mock mv: expected at least 2 path arguments" >&2
    exit 99
fi
for p in "\$p1" "\$p2"; do
    case "\$p" in
        "\$sandbox"/*|"\$sandbox") ;;
        *)
            echo "mock mv: path outside sandbox: \$p" >&2
            exit 99
            ;;
    esac
done
exec "$real_mv" "\$@"
WRAPEOF
    chmod 755 "$bin/mv"

    real_ln="$(command -v ln)"
    cat > "$bin/ln" <<WRAPEOF
#!/bin/sh
set -eu
sandbox='$sandbox'
p1=''; p2=''; n=0
for arg in "\$@"; do
    case "\$arg" in
        -*) continue ;;
    esac
    n=\$((n + 1))
    if [ "\$n" -eq 1 ]; then p1="\$arg"; fi
    p2="\$arg"
done
if [ "\$n" -ne 2 ]; then
    echo "mock ln: expected exactly 2 path arguments (got \$n)" >&2
    exit 99
fi
for p in "\$p1" "\$p2"; do
    case "\$p" in
        "\$sandbox"/*) ;;
        *)
            echo "mock ln: path outside sandbox: \$p" >&2
            exit 99
            ;;
    esac
done
# 公開直前競合 (TOCTOU) を再現するフック: 呼び出し直前に、あたかも別の
# プロセスが公開先へ既に何かを作成していたかのように、宛先(p2)へ内容を
# 先書きしておく。以降の実lnは (-f なしのため) 既存宛先に対して確実に
# 失敗し、production側のexit 60経路を検証できる。宛先はsandbox内である
# ことを上のループで既に確認済み。
if [ -n "\${MOCK_LN_PRECREATE_DEST:-}" ]; then
    printf '%s' "\$MOCK_LN_PRECREATE_DEST" > "\$p2"
fi
exec "$real_ln" "\$@"
WRAPEOF
    chmod 755 "$bin/ln"

    real_mktemp="$(command -v mktemp)"
    cat > "$bin/mktemp" <<WRAPEOF
#!/bin/sh
set -eu
sandbox='$sandbox'
real='$real_mktemp'
if [ "\$1" != '-d' ] || [ \$# -ne 2 ]; then
    echo "mock mktemp: unsupported invocation: \$*" >&2
    exit 99
fi
template="\$2"
case "\$template" in
    "\$sandbox"/*) ;;
    *)
        echo "mock mktemp: template outside sandbox: \$template" >&2
        exit 99
        ;;
esac
result="\$("\$real" -d "\$template")"
case "\$result" in
    "\$sandbox"/*) ;;
    *)
        echo "mock mktemp: result outside sandbox: \$result" >&2
        exit 99
        ;;
esac
printf '%s\n' "\$result"
WRAPEOF
    chmod 755 "$bin/mktemp"

    real_dd="$(command -v dd)"
    cat > "$bin/dd" <<WRAPEOF
#!/bin/sh
set -eu
sandbox='$sandbox'
real='$real_dd'
of_val=''
if_val=''
for arg in "\$@"; do
    case "\$arg" in
        of=*) of_val="\${arg#of=}" ;;
        if=*) if_val="\${arg#if=}" ;;
    esac
done
if [ -z "\$of_val" ]; then
    echo "mock dd: of= argument not found" >&2
    exit 99
fi
case "\$of_val" in
    "\$sandbox"/*) ;;
    *)
        echo "mock dd: write target (of=) outside sandbox: \$of_val" >&2
        exit 99
        ;;
esac
# if= はsandbox内、または明示allowlist (MOCK_DD_IF_ALLOWLIST、空白区切りの
# 完全一致パス一覧) に含まれる場合のみ許可する。読み取り専用引数だが、
# 想定外のパスを黙って読ませないため同水準で検査する。
if [ -n "\$if_val" ]; then
    if_allowed=0
    case "\$if_val" in
        "\$sandbox"/*) if_allowed=1 ;;
    esac
    if [ "\$if_allowed" -ne 1 ] && [ -n "\${MOCK_DD_IF_ALLOWLIST:-}" ]; then
        for allowed in \$MOCK_DD_IF_ALLOWLIST; do
            [ "\$if_val" = "\$allowed" ] && if_allowed=1
        done
    fi
    if [ "\$if_allowed" -ne 1 ]; then
        echo "mock dd: read source (if=) outside sandbox and not allowlisted: \$if_val" >&2
        exit 99
    fi
fi
exec "\$real" "\$@"
WRAPEOF
    chmod 755 "$bin/dd"

    # ---- 完全モック: df (空き容量シナリオを決定論的に再現するため) --------
    cat > "$bin/df" <<WRAPEOF
#!/bin/sh
set -eu
sandbox='$sandbox'
args=" \$* "
case "\$args" in
    *' -P -B1 -- '*) ;;
    *)
        echo "mock df: unsupported invocation: \$*" >&2
        exit 99
        ;;
esac
dir=''
for arg in "\$@"; do
    dir="\$arg"
done
case "\$dir" in
    "\$sandbox"/*|"\$sandbox") ;;
    *)
        echo "mock df: path outside sandbox: \$dir" >&2
        exit 99
        ;;
esac
avail="\${MOCK_DF_AVAILABLE_BYTES:-99999999999}"
printf 'Filesystem        1B-blocks         Used    Available Capacity Mounted on\n'
printf 'mockfs        200000000000 100000000000 %s      50%% %s\n' "\$avail" "\$dir"
WRAPEOF
    chmod 755 "$bin/df"

    # ---- 完全モック: mke2fs -------------------------------------------------
    # IMGを実サイズ (--persistence-sizeそのもの) のsparseファイルとして
    # truncateで作る (以降のxorriso生成モックがpartition 3の内容として
    # そのまま連結できるようにするため。実ext4構造は作らない)。
    cat > "$bin/mke2fs" <<'MOCKEOF'
#!/bin/sh
set -eu
if [ "${MOCK_MKE2FS_FAIL:-0}" = '1' ]; then
    echo "mock mke2fs: forced failure" >&2
    exit 1
fi
# シグナルテスト用: 実行に猶予を作り、その間にテストドライバがシグナルを
# 送出できるようにする。
if [ -n "${MOCK_MKE2FS_SLEEP_SECONDS:-}" ]; then
    sleep "$MOCK_MKE2FS_SLEEP_SECONDS"
fi
# 呼び出し形式: mke2fs -F -t ext4 -L persistence -d DIR IMG SIZE
# evalを使わず、forループで位置をずらしながら最後(SIZE)・最後から
# 2番目(IMG)を安全に取得する。
a1=''; a2=''
for arg in "$@"; do
    a2="$a1"
    a1="$arg"
done
img="$a2"
size="$a1"

# 書き込み前にsandbox内であることを検証する (SANDBOX環境変数は
# create_sandboxがexportする。未設定・空なら安全側に倒して拒否する)。
: "${SANDBOX:?mock mke2fs: SANDBOX environment variable is not set}"
case "$img" in
    "$SANDBOX"/*) ;;
    *)
        echo "mock mke2fs: write target outside sandbox: $img" >&2
        exit 99
        ;;
esac

/usr/bin/truncate -s "$size" "$img"

# 「実行中に入力が変化した」シナリオ (exit 49/50) を再現するための
# フック。この時点 (入力整合性検査は完了済み、最終再検証はまだ) で
# 指定パスへ1バイト追記する。テストが明示的に設定した場合のみ発火する。
if [ -n "${MOCK_TAMPER_TARGET_PATH:-}" ]; then
    case "$MOCK_TAMPER_TARGET_PATH" in
        "$SANDBOX"/*) ;;
        *)
            echo "mock mke2fs: MOCK_TAMPER_TARGET_PATH outside sandbox: $MOCK_TAMPER_TARGET_PATH" >&2
            exit 99
            ;;
    esac
    printf 'X' >> "$MOCK_TAMPER_TARGET_PATH"
fi

exit 0
MOCKEOF
    chmod 755 "$bin/mke2fs"

    # ---- 完全モック: e2fsck -------------------------------------------------
    # 対象パスのbasenameで pre (persistence.img) / post
    # (extracted_partition3.img) を区別する (production script自身の
    # 固定命名規則に基づく)。
    cat > "$bin/e2fsck" <<'MOCKEOF'
#!/bin/sh
set -eu
target=''
for arg in "$@"; do
    target="$arg"
done
: "${SANDBOX:?mock e2fsck: SANDBOX environment variable is not set}"
case "$target" in
    "$SANDBOX"/*) ;;
    *)
        echo "mock e2fsck: target outside sandbox: $target" >&2
        exit 99
        ;;
esac
case "$target" in
    */persistence.img)
        if [ "${MOCK_E2FSCK_FAIL_PRE:-0}" = '1' ]; then
            echo "mock e2fsck: forced failure (pre)" >&2
            exit 4
        fi
        ;;
    */extracted_partition3.img)
        if [ "${MOCK_E2FSCK_FAIL_POST:-0}" = '1' ]; then
            echo "mock e2fsck: forced failure (post)" >&2
            exit 4
        fi
        ;;
esac
echo "mock e2fsck: clean"
exit 0
MOCKEOF
    chmod 755 "$bin/e2fsck"

    # ---- 完全モック: debugfs ------------------------------------------------
    # -w (所有権/mode修正) と -R (stat/cat) の両方をサポートする。
    # stat/catの対象は最後の引数 (IMG) のbasenameでpre/postを区別する。
    cat > "$bin/debugfs" <<'MOCKEOF'
#!/bin/sh
set -eu
args=" $* "
target=''
for arg in "$@"; do
    target="$arg"
done

: "${SANDBOX:?mock debugfs: SANDBOX environment variable is not set}"
case "$target" in
    "$SANDBOX"/*) ;;
    *)
        echo "mock debugfs: target outside sandbox: $target" >&2
        exit 99
        ;;
esac

case "$args" in
    *' -w '*)
        if [ "${MOCK_DEBUGFS_FAIL_WRITE:-0}" = '1' ]; then
            echo "mock debugfs: forced failure (-w)" >&2
            exit 1
        fi
        exit 0
        ;;
    *"stat /persistence.conf"*)
        bad=0
        case "$target" in
            */persistence.img)
                [ "${MOCK_DEBUGFS_BAD_STAT_PRE:-0}" = '1' ] && bad=1
                ;;
            */extracted_partition3.img)
                [ "${MOCK_DEBUGFS_BAD_STAT_POST:-0}" = '1' ] && bad=1
                ;;
        esac
        if [ "$bad" = '1' ]; then
            cat <<'STATEOF'
Inode: 13   Type: regular    Mode:  0644   Flags: 0x80000
User:  1000   Group:  1000   Project:     0   Size: 6
STATEOF
        else
            # Size 45 = "/home\n/etc/NetworkManager/system-connections\n" の
            # 実バイト数 (build-usb-persistence-image.shのCONF_EXPECTED_CONTENT
            # と一致させること)。
            cat <<'STATEOF'
Inode: 13   Type: regular    Mode:  0600   Flags: 0x80000
User:     0   Group:     0   Project:     0   Size: 45
STATEOF
        fi
        exit 0
        ;;
    *"cat /persistence.conf"*)
        bad=0
        case "$target" in
            */persistence.img)
                [ "${MOCK_DEBUGFS_BAD_CONTENT_PRE:-0}" = '1' ] && bad=1
                ;;
            */extracted_partition3.img)
                [ "${MOCK_DEBUGFS_BAD_CONTENT_POST:-0}" = '1' ] && bad=1
                ;;
        esac
        if [ "$bad" = '1' ]; then
            printf 'wrong-content'
        else
            printf '/home\n/etc/NetworkManager/system-connections'
        fi
        exit 0
        ;;
    *)
        echo "mock debugfs: unrecognized invocation: $*" >&2
        exit 97
        ;;
esac
MOCKEOF
    chmod 755 "$bin/debugfs"

    # ---- 完全モック: xorriso -------------------------------------------------
    # 定数: 生成物のpartition 1/2レイアウト (固定、入力ISO側の合成報告と
    # 出力側の合成報告とで共通に使う値)。
    cat > "$bin/xorriso" <<'MOCKEOF'
#!/bin/sh
set -eu

PART1_BLOCKS=2000
PART2_START=540
PART2_BLOCKS=100
GPT2_TYPE_GUID='a2a0d0ebe5b9334487c068b6b72699c7'
GPT2_NAME='ISOHybrid1'
GPT3_TYPE_GUID_GOOD='af3dc60f838472478e793d69d8477de4'
GPT3_TYPE_GUID_BAD='deadbeefdeadbeefdeadbeefdeadbeef'
GPT3_NAME='Appended3'

args=" $* "

# 最後の引数、"-indev"の次の引数、GUIDトークンの次の引数、"-o"の次の
# 引数を、evalを使わずforループで安全に取得する。
last=''
indev=''
want_indev=0
persist_img=''
want_persist_img=0
dest=''
want_dest=0
for arg in "$@"; do
    if [ "$want_indev" = '1' ]; then
        indev="$arg"
        want_indev=0
    fi
    if [ "$want_persist_img" = '1' ]; then
        persist_img="$arg"
        want_persist_img=0
    fi
    if [ "$want_dest" = '1' ]; then
        dest="$arg"
        want_dest=0
    fi
    case "$arg" in
        -indev) want_indev=1 ;;
        0FC63DAF-8483-4772-8E79-3D69D8477DE4) want_persist_img=1 ;;
        -o) want_dest=1 ;;
    esac
    last="$arg"
done

print_mbr_gpt_report() {
    # print_mbr_gpt_report TOTAL_SECTORS PART3_START PART3_BLOCKS MODE
    total_sectors="$1"; part3_start="$2"; part3_blocks="$3"; mode="$4"
    part1_end=$((PART1_BLOCKS + 64))
    backup_lba=$((total_sectors - 1))
    if [ "${MOCK_XORRISO_BACKUP_LBA_WRONG:-0}" = '1' ] && [ "$mode" = 'output' ]; then
        backup_lba=$((backup_lba - 1))
    fi

    echo "System area summary: MBR isohybrid cyl-align-off GPT APM"
    echo "ISO image size/512 : $total_sectors"

    if [ "${MOCK_XORRISO_MBR_DROP:-0}" = '1' ] && [ "$mode" = 'output' ]; then
        : # partition 3行を省略 (欠落シナリオ)
    else
        echo "MBR partition      :   1   0x80  0x00           64      $PART1_BLOCKS"
        echo "MBR partition      :   2   0x00  0xef      $PART2_START      $PART2_BLOCKS"
        if [ "${MOCK_XORRISO_MBR_DUPLICATE:-0}" = '1' ] && [ "$mode" = 'output' ]; then
            echo "MBR partition      :   1   0x80  0x00           64      $PART1_BLOCKS"
        fi
        if [ -n "$part3_start" ]; then
            echo "MBR partition      :   3   0x00  0x83      $part3_start      $part3_blocks"
        fi
    fi

    echo "GPT lba range      :      64  $((total_sectors - 1))  $backup_lba"
    echo "GPT start and size :   1  64  $PART1_BLOCKS"
    gpt2_start="$PART2_START"
    gpt2_size="$PART2_BLOCKS"
    gpt2_guid="$GPT2_TYPE_GUID"
    gpt2_name="$GPT2_NAME"
    if [ "${MOCK_XORRISO_GPT2_MISMATCH:-0}" = '1' ] && [ "$mode" = 'output' ]; then
        gpt2_start=$((gpt2_start + 1))
    fi
    if [ "${MOCK_XORRISO_GPT_DUPLICATE:-0}" = '1' ] && [ "$mode" = 'output' ]; then
        echo "GPT start and size :   2  $gpt2_start  $gpt2_size"
    fi
    echo "GPT start and size :   2  $gpt2_start  $gpt2_size"
    echo "GPT type GUID      :   2  $gpt2_guid"
    echo "GPT partname local :   2  $gpt2_name"
    if [ -n "$part3_start" ] && { [ "${MOCK_XORRISO_GPT_DROP:-0}" != '1' ] || [ "$mode" != 'output' ]; }; then
        echo "GPT start and size :   3  $part3_start  $part3_blocks"
        gpt3_guid="$GPT3_TYPE_GUID_GOOD"
        if [ "${MOCK_XORRISO_GPT3_MISMATCH:-0}" = '1' ] && [ "$mode" = 'output' ]; then
            gpt3_guid="$GPT3_TYPE_GUID_BAD"
        fi
        echo "GPT type GUID      :   3  $gpt3_guid"
        echo "GPT partname local :   3  $GPT3_NAME"
    fi
}

print_el_torito_report() {
    mode="$1"
    echo "El Torito catalog  : 134  1"
    echo "El Torito boot img :   1  BIOS  y   none  0x0000  0x00      4        1799"
    if [ "${MOCK_XORRISO_EL_TORITO_MISMATCH:-0}" = '1' ] && [ "$mode" = 'output' ]; then
        echo "El Torito boot img :   2  UEFI  y   none  0x0000  0x00   9999         135"
    else
        echo "El Torito boot img :   2  UEFI  y   none  0x0000  0x00   6656         135"
    fi
    echo "El Torito img path :   1  /isolinux/isolinux.bin"
    echo "El Torito img path :   2  /boot/grub/efi.img"
}

case "$args" in
    *' -report_system_area as_mkisofs '*)
        if [ "${MOCK_XORRISO_FAIL_REPORT:-0}" = '1' ]; then
            echo "mock xorriso: forced failure (report_system_area as_mkisofs)" >&2
            exit 1
        fi
        if [ "${MOCK_XORRISO_BAD_VOLID:-0}" = '1' ]; then
            printf "%s\n" "-V 'unterminated"
        else
            printf "%s\n" "-V '${MOCK_VOLID:-MockVolume}'"
        fi
        printf "%s\n" "--modification-date='${MOCK_MODDATE:-2026010100000000}'"
        exit 0
        ;;
    *' -osirrox on '*)
        if [ "${MOCK_XORRISO_FAIL_EXTRACT:-0}" = '1' ]; then
            echo "mock xorriso: forced failure (osirrox extract)" >&2
            exit 1
        fi
        dest_extract="$last"
        : "${SANDBOX:?mock xorriso: SANDBOX environment variable is not set}"
        case "$dest_extract" in
            "$SANDBOX"/*) ;;
            *)
                echo "mock xorriso: extract destination outside sandbox: $dest_extract" >&2
                exit 99
                ;;
        esac
        n=$(($# - 1))
        i=0
        iso_rr_path=''
        for arg in "$@"; do
            i=$((i + 1))
            if [ "$i" -eq "$n" ]; then
                iso_rr_path="$arg"
            fi
        done
        case "$iso_rr_path" in
            /isolinux/isolinux.bin) printf '%s' "${MOCK_CONTENT_ISOLINUX_BIN:-}" > "$dest_extract" ;;
            /boot/grub/efi.img) printf '%s' "${MOCK_CONTENT_EFI_IMG:-mock-efi-content}" > "$dest_extract" ;;
            /live/filesystem.squashfs) printf '%s' "${MOCK_CONTENT_SQUASHFS:-mock-squashfs-content}" > "$dest_extract" ;;
            *)
                echo "mock xorriso: unexpected extract path: $iso_rr_path" >&2
                exit 97
                ;;
        esac
        exit 0
        ;;
    *' -report_system_area plain '*)
        case "$indev" in
            *fake.iso)
                [ "${MOCK_XORRISO_FAIL_REPORT_INPUT_PLAIN:-0}" = '1' ] && { echo "mock xorriso: forced failure (input plain)" >&2; exit 1; }
                total=$((64 + PART1_BLOCKS))
                print_mbr_gpt_report "$total" '' '' 'input'
                exit 0
                ;;
            */output.img)
                [ "${MOCK_XORRISO_FAIL_REPORT_OUTPUT_PLAIN:-0}" = '1' ] && { echo "mock xorriso: forced failure (output plain)" >&2; exit 1; }
                size="$(/usr/bin/stat -c '%s' -- "$indev")"
                total=$((size / 512))
                part1_end=$((64 + PART1_BLOCKS))
                part3_blocks=$((total - part1_end))
                print_mbr_gpt_report "$total" "$part1_end" "$part3_blocks" 'output'
                exit 0
                ;;
            *)
                echo "mock xorriso: unrecognized -indev for report_system_area plain: $indev" >&2
                exit 97
                ;;
        esac
        ;;
    *' -report_el_torito plain '*)
        case "$indev" in
            *fake.iso) print_el_torito_report 'input'; exit 0 ;;
            */output.img) print_el_torito_report 'output'; exit 0 ;;
            *)
                echo "mock xorriso: unrecognized -indev for report_el_torito plain: $indev" >&2
                exit 97
                ;;
        esac
        ;;
    *' -find '*)
        # 呼び出し形式: xorriso -indev output.img -find PATH
        find_path="$last"
        if [ "$find_path" = "${MOCK_XORRISO_FIND_MISSING_PATH:-}" ]; then
            echo "mock xorriso: (path not found, as designed for this test)"
            exit 0
        fi
        printf "'%s'\n" "$find_path"
        exit 0
        ;;
    *' -as mkisofs '*)
        if [ "${MOCK_XORRISO_FAIL_GENERATE:-0}" = '1' ]; then
            echo "mock xorriso: forced failure (-as mkisofs generation)" >&2
            exit 1
        fi
        if [ -z "$persist_img" ] || [ -z "$dest" ]; then
            echo "mock xorriso: could not locate persistence image or -o destination in args" >&2
            exit 97
        fi
        : "${SANDBOX:?mock xorriso: SANDBOX environment variable is not set}"
        case "$dest" in
            "$SANDBOX"/*) ;;
            *)
                echo "mock xorriso: generation destination outside sandbox: $dest" >&2
                exit 99
                ;;
        esac
        {
            /usr/bin/head -c $(((64 + PART1_BLOCKS) * 512)) /dev/zero
            if [ "${MOCK_XORRISO_PART3_CORRUPT:-0}" = '1' ]; then
                /usr/bin/head -c "$(/usr/bin/stat -c '%s' -- "$persist_img")" /dev/zero | /usr/bin/tr '\0' '\377'
            else
                /usr/bin/cat -- "$persist_img"
            fi
        } > "$dest"
        exit 0
        ;;
    *)
        echo "mock xorriso: unrecognized invocation: $*" >&2
        exit 97
        ;;
esac
MOCKEOF
    chmod 755 "$bin/xorriso"
}
