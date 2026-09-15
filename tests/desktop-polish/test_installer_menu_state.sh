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
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/config/includes.chroot/usr/local/bin/mypocketos-installer-menu-state"
AUTOSTART="${REPO_ROOT}/config/includes.chroot/etc/skel/.config/openbox/autostart"

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

target_path() {
	# $1 = HOMEディレクトリ
	printf '%s/.local/share/applications/calamares.desktop' "$1"
}

new_home() {
	# 一意なテスト用HOMEディレクトリを作成し、パスを返す。
	h="$(mktemp -d "${TMPDIR}/home.XXXXXX")"
	printf '%s' "$h"
}

check "production script exists" test -f "${SCRIPT}"
check "production script is executable" test -x "${SCRIPT}"

#==========================
# 1. Installed -> Hidden overrideを作成する
#==========================
h1="$(new_home)"
HOME="$h1" "${SCRIPT}" Installed
check "Installed: override file is created" test -f "$(target_path "$h1")"

#==========================
# 2. Installed時の内容 -> Hidden=true・MyPocketOS管理と識別可能
#==========================
check "Installed: content is exactly [Desktop Entry]/Hidden=true/marker" \
	sh -c '
	want="$(printf "[Desktop Entry]\nHidden=true\nX-MyPocketOS-Managed=true")"
	got="$(cat "$1")"
	[ "$got" = "$want" ]
	' _ "$(target_path "$h1")"
check "Installed: marker line X-MyPocketOS-Managed=true is present" \
	grep -qxF 'X-MyPocketOS-Managed=true' "$(target_path "$h1")"
check "Installed: Hidden=true line is present" \
	grep -qxF 'Hidden=true' "$(target_path "$h1")"

#==========================
# 3. Normal Live -> Calamaresを隠さない (overrideを削除する)
#==========================
h2="$(new_home)"
HOME="$h2" "${SCRIPT}" Installed
check "precondition: override exists before Normal Live test" test -f "$(target_path "$h2")"
HOME="$h2" "${SCRIPT}" "Normal Live"
check "Normal Live: managed override is removed (Calamares becomes visible again)" \
	sh -c '[ ! -e "$1" ]' _ "$(target_path "$h2")"

#==========================
# 4. Persistence -> Calamaresを隠さない (overrideを削除する)
#==========================
h3="$(new_home)"
HOME="$h3" "${SCRIPT}" Installed
check "precondition: override exists before Persistence test" test -f "$(target_path "$h3")"
HOME="$h3" "${SCRIPT}" Persistence
check "Persistence: managed override is removed (Calamares becomes visible again)" \
	sh -c '[ ! -e "$1" ]' _ "$(target_path "$h3")"

#==========================
# 5. Unknown -> 既存状態を破壊しない
#==========================
h4="$(new_home)"
HOME="$h4" "${SCRIPT}" Unknown
check "Unknown (no prior state): does not create ~/.local/share/applications at all" \
	sh -c '[ ! -e "$1/.local/share/applications" ]' _ "$h4"

h5="$(new_home)"
HOME="$h5" "${SCRIPT}" Installed
check "precondition: override exists before Unknown-preserves test" test -f "$(target_path "$h5")"
HOME="$h5" "${SCRIPT}" Unknown
check "Unknown (existing managed override present): leaves it untouched (fail-closed, no action either way)" \
	test -f "$(target_path "$h5")"

#==========================
# 6. Installedを複数回実行 -> 冪等 (mtimeが変化しない)
#==========================
h6="$(new_home)"
HOME="$h6" "${SCRIPT}" Installed
mtime_before="$(stat -c '%Y' "$(target_path "$h6")")"
sleep 1
HOME="$h6" "${SCRIPT}" Installed
mtime_after="$(stat -c '%Y' "$(target_path "$h6")")"
check "Installed run twice: idempotent, no unnecessary rewrite (mtime unchanged)" \
	sh -c '[ "$1" = "$2" ]' _ "${mtime_before}" "${mtime_after}"

#==========================
# 7. Liveへ戻った場合 -> MyPocketOS管理overrideだけ削除できる
#==========================
# (3・4のシナリオで既に確認済みだが、Installed->Persistence->Normal Live
# という往復シーケンスでも壊れないことを追加確認する)
h7="$(new_home)"
HOME="$h7" "${SCRIPT}" Installed
HOME="$h7" "${SCRIPT}" Persistence
check "after Installed->Persistence: override removed" sh -c '[ ! -e "$1" ]' _ "$(target_path "$h7")"
HOME="$h7" "${SCRIPT}" Installed
HOME="$h7" "${SCRIPT}" "Normal Live"
check "after Installed->Normal Live: override removed" sh -c '[ ! -e "$1" ]' _ "$(target_path "$h7")"

#==========================
# 8. ユーザーが独自に作った calamares.desktop を誤削除・誤上書きしない
#==========================
h8="$(new_home)"
mkdir -p "${h8}/.local/share/applications"
printf '[Desktop Entry]\nName=My Own Thing\n' >"$(target_path "$h8")"
HOME="$h8" "${SCRIPT}" Installed
check "Installed: does not overwrite a user-owned (non-managed) calamares.desktop" \
	sh -c '[ "$(cat "$1")" = "$(printf "[Desktop Entry]\nName=My Own Thing")" ]' _ "$(target_path "$h8")"
HOME="$h8" "${SCRIPT}" "Normal Live"
check "Normal Live: does not delete a user-owned (non-managed) calamares.desktop" \
	test -f "$(target_path "$h8")"

#==========================
# 9. HOME未設定等 -> 安全に終了
#==========================
check "HOME unset: exits 0 without error" \
	sh -c 'env -u HOME "$1" Installed >/dev/null 2>&1' _ "${SCRIPT}"

h9_notdir="${TMPDIR}/not-a-directory"
: >"${h9_notdir}"
check "HOME points to a non-directory: exits 0 without creating anything" \
	sh -c 'HOME="$1" "$2" Installed >/dev/null 2>&1; [ ! -e "$1.local" ]' _ "${h9_notdir}" "${SCRIPT}"

h9_real="$(new_home)"
h9_sym="${TMPDIR}/symlinked-home"
ln -s "${h9_real}" "${h9_sym}"
check "HOME is a symlink: exits without writing through it" \
	sh -c 'HOME="$1" "$2" Installed >/dev/null 2>&1; [ ! -e "$3/.local" ]' _ "${h9_sym}" "${SCRIPT}" "${h9_real}"

#==========================
# 10. mypocketos-boot-modeが失敗 -> 安全側で何もしない
#==========================
h10="$(new_home)"
check "mypocketos-boot-mode unavailable (broken PATH): falls back to Unknown, no-op" \
	sh -c 'PATH=/nonexistent HOME="$1" "$2" >/dev/null 2>&1; [ ! -e "$1/.local/share/applications" ]' _ "${h10}" "${SCRIPT}"

#==========================
# 追加: TARGET/対象ディレクトリがシンボリックリンクの場合の防御
#==========================
h11="$(new_home)"
mkdir -p "${h11}/.local/share/applications"
ln -s /etc/passwd "$(target_path "$h11")"
HOME="$h11" "${SCRIPT}" Installed
check "Installed: does not follow/overwrite when target path is itself a symlink" \
	sh -c '[ -L "$1" ] && [ "$(readlink "$1")" = "/etc/passwd" ]' _ "$(target_path "$h11")"
HOME="$h11" "${SCRIPT}" "Normal Live"
check "Normal Live: does not delete when target path is itself a symlink" \
	test -L "$(target_path "$h11")"

#==========================
# autostart連携の静的確認
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
