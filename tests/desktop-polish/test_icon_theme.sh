#!/bin/sh
#
# MyPocketOS側 (継承テーマ・GTK2/GTK3設定・pasystray) と追加パッケージ
# (mousepad/galculator) に対する静的テスト。
# Fluent-yellow本体 (アーカイブの中身) の検証は test_fluent_archive.sh が
# 別途担当する。ネットワークアクセス・実gtk-update-icon-cache等は
# 一切行わない。
#
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ICONS_DIR="${REPO_ROOT}/config/includes.chroot/usr/share/icons"
MPOS_THEME="${ICONS_DIR}/MyPocketOS/index.theme"
GTK3_SETTINGS="${REPO_ROOT}/config/includes.chroot/etc/skel/.config/gtk-3.0/settings.ini"
GTK2_SETTINGS="${REPO_ROOT}/config/includes.chroot/etc/skel/.gtkrc-2.0"
AUTOSTART="${REPO_ROOT}/config/includes.chroot/etc/skel/.config/openbox/autostart"
STANDARD_LIST="${REPO_ROOT}/config/package-lists.d/mypocketos-standard.list.chroot"
FLUENT_ARCHIVE="${REPO_ROOT}/config/includes.chroot/usr/share/mypocketos/icon-themes/MyPocketOS-Fluent-yellow.tar.gz"
FLUENT_HOOK="${REPO_ROOT}/config/hooks/normal/mypocketos-fluent-icon-theme.hook.chroot"

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

#==========================
# MyPocketOSテーマの継承順
#==========================
check "MyPocketOS index.theme exists" test -f "${MPOS_THEME}"
check "MyPocketOS inherits MyPocketOS-Fluent-yellow,Adwaita,hicolor (この順序)" \
	grep -qx 'Inherits=MyPocketOS-Fluent-yellow,Adwaita,hicolor' "${MPOS_THEME}"

#==========================
# GTK2・GTK3設定がMyPocketOSを参照すること
#==========================
check "GTK3 settings.ini references MyPocketOS" \
	grep -qx 'gtk-icon-theme-name=MyPocketOS' "${GTK3_SETTINGS}"
check "GTK2 .gtkrc-2.0 references MyPocketOS" \
	grep -qx 'gtk-icon-theme-name="MyPocketOS"' "${GTK2_SETTINGS}"

# GTKテーマ (gtk-theme-name) 自体は変更していないこと (未指定のまま)。
# コメント文中の言及ではなく、行頭のキー代入としての出現のみを見る。
check "GTK3 settings.ini does not set gtk-theme-name" \
	sh -c '! grep -qE "^gtk-theme-name" "$1"' _ "${GTK3_SETTINGS}"
check "GTK2 .gtkrc-2.0 does not set gtk-theme-name" \
	sh -c '! grep -qE "^gtk-theme-name" "$1"' _ "${GTK2_SETTINGS}"

#==========================
# pasystrayのGTK_THEME=Adwaita:darkが維持されていること
#==========================
check "autostart still sets GTK_THEME=Adwaita:dark for pasystray only" \
	grep -q 'GTK_THEME=Adwaita:dark pasystray' "${AUTOSTART}"
check "GTK_THEME is not exported globally in autostart" \
	sh -c '! grep -qE "^export GTK_THEME" "$1"' _ "${AUTOSTART}"

#==========================
# 非symbolic独自音量SVG (pasystrayが実際に要求する4種、strings/grep -aで
# バイナリから確認済みの名前。symbolicサフィックスは要求されないため
# symbolic版は今回追加しない)
#==========================
VOL_DIR_NONSYMBOLIC="${ICONS_DIR}/MyPocketOS/scalable/status"
for icon in muted low medium high; do
	svg="${VOL_DIR_NONSYMBOLIC}/audio-volume-${icon}.svg"
	check "non-symbolic audio-volume-${icon}.svg exists" test -f "${svg}"
	check "audio-volume-${icon}.svg is well-formed XML" \
		python3 -c "import xml.dom.minidom as m; m.parse('${svg}')"
	check "audio-volume-${icon}.svg is not empty" test -s "${svg}"
done

# muted/low/medium/highが形状で区別できること (色だけに依存しない設計の
# 最低限の確認)。muted は交差する直線2本による「×」印(stroke path 2本)、
# low/medium/high は音波の弧の本数が1/2/3本であることを、円弧を表す "Q"
# (quadratic bezier) コマンドの出現回数で確認する
MUTED_SVG="${VOL_DIR_NONSYMBOLIC}/audio-volume-muted.svg"
check "muted icon has no wave arcs (Q commands)" \
	sh -c '[ "$(grep -o "Q" "$1" | wc -l)" -eq 0 ]' _ "${MUTED_SVG}"
# 「×」を構成する2本の交差線が、スピーカー形状(fill付きpath)とは別の
# 独立したstroke path(fill="none")として2本存在することを確認する
# (low/medium/highの音波弧と同じ「stroke pathの本数」という設計で揃える)。
check "muted icon has exactly 2 stroke paths (the two crossing lines of the X mark)" \
	sh -c '[ "$(grep -c "fill=\"none\" stroke=" "$1")" -eq 2 ]' _ "${MUTED_SVG}"
# その2本が直線(L コマンド)で描かれ、弧(Q)ではないことを確認する
check "muted icon's 2 stroke paths are straight lines (L commands, not arcs)" \
	sh -c '[ "$(grep -A1 "fill=\"none\" stroke=" "$1" | grep -c "d=\"M[0-9.]*,[0-9.]* L[0-9.]*,[0-9.]*\"")" -eq 2 ]' _ "${MUTED_SVG}"
# 2本の線が実際に交差する(× の形になる)ことを確認する。スピーカー形状
# (fill付きpath)を除いた2本のstroke path(直線)それぞれの始点x座標が
# 異なる(一方は左上→右下、もう一方は右上→左下)ことを確認する
check "muted icon's 2 lines cross (start x-coordinates differ, forming an X not parallel lines)" \
	sh -c '
		starts="$(grep -A1 "fill=\"none\" stroke=" "$1" | grep -oE "d=\"M[0-9.]+,[0-9.]+" | sed -E "s/.*M([0-9.]+),.*/\1/")"
		set -- $starts
		[ "$#" -eq 2 ] && [ "$1" != "$2" ]
	' _ "${MUTED_SVG}"
LOW_SVG="${VOL_DIR_NONSYMBOLIC}/audio-volume-low.svg"
check "low icon has exactly 1 wave arc" \
	sh -c '[ "$(grep -o "Q" "$1" | wc -l)" -eq 1 ]' _ "${LOW_SVG}"
MEDIUM_SVG="${VOL_DIR_NONSYMBOLIC}/audio-volume-medium.svg"
check "medium icon has exactly 2 wave arcs" \
	sh -c '[ "$(grep -o "Q" "$1" | wc -l)" -eq 2 ]' _ "${MEDIUM_SVG}"
HIGH_SVG="${VOL_DIR_NONSYMBOLIC}/audio-volume-high.svg"
check "high icon has exactly 3 wave arcs" \
	sh -c '[ "$(grep -o "Q" "$1" | wc -l)" -eq 3 ]' _ "${HIGH_SVG}"

# index.theme に scalable/status が登録され、専用セクションを持つこと
check "index.theme Directories includes scalable/status" \
	grep -E '^Directories=' "${MPOS_THEME}" | grep -q 'scalable/status'
check "index.theme has a [scalable/status] section" \
	grep -qx '\[scalable/status\]' "${MPOS_THEME}"
check "[scalable/status] section declares Context=Status" \
	sh -c "awk '/^\[scalable\/status\]/{f=1;next} /^\[/{f=0} f && /^Context=Status\$/{found=1} END{exit !found}' \"\$1\"" _ "${MPOS_THEME}"
check "[scalable/status] section declares Type=Scalable" \
	sh -c "awk '/^\[scalable\/status\]/{f=1;next} /^\[/{f=0} f && /^Type=Scalable\$/{found=1} END{exit !found}' \"\$1\"" _ "${MPOS_THEME}"

# symbolic版は今回のスコープ外のまま追加しないこと (pasystrayが -symbolic
# サフィックス付きの名前を要求しないことを実機のバイナリ文字列から確認済み)
VOL_DIR_SYMBOLIC="${ICONS_DIR}/MyPocketOS/symbolic/status"
check "no custom symbolic volume SVGs added (not requested by pasystray)" \
	sh -c '[ ! -d "$1" ] || ! ls "$1"/audio-volume-*.svg >/dev/null 2>&1' _ "${VOL_DIR_SYMBOLIC}"

#==========================
# MyPocketOS側がFluent本体を直接変更していないこと
# (展開先ディレクトリがMyPocketOS配下にネストしていないことの確認。
# Fluent-yellow本体はビルド時展開のためリポジトリには存在しない)
#==========================
check "MyPocketOS-Fluent-yellow dir is not nested inside MyPocketOS theme dir" \
	test ! -e "${ICONS_DIR}/MyPocketOS/MyPocketOS-Fluent-yellow"

# 独自SVG追加に伴いFluent派生アーカイブ自体を変更・再生成していないこと
# (内容の詳細な検証はtest_fluent_archive.shの担当だが、ここでも
# hook記載のSHA-256と実アーカイブが一致していることを直接再確認する)
check "Fluent-yellow archive SHA-256 still matches the hook's pinned value (archive not regenerated)" \
	sh -c '
		hook_sha="$(sed -n "s/^EXPECTED_ARCHIVE_SHA256=\"\([0-9a-f]\{64\}\)\"\$/\1/p" "$2")"
		actual_sha="$(sha256sum "$1" | awk "{print \$1}")"
		[ -n "${hook_sha}" ] && [ "${actual_sha}" = "${hook_sha}" ]
	' _ "${FLUENT_ARCHIVE}" "${FLUENT_HOOK}"

#==========================
# mousepad/galculatorがStandard版リストに各1回だけ存在し、
# 既存10パッケージも維持されていること
#==========================
for pkg in firefox-esr firefox-esr-l10n-ja libreoffice-writer libreoffice-calc \
	libreoffice-impress libreoffice-draw libreoffice-gtk3 libreoffice-l10n-ja \
	libreoffice-help-ja drawing mousepad galculator; do
	count="$(grep -cx "${pkg}" "${STANDARD_LIST}")"
	check "package listed exactly once: ${pkg}" test "${count}" -eq 1
done

echo "SCENARIOS=$((PASS + FAIL)) PASS=${PASS} FAIL=${FAIL}"
[ "${FAIL}" -eq 0 ]
