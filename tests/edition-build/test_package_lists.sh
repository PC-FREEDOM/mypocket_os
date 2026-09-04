#!/bin/sh
#
# config/package-lists.d/ の内容に対する静的テスト。
# 実ファイルの読み取りのみ行い、config/package-lists/への配置・実lb・
# sudoは一切行わない。
#
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COMMON_LIST="${REPO_ROOT}/config/package-lists.d/mypocketos-common.list.chroot"
STANDARD_LIST="${REPO_ROOT}/config/package-lists.d/mypocketos-standard.list.chroot"

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

check "mypocketos-common.list.chroot exists" test -f "${COMMON_LIST}"
check "mypocketos-standard.list.chroot exists" test -f "${STANDARD_LIST}"

# 旧パス (config/package-lists/直下への恒久配置) が復活していないこと。
# config/package-lists/ にはlive.list.chroot (lb config自動生成、
# .gitignoreで無視) 以外のファイルが常駐していてはならない。
check "config/package-lists/ has no permanently-tracked common/standard list" \
	sh -c '! git -C "$1" ls-files config/package-lists/ | grep -qE "mypocketos-(common|standard)\.list\.chroot"' _ "${REPO_ROOT}"

# ---- Standard専用アプリがcommonに含まれないこと ------------------------------
for pkg in firefox-esr firefox-esr-l10n-ja \
	libreoffice-writer libreoffice-calc libreoffice-impress libreoffice-draw \
	libreoffice-gtk3 libreoffice-l10n-ja libreoffice-help-ja \
	drawing mousepad galculator; do
	check "common list does not contain Standard-only package: ${pkg}" \
		sh -c '! grep -qx "$1" "$2"' _ "${pkg}" "${COMMON_LIST}"
done

# ---- standardに現在の12パッケージが存在すること -------------------------------
for pkg in firefox-esr firefox-esr-l10n-ja \
	libreoffice-writer libreoffice-calc libreoffice-impress libreoffice-draw \
	libreoffice-gtk3 libreoffice-l10n-ja libreoffice-help-ja \
	drawing mousepad galculator; do
	count="$(grep -cx "${pkg}" "${STANDARD_LIST}")"
	check "standard list contains exactly once: ${pkg}" test "${count}" -eq 1
done

# ---- commonの中身がBase版として意味を持つ最小構成であることの基本確認 --------
for pkg in openbox tint2 lightdm pcmanfm jgmenu conky-std pasystray yad; do
	check "common list contains: ${pkg}" grep -qx "${pkg}" "${COMMON_LIST}"
done

# ---- Flatpakがcommon (Base/Standard共通) に含まれること -----------------------
# 追加アプリ導入の正式な方法として`flatpak --user`をBase/Standard両方で
# 使えるようにするため、Standard専用ではなくcommonへ追加する。
check "common list contains: flatpak" grep -qx 'flatpak' "${COMMON_LIST}"
check "flatpak is listed exactly once in common list" \
	sh -c '[ "$(grep -cx "flatpak" "$1")" -eq 1 ]' _ "${COMMON_LIST}"
check "flatpak is not duplicated into standard list" \
	sh -c '! grep -qx "flatpak" "$1"' _ "${STANDARD_LIST}"

# ---- 不要なFlatpak関連GUIフロントエンド・ソフトウェアセンターを追加していないこと ----
# gnome-software等のGUIストアや、flatpak以外のパッケージ管理GUIフロント
# エンドは今回追加しない方針のため、common/standard双方に存在しないことを
# 確認する。
for pkg in gnome-software gnome-software-plugin-flatpak plasma-discover \
	flatpak-builder software-properties-gtk synaptic; do
	check "no GUI software-center frontend added to common: ${pkg}" \
		sh -c '! grep -qx "$1" "$2"' _ "${pkg}" "${COMMON_LIST}"
	check "no GUI software-center frontend added to standard: ${pkg}" \
		sh -c '! grep -qx "$1" "$2"' _ "${pkg}" "${STANDARD_LIST}"
done

# ---- Flathub等のremoteをシステムワイドに自動登録していないこと --------------
# 既存設計の確認結果、自動登録の要否は独断で決めない方針のため、今回は
# flatpakパッケージ本体の追加のみとし、remote登録を行うhook・
# includes.chrootファイルを追加していないことを確認する。
check "no flatpakrepo file added under config/includes.chroot" \
	sh -c '! find "$1/config/includes.chroot" -iname "*.flatpakrepo" 2>/dev/null | grep -q .' _ "${REPO_ROOT}"
check "no hook performs flatpak remote-add (system-wide auto-registration)" \
	sh -c '! grep -rl "remote-add" "$1/config/hooks" 2>/dev/null | grep -q .' _ "${REPO_ROOT}"

echo "SCENARIOS=$((PASS + FAIL)) PASS=${PASS} FAIL=${FAIL}"
[ "${FAIL}" -eq 0 ]
