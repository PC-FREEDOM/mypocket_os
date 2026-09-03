#!/bin/sh
#
# 配布前デスクトップ調整 (起動モード判定・右クリックメニュー・
# アイコンテーマ・追加パッケージ) の単一エントリポイント。
#
set -eu

DIR="$(cd "$(dirname "$0")" && pwd)"
status=0

for t in test_boot_mode.sh test_menu.sh test_icon_theme.sh test_fluent_archive.sh test_battery.sh; do
	echo "=== ${t} ==="
	if ! "${DIR}/${t}"; then
		status=1
	fi
	echo
done

exit "${status}"
