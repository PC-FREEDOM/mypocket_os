#!/bin/sh
#
# パネルのバッテリー残量%表示 (tint2標準Battery機能) に対する静的テスト。
# 実tint2は起動せず、tint2rcの記述内容のみを確認する。upower等の外部
# デーモン・アプレットは一切追加していないため、それらの存在確認も行わない。
#
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TINT2RC="${REPO_ROOT}/config/includes.chroot/etc/skel/.config/tint2/tint2rc"
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

check "tint2rc exists" test -f "${TINT2RC}"

#==========================
# panel_items にBが追加され、既存のP/T/S/Cが維持されていること
#==========================
check "panel_items includes B (battery)" \
	grep -qE '^panel_items = .*B' "${TINT2RC}"
check "panel_items still starts with PTSC (existing order preserved)" \
	grep -qx 'panel_items = PTSCB' "${TINT2RC}"
check "panel_items has exactly one P, T, S, C, B (no duplicates/typos)" \
	sh -c '
		line="$(grep "^panel_items = " "$1" | sed "s/^panel_items = //")"
		[ "${#line}" -eq 5 ] &&
		[ "$(printf "%s" "$line" | grep -o P | wc -l)" -eq 1 ] &&
		[ "$(printf "%s" "$line" | grep -o T | wc -l)" -eq 1 ] &&
		[ "$(printf "%s" "$line" | grep -o S | wc -l)" -eq 1 ] &&
		[ "$(printf "%s" "$line" | grep -o C | wc -l)" -eq 1 ] &&
		[ "$(printf "%s" "$line" | grep -o B | wc -l)" -eq 1 ]
	' _ "${TINT2RC}"

#==========================
# 残量%のみのテキスト表示 (1行、2行表示にしない)
#==========================
check "bat1_format is exactly %p (percentage only)" \
	grep -qx 'bat1_format = %p' "${TINT2RC}"
check "bat2_format is empty (no second line, avoids 2-line display)" \
	grep -qx 'bat2_format =' "${TINT2RC}"
#==========================
# バッテリー%表示・ツールチップのフォントが既存UIと統一されていること
# (button_font/tooltip_fontと同じ"sans 10"を明示指定する。未指定のまま
# だとtint2内部の既定フォント(DEFAULT_FONT "sans 10"、tint2本体の
# src/panel.c参照)を1pt縮小したサイズが暗黙に使われ、他パネル文字と
# 統一されないため、明示指定を必須とする)
#==========================
check "bat1_font is explicitly set to sans 10 (matches button_font/tooltip_font)" \
	grep -qx 'bat1_font = sans 10' "${TINT2RC}"
check "bat1_font matches button_font exactly (same family and size)" \
	sh -c '
		bat1="$(grep "^bat1_font = " "$1" | sed "s/^bat1_font = //")"
		btn="$(grep "^button_font = " "$1" | sed "s/^button_font = //")"
		[ "$bat1" = "$btn" ]
	' _ "${TINT2RC}"
check "bat1_font matches tooltip_font exactly (battery tooltip uses the shared tooltip_font, no per-item override exists in tint2)" \
	sh -c '
		bat1="$(grep "^bat1_font = " "$1" | sed "s/^bat1_font = //")"
		tt="$(grep "^tooltip_font = " "$1" | sed "s/^tooltip_font = //")"
		[ "$bat1" = "$tt" ]
	' _ "${TINT2RC}"
check "bat2_font is left unset (bat2 is never rendered since bat2_format is empty)" \
	grep -qx 'bat2_font =' "${TINT2RC}"

#==========================
# バッテリー非搭載機で自動非表示になること (battery_hide = never は
# 「満充電で自動非表示」を無効化する設定であり、バッテリー非搭載機での
# 自動非表示はtint2自身のbattery_found判定によるものなので、
# battery_hide = never のままで問題ない)
#==========================
check "battery_hide = never (do not auto-hide on full charge; absence of a battery is still auto-hidden by tint2 itself)" \
	grep -qx 'battery_hide = never' "${TINT2RC}"

#==========================
# 通知・ツールチップ設定
#==========================
check "battery_tooltip_enabled = 1" \
	grep -qx 'battery_tooltip_enabled = 1' "${TINT2RC}"
check "battery_low_status is set to a reasonable threshold (10)" \
	grep -qx 'battery_low_status = 10' "${TINT2RC}"

#==========================
# パネルの既存デザイン(clock)と統一された文字色・余白・背景であること
#==========================
check "battery_font_color matches existing clock_font_color (#eeeeee 100)" \
	grep -qx 'battery_font_color = #eeeeee 100' "${TINT2RC}"
check "battery_padding matches existing clock_padding (1 0)" \
	grep -qx 'battery_padding = 1 0' "${TINT2RC}"
check "battery_background_id matches existing clock_background_id (0)" \
	grep -qx 'battery_background_id = 0' "${TINT2RC}"

#==========================
# グラフィカルなアイコンを採用しないこと (アイコンテーマ関連の設定・
# 独自SVG追加を行っていないことの確認。tint2のBattery項目はテキスト描画
# のみで、そもそもアイコンテーマ設定を持たない)
#==========================
check "no custom battery icon added to MyPocketOS icon theme" \
	sh -c '! find "$1/config/includes.chroot/usr/share/icons/MyPocketOS" -iname "*battery*" 2>/dev/null | grep -q .' _ "${REPO_ROOT}"

#==========================
# 外部アプレット・追加パッケージ・常駐daemonを追加していないこと
#==========================
for pkg in upower acpi acpid xfce4-power-manager cbatticon batti; do
	check "no new power-management package added: ${pkg}" \
		sh -c '! grep -qx "$1" "$2" 2>/dev/null && ! grep -qx "$1" "$3" 2>/dev/null' \
		_ "${pkg}" "${COMMON_LIST}" "${STANDARD_LIST}"
done
check "autostart does not launch a new battery-related process" \
	sh -c '! grep -iE "upower|acpi|cbatticon|batti|power-manager" "$1"' _ \
	"${REPO_ROOT}/config/includes.chroot/etc/skel/.config/openbox/autostart"

#==========================
# 既存panel項目(メニュー・タスクバー・systray・clock)の設定が壊れていないこと
#==========================
check "button_lclick_command is unchanged (jgmenu_run)" \
	grep -qx 'button_lclick_command = jgmenu_run' "${TINT2RC}"
check "systray_icon_size is unchanged (22)" \
	grep -qx 'systray_icon_size = 22' "${TINT2RC}"
check "clock time1_format is unchanged (%H:%M)" \
	grep -qx 'time1_format = %H:%M' "${TINT2RC}"
check "clock_font_color is unchanged (#eeeeee 100)" \
	grep -qx 'clock_font_color = #eeeeee 100' "${TINT2RC}"

echo "SCENARIOS=$((PASS + FAIL)) PASS=${PASS} FAIL=${FAIL}"
[ "${FAIL}" -eq 0 ]
