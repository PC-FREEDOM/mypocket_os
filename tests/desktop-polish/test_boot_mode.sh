#!/bin/sh
#
# mypocketos-boot-mode の判定ロジックに対する直接実行テスト、および
# Conky側の起動モード表示 (mypocketos-boot-mode.lua・conky.conf・
# autostart) に対する静的テスト。
# productionスクリプトはテスト用にcmdlineファイルを引数で差し替えられる
# 設計になっているため (本番呼び出しは常に無引数)、モック・sandboxは
# 不要で、productionをそのまま直接実行して検証する。
# Lua側はLuaインタプリタ・Conky実体を一切使わず、ソースをテキストとして
# 静的に確認する (このリポジトリ・テスト環境にLuaが無くても実行できる)。
#
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HELPER="${REPO_ROOT}/config/includes.chroot/usr/local/bin/mypocketos-boot-mode"
LUA_FILE="${REPO_ROOT}/config/includes.chroot/etc/skel/.config/conky/mypocketos-boot-mode.lua"
CONKY_CONF="${REPO_ROOT}/config/includes.chroot/etc/skel/.config/conky/conky.conf"
AUTOSTART="${REPO_ROOT}/config/includes.chroot/etc/skel/.config/openbox/autostart"

PASS=0
FAIL=0

TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT

expect() {
	desc="$1"
	file="$2"
	want="$3"
	got="$("${HELPER}" "${file}" 2>/dev/null || true)"
	if [ "${got}" = "${want}" ]; then
		PASS=$((PASS + 1))
	else
		echo "FAIL: ${desc} (got '${got}', want '${want}')" >&2
		FAIL=$((FAIL + 1))
	fi
}

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

printf 'boot=live components persistence noeject' >"${TMPDIR}/only_p"
expect "persistenceのみ" "${TMPDIR}/only_p" "Persistence"

printf 'boot=live components nopersistence noeject' >"${TMPDIR}/only_np"
expect "nopersistenceのみ" "${TMPDIR}/only_np" "Normal Live"

printf 'boot=live persistence nopersistence' >"${TMPDIR}/both"
expect "両方あり" "${TMPDIR}/both" "Unknown"

printf 'boot=live components noeject' >"${TMPDIR}/neither"
expect "両方なし" "${TMPDIR}/neither" "Unknown"

printf 'boot=live persistence persistence' >"${TMPDIR}/dup_p"
expect "persistence重複" "${TMPDIR}/dup_p" "Unknown"

printf 'boot=live nopersistence nopersistence' >"${TMPDIR}/dup_np"
expect "nopersistence重複" "${TMPDIR}/dup_np" "Unknown"

printf 'boot=live mypersistence-thing xpersistencey persistence=1' >"${TMPDIR}/partial"
expect "部分一致のみ" "${TMPDIR}/partial" "Unknown"

: >"${TMPDIR}/empty"
expect "空ファイル" "${TMPDIR}/empty" "Unknown"

expect "存在しないファイル" "${TMPDIR}/does-not-exist" "Unknown"

: >"${TMPDIR}/unreadable"
chmod 000 "${TMPDIR}/unreadable"
expect "読み取り不可" "${TMPDIR}/unreadable" "Unknown"
chmod 644 "${TMPDIR}/unreadable"

#==========================
# mypocketos-boot-mode.lua (静的確認。Luaインタプリタ・Conky実体は使わない)
#==========================
check "boot-mode Lua helper file exists" test -f "${LUA_FILE}"
check "Lua helper references XDG_RUNTIME_DIR" grep -q 'XDG_RUNTIME_DIR' "${LUA_FILE}"
check "Lua helper references mypocketos-boot-mode.txt" \
	grep -q 'mypocketos-boot-mode.txt' "${LUA_FILE}"
check "Lua helper reads only the first line (f:read(\"*l\"))" \
	grep -qF 'f:read("*l")' "${LUA_FILE}"

check "Lua helper allow-list includes: Normal Live" \
	grep -qF 'line == "Normal Live"' "${LUA_FILE}"
check "Lua helper allow-list includes: Persistence" \
	grep -qF 'line == "Persistence"' "${LUA_FILE}"
check "Lua helper allow-list includes: Unknown" \
	grep -qF 'line == "Unknown"' "${LUA_FILE}"

# 3箇所すべて (XDG_RUNTIME_DIR未設定・ファイルを開けない・許可リスト外)
# がUnknownへfail-closeすることを、"return \"Unknown\"" の出現数で確認する
check "Lua helper falls back to Unknown at all 3 failure points (unset dir / unopenable file / unrecognized value)" \
	sh -c '[ "$(grep -c "return \"Unknown\"" "$1")" -eq 3 ]' _ "${LUA_FILE}"
check "Lua helper returns Unknown immediately after the XDG_RUNTIME_DIR unset/empty check" \
	sh -c 'grep -A2 "dir == nil or dir == \"\"" "$1" | grep -q "return \"Unknown\""' _ "${LUA_FILE}"
check "Lua helper returns Unknown immediately after the file-open failure check" \
	sh -c 'grep -A2 "f == nil" "$1" | grep -q "return \"Unknown\""' _ "${LUA_FILE}"

#==========================
# conky.conf (静的確認)
#==========================
check "conky.conf uses \${lua mypocketos_boot_mode}" \
	grep -qF '${lua mypocketos_boot_mode}' "${CONKY_CONF}"
check "conky.conf sets lua_load" grep -q 'lua_load' "${CONKY_CONF}"
check "conky.conf lua_load points at mypocketos-boot-mode.lua" \
	grep -q 'mypocketos-boot-mode\.lua' "${CONKY_CONF}"
check "conky.conf no longer uses \${env MYPOCKETOS_BOOT_MODE}" \
	sh -c '! grep -qF "\${env MYPOCKETOS_BOOT_MODE}" "$1"' _ "${CONKY_CONF}"
check "conky.conf does not use \${exec.../\${execi... (any exec-family variable)" \
	sh -c '! grep -qF "\${exec" "$1"' _ "${CONKY_CONF}"

#==========================
# openbox/autostart (静的確認)
#==========================
check "autostart invokes mypocketos-boot-mode exactly once" \
	sh -c '[ "$(grep -c "mypocketos-boot-mode 2>/dev/null" "$1")" -eq 1 ]' _ "${AUTOSTART}"
check "autostart writes to \$XDG_RUNTIME_DIR/mypocketos-boot-mode.txt" \
	grep -q 'XDG_RUNTIME_DIR.*mypocketos-boot-mode\.txt' "${AUTOSTART}"
check "autostart no longer exports MYPOCKETOS_BOOT_MODE" \
	sh -c '! grep -qE "^export MYPOCKETOS_BOOT_MODE" "$1"' _ "${AUTOSTART}"
# コメント行 (説明文) 中の "/dev/shm" への言及は許容し、実際に
# コマンド・パスとして使われていないことだけを確認する
check "autostart does not use /dev/shm as an actual path (comment mentions are OK)" \
	sh -c '! grep -vE "^[[:space:]]*#" "$1" | grep -q "/dev/shm"' _ "${AUTOSTART}"
check "autostart does not create a symlink (ln -s)" \
	sh -c '! grep -qE "ln[[:space:]]+-.*s" "$1"' _ "${AUTOSTART}"
check "autostart validates XDG_RUNTIME_DIR is not a symlink before writing" \
	grep -qE '\[ -L "\$XDG_RUNTIME_DIR" \]' "${AUTOSTART}"
check "autostart validates XDG_RUNTIME_DIR ownership (uid) before writing" \
	grep -q 'stat -c' "${AUTOSTART}"
check "autostart writes via a temp file then renames (mktemp + mv)" \
	sh -c 'grep -q "mktemp" "$1" && grep -q "mv -f" "$1"' _ "${AUTOSTART}"

# 起動モード書き込み (write_boot_mode_state呼び出し) がconky起動より前で
# あることを行番号で確認する
write_call_line="$(grep -n '^write_boot_mode_state$' "${AUTOSTART}" | head -n1 | cut -d: -f1)"
conky_start_line="$(grep -n 'conky -p 3 -U &' "${AUTOSTART}" | head -n1 | cut -d: -f1)"
check "write_boot_mode_state call precedes conky startup" \
	sh -c '[ -n "$1" ] && [ -n "$2" ] && [ "$1" -lt "$2" ]' _ "${write_call_line}" "${conky_start_line}"

echo "SCENARIOS=$((PASS + FAIL)) PASS=${PASS} FAIL=${FAIL}"
[ "${FAIL}" -eq 0 ]
