#!/bin/sh
#
# [オプション・非必須] Conky設定を実conkyバイナリで一時的に実行し、
# 静的テスト (test_conky_display.sh) では検出できないランタイムエラー
# (Lua実行時エラー、テンプレート構文の実行時不整合等) を確認する
# smokeテスト。
#
# 背景 (2026-09-07): ネットワーク表示の実装で、静的テストは一貫して
# PASSしていたにもかかわらず、実機のConkyプロセスでは2回続けて異なる
# ランタイム限定の不具合 (1回目: 引数なし${downspeed}/${upspeed}が
# default route interfaceを正しく選ばずDown/Upが常に0Bになる。2回目:
# Luaヘルパー内でconky_parse()を再帰的に呼ぶことで
# "attempt to call a nil value"というLua実行時エラーが発生し値が空欄に
# なる) が発生した。grepベースの静的検証だけでは、この種の「実行して
# 初めて分かる」問題を検出できないため、可能な範囲でこのオプション
# テストを追加する。
#
# 【検討したが自動化しなかった項目】3回目の不具合 (Conkyがネットワーク
# 接続確立前に起動していると、そのプロセスの生存中はDown/Upが0Bのまま
# 変化しない) の再現・検出は、実際のNetworkManager接続状態遷移
# (未接続→接続確立) を必要とし、CI・本スクリプトのようなヘッドレスな
# 一時プロセス実行だけでは安全に再現できないため、本スクリプトには
# 含めていない。この不具合への対応
# (config/includes.chroot/etc/NetworkManager/dispatcher.d/
# 01-mypocketos-conky-restart) の検証は、
# tests/desktop-polish/test_conky_network_restart.shで、モック
# pgrep/runuser + 実プロセス/実/proc/<pid>/environを使って行っている
# (dispatcherスクリプト自体の再起動ロジックを検証するものであり、
# 実際のNetworkManager接続イベントは使わない)。
#
# 追記 (2026-09-08、5commit目): 4commit目入りISOの実機確認で、
# dispatcher再起動自体はネットワーク速度表示について機能したが、
# LANG/XDG_RUNTIME_DIRが再起動後のConkyへ引き継がれず、日本語表示の
# 文字化け・起動モードのUnknown化が判明した。この対応
# (dispatcherへのLANG/XDG_RUNTIME_DIR/LC_*引き継ぎ) も
# test_conky_network_restart.shで検証しており、本スクリプトの対象では
# ない。また同commitで、ネットワーク表示のレイアウトを3行表示から
# 「ネットワーク: Down <値> / Up <値>」の1行表示へ変更したため、
# 本スクリプトのDown/Up値チェックもこの1行表示に合わせて更新した。
#
# 【検討したが自動化しなかった項目 (2026-09-08、6commit目)】5commit目
# 入りISOの実機確認で、ネットワーク速度・メモリ・ルートFS等の値が
# 変化するたびにConkyウィンドウ全体の横幅が変化する不具合が判明した
# (対応: minimum_width/maximum_widthの固定化)。本スクリプトは
# out_to_x=false (ヘッドレス、実際のXウィンドウを作成しない) で実行
# するため、実際のウィンドウの描画ピクセル幅そのものを測定・確認する
# ことはできない (out_to_x=falseでは、そもそもXウィンドウが作成されず
# xwininfo等で測定する対象が存在しない)。実際のピクセル幅測定は、本
# セッションの開発時にのみ、実際に稼働するX11ディスプレイ上でconkyを
# 一時的に動かし、xwininfoで直接確認する形で行った(reports/ai-review/
# 20260906-conky-system-network-polish.mdに手順と結果を記録)。この
# 測定はテストスイートの一部として自動化しておらず、CI・本スクリプト
# には含まれていない(ヘッドレス環境で安全に自動化できないため)。
# 本スクリプトは、固定幅設定を含む新しいconky.confがエラーなく起動・
# レンダリングできること(構文・Lua呼び出しレベルの検証)のみを確認
# する。実際のウィンドウ幅が実機で意図どおり安定しているかどうかは、
# 実機確認が必要である。
#
# 【重要】このテストは4つの必須ローカルテストスイート
# (tests/persistence, tests/edition-build, tests/desktop-polish,
# tests/usb-persistence-image) の一部ではなく、
# tests/desktop-polish/run.shからも呼び出されない。.github/workflows/の
# CIからも実行されない。実conkyバイナリが必要であり、CI環境
# (ubuntu-latest、Debianパッケージ未インストール)・素のgit checkout
# 直後にはconkyバイナリが存在しないため、その場合は何もエラーにせず
# SKIPして終了する (exit 0)。X (out_to_x) は使わず、out_to_x=false・
# out_to_console=trueの一時設定でヘッドレスに実行する。
#
# 実conkyバイナリの探索順序 (システムへのインストールは一切行わない):
#   1. $CONKY_BIN_OVERRIDE (明示指定、実行可能ファイル)
#   2. PATH上のconkyコマンド
#   3. 本リポジトリでこれまでに./scripts/build.shを実行済みであれば、
#      chroot/usr/bin/conky (Git管理外のビルド生成物)。共有ライブラリ
#      (liblua5.3-0・libimlib2t64) が不足している場合、
#      cache/packages.chroot/ (これもGit管理外、build.shが取得した
#      パッケージキャッシュ) 中の対応する.debから、一時ディレクトリへ
#      dpkg-deb -xで展開してLD_LIBRARY_PATHで解決する
#      (システムへのインストール・sudoは一切使わない)。
#
# 手動実行方法:
#   tests/desktop-polish/optional_conky_runtime_smoke.sh
#
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CONKY_SKEL_DIR="${REPO_ROOT}/config/includes.chroot/etc/skel/.config/conky"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

skip() {
	echo "SKIP: $1" >&2
	echo "SCENARIOS=0 PASS=0 FAIL=0 (skipped: ${1})"
	exit 0
}

CONKY_BIN=""
EXTRA_LIB_PATH=""

if [ -n "${CONKY_BIN_OVERRIDE:-}" ] && [ -x "${CONKY_BIN_OVERRIDE}" ]; then
	CONKY_BIN="${CONKY_BIN_OVERRIDE}"
elif command -v conky >/dev/null 2>&1; then
	CONKY_BIN="$(command -v conky)"
elif [ -x "${REPO_ROOT}/chroot/usr/bin/conky" ]; then
	CANDIDATE="${REPO_ROOT}/chroot/usr/bin/conky"
	if ldd "${CANDIDATE}" 2>/dev/null | grep -q 'not found'; then
		LUA_DEB="$(find "${REPO_ROOT}/cache/packages.chroot" -maxdepth 1 -name 'liblua5.3-0_*.deb' 2>/dev/null | head -n1 || true)"
		IMLIB_DEB="$(find "${REPO_ROOT}/cache/packages.chroot" -maxdepth 1 -name 'libimlib2*.deb' 2>/dev/null | head -n1 || true)"
		if [ -n "${LUA_DEB}" ] && [ -n "${IMLIB_DEB}" ] && command -v dpkg-deb >/dev/null 2>&1; then
			mkdir -p "${WORKDIR}/libs"
			dpkg-deb -x "${LUA_DEB}" "${WORKDIR}/libs/lua" 2>/dev/null || true
			dpkg-deb -x "${IMLIB_DEB}" "${WORKDIR}/libs/imlib2" 2>/dev/null || true
			EXTRA_LIB_PATH="${WORKDIR}/libs/lua/usr/lib/x86_64-linux-gnu:${WORKDIR}/libs/imlib2/usr/lib/x86_64-linux-gnu"
		fi
		if [ -n "${EXTRA_LIB_PATH}" ] && ! LD_LIBRARY_PATH="${EXTRA_LIB_PATH}" ldd "${CANDIDATE}" 2>/dev/null | grep -q 'not found'; then
			CONKY_BIN="${CANDIDATE}"
		fi
	else
		CONKY_BIN="${CANDIDATE}"
	fi
fi

[ -n "${CONKY_BIN}" ] || skip "実conkyバイナリが見つかりません (CI・素のgit checkout直後の想定どおりです)。static テスト (test_conky_display.sh) のみで検証してください。"

command -v python3 >/dev/null 2>&1 || skip "python3が見つからないため、一時設定の生成をスキップします。"

mkdir -p "${WORKDIR}/home/.config/conky"
cp "${CONKY_SKEL_DIR}/conky.conf" "${WORKDIR}/home/.config/conky/conky.conf.orig"
cp "${CONKY_SKEL_DIR}/mypocketos-boot-mode.lua" "${WORKDIR}/home/.config/conky/"

SMOKE_CONF="${WORKDIR}/home/.config/conky/smoke.conf"
python3 - "${WORKDIR}/home/.config/conky/conky.conf.orig" "${SMOKE_CONF}" << 'PYEOF'
import re
import sys

src = open(sys.argv[1], encoding='utf-8').read()
# out_to_x/out_to_consoleを上書きし、少数回の更新だけで終了するようにする
# (productionのconky.confを直接編集せず、一時コピー上でのみ変更する)。
src = re.sub(r'out_to_x\s*=\s*true', 'out_to_x = false', src)
src = re.sub(r'out_to_console\s*=\s*false', 'out_to_console = true', src)
src = src.replace('conky.config = {\n', 'conky.config = {\n    total_run_times = 3,\n', 1)
open(sys.argv[2], 'w', encoding='utf-8').write(src)
PYEOF

OUT_FILE="${WORKDIR}/out.txt"
if [ -n "${EXTRA_LIB_PATH}" ]; then
	HOME="${WORKDIR}/home" LD_LIBRARY_PATH="${EXTRA_LIB_PATH}" timeout 20 "${CONKY_BIN}" -c "${SMOKE_CONF}" >"${OUT_FILE}" 2>&1 || true
else
	HOME="${WORKDIR}/home" timeout 20 "${CONKY_BIN}" -c "${SMOKE_CONF}" >"${OUT_FILE}" 2>&1 || true
fi

PASS=0
FAIL=0

check() {
	desc="$1"
	shift
	if "$@"; then
		PASS=$((PASS + 1))
	else
		echo "FAIL: ${desc}" >&2
		echo "----- conky output -----" >&2
		cat "${OUT_FILE}" >&2
		echo "-------------------------" >&2
		FAIL=$((FAIL + 1))
	fi
}

check "conky produced output" test -s "${OUT_FILE}"
check "no Lua runtime error (attempt to call/index a nil value)" \
	sh -c '! grep -qi "attempt to call a nil value\|attempt to index a nil value" "$1"' _ "${OUT_FILE}"
check "no llua execution-failure message" \
	sh -c '! grep -qi "execution failed"' _ "${OUT_FILE}" < "${OUT_FILE}"
check "existing items rendered: MyPocketOS heading" grep -q 'MyPocketOS' "${OUT_FILE}"
check "existing items rendered: ホスト名" grep -q 'ホスト名:' "${OUT_FILE}"
check "existing items rendered: ショートカット" grep -q 'ショートカット' "${OUT_FILE}"
check "existing items rendered: ウィンドウスナップ" grep -q 'ウィンドウスナップ' "${OUT_FILE}"
check "network label rendered: ネットワーク" grep -q 'ネットワーク' "${OUT_FILE}"

# 今回のこれまでの不具合と同種の症状 (ラベルは出るが値だけ空欄になる)
# が無いことを確認する。「未接続」表示になっている場合はこのチェックを
# 満たしたものとして扱う (未接続はfail-close方針として正しい挙動)。
# 2026-09-08 (5commit目): ネットワーク表示は「ネットワーク:」見出しと
# Down/Upの値が同一行の1行表示 ("ネットワーク: Down <値> / Up <値>")
# であるため、そのネットワーク行自体からDown/Upの値を抽出して確認する。
check "network line's Down/Up values are not blank (or the 未接続 fallback is shown)" \
	sh -c '
	out="$1"
	if grep -q "未接続" "${out}"; then
		exit 0
	fi
	network_line="$(grep "ネットワーク:" "${out}" | head -n1)"
	[ -n "${network_line}" ] || exit 1
	down_val="$(printf "%s" "${network_line}" | sed -n "s/.*Down \\(.*\\) \\/ Up.*/\\1/p")"
	up_val="$(printf "%s" "${network_line}" | sed -n "s/.*Up \\(.*\\)$/\\1/p")"
	[ -n "${down_val}" ] && [ -n "${up_val}" ]
	' _ "${OUT_FILE}"

echo "SCENARIOS=$((PASS + FAIL)) PASS=${PASS} FAIL=${FAIL}"
[ "${FAIL}" -eq 0 ]
