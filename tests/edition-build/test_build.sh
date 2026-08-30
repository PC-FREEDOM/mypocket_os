#!/bin/sh
#
# scripts/build.sh に対するモックテスト。実 lb・sudo は一切起動しない
# (sandbox配下のモックへ差し替える)。実ISOビルド・実chroot構築は行わない。
#
# scripts/build.sh 自体は改変せず、sandbox (mktemp -d) へコピーしたうえで
# 実行する。sandbox配下は「scripts/build.sh」「config/package-lists.d/」
# 「config/package-lists/ (空)」という、実リポジトリと同じ相対構造を再現する
# (build.sh が `cd "$(dirname "$0")/.."` でsandboxルートを自身のプロジェクト
# ルートとして扱うため)。
#
# モックlbは、単なる呼び出し記録に留めず、実lbの
# 「config/common に保存したLB_IMAGE_NAMEを次のlb config呼び出しまで
# 保持し続け、lb cleanがその時点の値を使ってISOを削除する」という挙動を
# sandbox内の状態ファイル (config/common相当) で再現する。この状態
# ファイルは1回のsandbox内で複数回build.shを実行しても持続するため、
# 「前回editionのビルドが残したLB_IMAGE_NAMEが、今回のeditionビルド開始
# 時点でどう扱われるか」を実ビルドと同じ形で検証できる (実機で発見された
# Base ISO誤削除バグの再現・fix確認に必須)。
#
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROD_BUILD_SH="${REPO_ROOT}/scripts/build.sh"

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

SANDBOX="$(mktemp -d)"
trap 'rm -rf "${SANDBOX}"' EXIT

MOCKBIN="${SANDBOX}/mockbin"
mkdir -p "${MOCKBIN}" \
	"${SANDBOX}/scripts" \
	"${SANDBOX}/config/package-lists.d" \
	"${SANDBOX}/config/package-lists"

cp -- "${PROD_BUILD_SH}" "${SANDBOX}/scripts/build.sh"
chmod +x "${SANDBOX}/scripts/build.sh"
cp -- "${REPO_ROOT}/config/package-lists.d/mypocketos-common.list.chroot" \
	"${SANDBOX}/config/package-lists.d/"
cp -- "${REPO_ROOT}/config/package-lists.d/mypocketos-standard.list.chroot" \
	"${SANDBOX}/config/package-lists.d/"

# config/common相当の永続状態ファイル。sandbox内で複数回build.shを実行
# しても保持される (実際のlive-buildがconfig/commonを次回invocationまで
# 保持するのと同じ)。scenarioごとにreset_lb_state/seed_lb_stateで明示的に
# 制御する。
LB_STATE_FILE="${SANDBOX}/config/common"

reset_lb_state() {
	rm -f -- "${LB_STATE_FILE}"
}

# 「前回、指定editionでビルドが行われ、config/commonにそのLB_IMAGE_NAMEが
# 残っている」状態を再現する。
seed_lb_state() {
	printf 'LB_IMAGE_NAME="mypocketos-%s"\n' "$1" >"${LB_STATE_FILE}"
}

# ---- モックコマンド --------------------------------------------------------
# sudo: 単純にそのまま実行するだけ (モックlbへ委譲するため)。
cat >"${MOCKBIN}/sudo" <<'EOF'
#!/bin/sh
exec "$@"
EOF
chmod +x "${MOCKBIN}/sudo"

# lb: clean/config/buildの3サブコマンドを扱う。呼び出し順序・引数・
# 「lb clean実行時点でconfig/common相当に保持されているLB_IMAGE_NAME」を
# 1本の時系列ログ (MOCK_LB_CALLS_FILE) へ記録する。configはbuild.sh内で
# 2回呼ばれる (clean前後) ため、1回目/2回目を区別した失敗注入もできる
# ようにしている。
#
# 環境変数で挙動を制御する:
#   MOCK_LB_CLEAN_EXIT
#   MOCK_LB_CONFIG_EXIT (MOCK_LB_CONFIG_FAIL_ON_CALL未指定なら毎回この
#     終了コードを返す。指定時は、その回数目のconfig呼び出しのみに適用)
#   MOCK_LB_CONFIG_FAIL_ON_CALL (1 または 2)
#   MOCK_LB_BUILD_EXIT
#   MOCK_LB_BUILD_SLEEP_SECONDS (SIGINTテスト用)
#   MOCK_LB_BUILD_CREATE_ISO=0 でISO成果物を作らない (存在確認の失敗テスト用)
#   MOCK_ISO_PATH ("lb build"成功時に作成する空ファイルのパス)
#   MOCK_LB_CALLS_FILE / MOCK_STAGED_LISTS_FILE
#   MOCK_LB_CONFIG_CALL_COUNT_FILE (このbuild.sh 1回の実行内でのconfig
#     呼び出し回数カウンタ。run_build毎に新規・0初期化する)
#   LB_STATE_FILE (config/common相当。sandbox内で永続、テスト側で管理)
cat >"${MOCKBIN}/lb" <<'EOF'
#!/bin/sh
set -eu
case "$1" in
	clean)
		if [ -f "${LB_STATE_FILE}" ]; then
			CUR="$(sed -n 's/^LB_IMAGE_NAME="\(.*\)"$/\1/p' "${LB_STATE_FILE}")"
		else
			CUR="live-image"
		fi
		echo "clean used=${CUR}" >>"${MOCK_LB_CALLS_FILE}"
		rm -f -- "${CUR}"*.iso 2>/dev/null || true
		exit "${MOCK_LB_CLEAN_EXIT:-0}"
		;;
	config)
		shift
		N=0
		if [ -f "${MOCK_LB_CONFIG_CALL_COUNT_FILE}" ]; then
			N="$(cat "${MOCK_LB_CONFIG_CALL_COUNT_FILE}")"
		fi
		N=$((N + 1))
		echo "${N}" >"${MOCK_LB_CONFIG_CALL_COUNT_FILE}"

		# --image-name の値を状態ファイルへ反映する (実lb configが
		# config/commonへLB_IMAGE_NAMEを保存する挙動の再現)。
		IMAGE_NAME=""
		prev=""
		for a in "$@"; do
			if [ "${prev}" = "--image-name" ]; then
				IMAGE_NAME="${a}"
			fi
			prev="${a}"
		done
		if [ -n "${IMAGE_NAME}" ]; then
			printf 'LB_IMAGE_NAME="%s"\n' "${IMAGE_NAME}" >"${LB_STATE_FILE}"
		fi

		echo "config $*" >>"${MOCK_LB_CALLS_FILE}"
		ls "${SANDBOX_PACKAGE_LISTS_DIR}" >"${MOCK_STAGED_LISTS_FILE}" 2>/dev/null || : >"${MOCK_STAGED_LISTS_FILE}"

		if [ -n "${MOCK_LB_CONFIG_FAIL_ON_CALL:-}" ]; then
			if [ "${N}" -eq "${MOCK_LB_CONFIG_FAIL_ON_CALL}" ]; then
				exit "${MOCK_LB_CONFIG_EXIT:-1}"
			fi
			exit 0
		fi
		exit "${MOCK_LB_CONFIG_EXIT:-0}"
		;;
	build)
		echo "build" >>"${MOCK_LB_CALLS_FILE}"
		if [ -n "${MOCK_LB_BUILD_SLEEP_SECONDS:-}" ]; then
			sleep "${MOCK_LB_BUILD_SLEEP_SECONDS}"
		fi
		if [ "${MOCK_LB_BUILD_EXIT:-0}" -eq 0 ] && [ "${MOCK_LB_BUILD_CREATE_ISO:-1}" -eq 1 ]; then
			: >"${MOCK_ISO_PATH}"
		fi
		exit "${MOCK_LB_BUILD_EXIT:-0}"
		;;
	*)
		echo "mock lb: unexpected subcommand: $1" >&2
		exit 1
		;;
esac
EOF
chmod +x "${MOCKBIN}/lb"

# ---- 実行ヘルパー -----------------------------------------------------------
# run_build EDITION [ARG2...]
# 戻り値は呼び出し元でcheckする。標準出力・標準エラーは捨てる
# (異常終了メッセージの内容までは検証しない)。
CALLS_FILE=""
STAGED_LISTS_FILE=""

run_build() {
	CALLS_FILE="$(mktemp)"
	STAGED_LISTS_FILE="$(mktemp)"
	CONFIG_CALL_COUNT_FILE="$(mktemp)"
	: >"${CALLS_FILE}"
	: >"${STAGED_LISTS_FILE}"
	echo 0 >"${CONFIG_CALL_COUNT_FILE}"

	(
		cd "${SANDBOX}"
		PATH="${MOCKBIN}:${PATH}" \
			MOCK_LB_CALLS_FILE="${CALLS_FILE}" \
			MOCK_STAGED_LISTS_FILE="${STAGED_LISTS_FILE}" \
			MOCK_LB_CONFIG_CALL_COUNT_FILE="${CONFIG_CALL_COUNT_FILE}" \
			LB_STATE_FILE="${LB_STATE_FILE}" \
			SANDBOX_PACKAGE_LISTS_DIR="${SANDBOX}/config/package-lists" \
			MOCK_ISO_PATH="${SANDBOX}/mypocketos-${1:-base}-amd64.hybrid.iso" \
			./scripts/build.sh "$@"
	)
}

reset_iso_state() {
	rm -f -- "${SANDBOX}"/mypocketos-*-amd64.hybrid.iso
}

# ==============================================================================
# 引数検証
# ==============================================================================
reset_iso_state
reset_lb_state
run_build >/dev/null 2>&1 && rc=0 || rc=$?
check "no args -> exit 2" test "${rc}" -eq 2
check "no args -> lb was never called" sh -c '[ ! -s "$1" ]' _ "${CALLS_FILE}"

reset_iso_state
reset_lb_state
run_build base extra >/dev/null 2>&1 && rc=0 || rc=$?
check "extra 2nd arg -> exit 2" test "${rc}" -eq 2
check "extra 2nd arg -> lb was never called" sh -c '[ ! -s "$1" ]' _ "${CALLS_FILE}"

reset_iso_state
reset_lb_state
run_build creator >/dev/null 2>&1 && rc=0 || rc=$?
check "invalid edition 'creator' -> exit 2" test "${rc}" -eq 2
check "invalid edition -> lb was never called" sh -c '[ ! -s "$1" ]' _ "${CALLS_FILE}"

# ==============================================================================
# base: 正常系。呼び出し順序 (config -> clean -> config -> build) と、
# lb clean実行時点でのLB_IMAGE_NAMEが正しく更新済みであることを、1本の
# 時系列ログで検証する。
# ==============================================================================
reset_iso_state
reset_lb_state
run_build base >/dev/null 2>&1 && rc=0 || rc=$?
check "base -> exit 0" test "${rc}" -eq 0
check "base -> lb called in order (config, clean, config, build) with correct --image-name each time" \
	sh -c '[ "$(cat "$1")" = "$(printf "config --image-name mypocketos-base\nclean used=mypocketos-base\nconfig --image-name mypocketos-base\nbuild")" ]' _ "${CALLS_FILE}"
check "base -> only mypocketos-common.list.chroot was staged" \
	sh -c '[ "$(cat "$1")" = "mypocketos-common.list.chroot" ]' _ "${STAGED_LISTS_FILE}"
check "base -> package-lists/ is clean after success (no leftover)" \
	sh -c '[ -z "$(ls -A "$1")" ]' _ "${SANDBOX}/config/package-lists"
check "base -> expected ISO exists" test -f "${SANDBOX}/mypocketos-base-amd64.hybrid.iso"

# ==============================================================================
# standard: 正常系
# ==============================================================================
reset_iso_state
reset_lb_state
run_build standard >/dev/null 2>&1 && rc=0 || rc=$?
check "standard -> exit 0" test "${rc}" -eq 0
check "standard -> lb called in order (config, clean, config, build) with correct --image-name each time" \
	sh -c '[ "$(cat "$1")" = "$(printf "config --image-name mypocketos-standard\nclean used=mypocketos-standard\nconfig --image-name mypocketos-standard\nbuild")" ]' _ "${CALLS_FILE}"
check "standard -> both common and standard were staged" \
	sh -c '[ "$(sort "$1")" = "$(printf "mypocketos-common.list.chroot\nmypocketos-standard.list.chroot" | sort)" ]' _ "${STAGED_LISTS_FILE}"
check "standard -> package-lists/ is clean after success (no leftover)" \
	sh -c '[ -z "$(ls -A "$1")" ]' _ "${SANDBOX}/config/package-lists"
check "standard -> expected ISO exists" test -f "${SANDBOX}/mypocketos-standard-amd64.hybrid.iso"

# ==============================================================================
# 回帰テスト (本題): 実ビルドで発見された「前回editionのLB_IMAGE_NAMEが
# 残った状態でlb cleanが走り、前回edition側のISOを誤って削除する」不具合の
# 再現・fix確認。config(1回目)をlb cleanより先に置く現在の実装であれば、
# lb clean実行時点で既に今回editionのLB_IMAGE_NAMEへ更新されているため、
# 他edition側のISOは一切削除されないはずである。
# ==============================================================================
reset_iso_state
seed_lb_state base
echo "base-iso-content" >"${SANDBOX}/mypocketos-base-amd64.hybrid.iso"
run_build standard >/dev/null 2>&1 && rc=0 || rc=$?
check "Base->Standard: exit 0" test "${rc}" -eq 0
check "Base->Standard: prior Base ISO still exists" test -f "${SANDBOX}/mypocketos-base-amd64.hybrid.iso"
check "Base->Standard: prior Base ISO content unchanged" \
	sh -c '[ "$(cat "$1")" = "base-iso-content" ]' _ "${SANDBOX}/mypocketos-base-amd64.hybrid.iso"
check "Base->Standard: new Standard ISO created" test -f "${SANDBOX}/mypocketos-standard-amd64.hybrid.iso"
check "Base->Standard: lb clean ran with the already-updated (standard) image name, not the stale base one" \
	grep -qx "clean used=mypocketos-standard" "${CALLS_FILE}"

reset_iso_state
seed_lb_state standard
echo "standard-iso-content" >"${SANDBOX}/mypocketos-standard-amd64.hybrid.iso"
run_build base >/dev/null 2>&1 && rc=0 || rc=$?
check "Standard->Base: exit 0" test "${rc}" -eq 0
check "Standard->Base: prior Standard ISO still exists" test -f "${SANDBOX}/mypocketos-standard-amd64.hybrid.iso"
check "Standard->Base: prior Standard ISO content unchanged" \
	sh -c '[ "$(cat "$1")" = "standard-iso-content" ]' _ "${SANDBOX}/mypocketos-standard-amd64.hybrid.iso"
check "Standard->Base: new Base ISO created" test -f "${SANDBOX}/mypocketos-base-amd64.hybrid.iso"
check "Standard->Base: lb clean ran with the already-updated (base) image name, not the stale standard one" \
	grep -qx "clean used=mypocketos-base" "${CALLS_FILE}"

# 同edition再ビルド: 古い同edition ISOは更新され、他edition ISOが存在
# していればそれには一切触れないこと。
reset_iso_state
seed_lb_state base
echo "old-base-iso" >"${SANDBOX}/mypocketos-base-amd64.hybrid.iso"
echo "untouched-standard-iso" >"${SANDBOX}/mypocketos-standard-amd64.hybrid.iso"
run_build base >/dev/null 2>&1 && rc=0 || rc=$?
check "Base->Base (same edition rebuild): exit 0" test "${rc}" -eq 0
check "Base->Base: Base ISO was regenerated (no longer the old content)" \
	sh -c '[ "$(cat "$1")" != "old-base-iso" ]' _ "${SANDBOX}/mypocketos-base-amd64.hybrid.iso"
check "Base->Base: pre-existing Standard ISO left untouched" \
	sh -c '[ "$(cat "$1")" = "untouched-standard-iso" ]' _ "${SANDBOX}/mypocketos-standard-amd64.hybrid.iso"

reset_iso_state
seed_lb_state standard
echo "old-standard-iso" >"${SANDBOX}/mypocketos-standard-amd64.hybrid.iso"
echo "untouched-base-iso" >"${SANDBOX}/mypocketos-base-amd64.hybrid.iso"
run_build standard >/dev/null 2>&1 && rc=0 || rc=$?
check "Standard->Standard (same edition rebuild): exit 0" test "${rc}" -eq 0
check "Standard->Standard: Standard ISO was regenerated (no longer the old content)" \
	sh -c '[ "$(cat "$1")" != "old-standard-iso" ]' _ "${SANDBOX}/mypocketos-standard-amd64.hybrid.iso"
check "Standard->Standard: pre-existing Base ISO left untouched" \
	sh -c '[ "$(cat "$1")" = "untouched-base-iso" ]' _ "${SANDBOX}/mypocketos-base-amd64.hybrid.iso"

reset_lb_state

# ==============================================================================
# cleanup: config(1回目)/lb clean/config(2回目)/lb build のいずれの失敗でも
# 一時ファイルが残らないこと。呼び出しがどこで打ち切られたかも、時系列
# ログで確認する。
# ==============================================================================
reset_iso_state
reset_lb_state
MOCK_LB_CONFIG_EXIT=1
export MOCK_LB_CONFIG_EXIT
run_build base >/dev/null 2>&1 && rc=0 || rc=$?
unset MOCK_LB_CONFIG_EXIT
check "1st lb config failure -> non-zero exit" test "${rc}" -ne 0
check "1st lb config failure -> package-lists/ has no leftover" \
	sh -c '[ -z "$(ls -A "$1")" ]' _ "${SANDBOX}/config/package-lists"
check "1st lb config failure -> lb clean/2nd config/build never reached" \
	sh -c '[ "$(cat "$1")" = "config --image-name mypocketos-base" ]' _ "${CALLS_FILE}"

reset_iso_state
reset_lb_state
MOCK_LB_CLEAN_EXIT=1
export MOCK_LB_CLEAN_EXIT
run_build base >/dev/null 2>&1 && rc=0 || rc=$?
unset MOCK_LB_CLEAN_EXIT
check "lb clean failure -> non-zero exit" test "${rc}" -ne 0
check "lb clean failure -> package-lists/ has no leftover" \
	sh -c '[ -z "$(ls -A "$1")" ]' _ "${SANDBOX}/config/package-lists"
check "lb clean failure -> 2nd config/build never reached" \
	sh -c '[ "$(cat "$1")" = "$(printf "config --image-name mypocketos-base\nclean used=mypocketos-base")" ]' _ "${CALLS_FILE}"

reset_iso_state
reset_lb_state
MOCK_LB_CONFIG_FAIL_ON_CALL=2
MOCK_LB_CONFIG_EXIT=1
export MOCK_LB_CONFIG_FAIL_ON_CALL MOCK_LB_CONFIG_EXIT
run_build base >/dev/null 2>&1 && rc=0 || rc=$?
unset MOCK_LB_CONFIG_FAIL_ON_CALL MOCK_LB_CONFIG_EXIT
check "2nd lb config failure -> non-zero exit" test "${rc}" -ne 0
check "2nd lb config failure -> package-lists/ has no leftover" \
	sh -c '[ -z "$(ls -A "$1")" ]' _ "${SANDBOX}/config/package-lists"
check "2nd lb config failure -> lb build never reached" \
	sh -c '[ "$(cat "$1")" = "$(printf "config --image-name mypocketos-base\nclean used=mypocketos-base\nconfig --image-name mypocketos-base")" ]' _ "${CALLS_FILE}"

reset_iso_state
reset_lb_state
MOCK_LB_BUILD_EXIT=1
export MOCK_LB_BUILD_EXIT
run_build base >/dev/null 2>&1 && rc=0 || rc=$?
unset MOCK_LB_BUILD_EXIT
check "lb build failure -> non-zero exit" test "${rc}" -ne 0
check "lb build failure -> package-lists/ has no leftover" \
	sh -c '[ -z "$(ls -A "$1")" ]' _ "${SANDBOX}/config/package-lists"
check "lb build failure -> full 4-call sequence was reached" \
	sh -c '[ "$(cat "$1")" = "$(printf "config --image-name mypocketos-base\nclean used=mypocketos-base\nconfig --image-name mypocketos-base\nbuild")" ]' _ "${CALLS_FILE}"

# lb buildは成功するがISO成果物が期待名で存在しない場合も、非0で終了する
# こと (build.shの「ISO存在確認」ステップ)。
reset_iso_state
reset_lb_state
MOCK_LB_BUILD_CREATE_ISO=0
export MOCK_LB_BUILD_CREATE_ISO
run_build base >/dev/null 2>&1 && rc=0 || rc=$?
unset MOCK_LB_BUILD_CREATE_ISO
check "missing expected ISO after build -> non-zero exit" test "${rc}" -ne 0
check "missing expected ISO after build -> package-lists/ has no leftover" \
	sh -c '[ -z "$(ls -A "$1")" ]' _ "${SANDBOX}/config/package-lists"

# ==============================================================================
# SIGINT: ビルド中 (lb build内でsleep中) にSIGINTを送っても一時ファイルが
# 残らないこと。timeout --preserve-status --signal=INT を使い、非同期
# バックグラウンド起動時にSIGINTが無視される問題 (POSIX shellの仕様) を
# 回避する (tests/usb-persistence-image/test_mocked.sh と同じ手法)。
# ==============================================================================
reset_iso_state
reset_lb_state
CALLS_FILE="$(mktemp)"
STAGED_LISTS_FILE="$(mktemp)"
CONFIG_CALL_COUNT_FILE="$(mktemp)"
: >"${CALLS_FILE}"
: >"${STAGED_LISTS_FILE}"
echo 0 >"${CONFIG_CALL_COUNT_FILE}"
(
	cd "${SANDBOX}"
	PATH="${MOCKBIN}:${PATH}" \
		MOCK_LB_CALLS_FILE="${CALLS_FILE}" \
		MOCK_STAGED_LISTS_FILE="${STAGED_LISTS_FILE}" \
		MOCK_LB_CONFIG_CALL_COUNT_FILE="${CONFIG_CALL_COUNT_FILE}" \
		LB_STATE_FILE="${LB_STATE_FILE}" \
		SANDBOX_PACKAGE_LISTS_DIR="${SANDBOX}/config/package-lists" \
		MOCK_ISO_PATH="${SANDBOX}/mypocketos-base-amd64.hybrid.iso" \
		MOCK_LB_BUILD_SLEEP_SECONDS=10 \
		timeout --preserve-status --signal=INT 2 ./scripts/build.sh base
) >/dev/null 2>&1 && rc=0 || rc=$?
check "SIGINT during lb build -> non-zero exit" test "${rc}" -ne 0
check "SIGINT during lb build -> package-lists/ has no leftover" \
	sh -c '[ -z "$(ls -A "$1")" ]' _ "${SANDBOX}/config/package-lists"

# ==============================================================================
# 上書き防止: config/package-lists/ に、このスクリプトが管理するはずの
# ファイルが既に存在する場合、上書きせず安全側に停止すること。
# ==============================================================================
reset_iso_state
reset_lb_state
: >"${SANDBOX}/config/package-lists/mypocketos-common.list.chroot"
run_build base >/dev/null 2>&1 && rc=0 || rc=$?
check "pre-existing common list in place -> non-zero exit (no silent overwrite)" test "${rc}" -ne 0
check "pre-existing common list in place -> lb was never called" sh -c '[ ! -s "$1" ]' _ "${CALLS_FILE}"
rm -f -- "${SANDBOX}/config/package-lists/mypocketos-common.list.chroot"

# ==============================================================================
# config/package-lists/ が最初から存在しない場合 (Gitは空ディレクトリを
# 保持しないため、新規cloneではこの状態になりうる) の確認。現在の作業
# ディレクトリにたまたま残っている空ディレクトリへ依存しないよう、ここで
# 明示的に削除してから検証する。
# ==============================================================================
reset_iso_state
reset_lb_state
rmdir -- "${SANDBOX}/config/package-lists"
run_build base >/dev/null 2>&1 && rc=0 || rc=$?
check "package-lists/ directory absent + base -> exit 0" test "${rc}" -eq 0
check "package-lists/ directory absent + base -> directory removed again after success (self-contained)" \
	sh -c '[ ! -e "$1" ]' _ "${SANDBOX}/config/package-lists"
check "package-lists/ directory absent + base -> expected ISO exists" \
	test -f "${SANDBOX}/mypocketos-base-amd64.hybrid.iso"

reset_iso_state
reset_lb_state
run_build standard >/dev/null 2>&1 && rc=0 || rc=$?
check "package-lists/ directory absent + standard -> exit 0" test "${rc}" -eq 0
check "package-lists/ directory absent + standard -> directory removed again after success (self-contained)" \
	sh -c '[ ! -e "$1" ]' _ "${SANDBOX}/config/package-lists"
check "package-lists/ directory absent + standard -> expected ISO exists" \
	test -f "${SANDBOX}/mypocketos-standard-amd64.hybrid.iso"

# ディレクトリ不存在 + ビルド途中失敗でも、一時package-listはもちろん、
# 自分で作成したディレクトリ自体も残らないこと。
reset_iso_state
reset_lb_state
[ -d "${SANDBOX}/config/package-lists" ] && rmdir -- "${SANDBOX}/config/package-lists"
MOCK_LB_BUILD_EXIT=1
export MOCK_LB_BUILD_EXIT
run_build base >/dev/null 2>&1 && rc=0 || rc=$?
unset MOCK_LB_BUILD_EXIT
check "package-lists/ directory absent + lb build failure -> non-zero exit" test "${rc}" -ne 0
check "package-lists/ directory absent + lb build failure -> directory removed again (no residue)" \
	sh -c '[ ! -e "$1" ]' _ "${SANDBOX}/config/package-lists"

# ---- 同名の通常ファイルが存在する異常状態では安全側に停止すること ------------
reset_iso_state
reset_lb_state
[ -d "${SANDBOX}/config/package-lists" ] && rmdir -- "${SANDBOX}/config/package-lists"
: >"${SANDBOX}/config/package-lists"
run_build base >/dev/null 2>&1 && rc=0 || rc=$?
check "package-lists/ path occupied by a regular file -> non-zero exit" test "${rc}" -ne 0
check "package-lists/ path occupied by a regular file -> lb was never called" \
	sh -c '[ ! -s "$1" ]' _ "${CALLS_FILE}"
rm -f -- "${SANDBOX}/config/package-lists"
mkdir -- "${SANDBOX}/config/package-lists"

# ==============================================================================
# 既存ISO成果物の取り扱い: 古い同edition ISOが残ったまま、今回のビルドが
# 実際には新しい成果物を生成しなかった場合に、古いファイルを新しい成果物
# だと誤認しないこと。他editionのISOには一切触れないこと。
# ==============================================================================
reset_iso_state
reset_lb_state
echo "stale-base-iso" >"${SANDBOX}/mypocketos-base-amd64.hybrid.iso"
MOCK_LB_BUILD_CREATE_ISO=0
export MOCK_LB_BUILD_CREATE_ISO
run_build base >/dev/null 2>&1 && rc=0 || rc=$?
unset MOCK_LB_BUILD_CREATE_ISO
check "stale ISO present but build produces nothing new -> non-zero exit (not masked by stale file)" \
	test "${rc}" -ne 0
check "stale ISO present but build produces nothing new -> old ISO was removed pre-build, not left behind" \
	sh -c '[ ! -e "$1" ]' _ "${SANDBOX}/mypocketos-base-amd64.hybrid.iso"

reset_iso_state
reset_lb_state
echo "other-edition-iso" >"${SANDBOX}/mypocketos-standard-amd64.hybrid.iso"
run_build base >/dev/null 2>&1 && rc=0 || rc=$?
check "base build -> exit 0 (other edition's ISO left untouched)" test "${rc}" -eq 0
check "base build -> other edition's (standard) ISO content is untouched" \
	sh -c '[ "$(cat "$1")" = "other-edition-iso" ]' _ "${SANDBOX}/mypocketos-standard-amd64.hybrid.iso"
rm -f -- "${SANDBOX}/mypocketos-standard-amd64.hybrid.iso"

echo "SCENARIOS=$((PASS + FAIL)) PASS=${PASS} FAIL=${FAIL}"
[ "${FAIL}" -eq 0 ]
