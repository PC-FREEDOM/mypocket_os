#!/usr/bin/env bash
#
# create-test-vm.sh - MyPocketOS 検証用 QEMU/KVM VM の作成 (BIOS/UEFI)
#
# 開発ホスト (Debian, virt-install/virsh/QEMU/KVM がセットアップ済みの環境) で
# 実行するスクリプトです。MyPocketOSのISO内では実行しません。
#
# 使い方:
#   ./scripts/create-test-vm.sh base                        BIOS版 (mypocketos-test) をBase版ISOで作成
#   ./scripts/create-test-vm.sh standard                    同上をStandard版ISOで作成
#   ./scripts/create-test-vm.sh --firmware uefi base        UEFI版 (mypocketos-uefi-test) をBase版ISOで作成
#   ./scripts/create-test-vm.sh --firmware uefi standard    同上をStandard版ISOで作成
#
# このスクリプトは「作成」専用です。VM・仮想ディスク・配置済みISOといった
# 永続資産を削除する機能 (virsh undefine / vol-delete / 配置済みISOやqcow2
# へのsudo rm 等) は意図的に実装していません。自身が作成した一時ファイル
# (ISO_TMP, sudo mktemp で作成) のみ、trapで確実に削除します。
# また、既存のドメイン (BIOS/UEFI問わず) への操作も、共有ISOの安全確認
# (後述) 以外では一切行いません。
# VMやISOを更新・削除したい場合は、本スクリプトを直接いじらず、
# scripts/update-test-iso.sh や virsh/virt-manager を使ってください。
#
# 共有ISOの安全確認について:
# BIOS版・UEFI版は同じ /var/lib/libvirt/images/MyPocketOS-dev.iso を
# CD-ROMとして共有する。このISOを上書きする前に、このISOを参照している
# 全ドメインを動的に検出し (mypocketos-test / mypocketos-uefi-test という
# 名前をハードコードしない)、参照ドメインが1つでも「停止 (shut off)」
# 以外の状態であれば、ISOのコピーもVMの作成も行わない。
#
# 参照: virt-install(1), virsh(1) (Debian 13 trixie, virt-install 5.0.0,
#       libvirt/virsh 11.3.0 で --disk=?, --graphics=?, --channel=?,
#       --boot=?, --network=?, --tpm=?, --print-xml --dry-run の実出力を
#       確認して作成)

set -euo pipefail

# ---- 引数解析 (case文で限定。ネットワーク確認・sudo・ISO操作より前に行う) --
usage() {
    echo "usage: $(basename "${BASH_SOURCE[0]}") [--firmware bios|uefi] {base|standard}" >&2
    exit 2
}

FIRMWARE="bios"
EDITION=""

while [ $# -gt 0 ]; do
    case "$1" in
        --firmware)
            [ $# -ge 2 ] || usage
            case "$2" in
                bios|uefi)
                    FIRMWARE="$2"
                    ;;
                *)
                    usage
                    ;;
            esac
            shift 2
            ;;
        base | standard)
            [ -z "${EDITION}" ] || usage
            EDITION="$1"
            shift
            ;;
        *)
            usage
            ;;
    esac
done

if [ -z "${EDITION}" ]; then
    usage
fi

# ---- Debianホスト専用であることの確認 --------------------------------------
if [ ! -r /etc/os-release ] || ! grep -q '^ID=debian$' /etc/os-release; then
    echo "エラー: このスクリプトは Debian の開発ホスト専用です。" >&2
    echo "        (/etc/os-release に ID=debian が見つかりません)" >&2
    exit 1
fi

# ---- パスの解決 (スクリプト自身の位置からプロジェクトルートを決定) ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

case "${FIRMWARE}" in
    bios)
        VM_NAME="mypocketos-test"
        FIRMWARE_LABEL="BIOS"
        BOOT_ARGS=(--boot bootmenu.enable=yes)
        TPM_ARGS=()
        ;;
    uefi)
        VM_NAME="mypocketos-uefi-test"
        FIRMWARE_LABEL="UEFI"
        BOOT_ARGS=(--boot uefi,bootmenu.enable=yes)
        TPM_ARGS=(--tpm none)
        ;;
esac

VM_MEMORY_MIB=2048
VM_VCPUS=2
LIBVIRT_URI="qemu:///system"
LIBVIRT_NETWORK="default"
LIBVIRT_OWNER="libvirt-qemu:libvirt-qemu"
IMAGES_DIR="/var/lib/libvirt/images"
DISK_PATH="${IMAGES_DIR}/${VM_NAME}.qcow2"
DISK_SIZE_GIB=16
ISO_SRC="${PROJECT_ROOT}/mypocketos-${EDITION}-amd64.hybrid.iso"
ISO_DEST="${IMAGES_DIR}/MyPocketOS-dev.iso"

echo "== 処理対象の絶対パス =="
echo "edition             : ${EDITION}"
echo "プロジェクトルート : ${PROJECT_ROOT}"
echo "ISOソース          : ${ISO_SRC}"
echo "ISO配置先          : ${ISO_DEST}"
echo "仮想ディスク        : ${DISK_PATH}"
echo "VM名                : ${VM_NAME}"
echo "ファームウェア      : ${FIRMWARE_LABEL}"
echo "libvirt接続先       : ${LIBVIRT_URI}"
echo

# ---- 必要コマンドの存在確認 -------------------------------------------------
for cmd in virt-install virsh sudo sha256sum awk; do
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
    echo "        先に ./scripts/build.sh ${EDITION} でISOをビルドしてください。" >&2
    exit 1
fi

# ---- ISO配置先の型チェック (存在する場合、通常ファイル以外なら中止) --------
if [ -e "${ISO_DEST}" ] && [ ! -f "${ISO_DEST}" ]; then
    echo "エラー: ISO配置先 '${ISO_DEST}' が通常ファイルではありません。想定外の状態のため中止します。" >&2
    exit 1
fi

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
    echo "エラー: 共有ISOを利用しているドメインの確認に失敗しました。作成を中止します。" >&2
    exit 1
fi

if [ -n "${SHARED_ISO_USERS}" ]; then
    if ! check_all_shut_off "${SHARED_ISO_USERS}"; then
        echo "エラー: 共有ISO ('${ISO_DEST}') を利用している一部のドメインが停止状態ではないため、作成を中止します。" >&2
        exit 1
    fi
    echo "共有ISO利用ドメイン (すべて停止中):"
    while IFS= read -r _domain; do
        [ -z "${_domain}" ] && continue
        echo "  - ${_domain}"
    done <<< "${SHARED_ISO_USERS}"
else
    echo "共有ISOを利用しているドメインはありません。"
fi
echo

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
VIRT_INSTALL_ARGS=(
    --connect "${LIBVIRT_URI}"
    --name "${VM_NAME}"
    --memory "${VM_MEMORY_MIB}"
    --vcpus "${VM_VCPUS}"
    --cpu host-passthrough
    --os-variant debian13
    --disk "path=${DISK_PATH},size=${DISK_SIZE_GIB},format=qcow2,bus=virtio,boot.order=2"
    --disk "device=cdrom,path=${ISO_DEST},boot.order=1"
    "${BOOT_ARGS[@]}"
    --network "network=${LIBVIRT_NETWORK},model=virtio"
    --graphics spice,listen=127.0.0.1,clipboard.copypaste=yes
    --channel spicevmc
    --video virtio
    --sound model=ich9
    "${TPM_ARGS[@]}"
    --import
    --noautoconsole
)

echo "== VM '${VM_NAME}' (${FIRMWARE_LABEL}) を作成します =="
virt-install "${VIRT_INSTALL_ARGS[@]}"

echo
echo "VM '${VM_NAME}' (${FIRMWARE_LABEL}) を作成しました。virt-manager から画面を開いて確認してください。"
