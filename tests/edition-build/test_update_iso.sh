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
# 「Debianホスト専用」を要求する設計 (/etc/os-release のID=debian判定、
# production側のこの制約自体は今回変更していない) を持つため、
# sandboxへコピーした後のスクリプトだけを対象に、実ホストの
# /etc/os-release ではなくsandbox内fixture (ID=debianのみを持つ最小限の
# ファイル) を読むようinstrumentする。これにより、テスト実行ホスト自身が
# Debianでなくても (GitHub ActionsのUbuntu runner上でも) この検証を実行
# できる。IMAGES_DIR ("/var/lib/libvirt/images") は固定値のままであり
# 変更していないため、ISO不存在の検証はISO_DESTへの操作へ到達する前に
# 必ず停止することを利用し、実libvirtディレクトリには一切書き込まない。
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
#
# production script (scripts/update-test-iso.sh) 自身が持つDebianホスト
# 専用の判定 (/etc/os-release の ID=debian) は変更しない。このテストでは、
# sandboxへコピーしたproduction scriptのコピーだけを対象に、実ホストの
# /etc/os-release ではなくsandbox内のfixtureファイルを読むよう
# instrumentすることで、テスト実行ホスト自身のOSに関わらず (GitHub
# ActionsのUbuntu runner上でも) この検証を実行できるようにする。対象は
# 実際のファイル読み取りに使われている行1箇所のみとし、エラーメッセージ
# 内の "/etc/os-release" という説明文字列 (この判定に失敗した場合にのみ
# 表示される、productionのメッセージそのもの) は変更しない。
# ==============================================================================
SANDBOX="$(mktemp -d)"
trap 'rm -rf "${SANDBOX}"' EXIT

MOCKBIN="${SANDBOX}/mockbin"
mkdir -p "${MOCKBIN}" "${SANDBOX}/scripts"
cp -- "${PROD_SCRIPT}" "${SANDBOX}/scripts/update-test-iso.sh"
chmod +x "${SANDBOX}/scripts/update-test-iso.sh"

# Debianホスト判定行 (/etc/os-release への実ファイル読み取りを行っている
# 箇所) が想定どおり1件だけ存在することを確認したうえで、sandbox内
# fixtureを読むよう置換する。sedではなくawkの完全一致比較を用いることで、
# この行に含まれる正規表現特殊文字 ([ ] $ ' ^ !) のエスケープ問題を
# 避ける。production側の判定ロジック自体 (ID=debianでなければ拒否する)
# は変更しない。
OS_RELEASE_CHECK_LINE="if [ ! -r /etc/os-release ] || ! grep -q '^ID=debian\$' /etc/os-release; then"
os_release_check_count="$(grep -cF "${OS_RELEASE_CHECK_LINE}" "${SANDBOX}/scripts/update-test-iso.sh")" || os_release_check_count=0
if [ "${os_release_check_count}" -ne 1 ]; then
	echo "FAIL: sandboxed copy内のos-release判定行の出現件数が想定 (1件) と一致しません (検出: ${os_release_check_count}件)。production script側が変更された可能性があります。" >&2
	exit 1
fi

OS_RELEASE_FIXTURE="${SANDBOX}/etc/os-release"
mkdir -p "${SANDBOX}/etc"
# production側が実際に必要としている情報はID=debianのみのため、
# バージョン番号等の不要な情報は持たせない最小限のfixtureとする。
printf 'ID=debian\n' >"${OS_RELEASE_FIXTURE}"

OS_RELEASE_CHECK_LINE_NEW="if [ ! -r \"${OS_RELEASE_FIXTURE}\" ] || ! grep -q '^ID=debian\$' \"${OS_RELEASE_FIXTURE}\"; then"
awk -v old="${OS_RELEASE_CHECK_LINE}" -v new="${OS_RELEASE_CHECK_LINE_NEW}" '
	$0 == old { print new; next }
	{ print }
' "${SANDBOX}/scripts/update-test-iso.sh" >"${SANDBOX}/scripts/update-test-iso.sh.new"
mv -- "${SANDBOX}/scripts/update-test-iso.sh.new" "${SANDBOX}/scripts/update-test-iso.sh"
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
