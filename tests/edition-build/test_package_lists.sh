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

echo "SCENARIOS=$((PASS + FAIL)) PASS=${PASS} FAIL=${FAIL}"
[ "${FAIL}" -eq 0 ]
