#!/bin/sh
#
# MyPocketOS boot branding の静的テスト。
#
# 確認対象:
#   - Live ISO の GRUB / ISOLINUX 共通 splash.svg
#   - GRUB Live theme
#   - インストール後 GRUB の背景・quiet splash
#   - Plymouth の MyPocketOS theme
#
# 実ISO・実GRUB・実Plymouthは起動せず、
# リポジトリ内の設定・画像・スクリプトのみを確認する。
#
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

LIVE_SPLASH="${REPO_ROOT}/config/bootloaders/splash.svg"
LIVE_THEME="${REPO_ROOT}/config/bootloaders/grub-pc/live-theme/theme.txt"

CHROOT_INC="${REPO_ROOT}/config/includes.chroot"

GRUB_DROPIN="${CHROOT_INC}/etc/default/grub.d/60-mypocketos.cfg"
GRUB_BACKGROUND="${CHROOT_INC}/usr/share/images/mypocketos/grub-background.png"

PLYMOUTH_CONF="${CHROOT_INC}/etc/plymouth/plymouthd.conf"
PLYMOUTH_DIR="${CHROOT_INC}/usr/share/plymouth/themes/mypocketos"
PLYMOUTH_DESC="${PLYMOUTH_DIR}/mypocketos.plymouth"
PLYMOUTH_SCRIPT="${PLYMOUTH_DIR}/mypocketos.script"
PLYMOUTH_LOGO="${PLYMOUTH_DIR}/logo.png"

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

# ---- Live boot splash ---------------------------------------------------------

check "Live boot splash exists" test -f "${LIVE_SPLASH}"

check "Live boot splash uses 640x480 source canvas" \
	grep -Eq 'width="640"' "${LIVE_SPLASH}"

check "Live boot splash uses 480px height" \
	grep -Eq 'height="480"' "${LIVE_SPLASH}"

check "Live boot splash background is black" \
	grep -Eq '<rect width="640" height="480" fill="#000000"/>' "${LIVE_SPLASH}"

check "Live boot splash contains MyPocketOS product name" \
	grep -q '>MyPocketOS</text>' "${LIVE_SPLASH}"

check "Live boot splash contains Live label" \
	grep -q '>Live</text>' "${LIVE_SPLASH}"

check "Live boot splash contains build timestamp placeholders" \
	grep -q 'Built: @YEAR@-@MONTH@-@DAY@ @HOUR@:@MINUTE@ @TIMEZONE@' "${LIVE_SPLASH}"

check "Live boot splash contains kernel version placeholder" \
	grep -q 'Kernel: @LINUX_VERSIONS@' "${LIVE_SPLASH}"

check "Live boot splash does not contain Debian branding" \
	sh -c '! grep -qi "Debian GNU/Linux" "$1"' _ "${LIVE_SPLASH}"

check "Live boot splash embeds the logo image" \
	grep -q 'data:image/png;base64,' "${LIVE_SPLASH}"

# ---- GRUB Live theme ----------------------------------------------------------

check "MyPocketOS GRUB Live theme exists" test -f "${LIVE_THEME}"

check "GRUB Live theme uses splash.png" \
	grep -qx 'desktop-image: "../splash.png"' "${LIVE_THEME}"

check "GRUB Live theme hides the default GRUB title" \
	grep -qx 'title-text: ""' "${LIVE_THEME}"

check "GRUB Live boot menu is aligned at 28 percent" \
	grep -Eq '^[[:space:]]*left = 28%$' "${LIVE_THEME}"

check "GRUB Live theme contains no decimal percentages" \
	sh -c '! grep -Eq "[0-9]+\.[0-9]+%" "$1"' _ "${LIVE_THEME}"

check "GRUB Live theme contains no Debian branding" \
	sh -c '! grep -qi "Debian" "$1"' _ "${LIVE_THEME}"

# ---- Installed GRUB -----------------------------------------------------------

check "MyPocketOS GRUB drop-in exists" test -f "${GRUB_DROPIN}"

check "installed GRUB enables quiet splash" \
	grep -qx 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"' "${GRUB_DROPIN}"

check "installed GRUB points to MyPocketOS background" \
	grep -qx 'GRUB_BACKGROUND="/usr/share/images/mypocketos/grub-background.png"' "${GRUB_DROPIN}"

check "installed GRUB background exists" test -f "${GRUB_BACKGROUND}"

check "installed GRUB background is PNG" \
	python3 -c "
d = open('${GRUB_BACKGROUND}', 'rb').read(8)
assert d == b'\x89PNG\r\n\x1a\n', 'not a PNG'
"

# ---- Plymouth -----------------------------------------------------------------

check "Plymouth configuration exists" test -f "${PLYMOUTH_CONF}"

check "Plymouth selects MyPocketOS theme" \
	grep -qx 'Theme=mypocketos' "${PLYMOUTH_CONF}"

check "MyPocketOS Plymouth descriptor exists" test -f "${PLYMOUTH_DESC}"

check "MyPocketOS Plymouth script exists" test -f "${PLYMOUTH_SCRIPT}"

check "MyPocketOS Plymouth logo exists" test -f "${PLYMOUTH_LOGO}"

check "Plymouth descriptor uses script module" \
	grep -qx 'ModuleName=script' "${PLYMOUTH_DESC}"

check "Plymouth descriptor points to MyPocketOS script" \
	grep -q 'ScriptFile=/usr/share/plymouth/themes/mypocketos/mypocketos.script' "${PLYMOUTH_DESC}"

check "Plymouth script uses MyPocketOS logo" \
	grep -q 'Image("logo.png")' "${PLYMOUTH_SCRIPT}"

check "Plymouth logo is scaled to approved 168px size" \
	grep -q 'logo.Scale(168, 168)' "${PLYMOUTH_SCRIPT}"

check "Plymouth script contains three activity dots" \
	sh -c '
		grep -q "dot1 = Sprite" "$1" &&
		grep -q "dot2 = Sprite" "$1" &&
		grep -q "dot3 = Sprite" "$1"
	' _ "${PLYMOUTH_SCRIPT}"

check "Plymouth script registers refresh animation" \
	grep -q 'Plymouth.SetRefreshFunction(refresh_callback);' "${PLYMOUTH_SCRIPT}"

check "Plymouth logo is PNG" \
	python3 -c "
d = open('${PLYMOUTH_LOGO}', 'rb').read(8)
assert d == b'\x89PNG\r\n\x1a\n', 'not a PNG'
"

echo "SCENARIOS=$((PASS + FAIL)) PASS=${PASS} FAIL=${FAIL}"
[ "${FAIL}" -eq 0 ]
