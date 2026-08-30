#!/usr/bin/env bash
#
# update-test-iso.sh - 共有ISO (MyPocketOS-dev.iso) の更新 (Base/Standard edition選択制)
#
# 使い方:
#   ./scripts/update-test-iso.sh base       Base版ISOで更新
#   ./scripts/update-test-iso.sh standard   Standard版ISOで更新
#
# 開発ホスト (Debian) で実行するスクリプトです。MyPocketOSのISO内では
# 実行しません。ISOビルドの再実行後、このISOを参照している全VMを停止した
# 状態で使用してください:
#
#   1. virsh --connect qemu:///system shutdown <ドメイン名>
#      (状態確認: virsh --connect qemu:///system domstate <ドメイン名>)
#   2. ./scripts/build.sh {base|standard} でISOを再ビルド
#   3. ./scripts/update-test-iso.sh {base|standard} を実行 (ビルドしたeditionと
#      同じものを指定する)
#   4. 更新完了時に表示される起動コマンドで、各VMを起動する
#
# このスクリプトはISOファイルの更新のみを行います。VM定義・仮想ディスクの
# 削除や変更は一切行いません。VM・仮想ディスク・配置済みISOといった永続資産を
# 削除する機能は意図的に実装していませんが、自身が作成した一時ファイル
# (ISO_TMP, sudo mktemp で作成) のみは、trapで確実に削除します。
#
# 共有ISOの安全確認について:
# 更新対象のISOを参照している全ドメインを動的に検出する
# (「mypocketos-test」「mypocketos-uefi-test」という名前を一切ハードコード
# しない)。参照ドメインが1件もなければ「更新対象のVMが見つからない」として
# 拒否し、1件以上ある場合は全ドメインが「停止 (shut off)」であるときのみ
# 更新する。

set -euo pipefail

# ---- edition引数の検証 (他のどの処理よりも前に行う) --------------------------
usage() {
    echo "usage: $(basename "${BASH_SOURCE[0]}") {base|standard}" >&2
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

# ---- Debianホスト専用であることの確認 --------------------------------------
if [ ! -r /etc/os-release ] || ! grep -q '^ID=debian$' /etc/os-release; then
    echo "エラー: このスクリプトは Debian の開発ホスト専用です。" >&2
    echo "        (/etc/os-release に ID=debian が見つかりません)" >&2
    exit 1
fi

# ---- パスの解決 (スクリプト自身の位置からプロジェクトルートを決定) ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

LIBVIRT_URI="qemu:///system"
LIBVIRT_OWNER="libvirt-qemu:libvirt-qemu"
IMAGES_DIR="/var/lib/libvirt/images"
ISO_SRC="${PROJECT_ROOT}/mypocketos-${EDITION}-amd64.hybrid.iso"
ISO_DEST="${IMAGES_DIR}/MyPocketOS-dev.iso"

echo "== 処理対象の絶対パス =="
echo "edition             : ${EDITION}"
echo "プロジェクトルート : ${PROJECT_ROOT}"
echo "ISOソース          : ${ISO_SRC}"
echo "ISO配置先          : ${ISO_DEST}"
echo

# ---- 必要コマンドの存在確認 -------------------------------------------------
for cmd in virsh sudo sha256sum mktemp awk; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        echo "エラー: 必要なコマンド '${cmd}' が見つかりません。" >&2
        exit 1
    fi
done

# ---- 共有ISOを利用している全ドメインの安全確認 -----------------------------
# ISO_DEST を参照している全ドメイン名を1行1件で標準出力へ書き出す。
# 「mypocketos-test」「mypocketos-uefi-test」という名前は一切ハードコード
# せず、現在存在する全ドメインを動的に調べる。取得に失敗した場合は
# 何も出力せず非0を返す (呼び出し側で安全側に倒す)。
find_shared_iso_domains() {
    local domain_list domain block_list awk_rc

    if ! domain_list="$(LC_ALL=C virsh --connect "${LIBVIRT_URI}" list --all --name 2>/dev/null)"; then
        return 1
    fi

    while IFS= read -r domain; do
        [ -z "${domain}" ] && continue
        # --inactive: 実行中の一時的な状態ではなく、次回起動時に使われる
        # 永続設定側のブロックデバイス一覧を取得する。
        if ! block_list="$(LC_ALL=C virsh --connect "${LIBVIRT_URI}" domblklist "${domain}" --inactive --details 2>/dev/null)"; then
            return 1
        fi
        # awk の終了コードを3状態で区別する:
        #   0    : 共有ISOと一致する行が見つかった (このドメインを利用中として出力)
        #   1    : 一致なし (END { exit !found } による正常な不一致。継続)
        #   2以上 : awk自体の実行エラー (安全側に倒し、確認全体を失敗させる)
        # set -e 下でも安全に動くよう、awk呼び出しをif/elseの条件として実行し
        # (単純な文として実行すると set -e により途中終了してしまう)、
        # 失敗時のみ else 内で $? を読み取って判別する。
        if awk -v iso="${ISO_DEST}" '$NF == iso { found = 1 } END { exit !found }' <<< "${block_list}"; then
            printf '%s\n' "${domain}"
        else
            awk_rc=$?
            if [ "${awk_rc}" -ge 2 ]; then
                return 1
            fi
        fi
    done <<< "${domain_list}"
}

# 引数のドメイン名一覧 (改行区切り) が全て厳密に "shut off" かどうかを判定
# する。running, paused, pmsuspended, in shutdown, crashed、空文字、
# 状態取得失敗を含め、"shut off" 以外は全て拒否する (ホワイトリスト方式)。
# 該当する全ドメインについて、ドメイン名と状態を標準エラーへ表示する。
check_all_shut_off() {
    local domains="$1" domain state failed=0

    while IFS= read -r domain; do
        [ -z "${domain}" ] && continue
        if ! state="$(LC_ALL=C virsh --connect "${LIBVIRT_URI}" domstate "${domain}" 2>/dev/null)"; then
            echo "エラー: ドメイン '${domain}' の状態を取得できませんでした。" >&2
            failed=1
            continue
        fi
        if [ "${state}" != "shut off" ]; then
            echo "エラー: ドメイン '${domain}' が停止状態 (shut off) ではありません (現在の状態: ${state:-(空)})。" >&2
            failed=1
        fi
    done <<< "${domains}"

    return "${failed}"
}

echo "== 共有ISOを利用しているドメインを確認しています =="
if ! SHARED_ISO_USERS="$(find_shared_iso_domains)"; then
    echo "エラー: 共有ISOを利用しているドメインの確認に失敗しました。更新を中止します。" >&2
    exit 1
fi

if [ -z "${SHARED_ISO_USERS}" ]; then
    echo "エラー: 共有ISO ('${ISO_DEST}') を利用しているVMが見つかりません。更新を中止します。" >&2
    echo "        先に scripts/create-test-vm.sh でVMを作成してください。" >&2
    exit 1
fi

if ! check_all_shut_off "${SHARED_ISO_USERS}"; then
    echo "エラー: 共有ISO ('${ISO_DEST}') を利用している一部のドメインが停止状態ではないため、更新を中止します。" >&2
    exit 1
fi

echo "共有ISO利用ドメイン (すべて停止中):"
while IFS= read -r _domain; do
    [ -z "${_domain}" ] && continue
    echo "  - ${_domain}"
done <<< "${SHARED_ISO_USERS}"
echo

# ---- ISOソースが通常ファイルであることの確認 --------------------------------
if [ ! -f "${ISO_SRC}" ]; then
    echo "エラー: ISOソース '${ISO_SRC}' が通常ファイルとして見つかりません。" >&2
    echo "        先に ./scripts/build.sh ${EDITION} でISOをビルドしてください。" >&2
    exit 1
fi

# ---- ISO配置先の型チェック (存在する場合、通常ファイルであること) ----------
if [ -e "${ISO_DEST}" ] && [ ! -f "${ISO_DEST}" ]; then
    echo "エラー: ISO配置先 '${ISO_DEST}' が通常ファイルではありません。想定外の状態のため中止します。" >&2
    exit 1
fi

# ---- 固定名を使わず、配置先と同じディレクトリーに一時ファイルを作成 --------
# ---- (検証後に mv で置き換える) ---------------------------------------------
# cleanup_iso_tmp が削除するのは、sudo mktemp によって自身が作成した
# 一時ファイル (ISO_TMP) のみ。VM・仮想ディスク・配置済みISO (ISO_DEST)
# 等の永続資産は削除しない。
ISO_TMP=""
cleanup_iso_tmp() {
    if [ -n "${ISO_TMP}" ]; then
        sudo rm -f -- "${ISO_TMP}"
    fi
}
trap cleanup_iso_tmp EXIT INT TERM HUP

echo "== ISOを更新しています: ${ISO_SRC} -> ${ISO_DEST} =="
ISO_TMP="$(sudo mktemp "${ISO_DEST}.XXXXXX")"
sudo cp -- "${ISO_SRC}" "${ISO_TMP}"
sudo chmod 0644 "${ISO_TMP}"
sudo chown "${LIBVIRT_OWNER}" "${ISO_TMP}"

SRC_SHA256="$(sha256sum -- "${ISO_SRC}" | cut -d' ' -f1)"
TMP_SHA256="$(sudo sha256sum -- "${ISO_TMP}" | cut -d' ' -f1)"

if [ "${SRC_SHA256}" != "${TMP_SHA256}" ]; then
    echo "エラー: コピーしたISOのSHA-256がソースと一致しません。更新を中止します。" >&2
    echo "        ソース: ${SRC_SHA256}" >&2
    echo "        コピー: ${TMP_SHA256}" >&2
    exit 1
fi

sudo mv -f -- "${ISO_TMP}" "${ISO_DEST}"
ISO_TMP=""

DEST_SHA256="$(sudo sha256sum -- "${ISO_DEST}" | cut -d' ' -f1)"
if [ "${SRC_SHA256}" != "${DEST_SHA256}" ]; then
    echo "エラー: 置き換え後のISOのSHA-256が一致しません。" >&2
    exit 1
fi

echo "ISOの更新とSHA-256検証が完了しました (edition: ${EDITION}, ${SRC_SHA256})。"
echo
echo "次のコマンドで各VMを起動してください:"
while IFS= read -r _domain; do
    [ -z "${_domain}" ] && continue
    echo "  virsh --connect ${LIBVIRT_URI} start ${_domain}"
done <<< "${SHARED_ISO_USERS}"
