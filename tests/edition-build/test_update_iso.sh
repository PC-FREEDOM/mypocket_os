#!/bin/sh
#
# scripts/update-test-iso.sh に対するモックテスト。実virsh・実sudoは
# 一切起動しない。実ISOコピー・実libvirt操作は行わない。
#
# 引数検証 (edition未指定・不正値) は、update-test-iso.sh自身の設計上
# Debianホスト確認より前に行われるため、どの環境でも直接実行して検証する。
#
# ISO_SRC解決・「ISO不存在ならコピー前に停止」の検証は、update-test-iso.sh
# のコピーをsandbox (mktemp -d) へ配置し、モックvirshで共有ISO利用ドメイン
# の安全確認を通過させたうえで実行する。update-test-iso.sh自身が
# 「Debianホスト専用」を要求する設計のため、この部分はDebian開発ホストでの
# 実行を前提とする (production側のこの制約自体は今回変更していない)。
# IMAGES_DIR ("/var/lib/libvirt/images") は固定値のままであり変更していない
# ため、ISO不存在の検証はISO_DESTへの操作へ到達する前に必ず停止することを
# 利用し、実libvirtディレクトリには一切書き込まない。
#
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROD_SCRIPT="${REPO_ROOT}/scripts/update-test-iso.sh"

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

# ==============================================================================
# 引数検証 (Debianホスト確認より前で完結するため、実スクリプトを直接
# 実行して検証する。virsh等のモックは不要)
# ==============================================================================
"${PROD_SCRIPT}" >/tmp/edition-build-noargs.$$ 2>&1 && rc=0 || rc=$?
check "no args -> exit 2" test "${rc}" -eq 2
rm -f "/tmp/edition-build-noargs.$$"

"${PROD_SCRIPT}" creator >/tmp/edition-build-badedition.$$ 2>&1 && rc=0 || rc=$?
check "invalid edition 'creator' -> exit 2" test "${rc}" -eq 2
rm -f "/tmp/edition-build-badedition.$$"

"${PROD_SCRIPT}" base standard >/tmp/edition-build-extra.$$ 2>&1 && rc=0 || rc=$?
check "extra 2nd arg -> exit 2" test "${rc}" -eq 2
rm -f "/tmp/edition-build-extra.$$"

# ==============================================================================
# ISO_SRC解決 / 「ISO不存在ならコピー前に停止」の検証
# (Debian開発ホストであることを前提とする。production自身の制約でもある)
# ==============================================================================
if [ -r /etc/os-release ] && grep -q '^ID=debian$' /etc/os-release; then
	SANDBOX="$(mktemp -d)"
	trap 'rm -rf "${SANDBOX}"' EXIT

	MOCKBIN="${SANDBOX}/mockbin"
	mkdir -p "${MOCKBIN}" "${SANDBOX}/scripts"
	cp -- "${PROD_SCRIPT}" "${SANDBOX}/scripts/update-test-iso.sh"
	chmod +x "${SANDBOX}/scripts/update-test-iso.sh"

	# virsh: 常に1ドメイン ("test-domain") が共有ISO
	# (/var/lib/libvirt/images/MyPocketOS-dev.iso, IMAGES_DIRは
	# production側で固定値のため変更していない) を参照し、shut offで
	# あるという状態を返す最小モック。
	cat >"${MOCKBIN}/virsh" <<'EOF'
#!/bin/sh
set -eu
case "$*" in
	*"list --all --name"*)
		echo "test-domain"
		;;
	*"domblklist test-domain --inactive --details"*)
		echo "vda    /var/lib/libvirt/images/MyPocketOS-dev.iso"
		;;
	*"domstate test-domain"*)
		echo "shut off"
		;;
	*)
		exit 1
		;;
esac
EOF
	chmod +x "${MOCKBIN}/virsh"

	cat >"${MOCKBIN}/sudo" <<'EOF'
#!/bin/sh
exec "$@"
EOF
	chmod +x "${MOCKBIN}/sudo"

	run_update() {
		(
			cd "${SANDBOX}"
			PATH="${MOCKBIN}:${PATH}" ./scripts/update-test-iso.sh "$@"
		)
	}

	OUT="$(mktemp)"
	run_update base >"${OUT}" 2>&1 && rc=0 || rc=$?
	check "base, ISO不存在 -> non-zero exit" test "${rc}" -ne 0
	check "base, ISO不存在 -> error names mypocketos-base-amd64.hybrid.iso" \
		grep -q "mypocketos-base-amd64.hybrid.iso" "${OUT}"
	check "base, ISO不存在 -> did not touch shared ISO_DEST" \
		sh -c '! grep -q "更新しています" "$1"' _ "${OUT}"

	run_update standard >"${OUT}" 2>&1 && rc=0 || rc=$?
	check "standard, ISO不存在 -> non-zero exit" test "${rc}" -ne 0
	check "standard, ISO不存在 -> error names mypocketos-standard-amd64.hybrid.iso" \
		grep -q "mypocketos-standard-amd64.hybrid.iso" "${OUT}"

	rm -f "${OUT}"
else
	echo "SKIP: Debian開発ホストではないため、ISO_SRC解決の実行時検証は省略します" >&2
fi

# ==============================================================================
# 構造的な回帰確認: SHA-256照合ロジック (SRC_SHA256/TMP_SHA256/DEST_SHA256の
# 比較) が今回の変更で失われていないこと。update-test-iso.shのこの部分は
# 今回一切変更していない (edition引数の追加とISO_SRC/メッセージの3行のみ
# 変更) ため、静的な存在確認で十分とする。
# ==============================================================================
check "SHA-256 comparison (SRC vs TMP) still present" \
	grep -q 'if \[ "\${SRC_SHA256}" != "\${TMP_SHA256}" \]' "${PROD_SCRIPT}"
check "SHA-256 comparison (SRC vs DEST) still present" \
	grep -q 'if \[ "\${SRC_SHA256}" != "\${DEST_SHA256}" \]' "${PROD_SCRIPT}"
check "trap-based tmp cleanup still present" \
	grep -q 'trap cleanup_iso_tmp EXIT INT TERM HUP' "${PROD_SCRIPT}"
check "shared-ISO domain shut-off safety check still present" \
	grep -q 'check_all_shut_off' "${PROD_SCRIPT}"

echo "SCENARIOS=$((PASS + FAIL)) PASS=${PASS} FAIL=${FAIL}"
[ "${FAIL}" -eq 0 ]
