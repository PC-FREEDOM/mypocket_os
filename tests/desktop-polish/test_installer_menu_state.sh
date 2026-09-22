#!/bin/sh
#
# mypocketos-installer-menu-state に対する直接実行テスト。
# productionスクリプトは起動モードを引数で差し替えられ、$HOME環境変数を
# 差し替えることで対象ディレクトリをテスト用の一時ディレクトリへ向け
# られる設計になっているため(本番呼び出しはいずれも無引数・実HOME)、
# モック・sandboxは不要で、productionをそのまま直接実行して検証する
# (test_boot_mode.shと同じ方針)。実xinput・実jgmenu・実Calamaresは
# 一切使用しない。
#
# 2026-09-15、実機VM確認により、Debian Live環境で実際にjgmenuへ表示
# されるCalamares関連の.desktopが以下の2種類であることが判明した
# (dpkg -S / dpkg-divertで確認済み)。
#   - calamares-install-debian.desktop (Debian公式ラッパー入口)
#   - calamares.desktop.orig (calamares-settings-debianがdpkg-divertで
#     退避した、本体パッケージの素朴なdesktop entry)
#
# 2026-09-16、さらに実機VMでInstalled環境まで確認したところ、Installed
# 環境ではdpkg-divertの効果が及ばず、calamares本体パッケージが提供する
# 素の /usr/share/applications/calamares.desktop がそのまま存在すること
# が判明した(dpkg -S で確認済み)。本テストはこの3ファイル構成
# (calamares.desktop / calamares.desktop.orig / calamares-install-debian
# .desktop) に対する挙動を検証する。
#
# 2026-09-22、jgmenuの「その他」カテゴリに空項目が現れる問題の原因が、
# 上書きファイルの内容 (Hidden=trueのみ) であることが判明した。jgmenu-apps
# (csv_cmd=apps) はHiddenを解釈せず、NoDisplay=trueかTryExec不在の場合だけ
# 項目を表示対象から外す (jgmenu 4.5.0 src/desktop.c・jgmenu-apps.c)。
# Hidden=trueのみの上書きファイルは、名前もExecもCategoriesも空のアプリ
# としてどのカテゴリにも属さず、「その他」に空項目として残っていた。
# 上書きファイルはHidden=trueにNoDisplay=trueを併記する内容とし、本テストは
# その内容と、jgmenu-appsの表示対象から外れることを確認する。
# 実際のjgmenu-appsバイナリが利用できる環境 (/usr/lib/jgmenu/jgmenu-apps、
# または環境変数 JGMENU_APPS で指定) では実際に実行して確認し、無い環境
# (CI等) ではその項目のみ省略して、jgmenu-appsの除外条件を再現した静的な
# 確認だけを行う。
#
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/config/includes.chroot/usr/local/bin/mypocketos-installer-menu-state"
AUTOSTART="${REPO_ROOT}/config/includes.chroot/etc/skel/.config/openbox/autostart"

DESKTOP_ID_PLAIN='calamares.desktop'
DESKTOP_ID_ORIG='calamares.desktop.orig'
DESKTOP_ID_INSTALL_DEBIAN='calamares-install-debian.desktop'

PASS=0
FAIL=0

TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT

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

# $1 = HOMEディレクトリ, $2 = desktop ID (ファイル名)
target_path() {
	printf '%s/.local/share/applications/%s' "$1" "$2"
}

new_home() {
	# 一意なテスト用HOMEディレクトリを作成し、パスを返す。
	h="$(mktemp -d "${TMPDIR}/home.XXXXXX")"
	printf '%s' "$h"
}

expected_managed_content() {
	printf '[Desktop Entry]\nHidden=true\nNoDisplay=true\nX-MyPocketOS-Managed=true'
}

check "production script exists" test -f "${SCRIPT}"
check "production script is executable" test -x "${SCRIPT}"

#==========================
# 1・2・3. Normal Live: calamares.desktop と calamares.desktop.orig を
#          隠し、calamares-install-debian.desktop は隠さない
#==========================
h1="$(new_home)"
HOME="$h1" "${SCRIPT}" "Normal Live"
check "Normal Live: calamares.desktop Hidden override is created" \
	test -f "$(target_path "$h1" "${DESKTOP_ID_PLAIN}")"
check "Normal Live: calamares.desktop content is Hidden=true + NoDisplay=true + managed marker" \
	sh -c '[ "$(cat "$1")" = "$2" ]' _ "$(target_path "$h1" "${DESKTOP_ID_PLAIN}")" "$(expected_managed_content)"
check "Normal Live: calamares.desktop.orig Hidden override is created" \
	test -f "$(target_path "$h1" "${DESKTOP_ID_ORIG}")"
check "Normal Live: calamares.desktop.orig content is Hidden=true + NoDisplay=true + managed marker" \
	sh -c '[ "$(cat "$1")" = "$2" ]' _ "$(target_path "$h1" "${DESKTOP_ID_ORIG}")" "$(expected_managed_content)"
check "Normal Live: calamares-install-debian.desktop Hidden override does NOT exist (installer stays visible)" \
	sh -c '[ ! -e "$1" ]' _ "$(target_path "$h1" "${DESKTOP_ID_INSTALL_DEBIAN}")"

#==========================
# 4. Persistence: Normal Liveと同じ
#==========================
h2="$(new_home)"
HOME="$h2" "${SCRIPT}" Persistence
check "Persistence: calamares.desktop Hidden override is created" \
	test -f "$(target_path "$h2" "${DESKTOP_ID_PLAIN}")"
check "Persistence: calamares.desktop.orig Hidden override is created" \
	test -f "$(target_path "$h2" "${DESKTOP_ID_ORIG}")"
check "Persistence: calamares-install-debian.desktop Hidden override does NOT exist (installer stays visible)" \
	sh -c '[ ! -e "$1" ]' _ "$(target_path "$h2" "${DESKTOP_ID_INSTALL_DEBIAN}")"

#==========================
# 5. Installed: 3つすべて隠す
#==========================
h3="$(new_home)"
HOME="$h3" "${SCRIPT}" Installed
check "Installed: calamares.desktop Hidden override is created" \
	test -f "$(target_path "$h3" "${DESKTOP_ID_PLAIN}")"
check "Installed: calamares.desktop.orig Hidden override is created" \
	test -f "$(target_path "$h3" "${DESKTOP_ID_ORIG}")"
check "Installed: calamares-install-debian.desktop Hidden override is created" \
	test -f "$(target_path "$h3" "${DESKTOP_ID_INSTALL_DEBIAN}")"
check "Installed: calamares-install-debian.desktop content is Hidden=true + NoDisplay=true + managed marker" \
	sh -c '[ "$(cat "$1")" = "$2" ]' _ "$(target_path "$h3" "${DESKTOP_ID_INSTALL_DEBIAN}")" "$(expected_managed_content)"

#==========================
# 6. Unknown: 3つとも状態変更しない
#==========================
h4="$(new_home)"
HOME="$h4" "${SCRIPT}" Unknown
check "Unknown (no prior state): does not create ~/.local/share/applications at all" \
	sh -c '[ ! -e "$1/.local/share/applications" ]' _ "$h4"

h5="$(new_home)"
HOME="$h5" "${SCRIPT}" Installed
HOME="$h5" "${SCRIPT}" Unknown
check "Unknown (existing state present): calamares.desktop left untouched" \
	test -f "$(target_path "$h5" "${DESKTOP_ID_PLAIN}")"
check "Unknown (existing state present): calamares.desktop.orig left untouched" \
	test -f "$(target_path "$h5" "${DESKTOP_ID_ORIG}")"
check "Unknown (existing state present): calamares-install-debian.desktop left untouched" \
	test -f "$(target_path "$h5" "${DESKTOP_ID_INSTALL_DEBIAN}")"

#==========================
# 7・8. Installed -> Normal Live / Persistence:
#       calamares-install-debian.desktopのMyPocketOS管理overrideだけ削除
#       (calamares.desktop / calamares.desktop.origは隠したまま)
#==========================
h6="$(new_home)"
HOME="$h6" "${SCRIPT}" Installed
HOME="$h6" "${SCRIPT}" "Normal Live"
check "Installed->Normal Live: calamares-install-debian.desktop override removed" \
	sh -c '[ ! -e "$1" ]' _ "$(target_path "$h6" "${DESKTOP_ID_INSTALL_DEBIAN}")"
check "Installed->Normal Live: calamares.desktop stays hidden" \
	test -f "$(target_path "$h6" "${DESKTOP_ID_PLAIN}")"
check "Installed->Normal Live: calamares.desktop.orig stays hidden" \
	test -f "$(target_path "$h6" "${DESKTOP_ID_ORIG}")"

h7="$(new_home)"
HOME="$h7" "${SCRIPT}" Installed
HOME="$h7" "${SCRIPT}" Persistence
check "Installed->Persistence: calamares-install-debian.desktop override removed" \
	sh -c '[ ! -e "$1" ]' _ "$(target_path "$h7" "${DESKTOP_ID_INSTALL_DEBIAN}")"
check "Installed->Persistence: calamares.desktop stays hidden" \
	test -f "$(target_path "$h7" "${DESKTOP_ID_PLAIN}")"
check "Installed->Persistence: calamares.desktop.orig stays hidden" \
	test -f "$(target_path "$h7" "${DESKTOP_ID_ORIG}")"

#==========================
# 9・10. calamares.desktop / calamares.desktop.orig は
#        Live/Persistence/Installed の全てでHidden維持であることの
#        直接的な確認(往復させても消えない)
#==========================
h8="$(new_home)"
HOME="$h8" "${SCRIPT}" "Normal Live"
HOME="$h8" "${SCRIPT}" Persistence
HOME="$h8" "${SCRIPT}" Installed
HOME="$h8" "${SCRIPT}" "Normal Live"
check "calamares.desktop remains hidden across Normal Live/Persistence/Installed transitions" \
	test -f "$(target_path "$h8" "${DESKTOP_ID_PLAIN}")"
check "calamares.desktop.orig remains hidden across Normal Live/Persistence/Installed transitions" \
	test -f "$(target_path "$h8" "${DESKTOP_ID_ORIG}")"

#==========================
# 11・12. 3desktop IDすべてについてユーザー独自ファイルを上書き・削除しない
#==========================
h9="$(new_home)"
mkdir -p "${h9}/.local/share/applications"
printf '[Desktop Entry]\nName=My Own Plain\n' >"$(target_path "$h9" "${DESKTOP_ID_PLAIN}")"
printf '[Desktop Entry]\nName=My Own Orig\n' >"$(target_path "$h9" "${DESKTOP_ID_ORIG}")"
printf '[Desktop Entry]\nName=My Own InstallDebian\n' >"$(target_path "$h9" "${DESKTOP_ID_INSTALL_DEBIAN}")"
HOME="$h9" "${SCRIPT}" Installed
check "Installed: does not overwrite a user-owned (non-managed) calamares.desktop" \
	sh -c '[ "$(cat "$1")" = "$(printf "[Desktop Entry]\nName=My Own Plain")" ]' _ "$(target_path "$h9" "${DESKTOP_ID_PLAIN}")"
check "Installed: does not overwrite a user-owned (non-managed) calamares.desktop.orig" \
	sh -c '[ "$(cat "$1")" = "$(printf "[Desktop Entry]\nName=My Own Orig")" ]' _ "$(target_path "$h9" "${DESKTOP_ID_ORIG}")"
check "Installed: does not overwrite a user-owned (non-managed) calamares-install-debian.desktop" \
	sh -c '[ "$(cat "$1")" = "$(printf "[Desktop Entry]\nName=My Own InstallDebian")" ]' _ "$(target_path "$h9" "${DESKTOP_ID_INSTALL_DEBIAN}")"
HOME="$h9" "${SCRIPT}" "Normal Live"
check "Normal Live: does not delete a user-owned (non-managed) calamares.desktop" \
	test -f "$(target_path "$h9" "${DESKTOP_ID_PLAIN}")"
check "Normal Live: does not delete a user-owned (non-managed) calamares.desktop.orig" \
	test -f "$(target_path "$h9" "${DESKTOP_ID_ORIG}")"
check "Normal Live: does not delete a user-owned (non-managed) calamares-install-debian.desktop" \
	test -f "$(target_path "$h9" "${DESKTOP_ID_INSTALL_DEBIAN}")"

#==========================
# 13. 3desktop IDすべてについてsymlink防御
#==========================
h10="$(new_home)"
mkdir -p "${h10}/.local/share/applications"
ln -s /etc/passwd "$(target_path "$h10" "${DESKTOP_ID_PLAIN}")"
ln -s /etc/hostname "$(target_path "$h10" "${DESKTOP_ID_ORIG}")"
ln -s /etc/hosts "$(target_path "$h10" "${DESKTOP_ID_INSTALL_DEBIAN}")"
HOME="$h10" "${SCRIPT}" Installed
check "Installed: does not follow/overwrite calamares.desktop when it is itself a symlink" \
	sh -c '[ -L "$1" ] && [ "$(readlink "$1")" = "/etc/passwd" ]' _ "$(target_path "$h10" "${DESKTOP_ID_PLAIN}")"
check "Installed: does not follow/overwrite calamares.desktop.orig when it is itself a symlink" \
	sh -c '[ -L "$1" ] && [ "$(readlink "$1")" = "/etc/hostname" ]' _ "$(target_path "$h10" "${DESKTOP_ID_ORIG}")"
check "Installed: does not follow/overwrite calamares-install-debian.desktop when it is itself a symlink" \
	sh -c '[ -L "$1" ] && [ "$(readlink "$1")" = "/etc/hosts" ]' _ "$(target_path "$h10" "${DESKTOP_ID_INSTALL_DEBIAN}")"
HOME="$h10" "${SCRIPT}" "Normal Live"
check "Normal Live: does not delete calamares-install-debian.desktop when it is itself a symlink" \
	test -L "$(target_path "$h10" "${DESKTOP_ID_INSTALL_DEBIAN}")"
check "Normal Live: does not touch calamares.desktop when it is itself a symlink" \
	test -L "$(target_path "$h10" "${DESKTOP_ID_PLAIN}")"
check "Normal Live: does not touch calamares.desktop.orig when it is itself a symlink" \
	test -L "$(target_path "$h10" "${DESKTOP_ID_ORIG}")"

#==========================
# 14. 冪等性 (3desktop IDともmtime不変)
#==========================
h11="$(new_home)"
HOME="$h11" "${SCRIPT}" Installed
mtime_plain_before="$(stat -c '%Y' "$(target_path "$h11" "${DESKTOP_ID_PLAIN}")")"
mtime_orig_before="$(stat -c '%Y' "$(target_path "$h11" "${DESKTOP_ID_ORIG}")")"
mtime_instdeb_before="$(stat -c '%Y' "$(target_path "$h11" "${DESKTOP_ID_INSTALL_DEBIAN}")")"
sleep 1
HOME="$h11" "${SCRIPT}" Installed
mtime_plain_after="$(stat -c '%Y' "$(target_path "$h11" "${DESKTOP_ID_PLAIN}")")"
mtime_orig_after="$(stat -c '%Y' "$(target_path "$h11" "${DESKTOP_ID_ORIG}")")"
mtime_instdeb_after="$(stat -c '%Y' "$(target_path "$h11" "${DESKTOP_ID_INSTALL_DEBIAN}")")"
check "Installed run twice: idempotent for calamares.desktop (mtime unchanged)" \
	sh -c '[ "$1" = "$2" ]' _ "${mtime_plain_before}" "${mtime_plain_after}"
check "Installed run twice: idempotent for calamares.desktop.orig (mtime unchanged)" \
	sh -c '[ "$1" = "$2" ]' _ "${mtime_orig_before}" "${mtime_orig_after}"
check "Installed run twice: idempotent for calamares-install-debian.desktop (mtime unchanged)" \
	sh -c '[ "$1" = "$2" ]' _ "${mtime_instdeb_before}" "${mtime_instdeb_after}"

#==========================
# 15. HOME異常時安全終了
#==========================
check "HOME unset: exits 0 without error" \
	sh -c 'env -u HOME "$1" Installed >/dev/null 2>&1' _ "${SCRIPT}"

h12_notdir="${TMPDIR}/not-a-directory"
: >"${h12_notdir}"
check "HOME points to a non-directory: exits 0 without creating anything" \
	sh -c 'HOME="$1" "$2" Installed >/dev/null 2>&1; [ ! -e "$1.local" ]' _ "${h12_notdir}" "${SCRIPT}"

h12_real="$(new_home)"
h12_sym="${TMPDIR}/symlinked-home"
ln -s "${h12_real}" "${h12_sym}"
check "HOME is a symlink: exits without writing through it" \
	sh -c 'HOME="$1" "$2" Installed >/dev/null 2>&1; [ ! -e "$3/.local" ]' _ "${h12_sym}" "${SCRIPT}" "${h12_real}"

#==========================
# 16. mypocketos-boot-modeが失敗 -> 安全側で何もしない
#==========================
h13="$(new_home)"
check "mypocketos-boot-mode unavailable (broken PATH): falls back to Unknown, no-op" \
	sh -c 'PATH=/nonexistent HOME="$1" "$2" >/dev/null 2>&1; [ ! -e "$1/.local/share/applications" ]' _ "${h13}" "${SCRIPT}"

#==========================
# 16b. 上書きファイルのNoDisplay=true (jgmenuの「その他」に空項目を出さない)
#==========================
# Normal Live (2個) と Installed (3個) の全上書きファイルについて、
# Hidden=trueとNoDisplay=trueの両方を持つこと。
for pair in "h1:Normal Live" "h3:Installed"; do
	var="${pair%%:*}"
	label="${pair#*:}"
	eval "hd=\${$var}"
	for id in "${DESKTOP_ID_PLAIN}" "${DESKTOP_ID_ORIG}" "${DESKTOP_ID_INSTALL_DEBIAN}"; do
		f="$(target_path "${hd}" "${id}")"
		[ -f "${f}" ] || continue
		check "${label}: ${id} override has NoDisplay=true" \
			grep -qxF 'NoDisplay=true' "${f}"
		check "${label}: ${id} override keeps Hidden=true" \
			grep -qxF 'Hidden=true' "${f}"
	done
done

# jgmenu-apps (jgmenu 4.5.0 desktop.c・jgmenu-apps.c) の除外条件の再現:
# [Desktop Entry]節のNoDisplayの値がtrue (大文字小文字を区別しない) であれば、
# 項目は表示対象から外れる。Hiddenは無視される。
check "jgmenu-apps rule: every override file is excluded from display (NoDisplay=true in [Desktop Entry])" \
	python3 -c "
import glob, sys
files = glob.glob('${h1}/.local/share/applications/*') + glob.glob('${h3}/.local/share/applications/*')
assert len(files) == 5, files
for f in files:
    in_entry = False; nodisplay = False
    for line in open(f, encoding='utf-8').read().splitlines():
        if line.startswith('['):
            in_entry = line.startswith('[Desktop Entry]')
        elif in_entry and '=' in line:
            k, v = line.split('=', 1)
            if k == 'NoDisplay' and v.lower() == 'true':
                nodisplay = True
    assert nodisplay, f
"

#==========================
# 16c. 古い内容 (Hidden=trueのみ) のMyPocketOS管理ファイルは、次回起動時に
#      新しい内容へ更新される (既存の「管理対象で内容が古い場合は更新」)
#==========================
legacy_content() {
	printf '[Desktop Entry]\nHidden=true\nX-MyPocketOS-Managed=true\n'
}
h14="$(new_home)"
mkdir -p "${h14}/.local/share/applications"
for id in "${DESKTOP_ID_PLAIN}" "${DESKTOP_ID_ORIG}" "${DESKTOP_ID_INSTALL_DEBIAN}"; do
	legacy_content >"$(target_path "$h14" "${id}")"
done
HOME="$h14" "${SCRIPT}" Installed
check "legacy managed calamares.desktop (no NoDisplay) is updated to the new content" \
	sh -c '[ "$(cat "$1")" = "$2" ]' _ "$(target_path "$h14" "${DESKTOP_ID_PLAIN}")" "$(expected_managed_content)"
check "legacy managed calamares.desktop.orig (no NoDisplay) is updated to the new content" \
	sh -c '[ "$(cat "$1")" = "$2" ]' _ "$(target_path "$h14" "${DESKTOP_ID_ORIG}")" "$(expected_managed_content)"
check "legacy managed calamares-install-debian.desktop (no NoDisplay) is updated to the new content" \
	sh -c '[ "$(cat "$1")" = "$2" ]' _ "$(target_path "$h14" "${DESKTOP_ID_INSTALL_DEBIAN}")" "$(expected_managed_content)"

# Live/Persistenceで起動した場合も、古いcalamares.desktop/.origは更新される。
h15="$(new_home)"
mkdir -p "${h15}/.local/share/applications"
legacy_content >"$(target_path "$h15" "${DESKTOP_ID_PLAIN}")"
legacy_content >"$(target_path "$h15" "${DESKTOP_ID_ORIG}")"
HOME="$h15" "${SCRIPT}" "Normal Live"
check "Normal Live: legacy managed calamares.desktop is updated to the new content" \
	sh -c '[ "$(cat "$1")" = "$2" ]' _ "$(target_path "$h15" "${DESKTOP_ID_PLAIN}")" "$(expected_managed_content)"
check "Normal Live: legacy managed calamares.desktop.orig is updated to the new content" \
	sh -c '[ "$(cat "$1")" = "$2" ]' _ "$(target_path "$h15" "${DESKTOP_ID_ORIG}")" "$(expected_managed_content)"

#==========================
# 16d. 実際のjgmenu-appsで、上書きファイルが「その他」に空項目を作らず、
#      同名のdesktop IDだけを隠すことを確認する (バイナリがある環境のみ)
#==========================
JGMENU_APPS_BIN="${JGMENU_APPS:-}"
if [ -z "${JGMENU_APPS_BIN}" ] && [ -x /usr/lib/jgmenu/jgmenu-apps ]; then
	JGMENU_APPS_BIN=/usr/lib/jgmenu/jgmenu-apps
fi
if [ -n "${JGMENU_APPS_BIN}" ] && [ -x "${JGMENU_APPS_BIN}" ]; then
	# 仮のシステム側desktop IDを用意する (名前は他と衝突しない固有の文字列)。
	sysdir="${TMPDIR}/sysdata"
	mkdir -p "${sysdir}/applications"
	for id in "${DESKTOP_ID_ORIG}" "${DESKTOP_ID_INSTALL_DEBIAN}"; do
		printf '[Desktop Entry]\nType=Application\nName=MPOSTEST %s\nExec=true\nCategories=System;\n' "${id}" \
			>"${sysdir}/applications/${id}"
	done
	run_apps() {
		env -u XDG_DATA_HOME HOME="$1" XDG_DATA_DIRS="${sysdir}" LANG=C LC_ALL=C \
			"${JGMENU_APPS_BIN}" 2>/dev/null
	}
	run_apps "$h1" >"${TMPDIR}/apps_live.csv" || true
	run_apps "$h3" >"${TMPDIR}/apps_installed.csv" || true
	empty_home="$(new_home)"
	run_apps "${empty_home}" >"${TMPDIR}/apps_none.csv" || true

	check "jgmenu-apps ran and produced the top-level category list (sanity)" \
		grep -q '^Accessories,' "${TMPDIR}/apps_none.csv"
	check "jgmenu-apps (no override): both fake system desktop IDs are listed (sanity)" \
		sh -c '[ "$(grep -c "MPOSTEST" "$1")" -eq 2 ]' _ "${TMPDIR}/apps_none.csv"
	check "jgmenu-apps (Normal Live): override files create no blank (nameless) menu entries" \
		sh -c '! grep -q "^\"\"\"\"\"\"," "$1"' _ "${TMPDIR}/apps_live.csv"
	check "jgmenu-apps (Normal Live): calamares.desktop.orig is hidden" \
		sh -c '! grep -q "MPOSTEST ${2}" "$1"' _ "${TMPDIR}/apps_live.csv" "${DESKTOP_ID_ORIG}"
	check "jgmenu-apps (Normal Live): calamares-install-debian.desktop stays visible" \
		grep -q "MPOSTEST ${DESKTOP_ID_INSTALL_DEBIAN}" "${TMPDIR}/apps_live.csv"
	check "jgmenu-apps (Installed): override files create no blank (nameless) menu entries" \
		sh -c '! grep -q "^\"\"\"\"\"\"," "$1"' _ "${TMPDIR}/apps_installed.csv"
	check "jgmenu-apps (Installed): calamares.desktop.orig is hidden" \
		sh -c '! grep -q "MPOSTEST ${2}" "$1"' _ "${TMPDIR}/apps_installed.csv" "${DESKTOP_ID_ORIG}"
	check "jgmenu-apps (Installed): calamares-install-debian.desktop is hidden" \
		sh -c '! grep -q "MPOSTEST ${2}" "$1"' _ "${TMPDIR}/apps_installed.csv" "${DESKTOP_ID_INSTALL_DEBIAN}"
else
	echo "SKIP: jgmenu-apps binary not found (set JGMENU_APPS or install jgmenu); real jgmenu-apps checks omitted" >&2
fi

#==========================
# 17. autostartからの呼び出しは1回のみ
#==========================
# コメント中の "mypocketos-installer-menu-state(1)" のような言及と、
# 実際の呼び出し行 (行頭から行末まで、引数なしのコマンド単体) を区別する
# ため、行全体が完全一致するパターンでのみ数える (test_boot_mode.shの
# 同様のcheckと同じ考え方)。
check "autostart invokes mypocketos-installer-menu-state exactly once (actual call, not comment mentions)" \
	sh -c '[ "$(grep -cx "mypocketos-installer-menu-state" "$1")" -eq 1 ]' _ "${AUTOSTART}"
check "autostart does not embed the hide/show logic directly (calls the dedicated script only)" \
	sh -c '! grep -q "X-MyPocketOS-Managed" "$1"' _ "${AUTOSTART}"

echo "SCENARIOS=$((PASS + FAIL)) PASS=${PASS} FAIL=${FAIL}"
[ "${FAIL}" -eq 0 ]
