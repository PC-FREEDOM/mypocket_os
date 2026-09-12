#!/bin/sh
#
# MyPocketOS専用タッチパッド設定GUI (mypocketos-touchpad-settings) に対する
# 静的テスト、およびモックxinput/yad + 実プロセスを使った機能テスト。
# 実X11・実libinput・実タッチパッド・実yadは一切使用しない。
#
# 背景 (2026-09-12、reports/ai-review/20260912-touchpad-settings-gui-design.md):
# タッチパッド設定 (タップ・2本指スクロール・スクロール方向・ポインタ速度)
# をGUIから変更できるようにする。既存の51-mypocketos-touchpad.conf
# (Xorg起動時の既定値) は変更せず、ログイン中のセッションでXInput
# プロパティを上書きする追加の層として動作する。libinput Tapping Enabled
# プロパティの有無だけでタッチパッドを判定し、USBマウス等には一切
# set-propしない設計になっている。
#
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/config/includes.chroot/usr/local/bin/mypocketos-touchpad-settings"
AUTOSTART="${REPO_ROOT}/config/includes.chroot/etc/skel/.config/openbox/autostart"
COMMON_LIST="${REPO_ROOT}/config/package-lists.d/mypocketos-common.list.chroot"
APPEND_CSV="${REPO_ROOT}/config/includes.chroot/etc/skel/.config/jgmenu/append.csv"
ICON_ARCHIVE="${REPO_ROOT}/config/includes.chroot/usr/share/mypocketos/icon-themes/MyPocketOS-Fluent-yellow.tar.gz"
DESKTOP_FILE="${REPO_ROOT}/config/includes.chroot/usr/share/applications/mypocketos-touchpad-settings.desktop"

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
check "script exists" test -f "${SCRIPT}"
check "script is executable" test -x "${SCRIPT}"
check "script has a POSIX sh shebang" \
	sh -c 'head -n1 "$1" | grep -qx "#!/bin/sh"' _ "${SCRIPT}"

check "does not use eval as an actual command (comments mentioning the word are fine)" \
	sh -c '! grep -vE "^[[:space:]]*#" "$1" | grep -qE "(^|[^a-zA-Z_])eval([^a-zA-Z_]|$)"' _ "${SCRIPT}"
check "does not source/dot the user config file (no '. \$CONF_FILE' style)" \
	sh -c '! grep -qE "^\s*\.\s+.*CONF_FILE|^\s*source\s+.*CONF_FILE" "$1"' _ "${SCRIPT}"
check "does not hardcode a specific touchpad vendor/model name (e.g. ELAN/Synaptics)" \
	sh -c '! grep -qiE "\bELAN\b|\bSynaptics\b|\bAlps\b" "$1"' _ "${SCRIPT}"
check "detects touchpads via the libinput Tapping Enabled property only" \
	grep -qF 'libinput Tapping Enabled (' "${SCRIPT}"
check "does not write/redirect to 51-mypocketos-touchpad.conf (mentioning it in comments is fine)" \
	sh -c '! grep -E "51-mypocketos-touchpad.conf" "$1" | grep -qE ">|sed -i|tee|rm "' _ "${SCRIPT}"
check "checks for xinput availability before using it" \
	grep -qE 'command -v xinput' "${SCRIPT}"
check "writes Scroll Method Enabled with edge/button always fixed to 0" \
	grep -qE '"libinput Scroll Method Enabled" "\$two_val" 0 0' "${SCRIPT}"
check "parses Scroll Methods Available via sed+cut+tr (matches confirmed real-device format)" \
	sh -c "grep -qF \"cut -d',' -f1\" \"\$1\" && grep -qF \"tr -d '[:space:]'\" \"\$1\"" _ "${SCRIPT}"
check "resets by deleting the config file, not by overwriting it with defaults" \
	sh -c 'grep -A2 "^conf_reset" "$1" | grep -qE "rm -f \"\\\$CONF_FILE\""' _ "${SCRIPT}"
check "does not add a resident daemon (no while-true, no systemd service/timer keywords)" \
	sh -c '! grep -qiE "while[[:space:]]+true|while[[:space:]]*:[[:space:]]|systemctl|\.timer\b|\.service\b" "$1"' _ "${SCRIPT}"
check "uses a bounded retry loop for --apply device detection (not an unbounded/fixed sleep)" \
	sh -c 'grep -qE "while \[ \"\\\$\{?i\}?\" -lt [0-9]+ \]" "$1" && grep -qF "sleep 0.3" "$1"' _ "${SCRIPT}"
check "does not use a top-level fixed sleep outside the bounded retry loop (sleep appears exactly once)" \
	sh -c '[ "$(grep -c "sleep " "$1")" -eq 1 ]' _ "${SCRIPT}"

check "common package list includes xinput" \
	grep -qx 'xinput' "${COMMON_LIST}"

check "autostart invokes mypocketos-touchpad-settings --apply" \
	grep -qF 'mypocketos-touchpad-settings --apply &' "${AUTOSTART}"
check "autostart syntax is valid (sh -n)" sh -n "${AUTOSTART}"
check "autostart syntax is valid (dash -n)" dash -n "${AUTOSTART}"

# ---- アプリメニュー登録 (.desktop、jgmenu-apps内蔵schemaのSettingsカテゴリへ
#      Categories=Settings; で自動分類させる。トップ階層への直接表示はしない) ----
check ".desktop file exists" test -f "${DESKTOP_FILE}"
check ".desktop file is valid per desktop-entry-spec (desktop-file-validate, if available)" \
	sh -c 'command -v desktop-file-validate >/dev/null 2>&1 || exit 0; desktop-file-validate "$1"' _ "${DESKTOP_FILE}"
check ".desktop Exec= launches mypocketos-touchpad-settings with no arguments (GUI mode)" \
	grep -qx 'Exec=mypocketos-touchpad-settings' "${DESKTOP_FILE}"
check ".desktop Icon= specifies preferences-desktop-touchpad (unchanged from previous revision)" \
	grep -qx 'Icon=preferences-desktop-touchpad' "${DESKTOP_FILE}"
check ".desktop Categories= includes Settings (so jgmenu-apps nests it under the existing 設定 category, not the top level)" \
	sh -c "sed -n 's/^Categories=//p' \"\$1\" | grep -qE '(^|;)Settings(;|\$)'" _ "${DESKTOP_FILE}"
check ".desktop has a Japanese Name (Name[ja]) for the ja_JP.UTF-8 locale" \
	grep -qx 'Name\[ja\]=タッチパッド設定' "${DESKTOP_FILE}"
check "the referenced icon actually exists in the committed MyPocketOS-Fluent-yellow icon theme archive (no new image asset added)" \
	sh -c 'tar tzf "$1" 2>/dev/null | grep -q "scalable/apps/preferences-desktop-touchpad.svg$"' _ "${ICON_ARCHIVE}"
check "タッチパッド設定 is NOT registered as a top-level append.csv entry (comments mentioning it are fine; only the .desktop file is the entry point)" \
	sh -c '! grep -vE "^[[:space:]]*#" "$1" | grep -qE "^タッチパッド設定,"' _ "${APPEND_CSV}"
check "no other new .desktop file was introduced besides mypocketos-touchpad-settings.desktop" \
	sh -c '[ "$(find "$1" -iname "*.desktop" 2>/dev/null | wc -l)" -eq 1 ]' _ "${REPO_ROOT}/config/includes.chroot"
check "existing append.csv entries (永続領域を作成 etc.) are still intact" \
	grep -q '永続領域を作成' "${APPEND_CSV}"
check "existing append.csv entry (Openbox再設定) is still intact" \
	grep -q 'Openbox再設定' "${APPEND_CSV}"
check "existing append.csv power submenu entries are still intact" \
	sh -c 'grep -q "ログアウト" "$1" && grep -q "再起動" "$1" && grep -q "電源オフ" "$1"' _ "${APPEND_CSV}"
check "jgmenurc still uses csv_cmd=apps (no menu-generation config change needed for category-based placement)" \
	grep -qE '^csv_cmd[[:space:]]*=[[:space:]]*apps' "${REPO_ROOT}/config/includes.chroot/etc/skel/.config/jgmenu/jgmenurc"

#==========================
# 機能テスト: モックxinput/yad + 実プロセス
# (実root権限・実X11・実xinput・実yadは一切使用しない)
#==========================
MOCKDIR="$(mktemp -d)"
FAKE_HOME="$(mktemp -d)"
trap 'rm -rf "${MOCKDIR}" "${FAKE_HOME}"' EXIT

export MOCK_STATE_DIR="${MOCKDIR}"

cat >"${MOCKDIR}/xinput" <<'MOCKEOF'
#!/bin/sh
case "$1" in
list)
	if [ "${2:-}" = "--id-only" ]; then
		cat "${MOCK_STATE_DIR}/ids.txt" 2>/dev/null
	fi
	exit 0
	;;
list-props)
	id="$2"
	cat "${MOCK_STATE_DIR}/props_${id}.txt" 2>/dev/null
	exit 0
	;;
set-prop)
	id="$2"
	shift 2
	printf '%s %s\n' "${id}" "$*" >>"${MOCK_STATE_DIR}/set_prop_calls.txt"
	if [ -f "${MOCK_STATE_DIR}/fail_ids.txt" ] && grep -qx "${id}" "${MOCK_STATE_DIR}/fail_ids.txt"; then
		exit 1
	fi
	exit 0
	;;
*)
	exit 0
	;;
esac
MOCKEOF
chmod +x "${MOCKDIR}/xinput"

cat >"${MOCKDIR}/yad" <<'MOCKEOF'
#!/bin/sh
# 2026-09-12: 「適用」で確定するまでダイアログを再表示し続けるループへ変更
# したため、yad_stdout/yad_exit を「1呼び出し=1行」のキュー(N回目の
# 呼び出しにはN行目を使う)として扱う。1行しか書かれていない既存テストは
# 常に1行目を使い続けるため後方互換になる。
printf '%s\n' "$*" >>"${MOCK_STATE_DIR}/yad_calls.txt"

count_file="${MOCK_STATE_DIR}/yad_call_count"
n=0
[ -f "${count_file}" ] && n="$(cat "${count_file}")"
n=$((n + 1))
printf '%s\n' "${n}" >"${count_file}"

if [ -f "${MOCK_STATE_DIR}/yad_stdout" ]; then
	line="$(sed -n "${n}p" "${MOCK_STATE_DIR}/yad_stdout")"
	[ -n "${line}" ] && printf '%s\n' "${line}"
fi

exit_code=""
if [ -f "${MOCK_STATE_DIR}/yad_exit" ]; then
	exit_code="$(sed -n "${n}p" "${MOCK_STATE_DIR}/yad_exit")"
	[ -z "${exit_code}" ] && exit_code="$(tail -n1 "${MOCK_STATE_DIR}/yad_exit")"
fi
exit "${exit_code:-0}"
MOCKEOF
chmod +x "${MOCKDIR}/yad"

mkdir -p "${MOCKDIR}/yadonly"
cp "${MOCKDIR}/yad" "${MOCKDIR}/yadonly/yad"

reset_mock_state() {
	rm -f "${MOCKDIR}"/ids.txt "${MOCKDIR}"/props_*.txt "${MOCKDIR}"/fail_ids.txt \
		"${MOCKDIR}"/set_prop_calls.txt "${MOCKDIR}"/yad_calls.txt \
		"${MOCKDIR}"/yad_stdout "${MOCKDIR}"/yad_exit "${MOCKDIR}"/yad_call_count
	: >"${MOCKDIR}/set_prop_calls.txt"
	: >"${MOCKDIR}/yad_calls.txt"
	rm -rf "${FAKE_HOME}/.config"
}

write_touchpad_props() {
	# $1 = id, two-finger対応の標準的なタッチパッド
	cat >"${MOCKDIR}/props_$1.txt" <<EOF
	Device Enabled (140):	1
	libinput Tapping Enabled (348):	1
	libinput Tapping Enabled Default (349):	0
	libinput Natural Scrolling Enabled (321):	1
	libinput Scroll Methods Available (323):	1, 1, 0
	libinput Scroll Method Enabled (324):	1, 0, 0
	libinput Accel Speed (330):	0.000000
EOF
}

write_touchpad_props_no2f() {
	# $1 = id, タッチパッドだが2本指スクロール非対応 (実測書式 "0, 1, 0" を模す)
	cat >"${MOCKDIR}/props_$1.txt" <<EOF
	Device Enabled (140):	1
	libinput Tapping Enabled (348):	1
	libinput Natural Scrolling Enabled (321):	1
	libinput Scroll Methods Available (323):	0, 1, 0
	libinput Scroll Method Enabled (324):	0, 1, 0
	libinput Accel Speed (330):	0.000000
EOF
}

write_mouse_props() {
	# $1 = id, USBマウス相当 (libinputのタッチパッド固有プロパティが一切無い)
	cat >"${MOCKDIR}/props_$1.txt" <<EOF
	Device Enabled (140):	1
	Device Accel Constant Deceleration (150):	1.000000
EOF
}

# ---- set-prop呼び出しログに対するアサーション用ヘルパー -------------------
# (プロセス置換 <(...) はdash非対応のため使わず、常にファイル/関数呼び出しで完結させる)
prop_applied() {
	# $1=id $2=grepパターン(行末アンカー等含む)
	grep "^$1 " "${MOCKDIR}/set_prop_calls.txt" 2>/dev/null | grep -q "$2"
}

prop_applied_to_all() {
	# $1=grepパターン、残りの引数=id一覧。全IDに対して真であることを確認する。
	pattern="$1"
	shift
	for id in "$@"; do
		prop_applied "${id}" "${pattern}" || return 1
	done
	return 0
}

any_prop_applied_to() {
	# $1=id。そのIDへのset-prop呼び出しが1回以上あるか。
	grep -q "^$1 " "${MOCKDIR}/set_prop_calls.txt" 2>/dev/null
}

no_prop_applied_to() {
	# $1=id。そのIDへのset-prop呼び出しが一度も無いか。
	! grep -q "^$1 " "${MOCKDIR}/set_prop_calls.txt" 2>/dev/null
}

run_gui() {
	HOME="${FAKE_HOME}" PATH="${MOCKDIR}:${PATH}" "${SCRIPT}" >/dev/null 2>&1
}

run_apply() {
	HOME="${FAKE_HOME}" PATH="${MOCKDIR}:${PATH}" "${SCRIPT}" --apply >/dev/null 2>&1
}

run_gui_noxinput() {
	# xinputが一切見つからないPATH (mockのyadだけを含む隔離ディレクトリ+基本コマンド)
	HOME="${FAKE_HOME}" PATH="${MOCKDIR}/yadonly:/usr/bin:/bin" "${SCRIPT}" >/dev/null 2>&1
}

run_apply_noxinput() {
	HOME="${FAKE_HOME}" PATH="${MOCKDIR}/yadonly:/usr/bin:/bin" "${SCRIPT}" --apply >/dev/null 2>&1
}

CONF_PATH="${FAKE_HOME}/.config/mypocketos/touchpad.conf"

# ---- 1: 設定ファイルなし → MyPocketOS既定値 (on/on/on/0.0) が使われる ----
reset_mock_state
printf '10\n' >"${MOCKDIR}/ids.txt"
write_touchpad_props 10
run_apply
check "1: no config file -> Tapping Enabled applied as 1 (default)" \
	prop_applied 10 "libinput Tapping Enabled 1$"
check "1: no config file -> Natural Scrolling applied as 1 (default)" \
	prop_applied 10 "libinput Natural Scrolling Enabled 1$"
check "1: no config file -> Scroll Method Enabled applied as 1 0 0 (default)" \
	prop_applied 10 "libinput Scroll Method Enabled 1 0 0$"
check "1: no config file -> Accel Speed applied as 0.0 (default)" \
	prop_applied 10 "libinput Accel Speed 0.0$"
check "1: no config file is created just by --apply (read-only load)" \
	test ! -e "${CONF_PATH}"

# ---- 2: 正常な設定ファイルあり → 保存済み値がそのまま使われる ----
reset_mock_state
printf '10\n' >"${MOCKDIR}/ids.txt"
write_touchpad_props 10
mkdir -p "$(dirname "${CONF_PATH}")"
{
	printf 'TAPPING=off\n'
	printf 'TWO_FINGER_SCROLL=off\n'
	printf 'NATURAL_SCROLLING=off\n'
	printf 'POINTER_SPEED=2\n'
} >"${CONF_PATH}"
run_apply
check "2: saved TAPPING=off -> applied as 0" \
	prop_applied 10 "libinput Tapping Enabled 0$"
check "2: saved NATURAL_SCROLLING=off -> applied as 0" \
	prop_applied 10 "libinput Natural Scrolling Enabled 0$"
check "2: saved TWO_FINGER_SCROLL=off -> applied as 0 0 0" \
	prop_applied 10 "libinput Scroll Method Enabled 0 0 0$"
check "2: saved POINTER_SPEED=2 -> applied as 0.8" \
	prop_applied 10 "libinput Accel Speed 0.8$"

# ---- 3: 不正値あり → キー単位で既定値へフォールバック ----
reset_mock_state
printf '10\n' >"${MOCKDIR}/ids.txt"
write_touchpad_props 10
mkdir -p "$(dirname "${CONF_PATH}")"
{
	printf 'TAPPING=maybe\n'
	printf 'TWO_FINGER_SCROLL=off\n'
	printf 'NATURAL_SCROLLING=banana\n'
	printf 'POINTER_SPEED=99\n'
} >"${CONF_PATH}"
run_apply
check "3: invalid TAPPING falls back to default (1)" \
	prop_applied 10 "libinput Tapping Enabled 1$"
check "3: valid TWO_FINGER_SCROLL=off is respected (not affected by other invalid keys) -> 0 0 0" \
	prop_applied 10 "libinput Scroll Method Enabled 0 0 0$"
check "3: invalid NATURAL_SCROLLING falls back to default (1)" \
	prop_applied 10 "libinput Natural Scrolling Enabled 1$"
check "3: invalid POINTER_SPEED falls back to default (0.0)" \
	prop_applied 10 "libinput Accel Speed 0.0$"

# ---- 4: xinputなし → GUIは日本語メッセージ表示、--applyは無言でexit 0 ----
reset_mock_state
run_gui_noxinput
check "4 (GUI): shows a Japanese message via yad when xinput is missing" \
	grep -q 'この環境ではタッチパッド設定機能を利用できません' "${MOCKDIR}/yad_calls.txt"

reset_mock_state
check "4 (--apply): exits 0 silently when xinput is missing" \
	run_apply_noxinput
check "4 (--apply): does not invoke yad at all when xinput is missing" \
	test ! -s "${MOCKDIR}/yad_calls.txt"

# ---- 5: タッチパッドなし ----
reset_mock_state
printf '20\n' >"${MOCKDIR}/ids.txt"
write_mouse_props 20
run_gui
check "5 (GUI): shows a Japanese message when no touchpad is detected" \
	grep -q 'タッチパッドが見つかりません' "${MOCKDIR}/yad_calls.txt"

reset_mock_state
printf '20\n' >"${MOCKDIR}/ids.txt"
write_mouse_props 20
check "5 (--apply): exits 0 silently when no touchpad is detected" run_apply
check "5 (--apply): does not invoke yad when no touchpad is detected" \
	test ! -s "${MOCKDIR}/yad_calls.txt"

# ---- 6/18: USBマウスのみ → set-propが一度も呼ばれない ----
reset_mock_state
printf '20\n' >"${MOCKDIR}/ids.txt"
write_mouse_props 20
run_apply
check "6/18: no set-prop call is made to a mouse-only device" \
	test ! -s "${MOCKDIR}/set_prop_calls.txt"

# ---- 7: タッチパッド1台 → そのIDにのみset-propされる ----
reset_mock_state
printf '10\n20\n' >"${MOCKDIR}/ids.txt"
write_touchpad_props 10
write_mouse_props 20
run_apply
check "7: set-prop is called for the touchpad id" \
	any_prop_applied_to 10
check "7: set-prop is NOT called for the mouse id (18: USBマウスに設定が適用されないこと)" \
	no_prop_applied_to 20

# ---- 8: タッチパッド複数台 → 全IDに同じ値でset-propされる ----
reset_mock_state
printf '10\n12\n' >"${MOCKDIR}/ids.txt"
write_touchpad_props 10
write_touchpad_props 12
run_apply
check "8: multiple touchpads both receive Tapping Enabled 1" \
	prop_applied_to_all "libinput Tapping Enabled 1$" 10 12

# ---- 9: Tapping ON/OFF ----
reset_mock_state
printf '10\n' >"${MOCKDIR}/ids.txt"
write_touchpad_props 10
mkdir -p "$(dirname "${CONF_PATH}")"
printf 'TAPPING=on\n' >"${CONF_PATH}"
run_apply
check "9: Tapping ON -> 1" prop_applied 10 "libinput Tapping Enabled 1$"
reset_mock_state
printf '10\n' >"${MOCKDIR}/ids.txt"
write_touchpad_props 10
mkdir -p "$(dirname "${CONF_PATH}")"
printf 'TAPPING=off\n' >"${CONF_PATH}"
run_apply
check "9: Tapping OFF -> 0" prop_applied 10 "libinput Tapping Enabled 0$"

# ---- 10: Two-finger scroll ON/OFF (edge/buttonは常に0) ----
reset_mock_state
printf '10\n' >"${MOCKDIR}/ids.txt"
write_touchpad_props 10
mkdir -p "$(dirname "${CONF_PATH}")"
printf 'TWO_FINGER_SCROLL=on\n' >"${CONF_PATH}"
run_apply
check "10: Two-finger ON -> 1 0 0" \
	prop_applied 10 "libinput Scroll Method Enabled 1 0 0$"
reset_mock_state
printf '10\n' >"${MOCKDIR}/ids.txt"
write_touchpad_props 10
mkdir -p "$(dirname "${CONF_PATH}")"
printf 'TWO_FINGER_SCROLL=off\n' >"${CONF_PATH}"
run_apply
check "10: Two-finger OFF -> 0 0 0" \
	prop_applied 10 "libinput Scroll Method Enabled 0 0 0$"

# ---- 11: Natural/Classic ----
reset_mock_state
printf '10\n' >"${MOCKDIR}/ids.txt"
write_touchpad_props 10
mkdir -p "$(dirname "${CONF_PATH}")"
printf 'NATURAL_SCROLLING=on\n' >"${CONF_PATH}"
run_apply
check "11: Natural -> 1" prop_applied 10 "libinput Natural Scrolling Enabled 1$"
reset_mock_state
printf '10\n' >"${MOCKDIR}/ids.txt"
write_touchpad_props 10
mkdir -p "$(dirname "${CONF_PATH}")"
printf 'NATURAL_SCROLLING=off\n' >"${CONF_PATH}"
run_apply
check "11: Classic -> 0" prop_applied 10 "libinput Natural Scrolling Enabled 0$"

# ---- 12: 速度5段階 ----
for pair in "-2:-0.8" "-1:-0.4" "0:0.0" "1:0.4" "2:0.8"; do
	speed="${pair%%:*}"
	expected="${pair##*:}"
	reset_mock_state
	printf '10\n' >"${MOCKDIR}/ids.txt"
	write_touchpad_props 10
	mkdir -p "$(dirname "${CONF_PATH}")"
	printf 'POINTER_SPEED=%s\n' "${speed}" >"${CONF_PATH}"
	run_apply
	check "12: POINTER_SPEED=${speed} -> Accel Speed ${expected}" \
		prop_applied 10 "libinput Accel Speed ${expected}$"
done

# ---- 13/22: Apply (yadが終了コード0+固定フォーム出力を返す。GUI初期表示値変換も確認) ----
reset_mock_state
printf '10\n' >"${MOCKDIR}/ids.txt"
write_touchpad_props 10
mkdir -p "$(dirname "${CONF_PATH}")"
{
	printf 'TAPPING=on\n'
	printf 'TWO_FINGER_SCROLL=on\n'
	printf 'NATURAL_SCROLLING=on\n'
	printf 'POINTER_SPEED=0\n'
} >"${CONF_PATH}"
printf 'FALSE|TRUE|指の動きと反対方向|速い|\n' >"${MOCKDIR}/yad_stdout"
printf '0\n' >"${MOCKDIR}/yad_exit"
run_gui
check "13: Apply writes the new TAPPING=off to the config file" \
	grep -qx 'TAPPING=off' "${CONF_PATH}"
check "13: Apply writes the new TWO_FINGER_SCROLL=on to the config file" \
	grep -qx 'TWO_FINGER_SCROLL=on' "${CONF_PATH}"
check "13: Apply writes the new NATURAL_SCROLLING=off (指の動きと反対方向) to the config file" \
	grep -qx 'NATURAL_SCROLLING=off' "${CONF_PATH}"
check "13: Apply writes the new POINTER_SPEED=2 (速い) to the config file" \
	grep -qx 'POINTER_SPEED=2' "${CONF_PATH}"
check "13: Apply immediately reflects Tapping=off via set-prop" \
	prop_applied 10 "libinput Tapping Enabled 0$"
check "13: Apply immediately reflects Pointer speed=速い via set-prop" \
	prop_applied 10 "libinput Accel Speed 0.8$"
check "22: initial CHK field passed to yad reflects the current on/on/on/0 config as TRUE/TRUE" \
	sh -c 'grep -qF "タップでクリックする:CHK TRUE" "$1" && grep -qF "2本指でスクロールする:CHK TRUE" "$1"' \
	_ "${MOCKDIR}/yad_calls.txt"
check "22: initial CB field marks 指の動きと同じ方向/標準 as the default (^) selection for on/0 config" \
	sh -c 'grep -qF "スクロール方向:CB ^指の動きと同じ方向!指の動きと反対方向" "$1" && grep -qF "ポインタの速さ:CB 遅い!やや遅い!^標準!やや速い!速い" "$1"' \
	_ "${MOCKDIR}/yad_calls.txt"
check "13: OK (rc=0) results in exactly one yad invocation (GUI closes immediately, no further loop iteration)" \
	sh -c '[ "$(wc -l < "$1")" -eq 1 ]' _ "${MOCKDIR}/yad_calls.txt"

# ---- 14: Cancel (yadが終了コード1を返す) → 何も変わらない ----
reset_mock_state
printf '10\n' >"${MOCKDIR}/ids.txt"
write_touchpad_props 10
mkdir -p "$(dirname "${CONF_PATH}")"
printf 'TAPPING=on\n' >"${CONF_PATH}"
printf 'FALSE|FALSE|指の動きと反対方向|遅い|\n' >"${MOCKDIR}/yad_stdout"
printf '1\n' >"${MOCKDIR}/yad_exit"
run_gui
check "14: Cancel does not change the config file" \
	grep -qx 'TAPPING=on' "${CONF_PATH}"
check "14: Cancel does not call set-prop at all" \
	test ! -s "${MOCKDIR}/set_prop_calls.txt"

# ---- 15: Default reset (yadが終了コード10を返す) → 設定ファイルが削除される ----
# 2026-09-12: 既定値に戻してもGUIは閉じない仕様になったため、ループを
# 終わらせるための2回目の呼び出し(Escape相当、rc=1)を続けて用意する。
reset_mock_state
printf '10\n' >"${MOCKDIR}/ids.txt"
write_touchpad_props 10
mkdir -p "$(dirname "${CONF_PATH}")"
{
	printf 'TAPPING=off\n'
	printf 'TWO_FINGER_SCROLL=off\n'
	printf 'NATURAL_SCROLLING=off\n'
	printf 'POINTER_SPEED=2\n'
} >"${CONF_PATH}"
{
	printf '10\n'
	printf '1\n'
} >"${MOCKDIR}/yad_exit"
run_gui
check "15: Default reset DELETES the config file (not overwrite)" \
	test ! -e "${CONF_PATH}"
check "15: Default reset applies MyPocketOS system default Tapping=1" \
	prop_applied 10 "libinput Tapping Enabled 1$"
check "15: Default reset applies MyPocketOS system default Two-finger=1 0 0" \
	prop_applied 10 "libinput Scroll Method Enabled 1 0 0$"
check "15: Default reset applies MyPocketOS system default Natural=1" \
	prop_applied 10 "libinput Natural Scrolling Enabled 1$"
check "15: Default reset applies MyPocketOS system default Accel Speed=0.0" \
	prop_applied 10 "libinput Accel Speed 0.0$"

# ---- 16: autostart再適用 (--apply) → GUI(yad)は一切起動されない ----
reset_mock_state
printf '10\n' >"${MOCKDIR}/ids.txt"
write_touchpad_props 10
mkdir -p "$(dirname "${CONF_PATH}")"
printf 'TAPPING=off\n' >"${CONF_PATH}"
run_apply
check "16: --apply never invokes yad" \
	test ! -s "${MOCKDIR}/yad_calls.txt"
check "16: --apply re-applies the saved TAPPING=off setting" \
	prop_applied 10 "libinput Tapping Enabled 0$"

# ---- 17: Persistenceを想定した$HOME保存 ----
reset_mock_state
printf '10\n' >"${MOCKDIR}/ids.txt"
write_touchpad_props 10
printf 'FALSE|TRUE|指の動きと同じ方向|標準|\n' >"${MOCKDIR}/yad_stdout"
printf '0\n' >"${MOCKDIR}/yad_exit"
run_gui
check "17: config file is created under the (fake) \$HOME/.config/mypocketos/ path" \
	test -f "${CONF_PATH}"

# ---- 19: 複数タッチパッドへの適用が一部失敗 (GUIモードは警告表示) ----
reset_mock_state
printf '10\n12\n' >"${MOCKDIR}/ids.txt"
write_touchpad_props 10
write_touchpad_props 12
printf '12\n' >"${MOCKDIR}/fail_ids.txt"
printf 'TRUE|TRUE|指の動きと同じ方向|標準|\n' >"${MOCKDIR}/yad_stdout"
printf '0\n' >"${MOCKDIR}/yad_exit"
run_gui
check "19 (GUI): shows a partial-failure warning when one of several touchpads fails" \
	grep -q '一部のタッチパッドに設定を適用できませんでした' "${MOCKDIR}/yad_calls.txt"
check "19 (GUI): the other (non-failing) touchpad still receives set-prop" \
	any_prop_applied_to 10

# ---- 20: 複数タッチパッドへの適用が一部失敗 (--applyモードは無言) ----
reset_mock_state
printf '10\n12\n' >"${MOCKDIR}/ids.txt"
write_touchpad_props 10
write_touchpad_props 12
printf '12\n' >"${MOCKDIR}/fail_ids.txt"
run_apply
check "20 (--apply): does not invoke yad even when one device fails" \
	test ! -s "${MOCKDIR}/yad_calls.txt"
check "20 (--apply): the other (non-failing) touchpad still receives set-prop" \
	any_prop_applied_to 10

# ---- 21: 複数タッチパッド時の2本指スクロールAND判定 ----
reset_mock_state
printf '10\n12\n' >"${MOCKDIR}/ids.txt"
write_touchpad_props 10
write_touchpad_props_no2f 12
run_gui
check "21: with one non-supporting touchpad among two, the checkbox is disabled (@disabled@)" \
	grep -qF '2本指でスクロールする:CHK @disabled@' "${MOCKDIR}/yad_calls.txt"
check "21: the multi-device note text is shown for the disabled checkbox" \
	grep -q '接続されているタッチパッドの一部が2本指スクロールに対応していません' "${MOCKDIR}/yad_calls.txt"

reset_mock_state
printf '10\n12\n' >"${MOCKDIR}/ids.txt"
write_touchpad_props 10
write_touchpad_props 12
run_gui
check "21: with both touchpads supporting two-finger, the checkbox stays operable" \
	sh -c '! grep -qF "2本指でスクロールする:CHK @disabled@" "$1"' _ "${MOCKDIR}/yad_calls.txt"

reset_mock_state
printf '12\n' >"${MOCKDIR}/ids.txt"
write_touchpad_props_no2f 12
run_gui
check "21: single non-supporting touchpad shows the singular-form note" \
	grep -q 'このタッチパッドは2本指スクロールに対応していません' "${MOCKDIR}/yad_calls.txt"

# ---- 23: 適用 (rc=20) → 保存+反映されるがGUIは閉じず、再度別の値で適用しOKで終了できる ----
reset_mock_state
printf '10\n' >"${MOCKDIR}/ids.txt"
write_touchpad_props 10
mkdir -p "$(dirname "${CONF_PATH}")"
{
	printf 'TAPPING=on\n'
	printf 'TWO_FINGER_SCROLL=on\n'
	printf 'NATURAL_SCROLLING=on\n'
	printf 'POINTER_SPEED=0\n'
} >"${CONF_PATH}"
{
	printf 'FALSE|TRUE|指の動きと反対方向|やや速い|\n'
	printf 'TRUE|TRUE|指の動きと同じ方向|速い|\n'
} >"${MOCKDIR}/yad_stdout"
{
	printf '20\n'
	printf '0\n'
} >"${MOCKDIR}/yad_exit"
run_gui
check "23 (1): Apply (20) results in more than one yad invocation (GUI stays open)" \
	sh -c '[ "$(wc -l < "$1")" -eq 2 ]' _ "${MOCKDIR}/yad_calls.txt"
check "23 (2): the first Apply's Tapping=off is actually reflected via set-prop before the second call" \
	sh -c '[ "$(grep -c "^10 libinput Tapping Enabled" "$1")" -eq 2 ]' _ "${MOCKDIR}/set_prop_calls.txt"
check "23 (3): after Apply then OK with a new value, the config file reflects the SECOND (latest) value" \
	grep -qx 'TAPPING=on' "${CONF_PATH}"
check "23 (4): the final POINTER_SPEED reflects the second Apply's 速い (2), confirming re-adjustment after the first Apply took effect" \
	grep -qx 'POINTER_SPEED=2' "${CONF_PATH}"
check "23 (5): xinput was updated for both the first (やや速い=0.4) and second (速い=0.8) Apply" \
	sh -c 'grep -q "libinput Accel Speed 0.4$" "$1" && grep -q "libinput Accel Speed 0.8$" "$1"' _ "${MOCKDIR}/set_prop_calls.txt"

# ---- 24: 適用してからEscape → 適用済みの内容は維持され、Escape時の未適用の変更は保存されない ----
reset_mock_state
printf '10\n' >"${MOCKDIR}/ids.txt"
write_touchpad_props 10
mkdir -p "$(dirname "${CONF_PATH}")"
{
	printf 'TAPPING=on\n'
	printf 'TWO_FINGER_SCROLL=on\n'
	printf 'NATURAL_SCROLLING=on\n'
	printf 'POINTER_SPEED=0\n'
} >"${CONF_PATH}"
{
	printf 'FALSE|TRUE|指の動きと反対方向|標準|\n'
	printf 'TRUE|TRUE|指の動きと同じ方向|速い|\n'
} >"${MOCKDIR}/yad_stdout"
{
	printf '20\n'
	printf '252\n'
} >"${MOCKDIR}/yad_exit"
run_gui
check "24 (1): Apply then Escape results in exactly two yad invocations (loop continued once, then exited)" \
	sh -c '[ "$(wc -l < "$1")" -eq 2 ]' _ "${MOCKDIR}/yad_calls.txt"
check "24 (2): the config file reflects only the applied (first call's) TAPPING=off, not the escaped second call" \
	grep -qx 'TAPPING=off' "${CONF_PATH}"
check "24 (3): the config file reflects only the applied (first call's) POINTER_SPEED=0 (標準), not the escaped 速い" \
	grep -qx 'POINTER_SPEED=0' "${CONF_PATH}"
check "24 (4): the escaped second call's field values (速い -> Accel Speed 0.8) are never applied to xinput" \
	sh -c '! grep -q "libinput Accel Speed 0.8" "$1"' _ "${MOCKDIR}/set_prop_calls.txt"

# ---- 25: 既定値に戻す (rc=10) → GUIは閉じず、表示も既定値へ更新される ----
reset_mock_state
printf '10\n' >"${MOCKDIR}/ids.txt"
write_touchpad_props 10
mkdir -p "$(dirname "${CONF_PATH}")"
{
	printf 'TAPPING=off\n'
	printf 'TWO_FINGER_SCROLL=off\n'
	printf 'NATURAL_SCROLLING=off\n'
	printf 'POINTER_SPEED=2\n'
} >"${CONF_PATH}"
{
	printf '10\n'
	printf '1\n'
} >"${MOCKDIR}/yad_exit"
run_gui
check "25 (1): Default reset results in exactly two yad invocations (GUI stays open after reset)" \
	sh -c '[ "$(wc -l < "$1")" -eq 2 ]' _ "${MOCKDIR}/yad_calls.txt"
check "25 (2): the second (post-reset) yad invocation shows the Tapping/Two-finger checkboxes reset to TRUE" \
	sh -c 'sed -n "2p" "$1" | grep -qF "タップでクリックする:CHK TRUE" && sed -n "2p" "$1" | grep -qF "2本指でスクロールする:CHK TRUE"' \
	_ "${MOCKDIR}/yad_calls.txt"
check "25 (3): the second (post-reset) yad invocation marks 指の動きと同じ方向/標準 as the default (^) selection" \
	sh -c 'sed -n "2p" "$1" | grep -qF "スクロール方向:CB ^指の動きと同じ方向!指の動きと反対方向" && sed -n "2p" "$1" | grep -qF "ポインタの速さ:CB 遅い!やや遅い!^標準!やや速い!速い"' \
	_ "${MOCKDIR}/yad_calls.txt"

# ---- 26: --apply モードの既存挙動に回帰がないこと (GUIループ変更の影響を受けない) ----
reset_mock_state
printf '10\n' >"${MOCKDIR}/ids.txt"
write_touchpad_props 10
run_apply
check "26 (1): --apply still never invokes yad (no GUI loop involvement)" \
	test ! -s "${MOCKDIR}/yad_calls.txt"
check "26 (2): --apply still applies MyPocketOS defaults when no config file exists" \
	prop_applied 10 "libinput Tapping Enabled 1$"

echo "SCENARIOS=$((PASS + FAIL)) PASS=${PASS} FAIL=${FAIL}"
[ "${FAIL}" -eq 0 ]
