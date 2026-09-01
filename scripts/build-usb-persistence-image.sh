#!/usr/bin/env bash
#
# build-usb-persistence-image.sh - USB persistence IMG生成 (試作)
#
# MyPocketOSの通常ISO (live-image-amd64.hybrid.iso) とは別成果物として、
# 単一のGPT/MBR/APM/El Toritoハイブリッド構造に、persistence用の第3
# パーティション (ext4, LABEL=persistence、persistence.confは
# "/home" と "/etc/NetworkManager/system-connections" の2行) を
# 追加したIMGファイルを、単一のxorriso生成処理で作る。
#
# 設計方針:
# - 元ISO・binary/ソースツリーを一切変更しない (読み取り専用ソース)。
# - sudo・loop・mount・USB/block device操作は一切行わない。
# - PATHを固定する前に外部コマンドを一切実行しない (PROG_NAMEはbashの
#   パラメータ展開のみで求める)。固定後は全コマンドを絶対パス変数
#   (CMD_*) 経由でのみ呼び出す。
# - 作業ファイルは、出力先と同じディレクトリ内に作るprivate work
#   directory (mktemp -d、直後にmode 0700を検証) にのみ置く。/tmp等の
#   共有領域は使わない (同一ファイルシステム内hard linkによる公開のため、
#   および空き容量検査を出力先と同じファイルシステムに対して行うため)。
# - 最終公開は「private work directory内の固定名で生成 -> 全検証成功後に
#   同一ファイルシステム内hard link (ln、-fなし) で公開 -> 成功したら
#   work directory内のコピーを削除」の順で行う。mv/mv -f/mv -nは最終
#   公開に使わない。lnは出力先が既に存在すれば失敗するため、TOCTOU窓での
#   上書きが構造的に起こらない。
# - シグナル (INT/TERM/HUP) は、それぞれ専用のtrapハンドラで検出し、
#   後始末を行ったうえで129/130/143の固定終了コードでexitする。各
#   ハンドラは開始直後に全trapを解除し (再入防止)、EXIT trapとの二重
#   実行を避ける。
# - xorrisoのreport出力 (-report_system_area / -report_el_torito) は
#   evalせず、固定書式を前提としたgrep/awk/sedによる抽出のみで扱う。
#   該当行が0件・複数件・grep自体の異常のいずれであっても、無言の
#   set -e終了ではなく、文書化した終了コードと明確なstderrになるように
#   全ての抽出をエラーハンドリングする。
# - 引数は --iso / --binary-dir / --persistence-size / --output の4個を
#   全て必須とし、既定値は設けない。
#
# 終了コード:
#   0   成功
#   2   引数エラー (未知フラグ・重複指定・不足)
#   10  必須コマンド欠落
#   11  --iso が不正 (存在しない・通常ファイルでない・symlink)
#   12  --binary-dir が不正 (自身、または必須3ファイルのいずれか)
#   13  --output が既に存在する (symlink含む)
#   14  --output が配置不可 (親ディレクトリ欠落・書込み不可)
#   15  入力パス同士の同一性衝突 (--iso/--binary-dir/--output)
#   16  --persistence-size の形式が不正
#   17  --persistence-size が最小値 (256M) 未満
#   18  合計サイズが上限 (8,000,000,000 bytes) を超過
#   19  出力先ファイルシステムの空き容量不足
#   20  MBRテンプレート抽出失敗、または抽出前後で入力ISOのSHA-256不一致
#   21  入力整合性 (isolinux.bin/efi.img/filesystem.squashfs) 不一致
#   22  volid/modification-date の取得・allowlist検証失敗
#   30  persistence.img作成 (mke2fs) 失敗
#   31  persistence.img所有権/mode修正 (debugfs -w) 失敗
#   32  persistence.img事前検証 (e2fsck -fn または inode/content) 失敗
#   40  xorriso生成失敗
#   41  MBR検証失敗 (件数不一致・重複・欠落・想定外の値を含む)
#   42  GPT検証失敗 (件数不一致・重複・欠落・想定外の値を含む)
#   43  GPT backup header位置、または出力ファイルサイズの512倍数性の検証失敗
#   44  El Torito検証失敗
#   45  ISO9660読み取り検証失敗
#   46  partition 3抽出/cmp検証失敗
#   47  抽出物のe2fsck検証失敗
#   48  抽出persistence.conf検証失敗
#   49  実行中の入力ISO SHA-256変化検出
#   50  実行中のbinary/主要3ファイルSHA-256変化検出
#   60  最終公開 (hard link作成) 失敗 (出力先が既に存在する場合を含む)
#   70  未分類の内部エラー
#   129 HUPによる中断
#   130 INTによる中断
#   143 TERMによる中断
#
set -euo pipefail

# PATHを固定する前に外部コマンドを一切実行しない (basename等の外部
# コマンドではなく、bashのパラメータ展開のみでPROG_NAMEを求める)。
PROG_NAME="${BASH_SOURCE[0]##*/}"

# ---- 固定PATH + 使用する全コマンドの絶対パス ------------------------------
PATH='/usr/sbin:/usr/bin:/sbin:/bin'
export PATH

CMD_XORRISO=/usr/bin/xorriso
CMD_MKE2FS=/usr/sbin/mke2fs
CMD_E2FSCK=/usr/sbin/e2fsck
CMD_DEBUGFS=/usr/sbin/debugfs
CMD_SHA256SUM=/usr/bin/sha256sum
CMD_STAT=/usr/bin/stat
CMD_DD=/usr/bin/dd
CMD_CMP=/usr/bin/cmp
CMD_DIFF=/usr/bin/diff
CMD_MKTEMP=/usr/bin/mktemp
CMD_MKDIR=/usr/bin/mkdir
CMD_RM=/usr/bin/rm
CMD_LN=/usr/bin/ln
CMD_CAT=/usr/bin/cat
CMD_DF=/usr/bin/df
CMD_GREP=/usr/bin/grep
CMD_SED=/usr/bin/sed
CMD_AWK=/usr/bin/awk
CMD_REALPATH=/usr/bin/realpath
CMD_DIRNAME=/usr/bin/dirname

fail() {
    code="$1"
    shift
    printf '%s: %s\n' "$PROG_NAME" "$*" >&2
    exit "$code"
}

usage() {
    "$CMD_CAT" >&2 <<EOF
usage: $PROG_NAME --iso PATH --binary-dir PATH --persistence-size SIZE --output PATH

全引数必須、既定値はありません。
  --iso PATH               入力ISO (live-image-amd64.hybrid.iso等)
  --binary-dir PATH        live-buildが組み立てたbinary/ツリー
  --persistence-size SIZE  例: 256M / 2G (最小256M、K/M/G以外は不可)
  --output PATH            出力先 (既に存在してはならない)
EOF
    exit 2
}

check_required_commands() {
    for c in \
        "$CMD_XORRISO" "$CMD_MKE2FS" "$CMD_E2FSCK" "$CMD_DEBUGFS" \
        "$CMD_SHA256SUM" "$CMD_STAT" "$CMD_DD" "$CMD_CMP" "$CMD_DIFF" \
        "$CMD_MKTEMP" "$CMD_MKDIR" "$CMD_RM" "$CMD_LN" "$CMD_CAT" "$CMD_DF" \
        "$CMD_GREP" "$CMD_SED" "$CMD_AWK" "$CMD_REALPATH" "$CMD_DIRNAME"
    do
        [ -x "$c" ] || fail 10 "必要なコマンドが見つからないか実行できません: $c"
    done
}

# ---- 加算によるオーバーフローで上限検査を回避されないための減算比較 --------
# fits_within CAP TERM...
# 「TERMの合計 <= CAP」を、TERMを加算してからCAPと比較するのではなく、
# CAPから毎回減算しながら判定する。TERMの合計がbash算術のオーバーフロー
# 上限に達するような極端な値であっても、判定結果が誤って「収まる」側へ
# ひっくり返ることがない。
fits_within() {
    cap="$1"; shift
    remaining="$cap"
    for term in "$@"; do
        if [ "$term" -gt "$remaining" ]; then
            return 1
        fi
        remaining=$((remaining - term))
    done
    return 0
}

# ---- 引数解析 ---------------------------------------------------------------
ISO_ARG=''
BINARY_DIR_ARG=''
PERSISTENCE_SIZE_ARG=''
OUTPUT_ARG=''

while [ $# -gt 0 ]; do
    case "$1" in
        --iso)
            [ $# -ge 2 ] || usage
            [ -z "$ISO_ARG" ] || usage
            ISO_ARG="$2"
            shift 2
            ;;
        --binary-dir)
            [ $# -ge 2 ] || usage
            [ -z "$BINARY_DIR_ARG" ] || usage
            BINARY_DIR_ARG="$2"
            shift 2
            ;;
        --persistence-size)
            [ $# -ge 2 ] || usage
            [ -z "$PERSISTENCE_SIZE_ARG" ] || usage
            PERSISTENCE_SIZE_ARG="$2"
            shift 2
            ;;
        --output)
            [ $# -ge 2 ] || usage
            [ -z "$OUTPUT_ARG" ] || usage
            OUTPUT_ARG="$2"
            shift 2
            ;;
        *)
            usage
            ;;
    esac
done

[ -n "$ISO_ARG" ] || usage
[ -n "$BINARY_DIR_ARG" ] || usage
[ -n "$PERSISTENCE_SIZE_ARG" ] || usage
[ -n "$OUTPUT_ARG" ] || usage

check_required_commands

# ---- --iso の検証 -----------------------------------------------------------
[ -L "$ISO_ARG" ] && fail 11 "--iso はシンボリックリンクのため使用できません: $ISO_ARG"
[ -e "$ISO_ARG" ] || fail 11 "--iso が存在しません: $ISO_ARG"
[ -f "$ISO_ARG" ] || fail 11 "--iso は通常ファイルではありません: $ISO_ARG"
ISO_ABS="$("$CMD_REALPATH" -e -- "$ISO_ARG")" || fail 11 "--iso の絶対パス解決に失敗しました: $ISO_ARG"

# ---- --binary-dir の検証 -----------------------------------------------------
[ -L "$BINARY_DIR_ARG" ] && fail 12 "--binary-dir はシンボリックリンクのため使用できません: $BINARY_DIR_ARG"
[ -d "$BINARY_DIR_ARG" ] || fail 12 "--binary-dir がディレクトリとして存在しません: $BINARY_DIR_ARG"
BINARY_DIR_ABS="$("$CMD_REALPATH" -e -- "$BINARY_DIR_ARG")" || fail 12 "--binary-dir の絶対パス解決に失敗しました: $BINARY_DIR_ARG"

BIN_ISOLINUX_BIN="$BINARY_DIR_ABS/isolinux/isolinux.bin"
BIN_EFI_IMG="$BINARY_DIR_ABS/boot/grub/efi.img"
BIN_SQUASHFS="$BINARY_DIR_ABS/live/filesystem.squashfs"

for f in "$BIN_ISOLINUX_BIN" "$BIN_EFI_IMG" "$BIN_SQUASHFS"; do
    [ -L "$f" ] && fail 12 "--binary-dir 配下の必須ファイルがシンボリックリンクです: $f"
    [ -f "$f" ] || fail 12 "--binary-dir 配下の必須ファイルが見つかりません: $f"
done

# ---- --output の検証 (存在すれば即拒否。symlink含む) ------------------------
[ -L "$OUTPUT_ARG" ] && fail 13 "--output は既にシンボリックリンクとして存在します: $OUTPUT_ARG"
[ -e "$OUTPUT_ARG" ] && fail 13 "--output は既に存在します: $OUTPUT_ARG"

OUTPUT_DIRNAME="$("$CMD_DIRNAME" -- "$OUTPUT_ARG")"
[ -d "$OUTPUT_DIRNAME" ] || fail 14 "--output の親ディレクトリが存在しません: $OUTPUT_DIRNAME"
[ -w "$OUTPUT_DIRNAME" ] || fail 14 "--output の親ディレクトリに書き込めません: $OUTPUT_DIRNAME"
OUTPUT_DIRNAME_ABS="$("$CMD_REALPATH" -e -- "$OUTPUT_DIRNAME")" || fail 14 "--output の親ディレクトリの絶対パス解決に失敗しました: $OUTPUT_DIRNAME"
OUTPUT_BASENAME="${OUTPUT_ARG##*/}"
[ -n "$OUTPUT_BASENAME" ] || fail 14 "--output のファイル名部分が空です: $OUTPUT_ARG"
OUTPUT_ABS="$OUTPUT_DIRNAME_ABS/$OUTPUT_BASENAME"

# ---- 入力パス同士の同一性検査 ------------------------------------------------
[ "$ISO_ABS" != "$OUTPUT_ABS" ] || fail 15 "--iso と --output が同一パスです: $ISO_ABS"
[ "$BINARY_DIR_ABS" != "$OUTPUT_ABS" ] || fail 15 "--binary-dir と --output が同一パスです: $BINARY_DIR_ABS"
case "$OUTPUT_ABS" in
    "$BINARY_DIR_ABS"/*)
        fail 15 "--output が --binary-dir の内側を指しています: $OUTPUT_ABS"
        ;;
esac
[ "$ISO_ABS" != "$BINARY_DIR_ABS" ] || fail 15 "--iso と --binary-dir が同一パスです: $ISO_ABS"

# ---- --persistence-size の検証 (allowlist正規表現、最小256M) ---------------
case "$PERSISTENCE_SIZE_ARG" in
    [1-9][0-9][0-9][0-9][0-9][0-9]M | [1-9][0-9][0-9][0-9][0-9]M | \
    [1-9][0-9][0-9][0-9]M | [1-9][0-9][0-9]M | [1-9][0-9]M | [1-9]M | \
    [1-9][0-9][0-9][0-9][0-9][0-9]G | [1-9][0-9][0-9][0-9][0-9]G | \
    [1-9][0-9][0-9][0-9]G | [1-9][0-9][0-9]G | [1-9][0-9]G | [1-9]G)
        ;;
    *)
        fail 16 "--persistence-size の形式が不正です (許可形式: 1〜999999 に続けてMまたはG): $PERSISTENCE_SIZE_ARG"
        ;;
esac
SIZE_UNIT="${PERSISTENCE_SIZE_ARG: -1}"
SIZE_NUM="${PERSISTENCE_SIZE_ARG%[MG]}"
case "$SIZE_UNIT" in
    M) PERSISTENCE_SIZE_BYTES=$((SIZE_NUM * 1024 * 1024)) ;;
    G) PERSISTENCE_SIZE_BYTES=$((SIZE_NUM * 1024 * 1024 * 1024)) ;;
    *) fail 70 "内部エラー: --persistence-size の単位解析に失敗しました: $PERSISTENCE_SIZE_ARG" ;;
esac

MIN_PERSISTENCE_SIZE_BYTES=$((256 * 1024 * 1024))
[ "$PERSISTENCE_SIZE_BYTES" -ge "$MIN_PERSISTENCE_SIZE_BYTES" ] \
    || fail 17 "--persistence-size が最小値 256M 未満です: $PERSISTENCE_SIZE_ARG"

# ---- 合計サイズ上限の検証 (xorriso実行前に拒否) ------------------------------
# 安全余白: シリンダ整列パディング等、xorrisoが追加しうる端数分の余裕
# (実測では最大でも数百KiB程度のため、8MiBあれば十分な余裕がある)。
CAP_SAFETY_MARGIN_BYTES=$((8 * 1024 * 1024))
CAP_BYTES=8000000000

ISO_SIZE_BYTES="$("$CMD_STAT" -c '%s' -- "$ISO_ABS")"
BIN_SQUASHFS_SIZE_BYTES="$("$CMD_STAT" -c '%s' -- "$BIN_SQUASHFS")"

fits_within "$CAP_BYTES" "$ISO_SIZE_BYTES" "$PERSISTENCE_SIZE_BYTES" "$CAP_SAFETY_MARGIN_BYTES" \
    || fail 18 "推定合計サイズが上限 ($CAP_BYTES bytes) を超えています (ISO: $ISO_SIZE_BYTES + persistence: $PERSISTENCE_SIZE_BYTES + 余白: $CAP_SAFETY_MARGIN_BYTES)"

# ---- private work directory (出力先と同一ディレクトリ・同一ファイルシステム) --
# 最終出力は、ここで作るwork directory内に固定名で生成し、全検証成功後に
# 同一ファイルシステム内hard linkで公開する。work directoryそのものが
# mktemp -dによる非公開・排他的な領域であるため、内部のファイル名は
# 固定名で構わない (それ自体で衝突しない)。
WORKROOT=''
TMP_OUTPUT=''

cleanup_workdir() {
    # 実際の後始末処理。複数回呼ばれても安全 (冪等)。WORKROOT配下を
    # rm -rfで丸ごと削除するため、TMP_OUTPUTが通常ファイルであっても
    # symlinkであっても (rm -rfはdirectory entryの種別を問わず削除する
    # ため) 特別扱いなしに除去される。OUTPUT_ABSはWORKROOTの外側
    # (親ディレクトリ) にあり、公開 (ln) 後も含め、cleanupが
    # OUTPUT_ABSに触れることは構造上あり得ない。
    if [ -n "$WORKROOT" ] && [ -d "$WORKROOT" ]; then
        "$CMD_RM" -rf -- "$WORKROOT" 2>/dev/null || :
    fi
}

on_exit() {
    ec=$?
    trap - EXIT INT TERM HUP
    cleanup_workdir
    exit "$ec"
}
on_int() {
    trap - EXIT INT TERM HUP
    cleanup_workdir
    exit 130
}
on_term() {
    trap - EXIT INT TERM HUP
    cleanup_workdir
    exit 143
}
on_hup() {
    trap - EXIT INT TERM HUP
    cleanup_workdir
    exit 129
}
trap on_exit EXIT
trap on_int INT
trap on_term TERM
trap on_hup HUP

WORKROOT="$("$CMD_MKTEMP" -d "$OUTPUT_DIRNAME_ABS/.${OUTPUT_BASENAME}.work.XXXXXXXX")" \
    || fail 70 "private work directoryの作成に失敗しました: $OUTPUT_DIRNAME_ABS"

WORKROOT_MODE="$("$CMD_STAT" -c '%a' -- "$WORKROOT")"
[ "$WORKROOT_MODE" = '700' ] \
    || fail 70 "private work directoryのmodeが0700ではありません (実際: $WORKROOT_MODE): $WORKROOT"

TMP_OUTPUT="$WORKROOT/output.img"

echo "== 入力 =="
echo "ISO         : $ISO_ABS"
echo "binary/     : $BINARY_DIR_ABS"
echo "サイズ指定  : $PERSISTENCE_SIZE_ARG ($PERSISTENCE_SIZE_BYTES bytes)"
echo "出力先      : $OUTPUT_ABS"
echo "work dir    : $WORKROOT (mode $WORKROOT_MODE)"
echo

# ---- 出力先ファイルシステムの空き容量検査 ------------------------------------
# 保守的に、以下すべてが同時に出力先ディレクトリのファイルシステム上に
# 存在しうる最大の状態を想定する:
#   - 生成途中の最終IMG (TMP_OUTPUT、概ねISO_SIZE_BYTES + persistence分)
#   - persistence.img (PERSISTENCE_SIZE_BYTES)
#   - 検証用に抽出するpartition 3のコピー (PERSISTENCE_SIZE_BYTES)
#   - 入力整合性検査でISOから一時抽出するfilesystem.squashfs
#     (BIN_SQUASHFS_SIZE_BYTES、抽出後は都度削除するが、保守的に
#     常時存在しうるものとして見積もる)
#   - 安全余白
DISK_SPACE_SAFETY_MARGIN_BYTES=$((16 * 1024 * 1024))
REQUIRED_BYTES_LIST=(
    "$ISO_SIZE_BYTES"
    "$PERSISTENCE_SIZE_BYTES"
    "$PERSISTENCE_SIZE_BYTES"
    "$PERSISTENCE_SIZE_BYTES"
    "$BIN_SQUASHFS_SIZE_BYTES"
    "$DISK_SPACE_SAFETY_MARGIN_BYTES"
)

DF_LINE="$("$CMD_DF" -P -B1 -- "$OUTPUT_DIRNAME_ABS" | "$CMD_AWK" 'NR==2')" \
    || fail 19 "出力先ファイルシステムの空き容量取得 (df) に失敗しました: $OUTPUT_DIRNAME_ABS"
[ -n "$DF_LINE" ] || fail 19 "出力先ファイルシステムの空き容量取得 (df) の出力が空でした: $OUTPUT_DIRNAME_ABS"
AVAILABLE_BYTES="$(printf '%s\n' "$DF_LINE" | "$CMD_AWK" '{print $4}')"
case "$AVAILABLE_BYTES" in
    '' | *[!0-9]*)
        fail 19 "dfの空き容量値が数値ではありません: ${AVAILABLE_BYTES:-(空)}"
        ;;
esac

fits_within "$AVAILABLE_BYTES" "${REQUIRED_BYTES_LIST[@]}" \
    || fail 19 "出力先ファイルシステムの空き容量が不足しています (空き: $AVAILABLE_BYTES bytes, 必要見積: $(IFS=+; echo "${REQUIRED_BYTES_LIST[*]}") bytes)"

echo "== 空き容量検査 =="
echo "出力先ファイルシステムの空き: $AVAILABLE_BYTES bytes"
echo "必要見積 (保守的): $(IFS=+; echo "${REQUIRED_BYTES_LIST[*]}") bytes 以内であることを確認"
echo

# ---- 入力ISO・binary/主要3ファイルのSHA-256基準値を記録 ---------------------
ISO_SHA_BASELINE="$("$CMD_SHA256SUM" -- "$ISO_ABS" | "$CMD_AWK" '{print $1}')"
BIN_EFI_IMG_SHA_BASELINE="$("$CMD_SHA256SUM" -- "$BIN_EFI_IMG" | "$CMD_AWK" '{print $1}')"
BIN_SQUASHFS_SHA_BASELINE="$("$CMD_SHA256SUM" -- "$BIN_SQUASHFS" | "$CMD_AWK" '{print $1}')"
BIN_ISOLINUX_BIN_SHA_BASELINE="$("$CMD_SHA256SUM" -- "$BIN_ISOLINUX_BIN" | "$CMD_AWK" '{print $1}')"

echo "== 基準SHA-256 =="
echo "ISO                    : $ISO_SHA_BASELINE"
echo "binary/isolinux/isolinux.bin : $BIN_ISOLINUX_BIN_SHA_BASELINE (boot-info-table差分により後続比較では非対象)"
echo "binary/boot/grub/efi.img     : $BIN_EFI_IMG_SHA_BASELINE"
echo "binary/live/filesystem.squashfs : $BIN_SQUASHFS_SHA_BASELINE"
echo

# ---- 入力ISOのsystem area / El Torito報告 (検証の基準値として保存) ---------
INPUT_SYSTEM_AREA="$WORKROOT/input_system_area.stdout"
"$CMD_XORRISO" -indev "$ISO_ABS" -report_system_area plain \
    > "$INPUT_SYSTEM_AREA" 2> "$WORKROOT/input_system_area.stderr" \
    || fail 22 "入力ISOのsystem area報告取得に失敗しました"

INPUT_EL_TORITO="$WORKROOT/input_el_torito.stdout"
"$CMD_XORRISO" -indev "$ISO_ABS" -report_el_torito plain \
    > "$INPUT_EL_TORITO" 2> "$WORKROOT/input_el_torito.stderr" \
    || fail 44 "入力ISOのEl Torito報告取得に失敗しました"

# ---- MBRテンプレート (入力ISO先頭432バイト) の抽出 --------------------------
ISOHDPFX="$WORKROOT/isohdpfx_extracted.bin"
"$CMD_DD" if="$ISO_ABS" of="$ISOHDPFX" bs=432 count=1 status=none \
    || fail 20 "入力ISO先頭432バイトの抽出に失敗しました"

ISO_SHA_AFTER_EXTRACT="$("$CMD_SHA256SUM" -- "$ISO_ABS" | "$CMD_AWK" '{print $1}')"
[ "$ISO_SHA_AFTER_EXTRACT" = "$ISO_SHA_BASELINE" ] \
    || fail 20 "MBRテンプレート抽出前後で入力ISOのSHA-256が変化しました"

echo "== MBRテンプレート抽出 =="
echo "抽出元: 入力ISO先頭432バイト -> $ISOHDPFX"
echo "抽出前後の入力ISO SHA-256: 不変を確認 ($ISO_SHA_BASELINE)"
echo

# ---- 入力整合性検査 (ISO内 vs binary/) --------------------------------------
extract_from_iso() {
    # extract_from_iso ISO_RR_PATH DISK_PATH
    "$CMD_XORRISO" -indev "$ISO_ABS" -osirrox on -extract "$1" "$2" \
        > "$WORKROOT/xorriso_extract.stdout" 2> "$WORKROOT/xorriso_extract.stderr"
}

echo "== 入力整合性検査 (ISO内 vs binary/) =="

# isolinux.bin: -boot-info-table によりbytes 8-63のみ書き換えられる仕様
# (xorriso 1.5.6 man -boot_image ... boot_info_table=on を参照)。
# 1) サイズ完全一致 2) bytes 0-7完全一致 3) bytes 8-63は差分許容
# 4) bytes 64-EOF完全一致、の4条件で判定する。SHA-256は記録のみ行う。
ISOLINUX_FROM_ISO="$WORKROOT/isolinux.bin.from_iso"
extract_from_iso /isolinux/isolinux.bin "$ISOLINUX_FROM_ISO" \
    || fail 21 "ISO内isolinux/isolinux.binの抽出に失敗しました"

ISOLINUX_FROM_ISO_SHA="$("$CMD_SHA256SUM" -- "$ISOLINUX_FROM_ISO" | "$CMD_AWK" '{print $1}')"
echo "isolinux.bin SHA-256 (ISO側)     : $ISOLINUX_FROM_ISO_SHA"
echo "isolinux.bin SHA-256 (binary/側) : $BIN_ISOLINUX_BIN_SHA_BASELINE"
echo "  (boot-info-table領域の差分により、上記2値は一致しないのが正常)"

SIZE_ISO_ISOLINUX="$("$CMD_STAT" -c '%s' -- "$ISOLINUX_FROM_ISO")"
SIZE_BIN_ISOLINUX="$("$CMD_STAT" -c '%s' -- "$BIN_ISOLINUX_BIN")"
[ "$SIZE_ISO_ISOLINUX" = "$SIZE_BIN_ISOLINUX" ] \
    || fail 21 "isolinux.binのサイズが一致しません (ISO側: $SIZE_ISO_ISOLINUX, binary/側: $SIZE_BIN_ISOLINUX)"

"$CMD_CMP" -n 8 -- "$ISOLINUX_FROM_ISO" "$BIN_ISOLINUX_BIN" \
    || fail 21 "isolinux.binのbytes 0-7が一致しません"

"$CMD_CMP" -i 64:64 -- "$ISOLINUX_FROM_ISO" "$BIN_ISOLINUX_BIN" \
    || fail 21 "isolinux.binのbytes 64-EOFが一致しません"

echo "isolinux.bin: サイズ一致・bytes 0-7一致・bytes 64-EOF一致を確認 (bytes 8-63は差分許容)"
"$CMD_RM" -f -- "$ISOLINUX_FROM_ISO"

# efi.img: 全体SHA-256完全一致必須
EFI_IMG_FROM_ISO="$WORKROOT/efi.img.from_iso"
extract_from_iso /boot/grub/efi.img "$EFI_IMG_FROM_ISO" \
    || fail 21 "ISO内boot/grub/efi.imgの抽出に失敗しました"
EFI_IMG_FROM_ISO_SHA="$("$CMD_SHA256SUM" -- "$EFI_IMG_FROM_ISO" | "$CMD_AWK" '{print $1}')"
[ "$EFI_IMG_FROM_ISO_SHA" = "$BIN_EFI_IMG_SHA_BASELINE" ] \
    || fail 21 "efi.imgのSHA-256が一致しません (ISO側: $EFI_IMG_FROM_ISO_SHA, binary/側: $BIN_EFI_IMG_SHA_BASELINE)"
echo "efi.img SHA-256: 完全一致を確認 ($EFI_IMG_FROM_ISO_SHA)"
"$CMD_RM" -f -- "$EFI_IMG_FROM_ISO"

# filesystem.squashfs: 全体SHA-256完全一致必須 (大容量のため抽出後即削除)
SQUASHFS_FROM_ISO="$WORKROOT/filesystem.squashfs.from_iso"
extract_from_iso /live/filesystem.squashfs "$SQUASHFS_FROM_ISO" \
    || fail 21 "ISO内live/filesystem.squashfsの抽出に失敗しました"
SQUASHFS_FROM_ISO_SHA="$("$CMD_SHA256SUM" -- "$SQUASHFS_FROM_ISO" | "$CMD_AWK" '{print $1}')"
[ "$SQUASHFS_FROM_ISO_SHA" = "$BIN_SQUASHFS_SHA_BASELINE" ] \
    || fail 21 "filesystem.squashfsのSHA-256が一致しません (ISO側: $SQUASHFS_FROM_ISO_SHA, binary/側: $BIN_SQUASHFS_SHA_BASELINE)"
echo "filesystem.squashfs SHA-256: 完全一致を確認 ($SQUASHFS_FROM_ISO_SHA)"
"$CMD_RM" -f -- "$SQUASHFS_FROM_ISO"
echo

# ---- volid / modification-date の取得 (allowlist方式、evalしない) ----------
REPORT_AS_MKISOFS="$WORKROOT/report_as_mkisofs.stdout"
"$CMD_XORRISO" -indev "$ISO_ABS" -report_system_area as_mkisofs \
    > "$REPORT_AS_MKISOFS" 2> "$WORKROOT/report_as_mkisofs.stderr" \
    || fail 22 "入力ISOのreport_system_area (as_mkisofs) 取得に失敗しました"

VOLID_LINE="$("$CMD_GREP" -m1 -E "^-V '" -- "$REPORT_AS_MKISOFS")" \
    || fail 22 "report出力に -V 行が見つかりません"
VOLID="$(printf '%s\n' "$VOLID_LINE" | "$CMD_SED" -nE "s/^-V '([^']*)'\$/\1/p")"
[ -n "$VOLID" ] || fail 22 "-V 行の解析に失敗しました (埋め込み引用符等の可能性): $VOLID_LINE"
printf '%s' "$VOLID" | LC_ALL=C "$CMD_GREP" -qE '^[[:print:]]{1,80}$' \
    || fail 22 "volidがallowlist (印字可能ASCII、最大80文字) の範囲外です"

MODDATE_LINE="$("$CMD_GREP" -m1 -E '^--modification-date=' -- "$REPORT_AS_MKISOFS")" \
    || fail 22 "report出力に --modification-date 行が見つかりません"
MODDATE="$(printf '%s\n' "$MODDATE_LINE" | "$CMD_SED" -nE "s/^--modification-date='([^']*)'\$/\1/p")"
printf '%s' "$MODDATE" | LC_ALL=C "$CMD_GREP" -qE '^[0-9]{16}$' \
    || fail 22 "modification-dateがallowlist (16桁の10進数) の範囲外です: $MODDATE_LINE"

echo "== volid/modification-date (allowlist検証済み) =="
echo "volid              : $VOLID"
echo "modification-date  : $MODDATE"
echo

# ---- persistence.img生成 ----------------------------------------------------
echo "== persistence.img生成 =="
PERSIST_POPULATE_DIR="$WORKROOT/persist_populate"
"$CMD_MKDIR" -p -- "$PERSIST_POPULATE_DIR"
# live-bootのpersistence.conf標準構文に従い、オプションなし (デフォルト
# bindマウント) の2行で、/home (ユーザーデータ) と
# /etc/NetworkManager/system-connections (Wi-Fi等の接続プロファイル) を
# 独立したcustom mountとして永続化する。union/link等の他オプションは
# 使用しない。mypocketos-persistence-setup-helperのfinalize_persistence_filesystem
# と内容を完全一致させること (AGENTS.md 14節)。
CONF_EXPECTED_CONTENT='/home
/etc/NetworkManager/system-connections'
printf '%s\n' "$CONF_EXPECTED_CONTENT" > "$PERSIST_POPULATE_DIR/persistence.conf"

PERSISTENCE_IMG="$WORKROOT/persistence.img"
"$CMD_MKE2FS" -F -t ext4 -L persistence -d "$PERSIST_POPULATE_DIR" \
    "$PERSISTENCE_IMG" "$PERSISTENCE_SIZE_ARG" \
    > "$WORKROOT/mke2fs.stdout" 2> "$WORKROOT/mke2fs.stderr" \
    || fail 30 "persistence.imgの作成 (mke2fs) に失敗しました (詳細: $WORKROOT/mke2fs.stderr)"

echo "mke2fs: 成功 ($PERSISTENCE_IMG, $PERSISTENCE_SIZE_ARG)"

DEBUGFS_FIX_CMDS="$WORKROOT/debugfs_fix_persistence.commands"
"$CMD_CAT" > "$DEBUGFS_FIX_CMDS" <<'EOF'
set_inode_field /persistence.conf uid 0
set_inode_field /persistence.conf gid 0
set_inode_field /persistence.conf mode 0100600
EOF

"$CMD_DEBUGFS" -w -f "$DEBUGFS_FIX_CMDS" -- "$PERSISTENCE_IMG" \
    > "$WORKROOT/debugfs_fix.stdout" 2> "$WORKROOT/debugfs_fix.stderr" \
    || fail 31 "persistence.imgの所有権/mode修正 (debugfs -w) に失敗しました (詳細: $WORKROOT/debugfs_fix.stderr)"

echo "debugfs -w: persistence.confをuid=0/gid=0/mode=0100600へ修正"

# e2fsck -fn の終了コード: 0=clean以外は全て検証失敗として扱う
set +e
"$CMD_E2FSCK" -fn -- "$PERSISTENCE_IMG" \
    > "$WORKROOT/e2fsck_pre.stdout" 2> "$WORKROOT/e2fsck_pre.stderr"
E2FSCK_PRE_RC=$?
set -e
[ "$E2FSCK_PRE_RC" -eq 0 ] \
    || fail 32 "persistence.imgのe2fsck -fnが異常を報告しました (exit=$E2FSCK_PRE_RC、詳細: $WORKROOT/e2fsck_pre.stdout)"
echo "e2fsck -fn: 異常なし"

# inode/content検証 (debugfs stat / cat、fail-closedな厳密パース)
verify_persistence_conf() {
    # verify_persistence_conf IMG_PATH
    img="$1"
    stat_out="$("$CMD_DEBUGFS" -R 'stat /persistence.conf' -- "$img" 2>/dev/null)"

    stat_type="$(printf '%s\n' "$stat_out" | "$CMD_SED" -nE 's/^Inode:[[:space:]]+[0-9]+[[:space:]]+Type:[[:space:]]+([a-z]+).*/\1/p')"
    stat_mode="$(printf '%s\n' "$stat_out" | "$CMD_SED" -nE 's/^Inode:.*Mode:[[:space:]]+([0-7]+).*/\1/p')"
    stat_user="$(printf '%s\n' "$stat_out" | "$CMD_SED" -nE 's/^User:[[:space:]]+([0-9]+)[[:space:]]+Group:.*/\1/p')"
    stat_group="$(printf '%s\n' "$stat_out" | "$CMD_SED" -nE 's/^User:.*Group:[[:space:]]+([0-9]+).*/\1/p')"
    stat_size="$(printf '%s\n' "$stat_out" | "$CMD_SED" -nE 's/^User:.*Size:[[:space:]]+([0-9]+)[[:space:]]*$/\1/p')"

    # 期待バイト数は決め打ちにせず、実際に書き込んだ内容
    # (CONF_EXPECTED_CONTENT) の文字数+末尾改行1個からその場で算出する
    # (2026-09-01時点でこの内容は45バイトになる)。
    conf_expected_size=$((${#CONF_EXPECTED_CONTENT} + 1))

    [ "$stat_type" = 'regular' ] || return 1
    [ "$stat_mode" = '0600' ] || return 1
    [ "$stat_user" = '0' ] || return 1
    [ "$stat_group" = '0' ] || return 1
    [ "$stat_size" = "$conf_expected_size" ] || return 1

    content="$("$CMD_DEBUGFS" -R 'cat /persistence.conf' -- "$img" 2>/dev/null)"
    [ "$content" = "$CONF_EXPECTED_CONTENT" ] || return 1

    return 0
}

verify_persistence_conf "$PERSISTENCE_IMG" \
    || fail 32 "persistence.img内persistence.confのinode/content検証に失敗しました"
echo "persistence.conf: UID=0 GID=0 Mode=0600 Size=${conf_expected_size} 内容=/home,/etc/NetworkManager/system-connections を確認"
echo

# ---- xorriso単一生成 ---------------------------------------------------------
echo "== xorriso単一生成 =="

"$CMD_XORRISO" -as mkisofs \
    -R -r -J -joliet-long -l -cache-inodes -iso-level 3 \
    -V "$VOLID" \
    --modification-date="$MODDATE" \
    -isohybrid-mbr "$ISOHDPFX" -partition_offset 16 \
    -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table \
    -eltorito-alt-boot \
    -e boot/grub/efi.img -no-emul-boot -isohybrid-gpt-basdat -isohybrid-apm-hfsplus \
    -append_partition 3 0FC63DAF-8483-4772-8E79-3D69D8477DE4 "$PERSISTENCE_IMG" \
    -o "$TMP_OUTPUT" \
    "$BINARY_DIR_ABS" \
    > "$WORKROOT/xorriso_build.stdout" 2> "$WORKROOT/xorriso_build.stderr" \
    || fail 40 "xorriso生成に失敗しました (詳細: $WORKROOT/xorriso_build.stderr)"

[ -f "$TMP_OUTPUT" ] || fail 40 "xorrisoはexit 0でしたが出力ファイルが見つかりません: $TMP_OUTPUT"
echo "xorriso: 成功 (exit 0) -> $TMP_OUTPUT"
echo

# ---- 生成後自動検証 ----------------------------------------------------------
echo "== 生成後自動検証 =="

POST_SYSTEM_AREA="$WORKROOT/post_system_area.stdout"
"$CMD_XORRISO" -indev "$TMP_OUTPUT" -report_system_area plain \
    > "$POST_SYSTEM_AREA" 2> "$WORKROOT/post_system_area.stderr" \
    || fail 41 "生成物のsystem area報告取得に失敗しました"

POST_EL_TORITO="$WORKROOT/post_el_torito.stdout"
"$CMD_XORRISO" -indev "$TMP_OUTPUT" -report_el_torito plain \
    > "$POST_EL_TORITO" 2> "$WORKROOT/post_el_torito.stderr" \
    || fail 44 "生成物のEl Torito報告取得に失敗しました"

# --- 行抽出ヘルパー: 該当行が0件・複数件・grep自体の異常のいずれでも、
#     無言のset -e終了ではなく、呼び出し側で文書化した終了コードへ
#     倒せるよう、戻り値のみで結果を伝える (fail/exitはここでは呼ばない。
#     command substitution経由で呼ばれるため、内部でexitしても親スクリプト
#     には伝播しない = 呼び出し側の外側でfail()すること) ----------------------
# 戻り値: 0=成功 (ちょうど1行、標準出力に返す)  1=該当行なし
#         2=該当行が複数 (重複)  3=grep自体が異常終了
require_single_line() {
    pattern="$1"; file="$2"
    matched="$("$CMD_GREP" -E -- "$pattern" "$file")" && grep_rc=0 || grep_rc=$?
    case "$grep_rc" in
        0)
            line_count="$(printf '%s\n' "$matched" | "$CMD_GREP" -c .)"
            [ "$line_count" -eq 1 ] || return 2
            printf '%s\n' "$matched"
            return 0
            ;;
        1) return 1 ;;
        *) return 3 ;;
    esac
}

# extract_field_or_fail VAR_NAME FAIL_CODE CONTEXT PATTERN FILE COLUMN
# require_single_lineの結果を解釈し、失敗ならここ (トップレベル、非
# subshell) でfail()を呼ぶ。成功時はCOLUMN番目のawkフィールドをVAR_NAME
# へ代入する (printf -vを使い、evalは使わない)。
extract_field_or_fail() {
    var_name="$1"; fail_code="$2"; context="$3"; pattern="$4"; file="$5"; column="$6"
    line="$(require_single_line "$pattern" "$file")" && rsl_rc=0 || rsl_rc=$?
    case "$rsl_rc" in
        0) ;;
        1) fail "$fail_code" "$context: 該当行が見つかりません" ;;
        2) fail "$fail_code" "$context: 該当行が複数あります (重複)" ;;
        *) fail "$fail_code" "$context: 取得処理 (grep) が異常終了しました" ;;
    esac
    value="$(printf '%s\n' "$line" | "$CMD_AWK" -v c="$column" '{print $c}')"
    printf -v "$var_name" '%s' "$value"
}

# --- MBRパーティション件数・partition 1/2/3 ---
# awk既定split (空白区切り) でのフィールド番号:
#   "MBR partition      :   N   STATUS  TYPE      START      BLOCKS"
#    1   2         3    4   5      6       7          8
MBR_COUNT="$("$CMD_GREP" -cE '^MBR partition[[:space:]]+:[[:space:]]+[0-9]+[[:space:]]' -- "$POST_SYSTEM_AREA")" && mbr_count_rc=0 || mbr_count_rc=$?
case "$mbr_count_rc" in
    0|1) ;;
    *) fail 41 "MBRパーティション行数の取得 (grep) が異常終了しました (exit=$mbr_count_rc)" ;;
esac
[ "$MBR_COUNT" -eq 3 ] || fail 41 "MBRパーティション数が3ではありません (検出数: $MBR_COUNT)"

extract_field_or_fail MBR1_STATUS 41 'MBR partition 1 (status)' '^MBR partition[[:space:]]+:[[:space:]]+1[[:space:]]' "$POST_SYSTEM_AREA" 5
extract_field_or_fail MBR1_TYPE   41 'MBR partition 1 (type)'   '^MBR partition[[:space:]]+:[[:space:]]+1[[:space:]]' "$POST_SYSTEM_AREA" 6
extract_field_or_fail MBR1_START  41 'MBR partition 1 (start)'  '^MBR partition[[:space:]]+:[[:space:]]+1[[:space:]]' "$POST_SYSTEM_AREA" 7
extract_field_or_fail MBR1_BLOCKS 41 'MBR partition 1 (blocks)' '^MBR partition[[:space:]]+:[[:space:]]+1[[:space:]]' "$POST_SYSTEM_AREA" 8

extract_field_or_fail MBR2_STATUS 41 'MBR partition 2 (status)' '^MBR partition[[:space:]]+:[[:space:]]+2[[:space:]]' "$POST_SYSTEM_AREA" 5
extract_field_or_fail MBR2_TYPE   41 'MBR partition 2 (type)'   '^MBR partition[[:space:]]+:[[:space:]]+2[[:space:]]' "$POST_SYSTEM_AREA" 6
extract_field_or_fail MBR2_START  41 'MBR partition 2 (start)'  '^MBR partition[[:space:]]+:[[:space:]]+2[[:space:]]' "$POST_SYSTEM_AREA" 7
extract_field_or_fail MBR2_BLOCKS 41 'MBR partition 2 (blocks)' '^MBR partition[[:space:]]+:[[:space:]]+2[[:space:]]' "$POST_SYSTEM_AREA" 8

extract_field_or_fail MBR3_STATUS 41 'MBR partition 3 (status)' '^MBR partition[[:space:]]+:[[:space:]]+3[[:space:]]' "$POST_SYSTEM_AREA" 5
extract_field_or_fail MBR3_TYPE   41 'MBR partition 3 (type)'   '^MBR partition[[:space:]]+:[[:space:]]+3[[:space:]]' "$POST_SYSTEM_AREA" 6
extract_field_or_fail MBR3_START  41 'MBR partition 3 (start)'  '^MBR partition[[:space:]]+:[[:space:]]+3[[:space:]]' "$POST_SYSTEM_AREA" 7
extract_field_or_fail MBR3_BLOCKS 41 'MBR partition 3 (blocks)' '^MBR partition[[:space:]]+:[[:space:]]+3[[:space:]]' "$POST_SYSTEM_AREA" 8

# partition 1: status/type/startのみ固定値として検証する。blocksは
# 検証しない (固定値と比較しない) — 総イメージサイズに応じてxorrisoの
# シリンダ整列パディングが変わるため、partition 1のblocksは入力ISOや
# 実行ごとに正当に変化しうる。その代わり、partition 3がpartition 1の
# 終端に正確に連続しているか (非重複・隙間なし) を、後段で
# partition 1自身のblocksを基準に検証する。
[ "$MBR1_STATUS" = '0x80' ] || fail 41 "MBR partition 1のStatusが想定外です: $MBR1_STATUS"
[ "$MBR1_TYPE" = '0x00' ] || fail 41 "MBR partition 1のTypeが想定外です: $MBR1_TYPE"
[ "$MBR1_START" = '64' ] || fail 41 "MBR partition 1のStartが想定外です (期待値64): $MBR1_START"

# partition 2 (efi.img): efi.imgの内容・サイズは入力ISOと生成物とで
# 完全に同一であり (入力整合性検査で確認済み)、El ToritoのUEFI boot
# imageとしての配置規則もxorrisoの同一ロジックで決まるため、
# status/type/start/blocksのいずれも入力ISOと完全一致することを
# 期待値として検証する (単純な固定値ハードコードではなく、入力ISO
# 自身のsystem area報告から動的に取得した値と比較する)。
extract_field_or_fail INPUT_MBR2_STATUS 41 '入力ISO MBR partition 2 (status)' '^MBR partition[[:space:]]+:[[:space:]]+2[[:space:]]' "$INPUT_SYSTEM_AREA" 5
extract_field_or_fail INPUT_MBR2_TYPE   41 '入力ISO MBR partition 2 (type)'   '^MBR partition[[:space:]]+:[[:space:]]+2[[:space:]]' "$INPUT_SYSTEM_AREA" 6
extract_field_or_fail INPUT_MBR2_START  41 '入力ISO MBR partition 2 (start)'  '^MBR partition[[:space:]]+:[[:space:]]+2[[:space:]]' "$INPUT_SYSTEM_AREA" 7
extract_field_or_fail INPUT_MBR2_BLOCKS 41 '入力ISO MBR partition 2 (blocks)' '^MBR partition[[:space:]]+:[[:space:]]+2[[:space:]]' "$INPUT_SYSTEM_AREA" 8

[ "$MBR2_STATUS" = "$INPUT_MBR2_STATUS" ] || fail 41 "MBR partition 2のStatusが入力ISOと一致しません (入力: $INPUT_MBR2_STATUS, 生成物: $MBR2_STATUS)"
[ "$MBR2_TYPE" = "$INPUT_MBR2_TYPE" ] || fail 41 "MBR partition 2のTypeが入力ISOと一致しません (入力: $INPUT_MBR2_TYPE, 生成物: $MBR2_TYPE)"
[ "$MBR2_START" = "$INPUT_MBR2_START" ] || fail 41 "MBR partition 2のStartが入力ISOと一致しません (入力: $INPUT_MBR2_START, 生成物: $MBR2_START)"
[ "$MBR2_BLOCKS" = "$INPUT_MBR2_BLOCKS" ] || fail 41 "MBR partition 2のBlocksが入力ISOと一致しません (入力: $INPUT_MBR2_BLOCKS, 生成物: $MBR2_BLOCKS)"
[ "$MBR2_TYPE" = '0xef' ] || fail 41 "MBR partition 2のTypeが想定外です: $MBR2_TYPE"

# partition 2 (efi.img) はpartition 1 (ISO9660領域) の内側にネストされる
# (isohybrid特有の意図的な設計)。partition 2がpartition 1の範囲に
# 完全に収まっていることを確認する。
MBR1_END=$((MBR1_START + MBR1_BLOCKS))
MBR2_END=$((MBR2_START + MBR2_BLOCKS))
[ "$MBR2_START" -ge "$MBR1_START" ] && [ "$MBR2_END" -le "$MBR1_END" ] \
    || fail 41 "MBR partition 2がpartition 1の範囲内に収まっていません (partition1: $MBR1_START-$MBR1_END, partition2: $MBR2_START-$MBR2_END)"

# partition 3 (persistence): typeとサイズを検証し、partition 1の直後
# (非重複・隙間なし) に連続していることを検証する。
[ "$MBR3_STATUS" = '0x00' ] || fail 41 "MBR partition 3のStatusが想定外です: $MBR3_STATUS"
[ "$MBR3_TYPE" = '0x83' ] || fail 41 "MBR partition 3のTypeが想定外です: $MBR3_TYPE"

EXPECTED_PART3_START="$MBR1_END"
EXPECTED_PART3_BLOCKS=$((PERSISTENCE_SIZE_BYTES / 512))

[ "$MBR3_START" -eq "$EXPECTED_PART3_START" ] \
    || fail 41 "MBR partition 3のStartが想定外です (期待値: $EXPECTED_PART3_START = partition1終端, 実際: $MBR3_START)"
[ "$MBR3_BLOCKS" -eq "$EXPECTED_PART3_BLOCKS" ] \
    || fail 41 "MBR partition 3のBlocksが想定外です (期待値: $EXPECTED_PART3_BLOCKS, 実際: $MBR3_BLOCKS)"

echo "MBR: partition 1 (start=$MBR1_START blocks=$MBR1_BLOCKS、blocksは実行毎に変化しうる)"
echo "MBR: partition 2 (start=$MBR2_START blocks=$MBR2_BLOCKS、入力ISOと完全一致)"
echo "MBR: partition 3 (start=$MBR3_START blocks=$MBR3_BLOCKS、partition 1に連続・非重複)"

# --- GPTエントリ件数・entry 1/2/3 ---
# "GPT start and size :   N  START  SIZE" のawk既定splitフィールド番号:
#   1   2     3   4  5   6      7      8
# "GPT type GUID      :   N  GUID" は 1=GPT 2=type 3=GUID 4=: 5=N 6=GUID
# "GPT partname local :   N  NAME" は 1=GPT 2=partname 3=local 4=: 5=N 6=NAME
GPT_COUNT="$("$CMD_GREP" -cE '^GPT start and size[[:space:]]+:[[:space:]]+[0-9]+[[:space:]]' -- "$POST_SYSTEM_AREA")" && gpt_count_rc=0 || gpt_count_rc=$?
case "$gpt_count_rc" in
    0|1) ;;
    *) fail 42 "GPTエントリ行数の取得 (grep) が異常終了しました (exit=$gpt_count_rc)" ;;
esac
[ "$GPT_COUNT" -eq 3 ] || fail 42 "GPTエントリ数が3ではありません (検出数: $GPT_COUNT)"

extract_field_or_fail GPT1_START 42 'GPT entry 1 (start)' '^GPT start and size[[:space:]]+:[[:space:]]+1[[:space:]]' "$POST_SYSTEM_AREA" 7
extract_field_or_fail GPT1_SIZE  42 'GPT entry 1 (size)'  '^GPT start and size[[:space:]]+:[[:space:]]+1[[:space:]]' "$POST_SYSTEM_AREA" 8
extract_field_or_fail GPT2_START 42 'GPT entry 2 (start)' '^GPT start and size[[:space:]]+:[[:space:]]+2[[:space:]]' "$POST_SYSTEM_AREA" 7
extract_field_or_fail GPT2_SIZE  42 'GPT entry 2 (size)'  '^GPT start and size[[:space:]]+:[[:space:]]+2[[:space:]]' "$POST_SYSTEM_AREA" 8
extract_field_or_fail GPT3_START 42 'GPT entry 3 (start)' '^GPT start and size[[:space:]]+:[[:space:]]+3[[:space:]]' "$POST_SYSTEM_AREA" 7
extract_field_or_fail GPT3_SIZE  42 'GPT entry 3 (size)'  '^GPT start and size[[:space:]]+:[[:space:]]+3[[:space:]]' "$POST_SYSTEM_AREA" 8

extract_field_or_fail GPT2_TYPE_GUID 42 'GPT entry 2 (type GUID)' '^GPT type GUID[[:space:]]+:[[:space:]]+2[[:space:]]' "$POST_SYSTEM_AREA" 6
extract_field_or_fail GPT3_TYPE_GUID 42 'GPT entry 3 (type GUID)' '^GPT type GUID[[:space:]]+:[[:space:]]+3[[:space:]]' "$POST_SYSTEM_AREA" 6
extract_field_or_fail GPT2_NAME 42 'GPT entry 2 (name)' '^GPT partname local[[:space:]]+:[[:space:]]+2[[:space:]]' "$POST_SYSTEM_AREA" 6
extract_field_or_fail GPT3_NAME 42 'GPT entry 3 (name)' '^GPT partname local[[:space:]]+:[[:space:]]+3[[:space:]]' "$POST_SYSTEM_AREA" 6

extract_field_or_fail INPUT_GPT2_START 42 '入力ISO GPT entry 2 (start)' '^GPT start and size[[:space:]]+:[[:space:]]+2[[:space:]]' "$INPUT_SYSTEM_AREA" 7
extract_field_or_fail INPUT_GPT2_SIZE  42 '入力ISO GPT entry 2 (size)'  '^GPT start and size[[:space:]]+:[[:space:]]+2[[:space:]]' "$INPUT_SYSTEM_AREA" 8
extract_field_or_fail INPUT_GPT2_TYPE_GUID 42 '入力ISO GPT entry 2 (type GUID)' '^GPT type GUID[[:space:]]+:[[:space:]]+2[[:space:]]' "$INPUT_SYSTEM_AREA" 6
extract_field_or_fail INPUT_GPT2_NAME 42 '入力ISO GPT entry 2 (name)' '^GPT partname local[[:space:]]+:[[:space:]]+2[[:space:]]' "$INPUT_SYSTEM_AREA" 6

# GPT entry 1が生成後MBR partition 1と整合していること
[ "$GPT1_START" -eq "$MBR1_START" ] && [ "$GPT1_SIZE" -eq "$MBR1_BLOCKS" ] \
    || fail 42 "GPT entry 1がMBR partition 1と一致しません (MBR: start=$MBR1_START size=$MBR1_BLOCKS, GPT: start=$GPT1_START size=$GPT1_SIZE)"

# GPT entry 2 (efi.img) は、start/size/type GUID/nameのいずれも入力ISOと
# 完全一致することを検証する。
[ "$GPT2_START" -eq "$INPUT_GPT2_START" ] || fail 42 "GPT entry 2のStartが入力ISOと一致しません (入力: $INPUT_GPT2_START, 生成物: $GPT2_START)"
[ "$GPT2_SIZE" -eq "$INPUT_GPT2_SIZE" ] || fail 42 "GPT entry 2のSizeが入力ISOと一致しません (入力: $INPUT_GPT2_SIZE, 生成物: $GPT2_SIZE)"
[ "$GPT2_TYPE_GUID" = "$INPUT_GPT2_TYPE_GUID" ] || fail 42 "GPT entry 2のtype GUIDが入力ISOと一致しません (入力: $INPUT_GPT2_TYPE_GUID, 生成物: $GPT2_TYPE_GUID)"
[ "$GPT2_NAME" = "$INPUT_GPT2_NAME" ] || fail 42 "GPT entry 2のnameが入力ISOと一致しません (入力: $INPUT_GPT2_NAME, 生成物: $GPT2_NAME)"
[ "$GPT2_START" -eq "$MBR2_START" ] && [ "$GPT2_SIZE" -eq "$MBR2_BLOCKS" ] \
    || fail 42 "GPT entry 2がMBR partition 2と一致しません (MBR: start=$MBR2_START size=$MBR2_BLOCKS, GPT: start=$GPT2_START size=$GPT2_SIZE)"

# GPT entry 3 (persistence)。type GUIDはGPTの混合エンディアン格納方式
# により、指定した0FC63DAF-8483-4772-8E79-3D69D8477DE4は各フィールドを
# バイト単位で反転した af3dc60f-8384-7247-8e79-3d69d8477de4 として
# plain表示される (実機で確認済み、-append_partition時のみこの表示に
# なる。isohybrid由来のentry 1/2は別のGUIDのため異なる)。
[ "$GPT3_START" -eq "$MBR3_START" ] && [ "$GPT3_SIZE" -eq "$MBR3_BLOCKS" ] \
    || fail 42 "GPT entry 3がMBR partition 3と一致しません (MBR: start=$MBR3_START size=$MBR3_BLOCKS, GPT: start=$GPT3_START size=$GPT3_SIZE)"
EXPECTED_GPT3_TYPE_GUID='af3dc60f838472478e793d69d8477de4'
[ "$GPT3_TYPE_GUID" = "$EXPECTED_GPT3_TYPE_GUID" ] \
    || fail 42 "GPT entry 3のtype GUIDが想定外です (期待値: $EXPECTED_GPT3_TYPE_GUID, 実際: $GPT3_TYPE_GUID)"
EXPECTED_GPT3_NAME='Appended3'
[ "$GPT3_NAME" = "$EXPECTED_GPT3_NAME" ] \
    || fail 42 "GPT entry 3のnameが想定外です (期待値: $EXPECTED_GPT3_NAME, 実際: $GPT3_NAME)"

echo "GPT: entry 1がMBR partition 1と整合、entry 2が入力ISOと完全一致、entry 3のstart/size/type GUID/nameを確認"

# --- GPT backup headerが出力ファイル末尾LBAにあること、出力ファイル
#     サイズが512で割り切れること ---
extract_field_or_fail GPT_BACKUP_LBA 43 'GPT lba range (backup header)' '^GPT lba range' "$POST_SYSTEM_AREA" 7

TMP_OUTPUT_SIZE="$("$CMD_STAT" -c '%s' -- "$TMP_OUTPUT")"
[ $((TMP_OUTPUT_SIZE % 512)) -eq 0 ] \
    || fail 43 "出力ファイルサイズが512の倍数ではありません: $TMP_OUTPUT_SIZE"

EXPECTED_BACKUP_LBA=$((TMP_OUTPUT_SIZE / 512 - 1))
[ "$GPT_BACKUP_LBA" -eq "$EXPECTED_BACKUP_LBA" ] \
    || fail 43 "GPT backup headerが出力ファイル末尾LBAにありません (期待値: $EXPECTED_BACKUP_LBA, 実際: $GPT_BACKUP_LBA)"
echo "GPT backup header: 出力ファイル末尾LBA ($EXPECTED_BACKUP_LBA)、サイズの512倍数性を確認"

# --- El Torito (入力ISOの報告値と完全一致を要求) ---
extract_el_torito_body() {
    # "El Torito"で始まる行だけを比較対象とする (Media summary等の可変行を除く)
    "$CMD_GREP" -E '^El Torito' -- "$1"
}
"$CMD_DIFF" -u <(extract_el_torito_body "$INPUT_EL_TORITO") <(extract_el_torito_body "$POST_EL_TORITO") \
    > "$WORKROOT/el_torito.diff" 2>&1 \
    || fail 44 "El Torito報告が入力ISOと一致しません (詳細: $WORKROOT/el_torito.diff)"
echo "El Torito: 入力ISOとの完全一致を確認 (BIOS/UEFIとも)"

# --- ISO9660読み取り ---
for p in /isolinux/isolinux.bin /boot/grub/efi.img /live/filesystem.squashfs /live/vmlinuz /live/initrd.img; do
    "$CMD_XORRISO" -indev "$TMP_OUTPUT" -find "$p" \
        > "$WORKROOT/find_check.stdout" 2> "$WORKROOT/find_check.stderr" \
        || fail 45 "ISO9660読み取り検証に失敗しました: $p"
    "$CMD_GREP" -qF "'$p'" "$WORKROOT/find_check.stdout" \
        || fail 45 "ISO9660上にファイルが見つかりません: $p"
done
echo "ISO9660: 主要ファイルの読み取りを確認"

# --- partition 3抽出とcmp ---
EXTRACTED_PART3="$WORKROOT/extracted_partition3.img"
OFFSET_BYTES=$((MBR3_START * 512))
LEN_BYTES=$((MBR3_BLOCKS * 512))
"$CMD_DD" if="$TMP_OUTPUT" of="$EXTRACTED_PART3" bs=1M \
    iflag=skip_bytes,count_bytes skip="$OFFSET_BYTES" count="$LEN_BYTES" status=none \
    || fail 46 "partition 3の抽出に失敗しました"

"$CMD_CMP" -- "$EXTRACTED_PART3" "$PERSISTENCE_IMG" \
    || fail 46 "抽出したpartition 3がpersistence.imgと一致しません"
echo "partition 3抽出: persistence.imgとのcmp完全一致を確認"

# --- 抽出物のe2fsck ---
set +e
"$CMD_E2FSCK" -fn -- "$EXTRACTED_PART3" \
    > "$WORKROOT/e2fsck_post.stdout" 2> "$WORKROOT/e2fsck_post.stderr"
E2FSCK_POST_RC=$?
set -e
[ "$E2FSCK_POST_RC" -eq 0 ] \
    || fail 47 "抽出したpartition 3のe2fsck -fnが異常を報告しました (exit=$E2FSCK_POST_RC)"
echo "partition 3抽出物: e2fsck -fn異常なし"

# --- 抽出物内persistence.confの検証 ---
verify_persistence_conf "$EXTRACTED_PART3" \
    || fail 48 "抽出したpartition 3内のpersistence.conf検証に失敗しました"
echo "partition 3抽出物: persistence.confのUID/GID/mode/size/contentを確認"
"$CMD_RM" -f -- "$EXTRACTED_PART3"
echo

# ---- 実行中の入力不変性の最終確認 -------------------------------------------
echo "== 実行中の入力不変性の最終確認 =="
ISO_SHA_FINAL="$("$CMD_SHA256SUM" -- "$ISO_ABS" | "$CMD_AWK" '{print $1}')"
[ "$ISO_SHA_FINAL" = "$ISO_SHA_BASELINE" ] \
    || fail 49 "実行中に入力ISOのSHA-256が変化しました"

BIN_EFI_IMG_SHA_FINAL="$("$CMD_SHA256SUM" -- "$BIN_EFI_IMG" | "$CMD_AWK" '{print $1}')"
BIN_SQUASHFS_SHA_FINAL="$("$CMD_SHA256SUM" -- "$BIN_SQUASHFS" | "$CMD_AWK" '{print $1}')"
BIN_ISOLINUX_BIN_SHA_FINAL="$("$CMD_SHA256SUM" -- "$BIN_ISOLINUX_BIN" | "$CMD_AWK" '{print $1}')"
[ "$BIN_EFI_IMG_SHA_FINAL" = "$BIN_EFI_IMG_SHA_BASELINE" ] \
    || fail 50 "実行中にbinary/boot/grub/efi.imgのSHA-256が変化しました"
[ "$BIN_SQUASHFS_SHA_FINAL" = "$BIN_SQUASHFS_SHA_BASELINE" ] \
    || fail 50 "実行中にbinary/live/filesystem.squashfsのSHA-256が変化しました"
[ "$BIN_ISOLINUX_BIN_SHA_FINAL" = "$BIN_ISOLINUX_BIN_SHA_BASELINE" ] \
    || fail 50 "実行中にbinary/isolinux/isolinux.binのSHA-256が変化しました"

echo "入力ISO・binary/主要3ファイル: 実行前後でSHA-256不変を確認"
echo

# ---- 最終公開 (全検証成功後のみ、同一ファイルシステム内hard link) ----------
# ln (mvではない) を使うことで、OUTPUT_ABSが既に存在する場合は失敗する
# (上書きしない)。-fは使わない。これによりTOCTOU窓での上書きが構造上
# 起こらない。成功後、work directory内のコピー (TMP_OUTPUT) は不要に
# なるため削除する (hard linkのため、OUTPUT_ABS側のデータは影響を
# 受けない)。
"$CMD_LN" -- "$TMP_OUTPUT" "$OUTPUT_ABS" \
    || fail 60 "最終公開 (hard link作成) に失敗しました: $TMP_OUTPUT -> $OUTPUT_ABS (出力先が既に存在する可能性があります)"
"$CMD_RM" -f -- "$TMP_OUTPUT"

echo "== 完了 =="
echo "出力: $OUTPUT_ABS"
"$CMD_SHA256SUM" -- "$OUTPUT_ABS"

exit 0
