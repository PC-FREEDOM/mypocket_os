#!/bin/sh
#
# scripts/create-test-vm.sh に対するテスト。実virsh・実virt-install・
# 実sudo・実VM作成は一切行わない。
#
# create-test-vm.sh は DISK_PATH ("/var/lib/libvirt/images/${VM_NAME}.qcow2")
# を固定のIMAGES_DIRから解決する設計であり (今回この点は変更していない)、
# この開発ホストには既存の実VM用ディスク (mypocketos-test.qcow2 等) が
# 既に存在するため、それらを一切操作せずに「ISO不存在ならvirt-installまで
# 到達しない」ことを最後まで実行して確認することはできない (実在する
# ディスクの存在確認で、より早い段階で安全側に停止してしまうため。これ自体は
# 正しい既存の安全動作であり、今回壊していない)。
#
# そのため、このテストは以下の2段構成にする。
#
# 1. 引数解析 (edition必須化・--firmwareとの併用) は、virsh呼び出しより
#    前に完結するため、実スクリプトを直接実行して検証する。受理された
#    引数の組み合わせについては、スクリプトが出力する診断ブロック
#    ("== 処理対象の絶対パス ==") の内容 (edition・ISOソース・VM名・
#    ファームウェア) を見て、editionからISO名・VM名への解決が正しいことを
#    確認する (この診断ブロックはvirsh呼び出しより前に出力されるため、
#    実環境のVM/ディスク状態に一切依存しない)。
# 2. 「ISO不存在ならvirt-installへ進まない」「不正editionならvirsh等を
#    呼ばない」という安全性は、上記の環境制約により実行時には確認できない
#    ため、静的な構造確認 (ISO存在チェックがvirt-install呼び出しより前に
#    存在すること) で代替する。
#
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROD_SCRIPT="${REPO_ROOT}/scripts/create-test-vm.sh"

PASS=0
FAIL=0

check() {
	desc="$1"
	shift
	if "$@"; then
		PASS=$((PASS + 1))
	else
		echo "FAIL: ${desc}" >&2
		FAIL=$((FAIL + 1))
	fi
}

MOCKBIN="$(mktemp -d)"
trap 'rm -rf "${MOCKBIN}"' EXIT

# virsh: 呼び出し自体を記録するだけの最小モック (何をされても失敗として
# 応答する。「不正editionならvirsh等を呼ばない」を検証する用途のみに使う)。
CALLS_FILE="$(mktemp)"
cat >"${MOCKBIN}/virsh" <<EOF
#!/bin/sh
echo "\$*" >>"${CALLS_FILE}"
exit 1
EOF
chmod +x "${MOCKBIN}/virsh"

run_create() {
	: >"${CALLS_FILE}"
	PATH="${MOCKBIN}:${PATH}" "${PROD_SCRIPT}" "$@"
}

# ==============================================================================
# 引数検証: 拒否されるべき組み合わせ (usage()でexit 2、virshは一切呼ばれない)
# ==============================================================================
OUT="$(mktemp)"

run_create >"${OUT}" 2>&1 && rc=0 || rc=$?
check "no args -> exit 2" test "${rc}" -eq 2
check "no args -> virsh never called" sh -c '[ ! -s "$1" ]' _ "${CALLS_FILE}"

run_create creator >"${OUT}" 2>&1 && rc=0 || rc=$?
check "invalid edition 'creator' -> exit 2" test "${rc}" -eq 2
check "invalid edition -> virsh never called" sh -c '[ ! -s "$1" ]' _ "${CALLS_FILE}"

run_create base standard >"${OUT}" 2>&1 && rc=0 || rc=$?
check "two editions -> exit 2" test "${rc}" -eq 2
check "two editions -> virsh never called" sh -c '[ ! -s "$1" ]' _ "${CALLS_FILE}"

run_create --firmware bios >"${OUT}" 2>&1 && rc=0 || rc=$?
check "--firmware without edition -> exit 2" test "${rc}" -eq 2

run_create --firmware xen base >"${OUT}" 2>&1 && rc=0 || rc=$?
check "invalid firmware value -> exit 2" test "${rc}" -eq 2
check "invalid firmware value -> virsh never called" sh -c '[ ! -s "$1" ]' _ "${CALLS_FILE}"

run_create --firmware >"${OUT}" 2>&1 && rc=0 || rc=$?
check "--firmware with no value -> exit 2" test "${rc}" -eq 2

# ==============================================================================
# 引数検証: 受理されるべき組み合わせ。virsh呼び出しより前に出力される
# 診断ブロックの内容で、edition -> ISO名/VM名の解決が正しいことを確認する。
# 診断ブロックより後の処理 (virsh net-info以降) は環境依存のため、ここでは
# 終了コードを問わない。
# ==============================================================================
run_create base >"${OUT}" 2>&1 || :
check "base (BIOS既定) -> shows edition: base" grep -qx "edition             : base" "${OUT}"
check "base (BIOS既定) -> shows ISO mypocketos-base-amd64.hybrid.iso" \
	grep -q "mypocketos-base-amd64.hybrid.iso" "${OUT}"
check "base (BIOS既定) -> VM名はmypocketos-test" grep -q "VM名  *: mypocketos-test$" "${OUT}"

run_create standard >"${OUT}" 2>&1 || :
check "standard (BIOS既定) -> shows edition: standard" grep -qx "edition             : standard" "${OUT}"
check "standard (BIOS既定) -> shows ISO mypocketos-standard-amd64.hybrid.iso" \
	grep -q "mypocketos-standard-amd64.hybrid.iso" "${OUT}"

run_create --firmware uefi base >"${OUT}" 2>&1 || :
check "--firmware uefi base -> shows edition: base" grep -qx "edition             : base" "${OUT}"
check "--firmware uefi base -> shows ISO mypocketos-base-amd64.hybrid.iso" \
	grep -q "mypocketos-base-amd64.hybrid.iso" "${OUT}"
check "--firmware uefi base -> VM名はmypocketos-uefi-test" grep -q "VM名  *: mypocketos-uefi-test$" "${OUT}"

run_create --firmware uefi standard >"${OUT}" 2>&1 || :
check "--firmware uefi standard -> shows edition: standard" grep -qx "edition             : standard" "${OUT}"
check "--firmware uefi standard -> shows ISO mypocketos-standard-amd64.hybrid.iso" \
	grep -q "mypocketos-standard-amd64.hybrid.iso" "${OUT}"

# 引数の順序が逆 (edition -> --firmware) でも同じ結果になること
# (edition引数追加によって既存--firmwareオプションの解釈が壊れていないこと)
run_create base --firmware uefi >"${OUT}" 2>&1 || :
check "base --firmware uefi (順序が逆) -> shows edition: base" \
	grep -qx "edition             : base" "${OUT}"
check "base --firmware uefi (順序が逆) -> VM名はmypocketos-uefi-test" \
	grep -q "VM名  *: mypocketos-uefi-test$" "${OUT}"

run_create --firmware bios base >"${OUT}" 2>&1 || :
check "--firmware bios base (明示的にBIOS指定) -> VM名はmypocketos-test" \
	grep -q "VM名  *: mypocketos-test$" "${OUT}"

rm -f -- "${OUT}"

# ==============================================================================
# 静的な構造確認: ISO不存在チェックがvirt-install呼び出しより前に存在する
# こと (実行時確認は環境制約により上記コメントのとおり代替する)。
# ==============================================================================
check "ISO_SRC existence check is present" \
	grep -qF 'if [ ! -f "${ISO_SRC}" ]; then' "${PROD_SCRIPT}"
ISO_CHECK_LINE="$(grep -n 'if \[ ! -f "\${ISO_SRC}" \]; then' "${PROD_SCRIPT}" | head -n1 | cut -d: -f1)"
VIRT_INSTALL_LINE="$(grep -n '^virt-install ' "${PROD_SCRIPT}" | head -n1 | cut -d: -f1)"
check "ISO_SRC existence check precedes virt-install invocation" \
	test "${ISO_CHECK_LINE}" -lt "${VIRT_INSTALL_LINE}"

echo "SCENARIOS=$((PASS + FAIL)) PASS=${PASS} FAIL=${FAIL}"
[ "${FAIL}" -eq 0 ]
