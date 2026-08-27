#!/bin/sh
# tests/persistence/instrument_gui.sh
#
# mypocketos-persistence-setup (GUI本体) の production ファイルを読み取り、
# サンドボックス化された実行コピーを生成する。production ファイルは一切
# 変更しない (常に "sed ... SRC > DEST" で新規ファイルへ出力し、sed -i は
# 使わない)。
#
# 使い方: instrument_gui.sh SANDBOX_DIR DEST_PATH
#
# 置換は2段階で行う。
#   段階1 (apply_rule): production中のリテラルを、正規表現メタ文字を
#         含まない固定トークン (@@SANDBOX_BIN@@ 等) へ、件数を厳密に
#         確認しながら置換する。件数不一致は即座に失敗する。
#   段階2 (resolve_token): 固定トークンを、このテスト実行で実際に
#         mktemp -d が生成したサンドボックスパスへ解決する。
#
# 各ルールの一致件数は、事前に `grep -cE` で本体ファイルに対して直接
# 確認済みの値である (2026年時点のソースに基づく)。
set -eu

TESTS_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$TESTS_DIR/../.." && pwd)"
PROD_GUI="$REPO_ROOT/config/includes.chroot/usr/local/bin/mypocketos-persistence-setup"
PROD_HELPER="$REPO_ROOT/config/includes.chroot/usr/local/libexec/mypocketos-persistence-setup-helper"
. "$TESTS_DIR/common.sh"

instrument_gui() {
    # instrument_gui SANDBOX DEST
    sandbox="$1"; dest="$2"

    cp -- "$PROD_GUI" "$dest"

    # ---- 段階1: リテラル -> 固定トークン --------------------------------
    apply_rule gui-fixed-path \
        "PATH='/usr/bin:/bin:/usr/sbin:/sbin'" \
        "PATH='@@SANDBOX_BIN@@'" \
        1 "$dest"

    apply_rule gui-helper-path \
        "HELPER='/usr/local/libexec/mypocketos-persistence-setup-helper'" \
        "HELPER='@@SANDBOX_HELPER_PATH@@'" \
        1 "$dest"

    apply_rule gui-sys-block \
        '/sys/block/' \
        '@@SANDBOX_SYS@@/block/' \
        1 "$dest"

    apply_rule gui-sys-class-block \
        '/sys/class/block/' \
        '@@SANDBOX_SYS@@/class/block/' \
        1 "$dest"

    apply_rule gui-proc-cmdline \
        'cat /proc/cmdline' \
        'cat @@SANDBOX_PROC_CMDLINE@@' \
        1 "$dest"

    apply_rule gui-proc-swaps \
        'cat /proc/swaps' \
        'cat @@SANDBOX_PROC_SWAPS@@' \
        1 "$dest"

    # check_live_env の判定文・エラーメッセージ・build_candidates の
    # findmnt --target の計3箇所に同一リテラルが出現する。
    apply_rule gui-run-live-medium \
        '/run/live/medium' \
        '@@SANDBOX_RUN@@/live/medium' \
        3 "$dest"

    # ancestor_knames_of_source: root/mknod無しで実block deviceを
    # 用意できないため、通常ファイルの存在確認 (-e) へ緩和する。
    apply_rule gui-ancestor-b-relax \
        '\[ ! -b "\$src" \]' \
        '[ ! -e "$src" ]' \
        1 "$dest"

    # kill呼び出しを絶対パスの完全モックへ置換する。dash組み込みの kill は
    # PATHから省略しても exit 127 にはならず (組み込みコマンドはPATH検索
    # を経由しないため)、意図せず実プロセスへ本物のシグナルを送ってしまう
    # 余地が残る。"/" を含む絶対パスで呼び出すことで、シェルは必ず外部
    # コマンドとしてexecする (組み込みが使われるのはパス区切りを含まない
    # 単純なコマンド名で呼ばれた場合のみ) ため、mock-kill を確実に経由
    # させることができる。
    apply_rule gui-kill-progress-pid \
        'kill "\$PROGRESS_PID"' \
        '@@SANDBOX_BIN@@/mock-kill "$PROGRESS_PID"' \
        2 "$dest"

    apply_rule gui-kill-helper-pid-probe \
        'kill -0 "\$helper_pid"' \
        '@@SANDBOX_BIN@@/mock-kill -0 "$helper_pid"' \
        1 "$dest"

    # ---- 段階2: 固定トークン -> 実サンドボックスパス ---------------------
    resolve_token '@@SANDBOX_BIN@@' "$sandbox/bin" "$dest"
    resolve_token '@@SANDBOX_HELPER_PATH@@' "$sandbox/work/helper-copy" "$dest"
    resolve_token '@@SANDBOX_SYS@@' "$sandbox/sys" "$dest"
    resolve_token '@@SANDBOX_PROC_CMDLINE@@' "$sandbox/proc/cmdline" "$dest"
    resolve_token '@@SANDBOX_PROC_SWAPS@@' "$sandbox/proc/swaps" "$dest"
    resolve_token '@@SANDBOX_RUN@@' "$sandbox/run" "$dest"

    chmod +x "$dest"

    verify_gui_invariants "$sandbox" "$dest"
}

verify_gui_invariants() {
    sandbox="$1"; dest="$2"
    sandbox_esc="$(escape_ere "$sandbox")"

    # 未解決トークンが0件であること。
    assert_count 'gui-invariant-no-unresolved-tokens' '@@[A-Z_]+@@' "$dest" 0

    # 固定PATHがsandbox binのみを指していること。
    assert_count 'gui-invariant-path-is-sandbox-bin' \
        "PATH='${sandbox_esc}/bin'" "$dest" 1

    # HELPERがsandbox配下を指していること。
    assert_count 'gui-invariant-helper-path-in-sandbox' \
        "HELPER='${sandbox_esc}/" "$dest" 1

    # 実システム絶対パス (/usr/, /sbin/) がコメント・shebang行以外に
    # 残っていないこと。
    real_path_lines="$(grep -nE '(^|[^#].*)(/usr/|/sbin/)' "$dest" \
        | grep -vE '^1:#!/bin/sh$' \
        | grep -vE '^[0-9]+:[[:space:]]*#' || true)"
    if [ -n "$real_path_lines" ]; then
        echo "[gui-invariant-no-real-system-paths] REFUSING: found real system path(s):" >&2
        printf '%s\n' "$real_path_lines" >&2
        exit 93
    fi

    # メイン抑止方式 (後続PR向け、未使用) のためのマーカーコメントが
    # 正確に1件であることを、今のうちから保証しておく。
    assert_count 'gui-invariant-main-marker-count' \
        '# ---- メイン処理 ' "$dest" 1

    # production形式の (絶対パスを経由しない、dash組み込みが使われうる)
    # kill呼び出しが0件であること。置換後は ".../mock-kill ..." という
    # 形になり、この文字列自体が末尾に "kill \"\$PROGRESS_PID\"" を含む
    # ため、単純な部分一致では常に一致してしまう。"kill"の直前の1文字が
    # 単語構成文字 (英数字・アンダースコア・ハイフン、"mock-kill"の
    # ハイフンを含む) ではないこと (行頭を含む) を条件に加えることで、
    # 置換済みのmock-kill呼び出しとproduction形式の裸のkill呼び出しを
    # 区別する。
    assert_count 'gui-invariant-no-bare-kill-progress' \
        '(^|[^[:alnum:]_-])kill "\$PROGRESS_PID"' "$dest" 0
    assert_count 'gui-invariant-no-bare-kill-helper-probe' \
        '(^|[^[:alnum:]_-])kill -0 "\$helper_pid"' "$dest" 0

    # sandbox/bin/mock-kill 経由の呼び出しが正確に3件であること
    # (kill "$PROGRESS_PID" x2 + kill -0 "$helper_pid" x1)。
    assert_count 'gui-invariant-mock-kill-count' \
        "${sandbox_esc}/bin/mock-kill" "$dest" 3
}

instrument_gui "$1" "$2"
