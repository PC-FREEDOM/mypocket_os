#!/bin/sh
#
# タッチパッド既定動作 (libinput Xorg InputClass) に対する静的テスト。
# 実Xorg・実libinput・実タッチパッドは一切使用しない。
#
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CONF="${REPO_ROOT}/config/includes.chroot/etc/X11/xorg.conf.d/51-mypocketos-touchpad.conf"
COMMON_LIST="${REPO_ROOT}/config/package-lists.d/mypocketos-common.list.chroot"

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

check "51-mypocketos-touchpad.conf exists" test -f "${CONF}"

# 40-libinput.conf (xserver-xorg-input-libinputパッケージ提供) より後に
# 読み込まれる必要がある (Xorgはxorg.conf.d配下をファイル名順に読み込み、
# 後から読み込まれたInputClassのOptionが同じデバイスに対して優先される)。
check "conf file is named to load after 40-libinput.conf (prefix > 40)" \
	python3 -c "
import os, re
name = os.path.basename('${CONF}')
m = re.match(r'^(\d+)-', name)
assert m, f'no numeric prefix in {name}'
assert int(m.group(1)) > 40, f'prefix {m.group(1)} is not > 40'
"

# InputClassセクションを構造的に解析し、次を確認する:
# - MatchIsTouchpad "on" を持つセクションが少なくとも1つ存在する
# - そのセクション内でTapping/TappingButtonMap/TappingDrag/ScrollMethodが
#   期待値どおり設定されている
# - デバイス名・vendor/product ID等のハードコード一致 (MatchProduct /
#   MatchVendor / MatchUSBID など) を使っていない
# - MatchIsPointer / MatchIsTouchscreen / MatchIsTablet を持つセクションには
#   同じOptionを適用していない (マウス・タッチスクリーン等への誤適用がない)
check "touchpad InputClass section has expected libinput options, is touchpad-only, and has no hardcoded device match" \
	python3 -c "
import re

with open('${CONF}', encoding='utf-8') as f:
    text = f.read()

sections = re.findall(r'Section\s+\"InputClass\"(.*?)EndSection', text, re.S | re.I)
assert sections, 'no InputClass section found'

def opt(body, name):
    m = re.search(r'Option\s+\"' + re.escape(name) + r'\"\s+\"([^\"]*)\"', body)
    return m.group(1) if m else None

def has_match(body, name):
    return re.search(r'Match' + name + r'\s+\"on\"', body, re.I) is not None

touchpad_sections = [s for s in sections if has_match(s, 'IsTouchpad')]
assert len(touchpad_sections) == 1, f'expected exactly 1 MatchIsTouchpad section, found {len(touchpad_sections)}'
body = touchpad_sections[0]

assert opt(body, 'Tapping') == 'on', f'Tapping={opt(body, \"Tapping\")}'
assert opt(body, 'TappingButtonMap') == 'lrm', f'TappingButtonMap={opt(body, \"TappingButtonMap\")}'
assert opt(body, 'TappingDrag') == 'on', f'TappingDrag={opt(body, \"TappingDrag\")}'
assert opt(body, 'ScrollMethod') == 'twofinger', f'ScrollMethod={opt(body, \"ScrollMethod\")}'

# デバイス名・vendor/product IDのハードコードがないこと
forbidden_matches = ['MatchProduct', 'MatchVendor', 'MatchUSBID', 'MatchTag']
for name in forbidden_matches:
    assert name not in text, f'{name} must not be used (would hardcode a specific device)'

# 他デバイスクラス (mouse/touchscreen/tablet) にはTapping系Optionを
# 適用していないこと
other_class_matches = ['IsPointer', 'IsTouchscreen', 'IsTablet']
for s in sections:
    if s is body:
        continue
    for name in other_class_matches:
        if has_match(s, name):
            for key in ('Tapping', 'TappingButtonMap', 'TappingDrag', 'ScrollMethod'):
                assert opt(s, key) is None, f'{name} section unexpectedly sets {key}'
"

# キーボード設定 (keyboard-configuration) やマウス以外の既存設定へ
# 影響していないこと。新規xorg.conf.dファイルは今回追加した1件のみである
# ことを確認する (mouse/keyboard向けの別ファイルを誤って追加していない)。
check "exactly one new xorg.conf.d file was added (51-mypocketos-touchpad.conf)" \
	sh -c '
	dir="${1}/config/includes.chroot/etc/X11/xorg.conf.d"
	count=$(find "$dir" -maxdepth 1 -type f | wc -l)
	[ "$count" -eq 1 ]
	' _ "${REPO_ROOT}"

# 必要なlibinput/Xorgパッケージ (xserver-xorg-input-all経由で
# xserver-xorg-input-libinputへ依存) が既に共通パッケージリストに
# 含まれていること。新規パッケージの追加は不要である。
check "common package list already includes xserver-xorg-input-all (pulls in xserver-xorg-input-libinput)" \
	grep -qx 'xserver-xorg-input-all' "${COMMON_LIST}"

echo "SCENARIOS=$((PASS + FAIL)) PASS=${PASS} FAIL=${FAIL}"
[ "${FAIL}" -eq 0 ]
