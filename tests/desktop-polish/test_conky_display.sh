#!/bin/sh
#
# Conky表示 (システム情報パネル) に対する静的テスト。
# 既存表示項目 (MyPocketOS見出し・ホスト名・カーネル・稼働時間・
# 起動モード・CPU使用率・メモリ・ルートFS・既存ショートカット5項目) が
# 維持されていること、ネットワーク表示・ウィンドウスナップ表示が期待
# どおりであることを確認する。
#
# ネットワーク表示は2026-09-07に2度修正されている。
#   1回目 (2026-09-06導入): 引数なし${downspeed}/${upspeed}にConky内部の
#     デバイス自動選択を委ねる方式。実機でdefault route interfaceを
#     正しく選ばずDown/Upが常に0Bになる不具合が判明。
#   2回目 (2026-09-07 1st fix): mypocketos-network.luaを追加し、
#     conky_parse()でLua側からinterfaceを解決する方式。実機で
#     "attempt to call a nil value"というLua実行時エラーを起こし、
#     ラベルだけ表示され値が空欄になる不具合が判明。
#   3回目 (2026-09-07 2nd fix、現行): Luaヘルパーを廃止し、
#     ${downspeed ${gw_iface}}/${upspeed ${gw_iface}}という、Conky変数の
#     引数に別のConky変数を直接ネストさせる記法のみで実装。実際に
#     ビルド済みconky-std 1.22.1バイナリで動作を検証済み(このテスト
#     ファイルのコメントで検証方法を記録する)。
#
# このテストスクリプト自体は実Conky・実Xを一切使用しない(静的解析の
# み)。実バイナリでの検証はtests/desktop-polish/README.mdおよびレビュー
# 資料に手順を記録している。
#
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CONKY_CONF="${REPO_ROOT}/config/includes.chroot/etc/skel/.config/conky/conky.conf"
NETWORK_LUA="${REPO_ROOT}/config/includes.chroot/etc/skel/.config/conky/mypocketos-network.lua"
BOOT_MODE_LUA="${REPO_ROOT}/config/includes.chroot/etc/skel/.config/conky/mypocketos-boot-mode.lua"

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

check "conky.conf exists" test -f "${CONKY_CONF}"

# conky.text = [[ ... ]] の本文部分だけを取り出す (ハードコード検査等を
# コメント行の説明文と区別するため)。
TEXT_BLOCK="$(sed -n '/^conky\.text = \[\[$/,/^\]\]$/p' "${CONKY_CONF}")"
check "conky.text block was extracted (non-empty)" \
	sh -c '[ -n "$1" ]' _ "${TEXT_BLOCK}"

#==========================
# 既存表示項目の維持 (削除・置換していないこと)
#==========================
check "existing: MyPocketOS heading is present" \
	sh -c 'printf "%s" "$1" | grep -qF "MyPocketOS\${font}"' _ "${TEXT_BLOCK}"
check "existing: hostname (ホスト名) line is present" \
	sh -c 'printf "%s" "$1" | grep -qF "ホスト名:"' _ "${TEXT_BLOCK}"
check "existing: hostname line still uses \${nodename}" \
	sh -c 'printf "%s" "$1" | grep -qF "\${nodename}"' _ "${TEXT_BLOCK}"
check "existing: kernel (カーネル) line is present" \
	sh -c 'printf "%s" "$1" | grep -qF "カーネル:"' _ "${TEXT_BLOCK}"
check "existing: kernel line still uses \${kernel}" \
	sh -c 'printf "%s" "$1" | grep -qF "\${kernel}"' _ "${TEXT_BLOCK}"
check "existing: uptime (稼働時間) line is present" \
	sh -c 'printf "%s" "$1" | grep -qF "稼働時間:"' _ "${TEXT_BLOCK}"
check "existing: uptime line still uses \${uptime}" \
	sh -c 'printf "%s" "$1" | grep -qF "\${uptime}"' _ "${TEXT_BLOCK}"
check "existing: boot mode (起動モード) line is present" \
	sh -c 'printf "%s" "$1" | grep -qF "起動モード:"' _ "${TEXT_BLOCK}"
check "existing: boot mode line still uses \${lua mypocketos_boot_mode}" \
	sh -c 'printf "%s" "$1" | grep -qF "\${lua mypocketos_boot_mode}"' _ "${TEXT_BLOCK}"
check "existing: CPU usage (CPU使用率) line is present" \
	sh -c 'printf "%s" "$1" | grep -qF "CPU使用率:"' _ "${TEXT_BLOCK}"
check "existing: CPU usage line still uses \${cpu}%" \
	sh -c 'printf "%s" "$1" | grep -qF "\${cpu}%"' _ "${TEXT_BLOCK}"
check "existing: CPU bar (\${cpubar 6}) is still present and unchanged" \
	sh -c 'printf "%s" "$1" | grep -qF "\${cpubar 6}"' _ "${TEXT_BLOCK}"
check "existing: memory (メモリ) line is present" \
	sh -c 'printf "%s" "$1" | grep -qF "メモリ:"' _ "${TEXT_BLOCK}"
check "existing: memory line still uses \${mem} / \${memmax} (\${memperc}%)" \
	sh -c 'printf "%s" "$1" | grep -qF "\${mem} / \${memmax} (\${memperc}%)"' _ "${TEXT_BLOCK}"
check "existing: memory bar (\${membar 6}) is still present and unchanged" \
	sh -c 'printf "%s" "$1" | grep -qF "\${membar 6}"' _ "${TEXT_BLOCK}"
check "existing: root filesystem line is present" \
	sh -c 'printf "%s" "$1" | grep -qF "ルートFS (/):"' _ "${TEXT_BLOCK}"
check "existing: root filesystem line still uses \${fs_used /} / \${fs_size /} (\${fs_used_perc /}%)" \
	sh -c 'printf "%s" "$1" | grep -qF "\${fs_used /} / \${fs_size /} (\${fs_used_perc /}%)"' _ "${TEXT_BLOCK}"
check "existing: root filesystem bar (\${fs_bar 6 /}) is still present and unchanged" \
	sh -c 'printf "%s" "$1" | grep -qF "\${fs_bar 6 /}"' _ "${TEXT_BLOCK}"

# 既存ショートカット5項目 (テキスト・キー割り当てとも変更していないこと)
for line in \
	'Super+Space  アプリメニュー' \
	'Super+T      端末' \
	'Super+E      ファイルマネージャー' \
	'Alt+F4       ウィンドウを閉じる' \
	'Alt+Tab      ウィンドウ切り替え'
do
	check "existing shortcut line is unchanged: ${line}" \
		sh -c 'printf "%s" "$1" | grep -qF "$2"' _ "${TEXT_BLOCK}" "${line}"
done
check "existing: ショートカット heading is present" \
	sh -c 'printf "%s" "$1" | grep -qF "ショートカット\$color"' _ "${TEXT_BLOCK}"

#==========================
# 新規追加: ネットワーク表示 (2026-09-07 2nd fix、現行実装)
#
# mypocketos-network.luaは廃止した。conky_parse()をLua ${lua ...} 呼び出し
# 内から再帰的に呼ぶ実装は、実機で"attempt to call a nil value"という
# Lua実行時エラーを起こすことが判明したため(このテストスイートの旧版は
# 静的にはPASSしていたが、この種の実行時限定の不具合は検出できなかった)。
# 現行実装は、Conky変数の引数へ別のConky変数を直接ネストさせる
# ${downspeed ${gw_iface}}/${upspeed ${gw_iface}}のみで完結する。
#==========================
check "mypocketos-network.lua no longer exists (Lua helper removed, root cause of the 2nd bug)" \
	sh -c '[ ! -e "$1" ]' _ "${NETWORK_LUA}"

check "network: ネットワーク heading is present" \
	sh -c 'printf "%s" "$1" | grep -qF "ネットワーク:"' _ "${TEXT_BLOCK}"
check "network: connectivity gating uses \${if_match \"\${gw_iface}\" != \"none\"} (nested Conky variable, no Lua)" \
	sh -c 'printf "%s" "$1" | grep -qF "\${if_match \"\${gw_iface}\" != \"none\"}"' _ "${TEXT_BLOCK}"
check "network: also excludes the ambiguous \"multiple\" gateway case via a nested \${if_match \"\${gw_iface}\" != \"multiple\"}" \
	sh -c 'printf "%s" "$1" | grep -qF "\${if_match \"\${gw_iface}\" != \"multiple\"}"' _ "${TEXT_BLOCK}"
check "network: \${if_match} blocks are closed with \${endif} (at least 2, for the nested pair)" \
	sh -c 'n=$(printf "%s" "$1" | grep -o "\${endif}" | wc -l); [ "$n" -ge 2 ]' _ "${TEXT_BLOCK}"
check "network: has \${else} branches for the disconnected/ambiguous cases" \
	sh -c 'n=$(printf "%s" "$1" | grep -o "\${else}" | wc -l); [ "$n" -ge 2 ]' _ "${TEXT_BLOCK}"
check "network: disconnected fallback text is 未接続" \
	sh -c 'printf "%s" "$1" | grep -qF "未接続"' _ "${TEXT_BLOCK}"
check "network: Down: line uses \${downspeed \${gw_iface}} (nested, no Lua, no hardcoded interface)" \
	sh -c 'printf "%s" "$1" | grep -qF "\${downspeed \${gw_iface}}"' _ "${TEXT_BLOCK}"
check "network: Up: line uses \${upspeed \${gw_iface}} (nested, no Lua, no hardcoded interface)" \
	sh -c 'printf "%s" "$1" | grep -qF "\${upspeed \${gw_iface}}"' _ "${TEXT_BLOCK}"

# 回帰防止: 過去2回の不具合を起こした実装に戻っていないことを確認する。
check "network: conky.text no longer uses bare (argument-less) \${downspeed} (2026-09-06版の不具合への回帰防止)" \
	sh -c '! printf "%s" "$1" | grep -qF "\${downspeed}"' _ "${TEXT_BLOCK}"
check "network: conky.text no longer uses bare (argument-less) \${upspeed} (2026-09-06版の不具合への回帰防止)" \
	sh -c '! printf "%s" "$1" | grep -qF "\${upspeed}"' _ "${TEXT_BLOCK}"
check "network: conky.text no longer uses \${if_gw} alone for the connectivity gate (replaced by gw_iface-based \${if_match})" \
	sh -c '! printf "%s" "$1" | grep -qF "\${if_gw}"' _ "${TEXT_BLOCK}"
check "network: conky.text no longer calls \${lua mypocketos_network_ (1st-fix版のLuaヘルパー呼び出しへの回帰防止)" \
	sh -c '! printf "%s" "$1" | grep -qF "\${lua mypocketos_network_"' _ "${TEXT_BLOCK}"

# lua_loadはmypocketos-boot-mode.luaのみを読み込み、mypocketos-network.lua
# への参照が残っていないこと(1st-fix版からの後始末漏れがないことの確認)
check "conky.conf lua_load still loads mypocketos-boot-mode.lua" \
	grep -q 'mypocketos-boot-mode\.lua' "${CONKY_CONF}"
# lua_load行 (conky.config内) だけを対象とする。冒頭のコメントには経緯
# 説明として"mypocketos-network.lua"という過去のファイル名への言及が
# 残っているため、コメント行 (--で始まる行) は対象から除外する。
check "conky.conf lua_load line no longer references mypocketos-network.lua" \
	sh -c '! grep -vE "^[[:space:]]*--" "$1" | grep -q "mypocketos-network\.lua"' _ "${CONKY_CONF}"
check "mypocketos-boot-mode.lua is unaffected (still exists, still used for boot mode only)" \
	test -f "${BOOT_MODE_LUA}"

# デバイス名・vendor固有のインターフェース名をハードコードしていないこと
# (wlan0/eth0/wlp2s0/enp3s0等のよくあるLinuxネットワークインターフェース
# 命名パターンが、conky.text本文に一切現れないことを確認する。gw_iface
# 自体はConkyが動的に判定するため、実際のinterface名の文字列がソース中に
# 登場することはない)
check "network: no hardcoded network interface name in conky.text (wlan/eth/wlp/enp/eno/ens/ppp/wwan)" \
	sh -c '! printf "%s" "$1" | grep -qiE "(wlan|eth|wlp|enp|eno|ens|ppp|wwan)[0-9]"' _ "${TEXT_BLOCK}"

#==========================
# 高頻度の重い外部コマンドを追加していないこと
#==========================
# conky.conf側: 既存の「execを使わない」方針が今回も維持されていること
# (test_boot_mode.shで既に確認されている内容の重複確認だが、ネットワーク
# 表示修正の文脈でも明示的に再確認する)。Luaヘルパーを廃止したため、
# os.execute/io.popen等のLua側チェックはもはや不要 (該当ファイル自体が
# 存在しない)。
check "no exec/execi variable was added to conky.conf for the network display" \
	sh -c '! grep -qF "\${exec" "$1"' _ "${CONKY_CONF}"

#==========================
# 新規追加: ウィンドウスナップ表示
#==========================
check "window snap: heading ウィンドウスナップ is present" \
	sh -c 'printf "%s" "$1" | grep -qF "ウィンドウスナップ\$color"' _ "${TEXT_BLOCK}"

for line in \
	'Super+Left   左半分' \
	'Super+Right  右半分' \
	'Super+Up     最大化' \
	'Super+Down   最大化解除'
do
	check "window snap line is present and unchanged: ${line}" \
		sh -c 'printf "%s" "$1" | grep -qF "$2"' _ "${TEXT_BLOCK}" "${line}"
done

# ショートカット5項目とウィンドウスナップ4項目が区別できるよう、
# 間に見出し ("ウィンドウスナップ") と区切り線 (${hr 1}) が入っていること。
# 既存ショートカットの最後の行 (Alt+Tab) より後に、新しい区切り線と
# 見出しがこの順で現れることを行番号で確認する。
alttab_line="$(printf '%s\n' "${TEXT_BLOCK}" | grep -n 'Alt+Tab' | head -n1 | cut -d: -f1)"
heading_line="$(printf '%s\n' "${TEXT_BLOCK}" | grep -n 'ウィンドウスナップ\$color' | head -n1 | cut -d: -f1)"
hr_line="$(printf '%s\n' "${TEXT_BLOCK}" | grep -n '\${hr 1}' | tail -n1 | cut -d: -f1)"
check "a second \${hr 1} separator and the window snap heading appear after the existing shortcuts" \
	sh -c '[ -n "$1" ] && [ -n "$2" ] && [ -n "$3" ] && [ "$1" -lt "$2" ] && [ "$2" -lt "$3" ]' \
	_ "${alttab_line}" "${hr_line}" "${heading_line}"

# 既存ショートカット5項目がウィンドウスナップより前の順序を維持している
# こと (大幅な並べ替えをしていないことの確認)
check "existing 5 shortcuts still appear before the window snap section" \
	sh -c '
	block="$1"
	last_shortcut_line=$(printf "%s\n" "$block" | grep -n "Alt+Tab" | head -n1 | cut -d: -f1)
	first_snap_line=$(printf "%s\n" "$block" | grep -n "Super+Left" | head -n1 | cut -d: -f1)
	[ -n "$last_shortcut_line" ] && [ -n "$first_snap_line" ] && [ "$last_shortcut_line" -lt "$first_snap_line" ]
	' _ "${TEXT_BLOCK}"

#==========================
# パッケージリストへの新規依存追加がないこと
#==========================
COMMON_LIST="${REPO_ROOT}/config/package-lists.d/mypocketos-common.list.chroot"
STANDARD_LIST="${REPO_ROOT}/config/package-lists.d/mypocketos-standard.list.chroot"
check "no network-monitoring helper package was added for the network display (vnstat/iftop/nload/bmon/nethogs/sysstat)" \
	sh -c '! grep -iE "^(vnstat|iftop|nload|bmon|nethogs|sysstat)$" "$1" "$2"' _ "${COMMON_LIST}" "${STANDARD_LIST}"
check "conky-std remains the only Conky-related package (no new conky-* package added)" \
	sh -c '[ "$(grep -c "^conky" "$1" "$2" 2>/dev/null | awk -F: "{s+=\$2} END{print s}")" -eq 1 ]' \
	_ "${COMMON_LIST}" "${STANDARD_LIST}"

echo "SCENARIOS=$((PASS + FAIL)) PASS=${PASS} FAIL=${FAIL}"
[ "${FAIL}" -eq 0 ]
