#!/usr/bin/env bash
#
# create-test-vm.sh - MyPocketOS 検証用 QEMU/KVM VM (mypocketos-test) の作成
#
# 開発ホスト (Debian, virt-install/virsh/QEMU/KVM がセットアップ済みの環境) で
# 実行するスクリプトです。MyPocketOSのISO内では実行しません。
#
# このスクリプトは「作成」専用です。VM・仮想ディスク・配置済みISOといった
# 永続資産を削除する機能 (virsh undefine / vol-delete / 配置済みISOやqcow2
# へのsudo rm 等) は意図的に実装していません。自身が作成した一時ファイル
# (ISO_TMP, sudo mktemp で作成) のみ、trapで確実に削除します。
# また、既存の "debian13" ドメインなど、mypocketos-test 以外への操作も
# 一切行いません。
# VMやISOを更新・削除したい場合は、本スクリプトを直接いじらず、
# scripts/update-test-iso.sh や virsh/virt-manager を使ってください。
#
# 参照: virt-install(1), virsh(1) (Debian 13 trixie, virt-install 5.0.0,
#       libvirt/virsh 11.3.0 で --disk=?, --graphics=?, --channel=?,
#       --boot=?, --network=?, --print-xml --dry-run の実出力を確認して作成)

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
VM_MEMORY_MIB=2048
VM_VCPUS=2
LIBVIRT_URI="qemu:///system"
LIBVIRT_NETWORK="default"
LIBVIRT_OWNER="libvirt-qemu:libvirt-qemu"
IMAGES_DIR="/var/lib/libvirt/images"
DISK_PATH="${IMAGES_DIR}/${VM_NAME}.qcow2"
DISK_SIZE_GIB=16
ISO_SRC="${PROJECT_ROOT}/live-image-amd64.hybrid.iso"
ISO_DEST="${IMAGES_DIR}/MyPocketOS-dev.iso"

echo "== 処理対象の絶対パス =="
echo "プロジェクトルート : ${PROJECT_ROOT}"
echo "ISOソース          : ${ISO_SRC}"
echo "ISO配置先          : ${ISO_DEST}"
echo "仮想ディスク        : ${DISK_PATH}"
echo "VM名                : ${VM_NAME}"
echo "libvirt接続先       : ${LIBVIRT_URI}"
echo

# ---- 必要コマンドの存在確認 -------------------------------------------------
for cmd in virt-install virsh sudo sha256sum; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        echo "エラー: 必要なコマンド '${cmd}' が見つかりません。" >&2
        exit 1
    fi
done

# ---- defaultネットワークが active であることの確認 (勝手に起動しない) -------
# LC_ALL=C: virsh の出力はロケールによって日本語化され (例: "起動中:"、
# "実行中")、文字列一致による判定が壊れるため、判定に使うvirsh呼び出しは
# 常にC (POSIX/英語) ロケールで実行する。
# 出力は一旦変数に captured してから、パイプを使わずヒアストリングで grep
# へ渡す (virsh の出力へ直接 `| grep -q` すると、grep が最初の一致行で
# 早期に読み込みを終了して virsh 側がSIGPIPEを受け、pipefail 下でパイプ
# ライン全体が誤って失敗扱いになることがあるため)。
NET_INFO="$(LC_ALL=C virsh --connect "${LIBVIRT_URI}" net-info "${LIBVIRT_NETWORK}" 2>/dev/null || true)"
if ! grep -q '^Active:[[:space:]]*yes' <<< "${NET_INFO}"; then
    echo "エラー: libvirt の '${LIBVIRT_NETWORK}' ネットワークが active ではありません。" >&2
    echo "        次のコマンドで起動してから再実行してください:" >&2
    echo "          virsh --connect ${LIBVIRT_URI} net-start ${LIBVIRT_NETWORK}" >&2
    exit 1
fi

# ---- 既存ドメインの確認 (存在すれば中止。他のVMには触れない) ---------------
if LC_ALL=C virsh --connect "${LIBVIRT_URI}" dominfo "${VM_NAME}" >/dev/null 2>&1; then
    echo "エラー: ドメイン '${VM_NAME}' は既に存在します。作成を中止します。" >&2
    echo "        既存のVMを更新したい場合は scripts/update-test-iso.sh を使ってください。" >&2
    exit 1
fi

# ---- 既存の仮想ディスクの確認 (存在すれば中止) ------------------------------
if [ -e "${DISK_PATH}" ]; then
    echo "エラー: 仮想ディスク '${DISK_PATH}' は既に存在します。作成を中止します。" >&2
    exit 1
fi

# ---- ISOソースが通常ファイルであることの確認 --------------------------------
if [ ! -f "${ISO_SRC}" ]; then
    echo "エラー: ISOソース '${ISO_SRC}' が通常ファイルとして見つかりません。" >&2
    echo "        先に ./scripts/build.sh でISOをビルドしてください。" >&2
    exit 1
fi

# ---- ISO配置先の型チェック (存在する場合、通常ファイル以外なら中止) --------
if [ -e "${ISO_DEST}" ] && [ ! -f "${ISO_DEST}" ]; then
    echo "エラー: ISO配置先 '${ISO_DEST}' が通常ファイルではありません。想定外の状態のため中止します。" >&2
    exit 1
fi

# ---- ISOをlibvirt側へコピー (固定名を直接上書きせず、一時ファイル経由で -----
# ---- 検証後に置き換える。想定外の既存ファイルを直接上書きしない) -----------
# cleanup_iso_tmp が削除するのは、このブロックで sudo mktemp によって
# 自身が作成した一時ファイル (ISO_TMP) のみ。VM・仮想ディスク・配置済み
# ISO (ISO_DEST) 等の永続資産は削除しない。
ISO_TMP=""
cleanup_iso_tmp() {
    if [ -n "${ISO_TMP}" ]; then
        sudo rm -f -- "${ISO_TMP}"
    fi
}
trap cleanup_iso_tmp EXIT INT TERM HUP

echo "== ISOをコピーしています: ${ISO_SRC} -> ${ISO_DEST} =="
ISO_TMP="$(sudo mktemp "${ISO_DEST}.XXXXXX")"
sudo cp -- "${ISO_SRC}" "${ISO_TMP}"
sudo chmod 0644 "${ISO_TMP}"
sudo chown "${LIBVIRT_OWNER}" "${ISO_TMP}"

SRC_SHA256="$(sha256sum -- "${ISO_SRC}" | cut -d' ' -f1)"
TMP_SHA256="$(sudo sha256sum -- "${ISO_TMP}" | cut -d' ' -f1)"

if [ "${SRC_SHA256}" != "${TMP_SHA256}" ]; then
    echo "エラー: コピーしたISOのSHA-256がソースと一致しません。VMは作成しません。" >&2
    echo "        ソース: ${SRC_SHA256}" >&2
    echo "        コピー: ${TMP_SHA256}" >&2
    exit 1
fi

sudo mv -f -- "${ISO_TMP}" "${ISO_DEST}"
ISO_TMP=""

echo "ISOのコピーとSHA-256検証が完了しました (${SRC_SHA256})。"
echo

# ---- 永続VMの作成 (--import で Live ISO を起動。インストーラは使わない) ----
echo "== VM '${VM_NAME}' を作成します =="
virt-install \
    --connect "${LIBVIRT_URI}" \
    --name "${VM_NAME}" \
    --memory "${VM_MEMORY_MIB}" \
    --vcpus "${VM_VCPUS}" \
    --cpu host-passthrough \
    --os-variant debian13 \
    --disk "path=${DISK_PATH},size=${DISK_SIZE_GIB},format=qcow2,bus=virtio,boot.order=2" \
    --disk "device=cdrom,path=${ISO_DEST},boot.order=1" \
    --boot bootmenu.enable=yes \
    --network "network=${LIBVIRT_NETWORK},model=virtio" \
    --graphics spice,listen=127.0.0.1,clipboard.copypaste=yes \
    --channel spicevmc \
    --video virtio \
    --sound model=ich9 \
    --import \
    --noautoconsole

echo
echo "VM '${VM_NAME}' を作成しました。virt-manager から画面を開いて確認してください。"
