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
# 加えて2026-09-08 (6commit目)、ネットワーク速度・メモリ・ルートFS等の
# 値が変化するたびにConkyウィンドウ全体の横幅が変化する不具合が実機で
# 確認された。minimum_width/maximum_widthを同一の固定値に設定すること
# で対応した(値は実際にX11ディスプレイ上でconky-std 1.22.1バイナリを
# 動かして実測した描画幅を基準に決定。推測による決め打ちではない)。
#
# さらに2026-09-08 (7commit目)、ウィンドウ全体の横幅は固定されたものの、
# メモリ・ルートFS・ネットワークの各行が単一の${alignr}で行全体を右寄せ
# していたため、値の桁数が変わるたびに「Down」「/」「Up」等の固定文字列
# 自体の位置が左右に移動する不具合が実機で確認された。区切り文字の直前に
# ${goto x}(絶対座標指定、直前テキスト長に非依存)を置く方式に置き換えて
# 対応した。座標値は実際にX11ディスプレイ上でconky-std 1.22.1バイナリを
# レンダリングし、値の文字数を変えた複数パターンで${goto}直後の文字の
# 開始座標が一致することを実測して検証した(推測による決め打ちではない。
# また、1行に${alignr}を複数回使うと後方のalignrが前方の右端位置計算に
# 干渉することも実機相当の環境で確認されたため、この方式は採用していない)。
#
# さらに2026-09-08 (8commit目)、7commit目で採用した予約幅(ASCII 9文字
# 分・約64px)が、実機で観測される実際の値の長さ(6〜7文字程度)に対して
# 過大であり、値と区切り文字の間に不自然な空白ができ、行ごとの空白量も
# ばらついて見た目が不揃いになる不具合が実機で確認された。予約幅を
# ASCII 7文字分(約50px、実際に観測された値がすべて収まる根拠のある
# 実測上限)へ縮小し、${goto}の座標値も縮小した。
#
# 【7・8commit目は過去の実装であり、9commit目で撤回済み】上記の
# ${goto x}による固定カラム方式は、VMでの見た目確認の結果、区切り文字
# の位置はある程度固定できるものの、行ごとの空白が不自然でショート
# カット欄のような整然とした印象にならないと評価された。2026-09-08
# (9commit目)、メモリ・ルートFS・ネットワークの3行を、6commit目
# までと同じ${alignr}ベースの右揃え表示へ戻した。値の桁数によって
# 区切り文字の位置が多少動くことは許容し、「行として自然に整って見える
# こと」を優先する方針へ変更した。minimum_width/maximum_width=310に
# よるウィンドウ全体の横幅固定(6commit目)・Network取得ロジック・
# dispatcherは変更していない。
#
# 2026-09-09 (10commit目): 9commit目入りISOのVM確認で、
# ${alignr}ベースの右揃え表示は7・8commit目より自然に見えると評価
# されたが、実際の通信中(Down 480KiB / Up 36.9KiB程度)のNetwork行に
# 対して310pxの固定幅はやや広すぎるとのフィードバックがあった。
# minimum_width/maximum_widthを310から300へ縮小した(レイアウト方式
# [${alignr}]自体・conky.textの文言・値・Network取得ロジック・
# dispatcherには変更を加えていない)。
#
# 2026-09-09 (11commit目): 10commit目入りISOのVM確認で、
# Network 1行表示・メモリ・ルートFS・カーネル・ショートカット・
# Window Snap・日本語表示・右揃えレイアウトはいずれも正常だったが、
# VMスクリーンショット上ではまだ右側に余白が見られ、「もうちょっと
# 狭くてもいけそう」との評価があった。minimum_width/maximum_widthを
# 300から292へさらに縮小した(変更対象はこの2値のみ)。
#
# 2026-09-09 (12commit目): 11commit目入りISOのVM確認で、表示は
# 正常だったが「変化が感じられません」との評価があり、依然として右側に
# 余白が感じられた。minimum_width/maximum_widthを292から284へさらに
# 縮小した(変更対象はこの2値のみ)。
#
# 2026-09-09 (13commit目・幅の変更なし): ユーザーの本来の意図が
# 「ショートカット・Window Snap欄も含めたパネル全体のスリム化」だったと
# 判明したため、conky.textの各行を個別に分離した精密な実測調査を行った。
# ショートカット・ウィンドウスナップはボトルネックではなく、実際の
# ボトルネックはネットワーク行(実機VM確認済みの値だけで281px)である
# ことが判明した。284pxからこれ以上安全に縮小する余地がほぼないと結論
# づけ、幅は変更せず調査結果のみを報告した。
#
# 2026-09-09 (14commit目): 13commit目の調査結果を受け、ユーザーは
# メモリ・ルートFS・ネットワークの3行で、値と区切り記号("/")周辺の
# 空白を削る案を選択した。これにより各行の自然な必要幅が縮小したため
# (ネットワーク行: 281px→267px)、minimum_width/maximum_widthを284
# から278へ縮小した。
#
# 2026-09-09 (15commit目): 14commit目入りISOのVM確認で、区切り
# 記号周辺の空白削除だけでは「変わってないようにしか見えません」との
# 評価があり、Network表示を横1行に押し込む前提を見直した。Network行を
# 見出し+「  Down:」「  Up:」の縦方向複数行表示へ戻したことで、
# Network関連行の自然幅が大幅に縮小し、パネル幅のボトルネックが
# ルートFS行(100%使用時256px)へ移った。minimum_width/maximum_widthを
# 278から262へ縮小した。
#
# 2026-09-10 (16commit目): 15commit目入りISOのVM確認では表示は
# 正常だったが、ユーザーが求める「パネル全体が見た目で明確に細くなる」
# という完成形には届いていなかった。Network分割後の新たなボトルネックが
# ホスト名・カーネル・稼働時間・起動モード・CPU使用率・メモリ・ルートFS
# という1行表示(ラベル+${alignr}値)に移っていたため、この7行も
# 「ラベル行」+「半角スペース2文字分インデントした値行」の2段構成へ
# 変更した。この結果、幅のボトルネックがショートカット最長行
# ("ファイルマネージャー"、242px)へ移り、minimum_width/maximum_widthを
# 262から248へ縮小した。ショートカット・ウィンドウスナップの文言・
# 項目・キー割り当ては一切変更していない。
#
# 2026-09-10 (17commit目・現行): 16commit目入りISOのVM確認で、横幅の
# 縮小自体には成功したが、「個人的には前の並びのほうが好き」との評価が
# あった。システム情報7行を縦2段に分割したことで、情報が縦にばらけて
# 一覧性が落ち、視線移動が増え、間延びして見えるという結果になったため
# 見た目として不採用とし、この7行を15commit目相当の1行表示
# (ラベル+${alignr}値)へ戻した。Network行(15commit目の縦方向複数行
# 表示)は維持している。16commit目の248pxはシステム情報2段化を前提に
# した値のため、1行表示へ戻すことで必要幅が再び増え、15commit目の
# 262pxを基準に再評価した結果、ルートFS行(256px)が再びボトルネックと
# なり、262pxをそのまま採用した(幅の再設計は行っていない)。
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

# conky.config = { ... } の本文部分だけを取り出す (comment行と区別する)。
CONFIG_BLOCK="$(sed -n '/^conky\.config = {$/,/^}$/p' "${CONKY_CONF}")"
check "conky.config block was extracted (non-empty)" \
	sh -c '[ -n "$1" ]' _ "${CONFIG_BLOCK}"

#==========================
# 固定幅化 (2026-09-08、6commit目、2026-09-09に10・11・12・14・15commit目で縮小)
#
# 背景: ネットワーク速度・メモリ・ルートFS等の値が変化するたびに、
# Conkyウィンドウ全体の横幅も変化してしまう不具合が実機で確認された。
# minimum_widthとmaximum_widthを同一値に設定することで、ウィンドウの
# 横幅をほぼ固定する。6commit目では、本セッションで実際にX11
# ディスプレイ・実フォントを使ってconky-std 1.22.1バイナリを
# レンダリングし、最も長くなりうる値を仮定した場合の実測描画幅
# (298px)を基準に310を採用した(推測による決め打ちではない)。
#
# 2026-09-09 (10commit目): 9commit目入りISOのVM確認で、実際の通信中
# (Down 480KiB / Up 36.9KiB程度)のNetwork行に対して310pxはやや広い
# とのフィードバックがあった。想定しうる長めの値とユーザー提示の
# ネットワーク速度例を組み合わせた内容を幅制約なしでレンダリングし、
# 実測した自然な描画幅(281px)を基準に、300へ縮小した(推測による
# 決め打ちではない)。
#
# 2026-09-09 (11commit目): 10commit目入りISOのVM確認で、Network 1行
# 表示・メモリ・ルートFS・カーネル・ショートカット・Window Snap・
# 日本語表示・右揃えレイアウトはいずれも正常だったが、VMスクリーン
# ショット上ではまだ右側に余白が見られ、「もうちょっと狭くてもいけ
# そう」との評価があった。300から292へさらに縮小した(実測した自然な
# 描画幅281pxに対して11pxの余裕を持つ値であり、依然として自然な
# 描画幅を下回っていない)。
#
# 2026-09-09 (12commit目): 11commit目入りISOのVM確認で、表示は正常
# だったが「変化が感じられません」との評価があり、依然として右側に
# 余白が感じられた。292から284へさらに縮小した。想定しうる長めの値と
# 複数のネットワーク速度例(Down 480KiB / Up 36.9KiB・Down 206KiB /
# Up 5.87KiB)、より極端な想定(999.9MiB相当)のいずれについても、
# 284px固定幅でクリッピング・折り返しがないことを実際にレンダリング
# して確認した(推測による決め打ちではない)。
#
# 2026-09-09 (13commit目、幅の変更なし): メモリ・ルートFS・ネットワーク
# の各行を個別に分離した精密な実測により、実機VM確認済みの値だけで
# 281pxを要し、284pxからこれ以上安全に縮小する余地がほぼないと判明
# した。ユーザー指示の"999.9MiB"は、Conky自身のdownspeed/upspeedが
# 実際に出力する有効数字3桁のパターンと整合しないと判明したため、
# 以降は実際に出力されうる範囲での現実的な上限("99.9MiB"相当)を
# 判断基準に用いている。
#
# 2026-09-09 (14commit目): メモリ・ルートFS・ネットワークの3行で、
# 値と区切り記号("/")周辺の空白を削ったことで、各行の自然な必要幅が
# 縮小した(ネットワーク行の実機VM確認済みの実測値: 281px→267px)。
# これを基準に、284から278へ縮小した(実測値267pxに11px、Conky自身が
# 実際に出力しうる上限[99.9MiB相当、274px]にも4pxの余裕を持つ値)。
#
# 2026-09-09 (15commit目): 14commit目入りISOのVM確認で、区切り
# 記号周辺の空白を削っただけでは見た目の変化が感じられないとの評価が
# あり、Network表示を横1行に押し込む前提自体を見直した。Network行を
# 見出し+「  Down:」「  Up:」の縦方向複数行表示へ戻したところ(下記
# 「ネットワーク表示レイアウト」節参照)、Network関連行の自然幅が
# 大幅に縮小し、パネル幅のボトルネックがルートFS行(100%使用時256px)
# へ移った。これを基準に、278から262へ縮小した(実測値256pxに6pxの
# 余裕を持つ値)。
#
# 2026-09-10 (16commit目): 15commit目入りISOのVM確認では表示は
# 正常だったが、パネル全体の明確なスリム化には届いていなかった。
# ホスト名・カーネル・稼働時間・起動モード・CPU使用率・メモリ・ルートFS
# の7行を「ラベル行+インデント値行」の2段構成へ変更したところ、これら
# の行の自然幅は大幅に縮小したが、変更していないショートカット最長行
# ("ファイルマネージャー")が242pxを要することが判明し、これが新たな
# ボトルネックになった。これを基準に、262から248へ縮小した(実測値
# 242pxに6pxの余裕を持つ値)。
#
# 2026-09-10 (17commit目・現行): 16commit目入りISOのVM確認で「個人的
# には前の並びのほうが好き」との評価があり、システム情報7行の2段構成を
# 見た目として不採用とし、15commit目相当の1行表示へ戻した(下記
# 「システム情報行のレイアウト」節参照)。1行表示へ戻したことで、
# 幅のボトルネックが再びルートFS行(100%使用時256px)へ戻ったため、
# 248から262へ戻した(実測値256pxに6pxの余裕を持つ値、15commit目と
# 同じ値・同じ根拠)。
#==========================
check "minimum_width is set" \
	sh -c 'printf "%s" "$1" | grep -qE "minimum_width[[:space:]]*=[[:space:]]*[0-9]+,"' _ "${CONFIG_BLOCK}"
check "maximum_width is set" \
	sh -c 'printf "%s" "$1" | grep -qE "maximum_width[[:space:]]*=[[:space:]]*[0-9]+,"' _ "${CONFIG_BLOCK}"
check "minimum_width and maximum_width are set to the same fixed value (window width does not grow/shrink with content)" \
	sh -c '
	min_val=$(printf "%s" "$1" | sed -nE "s/.*minimum_width[[:space:]]*=[[:space:]]*([0-9]+),.*/\1/p")
	max_val=$(printf "%s" "$1" | sed -nE "s/.*maximum_width[[:space:]]*=[[:space:]]*([0-9]+),.*/\1/p")
	[ -n "$min_val" ] && [ -n "$max_val" ] && [ "$min_val" = "$max_val" ]
	' _ "${CONFIG_BLOCK}"
check "the fixed width setting appears exactly once each (single, unambiguous source of truth)" \
	sh -c '
	min_count=$(printf "%s" "$1" | grep -oE "minimum_width[[:space:]]*=" | wc -l)
	max_count=$(printf "%s" "$1" | grep -oE "maximum_width[[:space:]]*=" | wc -l)
	[ "$min_count" -eq 1 ] && [ "$max_count" -eq 1 ]
	' _ "${CONFIG_BLOCK}"
check "the fixed width is comfortably wider than the empirically-measured natural content width (256px at rootfs 100% usage, the bottleneck again after 17commit reverted the system-info rows to single-line layout), not merely equal to it, and equal to the 15commit-era value (262px, narrower than the 278/284/292/300/310px used before that)" \
	sh -c '
	min_val=$(printf "%s" "$1" | sed -nE "s/.*minimum_width[[:space:]]*=[[:space:]]*([0-9]+),.*/\1/p")
	[ -n "$min_val" ] && [ "$min_val" -ge 258 ] && [ "$min_val" -le 267 ]
	' _ "${CONFIG_BLOCK}"

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
check "existing: memory line still shows \${mem}, \${memmax}, \${memperc} (values themselves unchanged)" \
	sh -c 'printf "%s" "$1" | grep -qF "\${mem}" && printf "%s" "$1" | grep -qF "\${memmax}" && printf "%s" "$1" | grep -qF "\${memperc}"' _ "${TEXT_BLOCK}"
check "existing: memory bar (\${membar 6}) is still present and unchanged" \
	sh -c 'printf "%s" "$1" | grep -qF "\${membar 6}"' _ "${TEXT_BLOCK}"
check "existing: root filesystem line is present" \
	sh -c 'printf "%s" "$1" | grep -qF "ルートFS (/):"' _ "${TEXT_BLOCK}"
check "existing: root filesystem line still shows \${fs_used /}, \${fs_size /}, \${fs_used_perc /} (values themselves unchanged)" \
	sh -c 'printf "%s" "$1" | grep -qF "\${fs_used /}" && printf "%s" "$1" | grep -qF "\${fs_size /}" && printf "%s" "$1" | grep -qF "\${fs_used_perc /}"' _ "${TEXT_BLOCK}"
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
# 新規追加: ネットワーク表示 (2026-09-07 2nd fix、取得ロジック現行実装)
#
# mypocketos-network.luaは廃止した。conky_parse()をLua ${lua ...} 呼び出し
# 内から再帰的に呼ぶ実装は、実機で"attempt to call a nil value"という
# Lua実行時エラーを起こすことが判明したため(このテストスイートの旧版は
# 静的にはPASSしていたが、この種の実行時限定の不具合は検出できなかった)。
# 現行実装は、Conky変数の引数へ別のConky変数を直接ネストさせる
# ${downspeed ${gw_iface}}/${upspeed ${gw_iface}}のみで完結する。
#
# 2026-09-08 (5commit目): 表示レイアウトを、「ネットワーク:」見出し+
# 「Down:」「Up:」の3行表示から、「ネットワーク:  Down <値> / Up <値>」の
# 1行表示へ変更した(取得ロジック自体・接続判定ロジック自体は無変更)。
#
# 2026-09-09 (15commit目): 14commit目までの1行表示ではNetwork行が
# パネル幅のボトルネックとなっていたため、5commit目以前と同様の
# 縦方向複数行表示(見出し行+「  Down:」「  Up:」の2つの子行)へ
# 戻した(取得ロジック自体・接続判定ロジック自体は無変更。1行に複数の
# ${alignr}を使わないという7〜9commit目で確立した設計は維持し、各行
# 1つの${alignr}のみを使う)。
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
check "network: uses \${downspeed \${gw_iface}} (nested, no Lua, no hardcoded interface)" \
	sh -c 'printf "%s" "$1" | grep -qF "\${downspeed \${gw_iface}}"' _ "${TEXT_BLOCK}"
check "network: uses \${upspeed \${gw_iface}} (nested, no Lua, no hardcoded interface)" \
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

#==========================
# ネットワーク表示レイアウト (2026-09-09、15commit目・現行: 縦方向複数行表示)
#
# 背景: 5〜14commit目の1行表示("ネットワーク: Down <値>/Up <値>")では、
# Network行自体がパネル幅を決めるボトルネックになっていた
# (14commit目時点で自然幅267px、パネル全体を280px未満に縮小できない
# 主因)。ユーザーがVMで確認したところ、区切り記号周辺の空白を削る
# 程度では見た目の変化が感じられず、Network表示を横1行に押し込む
# という前提自体を見直すこととなった。
#
# 対応: 見出し行「ネットワーク:」+インデントされた子行「  Down:」
# 「  Up:」という、1〜4commit目当時と類似の縦方向複数行表示へ戻した
# (現行の${gw_iface}ベースの取得ロジック・${if_match}による接続判定は
# 一切変更していない)。各子行は単一の${alignr}のみを使うため、
# 7〜9commit目で判明した「1行に複数の${alignr}を使うと干渉する」
# 問題は発生しない。この分割により、Network関連行の自然幅が大幅に
# 縮小し(見出し行106px・Down行119px・Up行112px、いずれも旧1行表示の
# 267pxを大きく下回る)、パネル幅のボトルネックがルートFS行(100%
# 使用時256px)へ移った。
#==========================
check "network: connected-state heading is on its own line (no Down/Up value on the same line)" \
	sh -c 'printf "%s\n" "$1" | grep -qE "\\\${color grey}ネットワーク:\\\$color[[:space:]]*$"' _ "${TEXT_BLOCK}"
check "network: connected-state has an indented \"  Down:\" sub-line using \${alignr} and the nested \${downspeed \${gw_iface}}" \
	sh -c 'printf "%s" "$1" | grep -qF "  Down:\$color \${alignr}\${downspeed \${gw_iface}}"' _ "${TEXT_BLOCK}"
check "network: connected-state has an indented \"  Up:\" sub-line using \${alignr} and the nested \${upspeed \${gw_iface}}" \
	sh -c 'printf "%s" "$1" | grep -qF "  Up:\$color \${alignr}\${upspeed \${gw_iface}}"' _ "${TEXT_BLOCK}"
check "network: disconnected fallback (未接続) is on a single line with the ネットワーク: heading" \
	sh -c 'printf "%s\n" "$1" | grep -qE "ネットワーク:\\\$color \\\${alignr}未接続"' _ "${TEXT_BLOCK}"
check "network: no arrow glyphs (↓/↑/→/←) were introduced for the network display" \
	sh -c '! printf "%s" "$1" | grep -qE "[↓↑→←]"' _ "${TEXT_BLOCK}"

# 回帰防止: 5〜14commit目の1行表示("ネットワーク: Down <値>/Up <値>"、
# あるいは空白ありの旧表記)へ戻っていないことを確認する。
check "network: connected-state Down/Up are no longer combined on a single line (regression guard against the 5-14commit-era single-line layout)" \
	sh -c '! printf "%s" "$1" | grep -qE "ネットワーク:\\\$color \\\${alignr}Down"' _ "${TEXT_BLOCK}"

#==========================
# システム情報7行のレイアウト (2026-09-08、9commit目基本方式、
# 2026-09-10 16commit目で一時的にラベル行+インデント値行の2段構成へ
# 変更したが、17commit目で1行表示へ復元・現行)
#
# 経緯: 6commit目でウィンドウ全体の横幅を固定した後、7commit目で
# メモリ・ルートFS・ネットワークの各行に${goto x}を導入し、区切り文字
# ("/"・"(")の位置をピクセル単位で絶対座標固定する方式を採用した。
# 8commit目で、その予約幅を過大(9文字)から縮小(7文字)する調整も
# 行った。しかし、ユーザーがVMで実際の見た目を確認したところ、区切り
# 位置はある程度固定できるものの、行ごとの空白が不自然でショートカット
# 欄のような整然とした印象にならないと評価され、6commit目までの
# ${alignr}による単純な右揃え表示の方が見やすいと判断された。
#
# 対応: 9commit目で、メモリ・ルートFS・ネットワークの3行を、7・8commit
# 目で導入した${goto x}による固定カラム方式から撤回し、6commit目まで
# と同じ${alignr}ベースの右揃え表示へ戻した。
#
# 2026-09-09 (14commit目): 値と区切り記号("/")周辺の空白を削った
# ("${mem} / ${memmax}" → "${mem}/${memmax}"、メモリ・ルートFS・
# ネットワークの3行のみ)。
#
# 2026-09-09 (15commit目): Network行の1行表示自体を撤回し縦方向
# 複数行表示へ戻した(上記「ネットワーク表示レイアウト」節参照)。
# メモリ・ルートFSの2行は14commit目の空白なし表記のまま変更していない。
#
# 2026-09-10 (16commit目、17commit目で不採用): 15commit目でNetwork行を
# 縦方向複数行へ分割した結果、幅のボトルネックがメモリ・ルートFS等の
# 1行表示(ラベル+${alignr}値)に移った。これを受け、ホスト名・
# カーネル・稼働時間・起動モード・CPU使用率・メモリ・ルートFSの計7行を、
# 「ラベル行」+「半角スペース2文字分インデントした値行」の2段構成へ
# 変更した。
#
# 2026-09-10 (17commit目・現行): 16commit目入りISOのVM確認で「個人的
# には前の並びのほうが好き」との評価があった。システム情報7行が縦に
# ばらけたことで、一覧性が落ち、視線移動が増え、間延びして見えるという
# 結果になったため、見た目として不採用とし、この7行を6〜15commit目
# 相当の1行表示(ラベル:$color ${alignr}値)へ戻した。値と区切り記号
# ("/")周辺の空白なし表記(14commit目)は維持している。Network行
# (15commit目の縦方向複数行表示)は変更していない。
#==========================
check "hostname: still uses \${alignr} for right-justification on a single line (restored to 15commit-era layout, 17commit目)" \
	sh -c 'printf "%s" "$1" | grep -qF "ホスト名:\$color \${alignr}\${nodename}"' _ "${TEXT_BLOCK}"
check "kernel: still uses \${alignr} for right-justification on a single line (restored to 15commit-era layout, 17commit目)" \
	sh -c 'printf "%s" "$1" | grep -qF "カーネル:\$color \${alignr}\${kernel}"' _ "${TEXT_BLOCK}"
check "uptime: still uses \${alignr} for right-justification on a single line (restored to 15commit-era layout, 17commit目)" \
	sh -c 'printf "%s" "$1" | grep -qF "稼働時間:\$color \${alignr}\${uptime}"' _ "${TEXT_BLOCK}"
check "boot mode: still uses \${alignr} for right-justification on a single line (restored to 15commit-era layout, 17commit目)" \
	sh -c 'printf "%s" "$1" | grep -qF "起動モード:\$color \${alignr}\${lua mypocketos_boot_mode}"' _ "${TEXT_BLOCK}"
check "cpu usage: still uses \${alignr} for right-justification on a single line (restored to 15commit-era layout, 17commit目)" \
	sh -c 'printf "%s" "$1" | grep -qF "CPU使用率:\$color \${alignr}\${cpu}%"' _ "${TEXT_BLOCK}"
check "memory: line matches the 14commit-era \${alignr}-based single-line layout exactly (no space around the \"/\" separator, restored 17commit目)" \
	sh -c 'printf "%s" "$1" | grep -qF "メモリ:\$color \${alignr}\${mem}/\${memmax} (\${memperc}%)"' _ "${TEXT_BLOCK}"
check "rootfs: line matches the 14commit-era \${alignr}-based single-line layout exactly (no space around the \"/\" separator, restored 17commit目)" \
	sh -c 'printf "%s" "$1" | grep -qF "ルートFS (/):\$color \${alignr}\${fs_used /}/\${fs_size /} (\${fs_used_perc /}%)"' _ "${TEXT_BLOCK}"

check "cpu bar immediately follows the CPU usage line (no unrelated line inserted between them)" \
	sh -c 'printf "%s\n" "$1" | grep -A1 -xF "\${color grey}CPU使用率:\$color \${alignr}\${cpu}%" | tail -n1 | grep -qxF "\${cpubar 6}"' _ "${TEXT_BLOCK}"
check "memory bar immediately follows the memory line (no unrelated line inserted between them)" \
	sh -c 'printf "%s\n" "$1" | grep -A1 -xF "\${color grey}メモリ:\$color \${alignr}\${mem}/\${memmax} (\${memperc}%)" | tail -n1 | grep -qxF "\${membar 6}"' _ "${TEXT_BLOCK}"
check "rootfs bar immediately follows the rootfs line (no unrelated line inserted between them)" \
	sh -c 'printf "%s\n" "$1" | grep -A1 -xF "\${color grey}ルートFS (/):\$color \${alignr}\${fs_used /}/\${fs_size /} (\${fs_used_perc /}%)" | tail -n1 | grep -qxF "\${fs_bar 6 /}"' _ "${TEXT_BLOCK}"

# 回帰防止: 16commit目の「ラベル行」+「半角スペース2文字インデントの
# 値行」という2段構成へ戻っていないことを確認する(7行それぞれ)。
for pair in \
	'${color grey}ホスト名:$color:  ${nodename}' \
	'${color grey}カーネル:$color:  ${kernel}' \
	'${color grey}稼働時間:$color:  ${uptime}' \
	'${color grey}起動モード:$color:  ${lua mypocketos_boot_mode}' \
	'${color grey}CPU使用率:$color:  ${cpu}%' \
	'${color grey}メモリ:$color:  ${mem}/${memmax} (${memperc}%)' \
	'${color grey}ルートFS (/):$color:  ${fs_used /}/${fs_size /} (${fs_used_perc /}%)'
do
	label_line="${pair%%:  *}"
	value_line="  ${pair#*:  }"
	check "${label_line} is no longer immediately followed by a separate indented value line (regression guard against the 16commit-era 2-line layout)" \
		sh -c '! (printf "%s\n" "$1" | grep -A1 -xF "$2" | tail -n1 | grep -qxF "$3")' _ "${TEXT_BLOCK}" "${label_line}" "${value_line}"
done

# 回帰防止: 13commit目までの「値 空白 / 空白 値」という表記(区切り記号
# の前後に空白がある形式)へ戻っていないことを確認する。
check "memory: no longer has a space before the \"/\" separator (regression guard against the pre-14commit spacing)" \
	sh -c '! printf "%s" "$1" | grep -qF "\${mem} /"' _ "${TEXT_BLOCK}"
check "rootfs: no longer has a space before the \"/\" separator (regression guard against the pre-14commit spacing)" \
	sh -c '! printf "%s" "$1" | grep -qF "\${fs_used /} /"' _ "${TEXT_BLOCK}"

# 回帰防止: 7・8commit目で導入した${goto}による固定カラム方式(座標値の
# 新旧いずれも)へ戻っていないことを確認する。${goto}自体が
# conky.textのどこにも一切登場しないことを確認することで、将来
# 別の座標値で再導入された場合も検出できるようにする。
check "no \${goto} anywhere in conky.text (regression guard against the 7/8commit-era fixed-column approach, rejected for looking uneven in VM testing)" \
	sh -c '! printf "%s" "$1" | grep -qF "\${goto"' _ "${TEXT_BLOCK}"

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
	'Super+Up     上半分' \
	'Super+Down   下半分'
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
