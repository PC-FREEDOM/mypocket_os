-- MyPocketOS - Conkyネットワーク表示用Luaヘルパー
--
-- conky.confのlua_loadで読み込まれ、conky.textから
-- ${lua mypocketos_network_connected}・${lua mypocketos_network_downspeed}・
-- ${lua mypocketos_network_upspeed}として呼ばれる。Conky本体のプロセス内
-- で実行され、conky_parse() (Conky公式のLua API。Conky自身のTEXT評価を
-- Luaから呼び出すだけの内部処理であり、exec/execiのような外部コマンド
-- 起動は一切発生しない) のみを使う。
--
-- 背景 (2026-09-07 実機不具合修正): 引数なしの${downspeed}/${upspeed}に
-- よるConky内部のネットワークデバイス自動選択が、実機ではdefault route
-- interface (今回はwlp2s0、`ip route show default`で確認) を選ばず、
-- 常に未使用の別interface (enp4s0) を選んでいたため、Wi-Fi通信中でも
-- Down/Upが常に0Bのまま変化しない不具合が生じた (`/proc/net/dev`では
-- wlp2s0のRX/TXバイト数が実際に増加していた)。
--
-- この修正では、Conky組み込みの${gw_iface} (default routeのinterface名。
-- 判定不能時は"none"/"multiple") をconky_parse()経由でLuaから取得し、
-- その値を明示的に${downspeed IFACE}/${upspeed IFACE}へ渡すことで、
-- 実際に使われているinterfaceの速度を確実に参照する。特定interface名の
-- ハードコードは行わず、毎回${gw_iface}から動的に取得する。

local function trim(s)
    return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

-- Linuxのネットワークインターフェース名として妥当な範囲だけを許可する
-- (IFNAMSIZ=16、末尾NUL込みのため実質15文字以内。英数字・'.'・':'・
-- '-'・'_'のみ)。conky_parse()へ渡す文字列は、Conky自身が再度TEXTとして
-- 解釈するため、想定外の文字列 (例: "none"/"multiple"、その他将来の
-- Conky/カーネル側の想定外出力) をそのまま埋め込まない多層防御として、
-- ここで厳密に検証する。検証に失敗した場合は「未接続」として扱う
-- (fail-close)。
local function valid_iface(name)
    if name == nil or name == "" or #name > 15 then
        return false
    end
    return name:match("^[%w%.:_%-]+$") ~= nil
end

-- default route interface名を返す。取得できない・不正な場合はnilを返す
-- (呼び出し側はnilを「未接続」として扱う)。
local function gw_iface()
    local iface = trim(conky_parse("${gw_iface}"))
    if not valid_iface(iface) then
        return nil
    end
    return iface
end

function conky_mypocketos_network_connected()
    if gw_iface() ~= nil then
        return "yes"
    end
    return "no"
end

function conky_mypocketos_network_downspeed()
    local iface = gw_iface()
    if iface == nil then
        return ""
    end
    return conky_parse("${downspeed " .. iface .. "}")
end

function conky_mypocketos_network_upspeed()
    local iface = gw_iface()
    if iface == nil then
        return ""
    end
    return conky_parse("${upspeed " .. iface .. "}")
end
