#!/bin/sh
#
# MyPocketOS-Fluent-yellow.tar.gz アーカイブ自体に対する静的テスト。
# 実際の展開・実gtk-update-icon-cache・sudo・chroot操作は一切行わない
# (tar -tzfによる読み取り専用のエントリ一覧確認のみ)。
#
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ARCHIVE="${REPO_ROOT}/config/includes.chroot/usr/share/mypocketos/icon-themes/MyPocketOS-Fluent-yellow.tar.gz"
HOOK="${REPO_ROOT}/config/hooks/normal/mypocketos-fluent-icon-theme.hook.chroot"
THEME_NAME="MyPocketOS-Fluent-yellow"

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

check "archive exists" test -f "${ARCHIVE}"
check "gzip integrity OK" gzip -t "${ARCHIVE}"

#==========================
# hook記載のSHA-256と実アーカイブの一致
#==========================
hook_sha="$(sed -n 's/^EXPECTED_ARCHIVE_SHA256="\([0-9a-f]\{64\}\)"$/\1/p' "${HOOK}")"
check "hook contains a 64-hex-char SHA-256 constant" test -n "${hook_sha}"
actual_sha="$(sha256sum "${ARCHIVE}" | awk '{print $1}')"
check "archive SHA-256 matches hook's EXPECTED_ARCHIVE_SHA256" test "${actual_sha}" = "${hook_sha}"

#==========================
# エントリ一覧の取得 (読み取り専用)
#==========================
LISTING="$(mktemp)"
trap 'rm -f "${LISTING}"' EXIT
tar -tzf "${ARCHIVE}" >"${LISTING}"

check "listing is non-empty" test -s "${LISTING}"

#==========================
# パス安全性 (絶対パス・".."・トップディレクトリ)
#==========================
check "no absolute paths in archive" sh -c '! grep -qE "^/" "$1"' _ "${LISTING}"
check "no unsafe .. segments in archive" sh -c '! grep -qE "(^|/)\.\.(/|\$)" "$1"' _ "${LISTING}"

all_under_prefix=true
while IFS= read -r entry; do
	case "${entry}" in
	"${THEME_NAME}" | "${THEME_NAME}/"*) ;;
	*)
		all_under_prefix=false
		echo "unexpected top-level entry: ${entry}" >&2
		;;
	esac
done <"${LISTING}"
check "all entries are under ${THEME_NAME}/" sh -c '[ "$1" = "true" ]' _ "${all_under_prefix}"

check "old top-level Fluent-yellow/ (without MyPocketOS- prefix) is absent" \
	sh -c '! grep -qE "^Fluent-yellow/" "$1"' _ "${LISTING}"

#==========================
# 必須ファイル
#==========================
check "COPYING present" grep -qx "${THEME_NAME}/COPYING" "${LISTING}"
check "MODIFICATIONS.md present" grep -qx "${THEME_NAME}/MODIFICATIONS.md" "${LISTING}"
check "index.theme present" grep -qx "${THEME_NAME}/index.theme" "${LISTING}"

#==========================
# symbolic音量4種
#==========================
for icon in muted low medium high; do
	check "symbolic audio-volume-${icon} present" \
		grep -qx "${THEME_NAME}/symbolic/status/audio-volume-${icon}-symbolic.svg" "${LISTING}"
done

#==========================
# 不正3ファイルの除外 (拡張子なし/破損したファイル名のみを厳密一致で確認。
# 正規の同名.svgファイルは別途存在してよい)
#==========================
check "malformed 'cinnamon-virtual-keyboard' (no extension) is absent" \
	sh -c '! grep -qx "$1" "$2"' _ "${THEME_NAME}/scalable/apps/cinnamon-virtual-keyboard" "${LISTING}"
check "malformed 'org.gnome.Weather.Application.svg}' is absent" \
	sh -c '! grep -qxF "$1" "$2"' _ "${THEME_NAME}/scalable/apps/org.gnome.Weather.Application.svg}" "${LISTING}"
check "malformed 'page.kramo.Cartridges' (no extension) is absent" \
	sh -c '! grep -qx "$1" "$2"' _ "${THEME_NAME}/scalable/apps/page.kramo.Cartridges" "${LISTING}"

#==========================
# 削除対象ディレクトリの不在 (固定サイズ・HiDPI)
#==========================
# ディレクトリ自体はtar一覧に "THEME/16/..." のようにスラッシュ付きで
# 現れるため、配下エントリの有無 (固定文字列前方一致) で不在を判定する。
for d in 16 16@2x 16@3x 22 22@2x 22@3x 24 24@2x 24@3x 32 32@2x 32@3x 256 256@2x 256@3x scalable@2x scalable@3x; do
	check "no entries under pruned directory: ${d}/" \
		sh -c '! grep -qF "$1" "$2"' _ "${THEME_NAME}/${d}/" "${LISTING}"
done

check "icon-theme.cache absent" sh -c '! grep -qF "icon-theme.cache" "$1"' _ "${LISTING}"

echo "SCENARIOS=$((PASS + FAIL)) PASS=${PASS} FAIL=${FAIL}"
[ "${FAIL}" -eq 0 ]
