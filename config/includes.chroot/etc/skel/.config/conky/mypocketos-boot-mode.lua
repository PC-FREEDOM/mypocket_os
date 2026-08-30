-- MyPocketOS - Conky起動モード表示用Luaヘルパー
--
-- conky.confのlua_loadで読み込まれ、${lua mypocketos_boot_mode}から呼ばれる。
-- Conky本体のプロセス内で実行されるため、exec/execiのような外部コマンド
-- 起動は一切発生しない。os.getenv("XDG_RUNTIME_DIR")は${env ...}テンプレート
-- 変数とは別のコード経路 (標準Cライブラリgetenv()) であり、影響を受けない。
--
-- 起動モードの判定自体 (mypocketos-boot-mode) はここでは行わない。Openbox
-- autostartが起動時に1回だけ実行し、結果をXDG_RUNTIME_DIR配下のファイルへ
-- 書き込む。ここでは、そのファイルの内容が許可された3値のいずれかで
-- あることだけを確認する。それ以外 (XDG_RUNTIME_DIR未設定・ファイル無し・
-- 想定外の内容) は、すべて安全側の "Unknown" へfail-closeする。

function conky_mypocketos_boot_mode()
    local dir = os.getenv("XDG_RUNTIME_DIR")
    if dir == nil or dir == "" then
        return "Unknown"
    end

    local f = io.open(dir .. "/mypocketos-boot-mode.txt", "r")
    if f == nil then
        return "Unknown"
    end

    local line = f:read("*l")
    f:close()

    if line == "Normal Live" or line == "Persistence" or line == "Unknown" then
        return line
    end

    return "Unknown"
end
