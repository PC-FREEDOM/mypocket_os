#!/bin/sh
#
# 右クリックメニュー・jgmenu連携に対する静的/モックテスト。
# 実jgmenu・実tint2・実Openboxは一切起動しない。
#
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WRAPPER="${REPO_ROOT}/config/includes.chroot/usr/local/bin/mypocketos-jgmenu-at-pointer"
TINT2RC="${REPO_ROOT}/config/includes.chroot/etc/skel/.config/tint2/tint2rc"
APPEND_CSV="${REPO_ROOT}/config/includes.chroot/etc/skel/.config/jgmenu/append.csv"
MENU_XML="${REPO_ROOT}/config/includes.chroot/etc/skel/.config/openbox/menu.xml"
RC_XML="${REPO_ROOT}/config/includes.chroot/etc/skel/.config/openbox/rc.xml"

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

# tint2側の既存コマンドが維持されていること (今回変更していない)
check "tint2 button_lclick_command is unchanged (jgmenu_run)" \
	grep -qx 'button_lclick_command = jgmenu_run' "${TINT2RC}"

# 右クリック側ラッパーがポインター位置指定 (--at-pointer) を渡すこと
check "wrapper invokes jgmenu --at-pointer" \
	grep -q -- '--at-pointer' "${WRAPPER}"

# 常駐daemonのロックファイルと競合しない短命モード (--simple) を使うこと
check "wrapper invokes jgmenu --simple (short-lived, no lockfile conflict)" \
	grep -q -- '--simple' "${WRAPPER}"

# daemon側 (csv_cmd = apps) と同じメニュー内容を生成する jgmenu_run apps を
# 使うこと (append.csv込みで内容を一致させるため)
check "wrapper uses jgmenu_run apps to generate menu content" \
	grep -q 'jgmenu_run apps' "${WRAPPER}"

# 旧方式 (jgmenu --at-pointer のみを直接実行し、常駐daemonのlockfileと
# 競合していた形) に戻っていないことを確認する。--simple を伴わない
# "jgmenu --at-pointer" 単独呼び出しが無いことを確認する
check "wrapper does not use the old lockfile-conflicting form (jgmenu --at-pointer alone, without --simple)" \
	sh -c '! grep -qE "jgmenu[[:space:]]+--at-pointer[[:space:]]*$" "$1"' _ "${WRAPPER}"

# append.csv 必須項目の存在
check "append.csv contains: 永続領域を作成" grep -q '永続領域を作成' "${APPEND_CSV}"
check "append.csv contains: Openbox再設定" grep -q 'Openbox再設定' "${APPEND_CSV}"
check "append.csv contains: ログアウト" grep -q 'ログアウト' "${APPEND_CSV}"
check "append.csv contains: 再起動" grep -q '再起動' "${APPEND_CSV}"
check "append.csv contains: 電源オフ" grep -q '電源オフ' "${APPEND_CSV}"
check "append.csv contains: ファームウェア設定" grep -q 'ファームウェア設定' "${APPEND_CSV}"

# 既存menu.xmlは置き換え・削除していないこと (復旧・代替操作用に維持)
check "menu.xml still exists" test -f "${MENU_XML}"
check "menu.xml still has 端末" grep -q '端末' "${MENU_XML}"
check "menu.xml still has ファイルマネージャー" grep -q 'ファイルマネージャー' "${MENU_XML}"
check "menu.xml still has Openbox再設定" grep -q 'Openbox再設定' "${MENU_XML}"

#==========================
# Root右クリック (デスクトップ背景右クリック) がjgmenuへ正式に切り替わって
# いること。rc.xmlはXML名前空間 (http://openbox.org/3.4/rc) を持つため、
# 行ベースのgrepではなくxml.etree.ElementTreeで構造的に確認する。
#==========================
check "rc.xml is well-formed XML" \
	python3 -c "import xml.etree.ElementTree as ET; ET.parse('${RC_XML}')"

check "openbox rc.xml exists" test -f "${RC_XML}"

check "Root context Right mousebind executes mypocketos-jgmenu-at-pointer" \
	python3 -c "
import xml.etree.ElementTree as ET
ns = {'ob': 'http://openbox.org/3.4/rc'}
root = ET.parse('${RC_XML}').getroot()
for ctx in root.findall('.//ob:context', ns):
    if ctx.get('name') != 'Root':
        continue
    for mb in ctx.findall('ob:mousebind', ns):
        if mb.get('button') != 'Right':
            continue
        cmd = mb.find('.//ob:action[@name=\"Execute\"]/ob:command', ns)
        assert cmd is not None, 'no Execute/command found'
        assert cmd.text.strip() == 'mypocketos-jgmenu-at-pointer', cmd.text
        raise SystemExit(0)
raise SystemExit('Root/Right mousebind not found')
"

check "Root context Right mousebind no longer shows the old ShowMenu root-menu" \
	python3 -c "
import xml.etree.ElementTree as ET
ns = {'ob': 'http://openbox.org/3.4/rc'}
root = ET.parse('${RC_XML}').getroot()
for ctx in root.findall('.//ob:context', ns):
    if ctx.get('name') != 'Root':
        continue
    for mb in ctx.findall('ob:mousebind', ns):
        if mb.get('button') != 'Right':
            continue
        showmenu = mb.find('.//ob:action[@name=\"ShowMenu\"]', ns)
        assert showmenu is None, 'old ShowMenu action still present'
"

# Root context のMiddleクリック (client-list-combined-menu) など、他の
# マウスバインドは変更していないこと
check "Root context Middle mousebind still shows client-list-combined-menu (unchanged)" \
	python3 -c "
import xml.etree.ElementTree as ET
ns = {'ob': 'http://openbox.org/3.4/rc'}
root = ET.parse('${RC_XML}').getroot()
for ctx in root.findall('.//ob:context', ns):
    if ctx.get('name') != 'Root':
        continue
    for mb in ctx.findall('ob:mousebind', ns):
        if mb.get('button') != 'Middle':
            continue
        menu = mb.find('.//ob:action[@name=\"ShowMenu\"]/ob:menu', ns)
        assert menu is not None and menu.text.strip() == 'client-list-combined-menu', menu
        raise SystemExit(0)
raise SystemExit('Root/Middle mousebind not found')
"

# tint2側の設定 (jgmenu_run呼び出し) が今回も変更されていないこと
# (28行目付近の既存チェックと同じ内容だが、Root右クリック切り替えの
# 文脈でも明示的に再確認する)
check "tint2rc still unmodified for menu button (jgmenu_run, re-checked for this change)" \
	grep -qx 'button_lclick_command = jgmenu_run' "${TINT2RC}"

# モックjgmenu_run・モックjgmenuで実バイナリを一切起動せず、
# (1) jgmenu_run apps が呼ばれること、(2) その標準出力が jgmenu --simple の
# 標準入力へそのままパイプされること、(3) jgmenu が --at-pointer --simple を
# 受け取ることを検証する
MOCKDIR="$(mktemp -d)"
trap 'rm -rf "${MOCKDIR}"' EXIT
ARGS_FILE="${MOCKDIR}/args.txt"
STDIN_FILE="${MOCKDIR}/stdin.txt"
RUN_ARGS_FILE="${MOCKDIR}/run_args.txt"

cat >"${MOCKDIR}/jgmenu_run" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" >"${MOCK_JGMENU_RUN_ARGS_FILE}"
printf 'MockItem,mock-command\n'
EOF
chmod +x "${MOCKDIR}/jgmenu_run"

cat >"${MOCKDIR}/jgmenu" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" >"${MOCK_JGMENU_ARGS_FILE}"
cat >"${MOCK_JGMENU_STDIN_FILE}"
EOF
chmod +x "${MOCKDIR}/jgmenu"

MOCK_JGMENU_ARGS_FILE="${ARGS_FILE}" \
MOCK_JGMENU_STDIN_FILE="${STDIN_FILE}" \
MOCK_JGMENU_RUN_ARGS_FILE="${RUN_ARGS_FILE}" \
PATH="${MOCKDIR}:${PATH}" "${WRAPPER}"

printf '%s\n' 'apps' >"${MOCKDIR}/run_args_expected.txt"
check "mocked jgmenu_run received exactly: apps" \
	cmp -s "${RUN_ARGS_FILE}" "${MOCKDIR}/run_args_expected.txt"

printf '%s\n' '--at-pointer' '--simple' >"${MOCKDIR}/args_expected.txt"
check "mocked jgmenu received exactly: --at-pointer then --simple (2 args, in order)" \
	cmp -s "${ARGS_FILE}" "${MOCKDIR}/args_expected.txt"

printf '%s\n' 'MockItem,mock-command' >"${MOCKDIR}/stdin_expected.txt"
check "jgmenu_run apps output was piped into jgmenu's stdin unchanged" \
	cmp -s "${STDIN_FILE}" "${MOCKDIR}/stdin_expected.txt"

#==========================
# ウィンドウスナップ (Super+矢印)。追加スクリプト・daemonは使わず、
# Openbox標準action (Unmaximize/MoveResizeTo/ToggleMaximize) のみで
# 実装されていることを、<keyboard>直下のkeybind構造から確認する。
#==========================
check "keyboard has exactly one W-Left keybind" \
	python3 -c "
import xml.etree.ElementTree as ET
ns = {'ob': 'http://openbox.org/3.4/rc'}
root = ET.parse('${RC_XML}').getroot()
kb = root.find('.//ob:keyboard', ns)
matches = [k for k in kb.findall('ob:keybind', ns) if k.get('key') == 'W-Left']
assert len(matches) == 1, f'expected exactly 1, found {len(matches)}'
"

check "keyboard has exactly one W-Right keybind" \
	python3 -c "
import xml.etree.ElementTree as ET
ns = {'ob': 'http://openbox.org/3.4/rc'}
root = ET.parse('${RC_XML}').getroot()
kb = root.find('.//ob:keyboard', ns)
matches = [k for k in kb.findall('ob:keybind', ns) if k.get('key') == 'W-Right']
assert len(matches) == 1, f'expected exactly 1, found {len(matches)}'
"

check "keyboard has exactly one W-Up keybind" \
	python3 -c "
import xml.etree.ElementTree as ET
ns = {'ob': 'http://openbox.org/3.4/rc'}
root = ET.parse('${RC_XML}').getroot()
kb = root.find('.//ob:keyboard', ns)
matches = [k for k in kb.findall('ob:keybind', ns) if k.get('key') == 'W-Up']
assert len(matches) == 1, f'expected exactly 1, found {len(matches)}'
"

check "keyboard has exactly one W-Down keybind" \
	python3 -c "
import xml.etree.ElementTree as ET
ns = {'ob': 'http://openbox.org/3.4/rc'}
root = ET.parse('${RC_XML}').getroot()
kb = root.find('.//ob:keyboard', ns)
matches = [k for k in kb.findall('ob:keybind', ns) if k.get('key') == 'W-Down']
assert len(matches) == 1, f'expected exactly 1, found {len(matches)}'
"

check "W-Left actions are, in order, Unmaximize then MoveResizeTo(x=0,y=0,width=50%,height=100%)" \
	python3 -c "
import xml.etree.ElementTree as ET
ns = {'ob': 'http://openbox.org/3.4/rc'}
root = ET.parse('${RC_XML}').getroot()
kb = root.find('.//ob:keyboard', ns)
kbd = [k for k in kb.findall('ob:keybind', ns) if k.get('key') == 'W-Left'][0]
actions = kbd.findall('ob:action', ns)
assert [a.get('name') for a in actions] == ['Unmaximize', 'MoveResizeTo'], [a.get('name') for a in actions]
mrt = actions[1]
def val(tag):
    e = mrt.find(f'ob:{tag}', ns)
    assert e is not None, f'missing {tag}'
    return e.text.strip()
assert val('x') == '0', val('x')
assert val('y') == '0', val('y')
assert val('width') == '50%', val('width')
assert val('height') == '100%', val('height')
"

check "W-Right actions are, in order, Unmaximize then MoveResizeTo(x=-0,y=0,width=50%,height=100%)" \
	python3 -c "
import xml.etree.ElementTree as ET
ns = {'ob': 'http://openbox.org/3.4/rc'}
root = ET.parse('${RC_XML}').getroot()
kb = root.find('.//ob:keyboard', ns)
kbd = [k for k in kb.findall('ob:keybind', ns) if k.get('key') == 'W-Right'][0]
actions = kbd.findall('ob:action', ns)
assert [a.get('name') for a in actions] == ['Unmaximize', 'MoveResizeTo'], [a.get('name') for a in actions]
mrt = actions[1]
def val(tag):
    e = mrt.find(f'ob:{tag}', ns)
    assert e is not None, f'missing {tag}'
    return e.text.strip()
assert val('x') == '-0', val('x')
assert val('y') == '0', val('y')
assert val('width') == '50%', val('width')
assert val('height') == '100%', val('height')
"

check "W-Up actions are, in order, Unmaximize then ToggleMaximize" \
	python3 -c "
import xml.etree.ElementTree as ET
ns = {'ob': 'http://openbox.org/3.4/rc'}
root = ET.parse('${RC_XML}').getroot()
kb = root.find('.//ob:keyboard', ns)
kbd = [k for k in kb.findall('ob:keybind', ns) if k.get('key') == 'W-Up'][0]
actions = kbd.findall('ob:action', ns)
assert [a.get('name') for a in actions] == ['Unmaximize', 'ToggleMaximize'], [a.get('name') for a in actions]
"

check "W-Down actions are exactly Unmaximize (only, no other action)" \
	python3 -c "
import xml.etree.ElementTree as ET
ns = {'ob': 'http://openbox.org/3.4/rc'}
root = ET.parse('${RC_XML}').getroot()
kb = root.find('.//ob:keyboard', ns)
kbd = [k for k in kb.findall('ob:keybind', ns) if k.get('key') == 'W-Down'][0]
actions = kbd.findall('ob:action', ns)
assert [a.get('name') for a in actions] == ['Unmaximize'], [a.get('name') for a in actions]
"

check "existing W-S-Left/Right/Up/Down DirectionalCycleWindows bindings are unchanged" \
	python3 -c "
import xml.etree.ElementTree as ET
ns = {'ob': 'http://openbox.org/3.4/rc'}
root = ET.parse('${RC_XML}').getroot()
kb = root.find('.//ob:keyboard', ns)
expected = {'W-S-Right': 'right', 'W-S-Left': 'left', 'W-S-Up': 'up', 'W-S-Down': 'down'}
for key, direction in expected.items():
    matches = [k for k in kb.findall('ob:keybind', ns) if k.get('key') == key]
    assert len(matches) == 1, f'{key}: expected exactly 1, found {len(matches)}'
    actions = matches[0].findall('ob:action', ns)
    assert [a.get('name') for a in actions] == ['DirectionalCycleWindows'], (key, [a.get('name') for a in actions])
    d = actions[0].find('ob:direction', ns)
    assert d is not None and d.text.strip() == direction, (key, d)
"

echo "SCENARIOS=$((PASS + FAIL)) PASS=${PASS} FAIL=${FAIL}"
[ "${FAIL}" -eq 0 ]
