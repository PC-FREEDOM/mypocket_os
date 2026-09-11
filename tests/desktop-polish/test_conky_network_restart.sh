#!/bin/sh
#
# NetworkManager dispatcher (Conky再起動) に対する静的テスト、および
# モックpgrep/runuser + 実プロセス/実/proc/<pid>/environを使った
# 機能テスト。実root権限・実conky・実NetworkManagerは一切使用しない。
#
# 背景 (2026-09-07、3度目の実機不具合修正): 実機で、Conkyがネットワーク
# 接続前に起動していると、そのプロセスの生存中はネットワークデバイスの
# 内部状態が更新されず、後から接続してもDown/Upが0Bのまま変化しない
# 不具合が確認された。ネットワーク取得ロジック自体
# (${downspeed ${gw_iface}}等) は実機で正常動作を確認済みのため、
# ネットワーク取得ロジックをさらに複雑化するのではなく、
# config/includes.chroot/etc/NetworkManager/dispatcher.d/
# 01-mypocketos-conky-restartが、NetworkManagerの接続確立イベント
# ("up") のたびに稼働中のConkyを再起動することで対応する。
#
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DISPATCHER="${REPO_ROOT}/config/includes.chroot/etc/NetworkManager/dispatcher.d/01-mypocketos-conky-restart"

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

#==========================
# 静的確認
#==========================
check "dispatcher script exists at the correct dispatcher.d path" test -f "${DISPATCHER}"
check "dispatcher script is executable on disk" test -x "${DISPATCHER}"
check "dispatcher script has a POSIX sh shebang" \
	sh -c 'head -n1 "$1" | grep -qx "#!/bin/sh"' _ "${DISPATCHER}"

check "only acts on action=up (second argument)" \
	grep -qF '[ "${ACTION}" = "up" ] || exit 0' "${DISPATCHER}"
check "targets the fixed MyPocketOS Live user (\"user\"), consistent with existing docs" \
	grep -qF 'LIVE_USER="user"' "${DISPATCHER}"
check "finds the running conky process via pgrep (no hardcoded PID)" \
	grep -qF 'pgrep -u "${LIVE_USER}" -x conky' "${DISPATCHER}"
check "no-op (exit 0) when no conky process is running (fail-safe)" \
	grep -qF '[ -n "${CONKY_PID}" ] || exit 0' "${DISPATCHER}"
check "reads DISPLAY from the running conky's own /proc/<pid>/environ (not hardcoded)" \
	grep -qF "sed -n 's/^DISPLAY=//p'" "${DISPATCHER}"
check "reads XAUTHORITY from the running conky's own /proc/<pid>/environ (not hardcoded)" \
	grep -qF "sed -n 's/^XAUTHORITY=//p'" "${DISPATCHER}"
check "does not hardcode a literal DISPLAY value such as :0" \
	sh -c '! grep -vE "^[[:space:]]*#" "$1" | grep -qE "DISPLAY=[\"]?:[0-9]"' _ "${DISPATCHER}"
check "fail-closes (exit 0, no restart attempt) when DISPLAY cannot be determined" \
	grep -qF '[ -n "${CONKY_DISPLAY}" ] || exit 0' "${DISPATCHER}"

#==========================
# 5commit目 (2026-09-08): LANG/XDG_RUNTIME_DIR/LC_*の引き継ぎ
#
# 背景: 4commit目のdispatcherはDISPLAY/XAUTHORITY/HOMEのみを引き継いで
# いたため、実機で再起動後のConkyの日本語表示が文字化けし
# (LANG未引き継ぎ)、起動モードが常にUnknownになる
# (XDG_RUNTIME_DIR未引き継ぎ、mypocketos-boot-mode.luaがXDG_RUNTIME_DIR
# 配下の状態ファイルを参照できないため)不具合が確認された。
#==========================
check "reads LANG from the running conky's own /proc/<pid>/environ (not hardcoded)" \
	grep -qF "sed -n 's/^LANG=//p'" "${DISPATCHER}"
check "reads XDG_RUNTIME_DIR from the running conky's own /proc/<pid>/environ (not hardcoded)" \
	grep -qF "sed -n 's/^XDG_RUNTIME_DIR=//p'" "${DISPATCHER}"
check "carries LANG over into the relaunched conky's environment" \
	grep -qF '"LANG=${CONKY_LANG}"' "${DISPATCHER}"
check "carries XDG_RUNTIME_DIR over into the relaunched conky's environment" \
	grep -qF '"XDG_RUNTIME_DIR=${CONKY_XDG_RUNTIME_DIR}"' "${DISPATCHER}"
check "LANG/XDG_RUNTIME_DIR are fail-safe (missing values do not block the restart, unlike DISPLAY)" \
	sh -c '! grep -qF '"'"'[ -n "${CONKY_LANG}" ] || exit 0'"'"' "$1" && ! grep -qF '"'"'[ -n "${CONKY_XDG_RUNTIME_DIR}" ] || exit 0'"'"' "$1"' _ "${DISPATCHER}"
check "handles LC_* via an explicit, bounded list of known variable names (not a wildcard/blind copy)" \
	grep -qE 'for lc_name in( LC_[A-Z]+){2,}; do' "${DISPATCHER}"
check "LC_ALL is included in the explicit LC_* list" \
	grep -qE 'for lc_name in.*\bLC_ALL\b' "${DISPATCHER}"
check "LC_* values are read from /proc/<pid>/environ per explicit name (not env -i / env dump)" \
	grep -qF 'sed -n "s/^${lc_name}=//p"' "${DISPATCHER}"
check "does not blindly copy the entire environ (no unfiltered pass-through of every NAME=VALUE line)" \
	sh -c '! grep -qiE "env[[:space:]]+-[[:space:]]|xargs[[:space:]]+env|cat[[:space:]].*environ.*\\|[[:space:]]*env\\b" "$1"' _ "${DISPATCHER}"
check "waits for the old process to actually exit before relaunching (bounded loop, not indefinite)" \
	sh -c 'grep -qF "kill -0" "$1" && grep -qE "while \[ \"\\\$\{?i\}?\" -lt [0-9]+ \]" "$1"' _ "${DISPATCHER}"
check "relaunches conky with -U (unique) and no startup pause (-p 0, intentionally shorter than autostart's -p 3; see 2026-09-11 comments)" \
	grep -qF 'set -- "$@" conky -p 0 -U' "${DISPATCHER}"
check "the relaunch invocation itself no longer uses the old -p 3 (historical mentions of -p 3 in comments are unaffected)" \
	sh -c '! grep -qF "set -- \"\$@\" conky -p 3 -U" "$1"' _ "${DISPATCHER}"
check "the relaunch invocation itself no longer uses the intermediate -p 1 (historical mentions of -p 1 in comments are unaffected)" \
	sh -c '! grep -qF "set -- \"\$@\" conky -p 1 -U" "$1"' _ "${DISPATCHER}"
check "relaunches via runuser (already available on Debian, no new package/dependency)" \
	grep -qF 'runuser -u "${LIVE_USER}"' "${DISPATCHER}"
check "no specific network interface name is referenced (\$1/INTERFACE unused for branching)" \
	sh -c '! grep -qiE "\bwlan|\beth[0-9]|\bwlp[0-9]|\benp[0-9]|\beno[0-9]|\bens[0-9]" "$1"' _ "${DISPATCHER}"

# 高頻度ポーリング・常駐監視・新規systemdサービスを追加していないこと
check "does not poll/monitor continuously (no while-true, no inotify, no systemd timer/service keywords)" \
	sh -c '! grep -qiE "while[[:space:]]+true|while[[:space:]]*:[[:space:]]|inotifywait|systemctl|\.timer\b|\.service\b" "$1"' _ "${DISPATCHER}"
check "does not use cron/at for scheduling" \
	sh -c '! grep -qiE "\bcrontab\b|\bat[[:space:]]+now\b" "$1"' _ "${DISPATCHER}"
check "does not add exec/execi to conky.conf (network fetch logic itself is unchanged)" \
	sh -c '! grep -qF "\${exec" "$1"' _ "${REPO_ROOT}/config/includes.chroot/etc/skel/.config/conky/conky.conf"

#==========================
# 機能テスト: モックpgrep/runuser + 実プロセス/実/proc/<pid>/environ
# (実root権限・実conky・実NetworkManagerは一切使用しない)
#==========================
MOCKDIR="$(mktemp -d)"
trap 'rm -rf "${MOCKDIR}"' EXIT

RUNUSER_CALLS="${MOCKDIR}/runuser_calls.txt"
: > "${RUNUSER_CALLS}"

cat > "${MOCKDIR}/runuser" << EOF
#!/bin/sh
printf '%s\n' "\$*" >> "${RUNUSER_CALLS}"
EOF
chmod +x "${MOCKDIR}/runuser"

LAST_TARGET_PID=""
make_target_process() {
	# 対象ユーザーのconky(既存プロセス)役として、指定した環境変数を持つ
	# 実プロセスを1つ起動し、そのPIDを${LAST_TARGET_PID}へ設定する。
	# /proc/<pid>/environを実際に読めるようにするため、実プロセスとして
	# 起動する(モックしない)。結果をコマンド置換 "$(...)" 経由で
	# 受け取らないのは、サブシェル終了時にバックグラウンドジョブが
	# 回収されてしまう(このテスト実行環境で確認済み)環境差異を避け、
	# 本スクリプト本体の直接の子プロセスとして残すためである。
	env -i "$@" sleep 30 &
	LAST_TARGET_PID=$!
}

run_dispatcher() {
	# $1: 対象PID (pgreqモックが返す値)。空文字なら「実行中のconkyなし」。
	# $2: action ("up"/"down"等)
	target_pid="$1"
	action="$2"

	cat > "${MOCKDIR}/pgrep" << EOF
#!/bin/sh
printf '%s\n' "${target_pid}"
EOF
	chmod +x "${MOCKDIR}/pgrep"

	: > "${RUNUSER_CALLS}"
	PATH="${MOCKDIR}:${PATH}" "${DISPATCHER}" wlp2s0 "${action}" >/dev/null 2>&1 || true

	# dispatcherは実機での挙動どおりrunuser呼び出しをバックグラウンドで
	# 起動してから即座に終了する (NetworkManagerのイベント処理を
	# ブロックしないため)。そのため、このテストの側で、バックグラウンド
	# 実行されたモックrunuserが実際に書き込みを終えるまで、短時間
	# (最大2秒) 待ってから結果を確認する。
	i=0
	while [ "${i}" -lt 20 ]; do
		[ -s "${RUNUSER_CALLS}" ] && break
		sleep 0.1
		i=$((i + 1))
	done
	# runuserが呼ばれないことを期待するケース (down・対象なし・DISPLAY欠落)
	# でも、誤検知を避けるため同程度の時間待ってから確認する。
	sleep 0.2
}

process_is_alive() {
	kill -0 "$1" 2>/dev/null
}

wait_until_dead() {
	pid="$1"
	i=0
	while [ "${i}" -lt 25 ]; do
		process_is_alive "${pid}" || return 0
		sleep 0.2
		i=$((i + 1))
	done
	return 1
}

# シナリオ1: action=up、対象プロセスが存在し、DISPLAY/XAUTHORITY/HOME/
# LANG/XDG_RUNTIME_DIR/LC_TIMEがすべて揃っている場合、旧プロセスがkillされ、
# runuserが正しい環境変数と引数で1回だけ呼ばれること。無関係な変数
# (UNRELATED_SECRET) は引き継がれないこと (無制限コピーになっていない
# ことの確認)。
make_target_process DISPLAY=:42 XAUTHORITY=/tmp/fake-xauth HOME=/tmp/fake-home \
	LANG=ja_JP.UTF-8 XDG_RUNTIME_DIR=/tmp/fake-run-1000 LC_TIME=ja_JP.UTF-8 \
	UNRELATED_SECRET=leakme
PID1="${LAST_TARGET_PID}"
run_dispatcher "${PID1}" "up"
check "scenario1: old conky process is killed after action=up" \
	wait_until_dead "${PID1}"
check "scenario1: runuser was called exactly once" \
	sh -c '[ "$(wc -l < "$1")" -eq 1 ]' _ "${RUNUSER_CALLS}"
check "scenario1: runuser call includes the recovered DISPLAY" \
	grep -q 'DISPLAY=:42' "${RUNUSER_CALLS}"
check "scenario1: runuser call includes the recovered XAUTHORITY" \
	grep -q 'XAUTHORITY=/tmp/fake-xauth' "${RUNUSER_CALLS}"
check "scenario1: runuser call includes the recovered HOME" \
	grep -q 'HOME=/tmp/fake-home' "${RUNUSER_CALLS}"
check "scenario1: runuser call includes the recovered LANG" \
	grep -q 'LANG=ja_JP.UTF-8' "${RUNUSER_CALLS}"
check "scenario1: runuser call includes the recovered XDG_RUNTIME_DIR" \
	grep -q 'XDG_RUNTIME_DIR=/tmp/fake-run-1000' "${RUNUSER_CALLS}"
check "scenario1: runuser call includes the recovered LC_TIME (present in the source environment)" \
	grep -q 'LC_TIME=ja_JP.UTF-8' "${RUNUSER_CALLS}"
check "scenario1: runuser call does NOT include the unrelated variable (no unrestricted environ copy)" \
	sh -c '! grep -q "UNRELATED_SECRET" "$1"' _ "${RUNUSER_CALLS}"
check "scenario1: runuser call launches conky -p 0 -U (no pause, 2026-09-11)" \
	grep -q 'conky -p 0 -U' "${RUNUSER_CALLS}"
# 万一プロセスが残っていた場合の後始末 (テスト自体の副作用を残さない)
kill "${PID1}" 2>/dev/null || true

# シナリオ2: action=down (接続が切れた場合)。再起動は不要なので、
# runuserが呼ばれないこと、既存プロセスもkillされないこと。
make_target_process DISPLAY=:42
PID2="${LAST_TARGET_PID}"
run_dispatcher "${PID2}" "down"
check "scenario2: runuser was NOT called for action=down" \
	sh -c '[ ! -s "$1" ]' _ "${RUNUSER_CALLS}"
check "scenario2: existing process was left running for action=down (no unnecessary restart)" \
	process_is_alive "${PID2}"
kill "${PID2}" 2>/dev/null || true
wait 2>/dev/null || true

# シナリオ3: action=up だが対象conkyプロセスが存在しない場合、
# runuserが呼ばれないこと (何もしない)。
run_dispatcher "" "up"
check "scenario3: runuser was NOT called when no conky process is running" \
	sh -c '[ ! -s "$1" ]' _ "${RUNUSER_CALLS}"

# シナリオ4: action=up・対象プロセスは存在するが、DISPLAYが環境変数に
# 含まれない場合、fail-closeでrunuserを呼ばず、既存プロセスも
# killしないこと。
make_target_process HOME=/tmp/fake-home
PID4="${LAST_TARGET_PID}"
run_dispatcher "${PID4}" "up"
check "scenario4: runuser was NOT called when DISPLAY is missing (fail-close)" \
	sh -c '[ ! -s "$1" ]' _ "${RUNUSER_CALLS}"
check "scenario4: existing process was left running when DISPLAY is missing (fail-close, no restart attempted)" \
	process_is_alive "${PID4}"
kill "${PID4}" 2>/dev/null || true
wait 2>/dev/null || true

# シナリオ5: action=up・DISPLAYは存在するが、LANG/XDG_RUNTIME_DIR/LC_*が
# 環境変数に含まれない場合。DISPLAYさえあれば再起動自体は行う
# (fail-safe。4commit目で実機確認された不具合の再発防止であり、
# LANG/XDG_RUNTIME_DIRが無いことを理由に再起動そのものを止めては
# ならない)。
make_target_process DISPLAY=:99 HOME=/tmp/fake-home
PID5="${LAST_TARGET_PID}"
run_dispatcher "${PID5}" "up"
check "scenario5: old conky process is killed even when LANG/XDG_RUNTIME_DIR are absent (fail-safe restart still happens)" \
	wait_until_dead "${PID5}"
check "scenario5: runuser was still called once (DISPLAY present is sufficient to attempt restart)" \
	sh -c '[ "$(wc -l < "$1")" -eq 1 ]' _ "${RUNUSER_CALLS}"
check "scenario5: runuser call includes DISPLAY" \
	grep -q 'DISPLAY=:99' "${RUNUSER_CALLS}"
check "scenario5: runuser call does not include a LANG entry (none was present to carry over)" \
	sh -c '! grep -q "LANG=" "$1"' _ "${RUNUSER_CALLS}"
check "scenario5: runuser call does not include an XDG_RUNTIME_DIR entry (none was present to carry over)" \
	sh -c '! grep -q "XDG_RUNTIME_DIR=" "$1"' _ "${RUNUSER_CALLS}"
kill "${PID5}" 2>/dev/null || true
wait 2>/dev/null || true

echo "SCENARIOS=$((PASS + FAIL)) PASS=${PASS} FAIL=${FAIL}"
[ "${FAIL}" -eq 0 ]
