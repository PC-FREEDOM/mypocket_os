#!/usr/bin/env bash
#
# MyPocketOS - live-build ビルドスクリプト (Base/Standard edition選択制)
#
# 使い方:
#   ./scripts/build.sh base       Base版をビルド
#   ./scripts/build.sh standard   Standard版をビルド
#
# config(--image-name) -> clean -> config(--image-name) -> build の順に
# 実行し、ログを build.log に保存する (順序の理由は後述)。
#
# package-listの正本は config/package-lists.d/ に置く。live-build
# (chroot_package-lists) は config/package-lists/*.list.chroot に一致する
# 全ファイルを無条件に取り込むため、config/package-lists.d/ 自体は
# live-buildの読み込み対象外にしてある。ビルド中のみ、選択された
# editionに必要なファイルだけを config/package-lists/ へ一時的にコピーし、
# ビルド終了後 (成功・失敗・SIGINT等いずれでも) trapで確実に削除する。
#
# config/package-lists/ はGit上では空ディレクトリになり (Gitは空ディレクトリ
# を保持しない)、新規cloneでは存在しない可能性がある。本スクリプトは、
# 存在しない場合は自分で作成し (mkdir、親のconfig/は既存前提)、ビルド終了後
# 自分で作成した場合に限りrmdirで復元する (元から中身がある/自分が作った
# のでない場合は削除しない)。
#
# config/package-lists/ に、このスクリプトが管理するはずのファイルが
# 既に存在する場合 (前回ビルドの後始末が何らかの理由で失敗した場合等)、
# 上書きせず安全側に停止する。
#
set -euo pipefail

cd "$(dirname "$0")/.."

# ---- edition引数の検証 (他のどの処理よりも前に行う) --------------------------
usage() {
    echo "usage: $(basename "$0") {base|standard}" >&2
    exit 2
}

if [ $# -ne 1 ]; then
    usage
fi

case "$1" in
    base | standard)
        EDITION="$1"
        ;;
    *)
        usage
        ;;
esac

# ---- 必要ファイル・ディレクトリの確認 ----------------------------------------
SRC_DIR="config/package-lists.d"
DEST_DIR="config/package-lists"

COMMON_SRC="${SRC_DIR}/mypocketos-common.list.chroot"
STANDARD_SRC="${SRC_DIR}/mypocketos-standard.list.chroot"
COMMON_DEST="${DEST_DIR}/mypocketos-common.list.chroot"
STANDARD_DEST="${DEST_DIR}/mypocketos-standard.list.chroot"
ISO_NAME="mypocketos-${EDITION}-amd64.hybrid.iso"

if [ ! -f "${COMMON_SRC}" ]; then
    echo "エラー: '${COMMON_SRC}' が見つかりません。" >&2
    exit 1
fi

if [ "${EDITION}" = "standard" ] && [ ! -f "${STANDARD_SRC}" ]; then
    echo "エラー: '${STANDARD_SRC}' が見つかりません。" >&2
    exit 1
fi

# DEST_DIR (config/package-lists/) はGit上では空ディレクトリになるため、
# 新規clone等では存在しないことがある。通常ファイル等、ディレクトリ以外の
# 何かが同名で既に存在する異常な状態では安全側に停止する。存在しない場合は
# 自分で作成し、その旨を記録しておく (ビルド終了後、自分で作った場合に限り
# 復元のため削除する)。
DEST_DIR_CREATED=0
if [ -e "${DEST_DIR}" ] && [ ! -d "${DEST_DIR}" ]; then
    echo "エラー: '${DEST_DIR}' はディレクトリではありません。想定外の状態のため中止します。" >&2
    exit 1
fi
if [ ! -d "${DEST_DIR}" ]; then
    mkdir -- "${DEST_DIR}"
    DEST_DIR_CREATED=1
fi

# 前回のビルドの後始末が失敗している等、想定外に既に存在する場合は
# 上書きせず安全側に停止する。このスクリプトが自分でコピーしたファイル
# だけを対象とし、config/package-lists/ 配下の他のファイル
# (live.list.chroot 等、live-build自身が生成するもの) には一切触れない。
if [ -e "${COMMON_DEST}" ]; then
    echo "エラー: '${COMMON_DEST}' が既に存在します。" >&2
    echo "        前回のビルドの後始末が失敗している可能性があります。" >&2
    echo "        内容を確認のうえ、問題なければ手動で削除してから再実行してください。" >&2
    exit 1
fi

if [ "${EDITION}" = "standard" ] && [ -e "${STANDARD_DEST}" ]; then
    echo "エラー: '${STANDARD_DEST}' が既に存在します。" >&2
    echo "        前回のビルドの後始末が失敗している可能性があります。" >&2
    echo "        内容を確認のうえ、問題なければ手動で削除してから再実行してください。" >&2
    exit 1
fi

# ---- cleanup trap (まだ何もコピーしていない時点で先に登録する) --------------
cleanup_package_lists() {
    rm -f -- "${COMMON_DEST}"
    if [ "${EDITION}" = "standard" ]; then
        rm -f -- "${STANDARD_DEST}"
    fi
    # 自分で作成した場合のみ、かつ空である場合のみ削除する (rmdirは非空
    # ディレクトリに対して失敗するため、live.list.chroot等がlb config/
    # lb buildの過程で新たに生成されていれば自然に何もしない)。
    if [ "${DEST_DIR_CREATED}" -eq 1 ]; then
        rmdir -- "${DEST_DIR}" 2>/dev/null || true
    fi
}
trap cleanup_package_lists EXIT INT TERM HUP

# ---- 一時package-list配置 ----------------------------------------------------
cp -- "${COMMON_SRC}" "${COMMON_DEST}"
if [ "${EDITION}" = "standard" ]; then
    cp -- "${STANDARD_SRC}" "${STANDARD_DEST}"
fi

echo "edition: ${EDITION}"
echo "配置したpackage-list:"
echo "  - ${COMMON_DEST}"
if [ "${EDITION}" = "standard" ]; then
    echo "  - ${STANDARD_DEST}"
fi
echo

# ---- 今回対象editionの既存ISOを事前に削除 ------------------------------------
# 前回ビルドの古い同edition ISOが残ったままだと、今回のビルドが (例えば
# 予期せぬ理由で) 実際には成果物を生成しなかった場合でも、後段の
# 「ISO存在確認」が古いファイルを新しい成果物と誤認してしまう。ここで対象
# editionのISO名だけを削除しておくことで、「ISO存在確認」に成功した時点で
# 今回のビルドが実際に生成したことを保証する。他editionのISO
# (例: base実行時のstandard ISO) には一切触れない。
rm -f -- "${ISO_NAME}"

LOG_FILE="build.log"
: > "${LOG_FILE}"

log_and_run() {
    echo "==> $*" | tee -a "${LOG_FILE}"
    "$@" 2>&1 | tee -a "${LOG_FILE}"
}

# ---- lb config (1回目) -> lb clean -> lb config (2回目) -> lb build --------
# 「sudo lb clean」は引数なしで呼ぶとRM_ALL相当になり、その一部として
# config/common に保存されている LB_IMAGE_NAME を使って
# 「rm -f ${LB_IMAGE_NAME}*.iso」を実行する (/usr/lib/live/build/clean で
# 確認済み)。config/common のLB_IMAGE_NAMEは、直前に実行したlb configの
# --image-name がそのまま残る (lb clean自体はconfig/common等の保存済み
# オプションを削除しない)。そのため、前回別editionをビルドした直後に
# 今回のeditionでいきなり「lb clean」を呼ぶと、前回editionのLB_IMAGE_NAME
# のままclean が走り、前回edition側のISOを誤って削除してしまう
# (実機ビルドで実際に発生・確認済みの不具合)。
#
# これを避けるため、lb cleanの前に一度 --image-name を今回editionへ
# 更新するためだけの lb config を挟む。lb clean自体はchroot/binary等の
# ビルド内部生成物 (config/{common,binary,chroot}等の保存済みオプション
# 自体は含まない) を削除するため、直後に同じ --image-name で改めて
# lb configを実行し、正式なビルド設定を確定してからlb buildへ進む。
# live-build内部のcleanがどの保存済み設定ファイルを保持するかへ
# 必要以上に依存しない設計を優先し、1回目・2回目とも同一の
# --image-name引数で統一している。
log_and_run lb config --image-name "mypocketos-${EDITION}"
log_and_run sudo lb clean
log_and_run lb config --image-name "mypocketos-${EDITION}"
log_and_run sudo lb build

if [ ! -f "${ISO_NAME}" ]; then
    echo "エラー: ビルドは完了しましたが、期待するISO '${ISO_NAME}' が見つかりません。" >&2
    exit 1
fi

cleanup_package_lists

echo "==> Build finished (edition: ${EDITION}). See ${LOG_FILE}" | tee -a "${LOG_FILE}"
echo "==> ISO: ${ISO_NAME}" | tee -a "${LOG_FILE}"
