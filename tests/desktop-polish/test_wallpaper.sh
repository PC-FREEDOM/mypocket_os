#!/bin/sh
#
# MyPocketOS標準壁紙の組み込みに対する静的テスト。実X・実hsetroot・
# 実ISOは一切使用しない (ファイル・設定の読み取りのみ)。
#
# 確認する設計:
#   - 壁紙画像がISO配置対象 (config/includes.chroot) に存在し、1920x1080の
#     PNGであること、branding/wallpaper/ の配布用書き出しと同一であること
#   - hsetrootがBase/Standard共通のpackage-list (common) にのみ1回含まれる
#     こと (Base/Standardで見た目が分かれないこと。scripts/build.shは
#     どちらのeditionでもcommonを配置し、config/includes.chrootは
#     edition非依存)
#   - Openbox autostartのhsetroot呼び出しが1回だけで、-cover (縦横比維持)
#     を使い、-fill (縦横比を無視した引き伸ばし) を使わず、存在する壁紙
#     パスを指し、tint2・Conkyより前にあり、構文が正しいこと
#
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHROOT_INC="${REPO_ROOT}/config/includes.chroot"
WALLPAPER_PATH="/usr/share/backgrounds/mypocketos/mypocketos-default.png"
WALLPAPER="${CHROOT_INC}${WALLPAPER_PATH}"
EXPORT="${REPO_ROOT}/branding/wallpaper/mypocketos-wallpaper-standard-1920x1080.png"
AUTOSTART="${CHROOT_INC}/etc/skel/.config/openbox/autostart"
COMMON_LIST="${REPO_ROOT}/config/package-lists.d/mypocketos-common.list.chroot"
STANDARD_LIST="${REPO_ROOT}/config/package-lists.d/mypocketos-standard.list.chroot"
BUILD_SH="${REPO_ROOT}/scripts/build.sh"

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

# ---- 壁紙ファイル ------------------------------------------------------------
check "wallpaper exists under config/includes.chroot" test -f "${WALLPAPER}"
check "wallpaper is a 1920x1080 8-bit RGB PNG (IHDR)" \
	python3 -c "
import struct, sys
d = open('${WALLPAPER}', 'rb').read(33)
assert d[:8] == b'\x89PNG\r\n\x1a\n', 'not a PNG'
assert d[12:16] == b'IHDR', 'no IHDR'
w, h, depth, ctype = struct.unpack('>IIBB', d[16:26])
assert (w, h) == (1920, 1080), f'size={w}x{h}'
assert (depth, ctype) == (8, 2), f'depth={depth} colortype={ctype}'
"
check "ISO-side wallpaper is identical to branding/wallpaper export" \
	cmp -s "${WALLPAPER}" "${EXPORT}"

# ---- パッケージリスト --------------------------------------------------------
check "common list contains hsetroot exactly once" \
	sh -c '[ "$(grep -cx "hsetroot" "$1")" -eq 1 ]' _ "${COMMON_LIST}"
check "standard list does not duplicate hsetroot (no Base/Standard split)" \
	sh -c '! grep -qx "hsetroot" "$1"' _ "${STANDARD_LIST}"
# build.shがeditionによらずcommonを配置していること (Baseにもhsetrootが入る前提)
check "build.sh copies the common list unconditionally (top-level cp, not inside an edition branch)" \
	grep -qxF 'cp -- "${COMMON_SRC}" "${COMMON_DEST}"' "${BUILD_SH}"

# ---- autostart ---------------------------------------------------------------
check "autostart exists" test -f "${AUTOSTART}"
check "autostart passes sh -n" sh -n "${AUTOSTART}"
# コメント行を除いた実行行のうち、行頭 (空白を除く) が hsetroot のものが1回だけ
check "autostart invokes hsetroot exactly once (non-comment lines)" \
	sh -c '[ "$(grep -E "^[[:space:]]*hsetroot[[:space:]]" "$1" | wc -l)" -eq 1 ]' _ "${AUTOSTART}"
check "autostart uses hsetroot -cover with the default wallpaper path" \
	grep -Eq "^[[:space:]]*hsetroot -cover ${WALLPAPER_PATH} \|\| true$" "${AUTOSTART}"
check "autostart does not use -fill (aspect-ignoring stretch), -full, -tile or -center" \
	sh -c '! grep -E "^[[:space:]]*hsetroot[[:space:]]+-(fill|full|tile|center|extend)" "$1"' _ "${AUTOSTART}"
check "wallpaper path referenced by autostart exists in config/includes.chroot" \
	test -f "${CHROOT_INC}$(sed -n 's|.*\(/usr/share/backgrounds/mypocketos/[A-Za-z0-9._-]*\.png\).*|\1|p' "${AUTOSTART}" | head -n 1)"
# 失敗してもセッション起動を止めないこと (画像・hsetroot不在時の存在確認ガード)
check "hsetroot call is guarded by file-readable and command-exists checks" \
	grep -Eq "^if \[ -r ${WALLPAPER_PATH} \] && command -v hsetroot >/dev/null 2>&1; then$" "${AUTOSTART}"
# 起動順: 壁紙 → tint2 → ... → conky (Conkyは背景透過のため壁紙設定後に起動する)
check "hsetroot runs before tint2" \
	sh -c 'h=$(grep -nE "^[[:space:]]*hsetroot[[:space:]]" "$1" | head -n1 | cut -d: -f1); t=$(grep -nE "^tint2 &" "$1" | head -n1 | cut -d: -f1); [ -n "$h" ] && [ -n "$t" ] && [ "$h" -lt "$t" ]' _ "${AUTOSTART}"
check "hsetroot runs before conky" \
	sh -c 'h=$(grep -nE "^[[:space:]]*hsetroot[[:space:]]" "$1" | head -n1 | cut -d: -f1); c=$(grep -nE "^conky " "$1" | head -n1 | cut -d: -f1); [ -n "$h" ] && [ -n "$c" ] && [ "$h" -lt "$c" ]' _ "${AUTOSTART}"
# 既存の起動項目を壊していないこと (主要項目が引き続き1回ずつ存在する)
for item in "tint2 &" "nm-applet &" "lxpolkit &" "fcitx5 &" "spice-vdagent &" \
	"mypocketos-installer-menu-state" "conky -p 3 -U &" "mypocketos-touchpad-settings --apply &"; do
	check "autostart still contains exactly once: ${item}" \
		sh -c '[ "$(grep -cxF "$1" "$2")" -eq 1 ]' _ "${item}" "${AUTOSTART}"
done

echo "SCENARIOS=$((PASS + FAIL)) PASS=${PASS} FAIL=${FAIL}"
[ "${FAIL}" -eq 0 ]
