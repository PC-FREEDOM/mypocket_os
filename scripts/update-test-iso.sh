#!/usr/bin/env bash
#
# update-test-iso.sh - mypocketos-test 用ISO (MyPocketOS-dev.iso) の更新
#
# 開発ホスト (Debian) で実行するスクリプトです。MyPocketOSのISO内では
# 実行しません。ISOビルドの再実行後、VMを停止した状態で使用してください:
#
#   1. virsh --connect qemu:///system shutdown mypocketos-test
#      (状態確認: virsh --connect qemu:///system domstate mypocketos-test)
#   2. ./scripts/build.sh でISOを再ビルド
#   3. ./scripts/update-test-iso.sh を実行
#   4. virsh --connect qemu:///system start mypocketos-test
#
# このスクリプトはISOファイルの更新のみを行います。VM定義・仮想ディスクの
# 削除や変更は一切行いません。VM・仮想ディスク・配置済みISOといった永続資産を
# 削除する機能は意図的に実装していませんが、自身が作成した一時ファイル
# (ISO_TMP, sudo mktemp で作成) のみは、trapで確実に削除します。

set -euo pipefail

# ---- Debianホスト専用であることの確認 --------------------------------------
if [ ! -r /etc/os-release ] || ! grep -q '^ID=debian$' /etc/os-release; then
    echo "エラー: このスクリプトは Debian の開発ホスト専用です。" >&2
    echo "        (/etc/os-release に ID=debian が見つかりません)" >&2
    exit 1
fi

# ---- パスの解決 (スクリプト自身の位置からプロジェクトルートを決定) ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

VM_NAME="mypocketos-test"
LIBVIRT_URI="qemu:///system"
LIBVIRT_OWNER="libvirt-qemu:libvirt-qemu"
IMAGES_DIR="/var/lib/libvirt/images"
ISO_SRC="${PROJECT_ROOT}/live-image-amd64.hybrid.iso"
ISO_DEST="${IMAGES_DIR}/MyPocketOS-dev.iso"

echo "== 処理対象の絶対パス =="
echo "プロジェクトルート : ${PROJECT_ROOT}"
echo "ISOソース          : ${ISO_SRC}"
echo "ISO配置先          : ${ISO_DEST}"
echo "VM名                : ${VM_NAME}"
echo

# ---- 必要コマンドの存在確認 -------------------------------------------------
for cmd in virsh sudo sha256sum mktemp; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        echo "エラー: 必要なコマンド '${cmd}' が見つかりません。" >&2
        exit 1
    fi
done

# ---- mypocketos-test ドメインの存在確認 -------------------------------------
# LC_ALL=C: virsh の出力・終了コード判定はロケールに依存しない形で行うため、
# 判定に使う virsh 呼び出しは常に C (POSIX/英語) ロケールで実行する。
if ! LC_ALL=C virsh --connect "${LIBVIRT_URI}" dominfo "${VM_NAME}" >/dev/null 2>&1; then
    echo "エラー: ドメイン '${VM_NAME}' が見つかりません。ISOを交換せず中止します。" >&2
    echo "        先に scripts/create-test-vm.sh でVMを作成してください。" >&2
    exit 1
fi

# ---- mypocketos-test が shut off であることの確認 (ホワイトリスト方式) ------
# 状態が厳密に "shut off" の場合のみ更新を許可する。running, paused,
# pmsuspended, in shutdown, crashed、空文字、状態取得失敗を含め、
# それ以外は全て拒否する (ホワイトリスト方式なので、ここに列挙していない
# 未知の状態文字列が返っても安全側に倒れる)。libvirtへの問い合わせ失敗を
# 停止状態として扱わないよう、状態取得そのものの成否も別途確認する。
if ! DOM_STATE="$(LC_ALL=C virsh --connect "${LIBVIRT_URI}" domstate "${VM_NAME}" 2>/dev/null)"; then
    echo "エラー: ドメイン '${VM_NAME}' の状態を取得できませんでした。ISOを交換せず中止します。" >&2
    exit 1
fi

if [ "${DOM_STATE}" != "shut off" ]; then
    echo "エラー: ドメイン '${VM_NAME}' が停止状態 (shut off) ではないため、ISOを交換せず中止します。" >&2
    echo "        現在の状態: ${DOM_STATE:-(空)}" >&2
    echo "        次のコマンドで停止してから再実行してください:" >&2
    echo "          virsh --connect ${LIBVIRT_URI} shutdown ${VM_NAME}" >&2
    exit 1
fi

# ---- ISOソースが通常ファイルであることの確認 --------------------------------
if [ ! -f "${ISO_SRC}" ]; then
    echo "エラー: ISOソース '${ISO_SRC}' が通常ファイルとして見つかりません。" >&2
    echo "        先に ./scripts/build.sh でISOをビルドしてください。" >&2
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

echo "ISOの更新とSHA-256検証が完了しました (${SRC_SHA256})。"
echo
echo "次のコマンドでVMを起動してください:"
echo "  virsh --connect ${LIBVIRT_URI} start ${VM_NAME}"
