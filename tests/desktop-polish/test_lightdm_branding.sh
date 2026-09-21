#!/bin/sh
#
# MyPocketOS LightDM (lightdm-gtk-greeter) のログイン画面背景の組み込みに
# 対する静的テスト。実LightDM・実greeter・実X・実ISOは一切使用しない
# (ファイル・設定の読み取りのみ)。
#
# 確認する設計:
#   - /etc/lightdm/lightdm-gtk-greeter.conf.d/50_mypocketos.conf (MyPocketOS
#     独自のdrop-in) が存在し、[greeter] セクションで background= に
#     MyPocketOS標準壁紙を指定していること (有効な設定キーはbackgroundのみ)
#   - 指定した壁紙がconfig/includes.chroot配下に実在すること
#   - theme-name・default-user-image を設定していないこと (今回は背景のみ)
#   - Debianパッケージ提供のconffile・drop-in (lightdm-gtk-greeter.conf・
#     lightdm.conf・01_debian.conf) をリポジトリ側で上書き・複製していないこと
#   - lightdm・lightdm-gtk-greeterがBase/Standard共通のpackage-list (common)
#     にあり、drop-inがedition非依存の config/includes.chroot にあること
#
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHROOT_INC="${REPO_ROOT}/config/includes.chroot"
DROPIN_DIR="${CHROOT_INC}/etc/lightdm/lightdm-gtk-greeter.conf.d"
DROPIN="${DROPIN_DIR}/50_mypocketos.conf"
WALLPAPER_PATH="/usr/share/backgrounds/mypocketos/mypocketos-default.png"
WALLPAPER="${CHROOT_INC}${WALLPAPER_PATH}"
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

# ---- drop-in -----------------------------------------------------------------
check "MyPocketOS greeter drop-in exists" test -f "${DROPIN}"
# lightdm-gtk-greeterは *.conf だけを、ファイル名順に読む。50_はDebianの
# 01_debian.confより後になる。
check "drop-in file name ends with .conf and sorts after 01_debian.conf" \
	sh -c 'n=$(basename "$1"); case "$n" in *.conf) [ "$n" \> "01_debian.conf" ] ;; *) false ;; esac' _ "${DROPIN}"
# [greeter] セクションが1つだけあり、有効な設定キーが background の1つだけ
# であること (コメント行は無視される)。
check "drop-in has exactly one [greeter] section with only the 'background' key" \
	python3 -c "
import configparser
p = configparser.RawConfigParser(strict=True, interpolation=None)
p.optionxform = str
with open('${DROPIN}', encoding='utf-8') as f:
    p.read_file(f)
assert p.sections() == ['greeter'], f'sections={p.sections()!r}'
assert list(p['greeter'].keys()) == ['background'], f'keys={list(p[\"greeter\"].keys())!r}'
assert p['greeter']['background'] == '${WALLPAPER_PATH}', f'background={p[\"greeter\"][\"background\"]!r}'
"
check "drop-in has exactly one active background= line" \
	sh -c '[ "$(grep -Ec "^[[:space:]]*background[[:space:]]*=" "$1")" -eq 1 ]' _ "${DROPIN}"
check "background= points to the MyPocketOS standard wallpaper (plain path, zoomed scaling)" \
	grep -Eqx "background=${WALLPAPER_PATH}" "${DROPIN}"

# ---- 壁紙ファイル ------------------------------------------------------------
check "referenced wallpaper exists under config/includes.chroot" test -f "${WALLPAPER}"
check "referenced wallpaper is a PNG" \
	python3 -c "
d = open('${WALLPAPER}', 'rb').read(8)
assert d == b'\x89PNG\r\n\x1a\n', 'not a PNG'
"

# ---- 今回は背景のみ (theme-name・default-user-image・ロゴ/CSSは設定しない) --
check "drop-in does not set theme-name (GTK theme unchanged)" \
	sh -c '! grep -Eq "^[[:space:]]*theme-name[[:space:]]*=" "$1"' _ "${DROPIN}"
check "drop-in does not set default-user-image (avatar feature is not used for branding)" \
	sh -c '! grep -Eq "^[[:space:]]*default-user-image[[:space:]]*=" "$1"' _ "${DROPIN}"
check "no MyPocketOS GTK theme / CSS for the greeter has been added" \
	sh -c '! find "$1/usr/share/themes" -type d -iname "*mypocketos*" 2>/dev/null | grep -q .' _ "${CHROOT_INC}"

# ---- Debianパッケージ提供ファイルを上書き・複製していないこと ----------------
check "package conffile /etc/lightdm/lightdm-gtk-greeter.conf is not shipped by the repo" \
	test ! -e "${CHROOT_INC}/etc/lightdm/lightdm-gtk-greeter.conf"
check "package conffile /etc/lightdm/lightdm.conf is not shipped by the repo" \
	test ! -e "${CHROOT_INC}/etc/lightdm/lightdm.conf"
check "Debian drop-in 01_debian.conf is not shipped or overridden by the repo" \
	test ! -e "${CHROOT_INC}/usr/share/lightdm"

# ---- Base/Standard共通 -------------------------------------------------------
for pkg in lightdm lightdm-gtk-greeter; do
	check "common list contains exactly once: ${pkg}" \
		sh -c '[ "$(grep -cx "$1" "$2")" -eq 1 ]' _ "${pkg}" "${COMMON_LIST}"
	check "standard list does not duplicate: ${pkg} (no Base/Standard split)" \
		sh -c '! grep -qx "$1" "$2"' _ "${pkg}" "${STANDARD_LIST}"
done
# includes.chrootはedition非依存: build.shが includes.chroot を edition別に
# 切り替えていないこと、commonを常に配置していること。
check "build.sh does not switch config/includes.chroot per edition" \
	sh -c '! grep -q "includes.chroot" "$1"' _ "${BUILD_SH}"
check "build.sh copies the common list unconditionally" \
	grep -qxF 'cp -- "${COMMON_SRC}" "${COMMON_DEST}"' "${BUILD_SH}"

echo "SCENARIOS=$((PASS + FAIL)) PASS=${PASS} FAIL=${FAIL}"
[ "${FAIL}" -eq 0 ]
