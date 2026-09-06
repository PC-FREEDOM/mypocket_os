#!/bin/sh
#
# Conky表示 (システム情報パネル) に対する静的テスト。
# 既存表示項目 (MyPocketOS見出し・ホスト名・カーネル・稼働時間・
# 起動モード・CPU使用率・メモリ・ルートFS・既存ショートカット5項目) が
# 維持されていること、新規追加したネットワーク表示・ウィンドウスナップ
# 表示が期待どおりであることを確認する。実Conky・実Xは一切使用しない。
#
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CONKY_CONF="${REPO_ROOT}/config/includes.chroot/etc/skel/.config/conky/conky.conf"

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
# 新規追加: ネットワーク表示
#==========================
check "network: ネットワーク heading is present" \
	sh -c 'printf "%s" "$1" | grep -qF "ネットワーク:"' _ "${TEXT_BLOCK}"
check "network: uses \${if_gw} (built-in default-gateway check, no exec)" \
	sh -c 'printf "%s" "$1" | grep -qF "\${if_gw}"' _ "${TEXT_BLOCK}"
check "network: \${if_gw} is closed with \${endif}" \
	sh -c 'printf "%s" "$1" | grep -qF "\${endif}"' _ "${TEXT_BLOCK}"
check "network: has an \${else} branch for the disconnected case" \
	sh -c 'printf "%s" "$1" | grep -qF "\${else}"' _ "${TEXT_BLOCK}"
check "network: disconnected fallback text is 未接続" \
	sh -c 'printf "%s" "$1" | grep -qF "未接続"' _ "${TEXT_BLOCK}"
check "network: Down: line uses bare \${downspeed} (no interface argument)" \
	sh -c 'printf "%s" "$1" | grep -qE "Down:\\\$color \\\${alignr}\\\$\\{downspeed\\}$"' _ "${TEXT_BLOCK}"
check "network: Up: line uses bare \${upspeed} (no interface argument)" \
	sh -c 'printf "%s" "$1" | grep -qE "Up:\\\$color \\\${alignr}\\\$\\{upspeed\\}"' _ "${TEXT_BLOCK}"

# デバイス名・vendor固有のインターフェース名をハードコードしていないこと
# (wlan0/eth0/wlp2s0/enp3s0等のよくあるLinuxネットワークインターフェース
# 命名パターンが、conky.text本文に一切現れないことを確認する)
check "network: no hardcoded network interface name in conky.text (wlan/eth/wlp/enp/eno/ens/ppp/wwan)" \
	sh -c '! printf "%s" "$1" | grep -qiE "(wlan|eth|wlp|enp|eno|ens|ppp|wwan)[0-9]"' _ "${TEXT_BLOCK}"

# ファイル全体 (コメントも含む) にも、実引数として使われる形の
# ハードコードされたインターフェース名が無いことを確認する。
# 説明用コメント中の一般名詞的な例示 (wlan0/eth0等) はコメント内でのみ許容し、
# ${downspeed ...}/${upspeed ...}のような実際の変数呼び出しの引数としては
# 使われていないことを確認する。
check "network: \${downspeed}/\${upspeed} never take an explicit interface argument anywhere in the file" \
	sh -c '! grep -qE "\\\$\\{(downspeed|upspeed)[[:space:]]+[^}]" "$1"' _ "${CONKY_CONF}"

#==========================
# 既存の「execを使わない」方針が今回も維持されていること
# (test_boot_mode.shで既に確認されている内容の重複確認だが、ネットワーク
# 表示追加の文脈でも明示的に再確認する)
#==========================
check "no exec/execi variable was added for the network display" \
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
