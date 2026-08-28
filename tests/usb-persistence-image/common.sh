#!/bin/sh
# tests/usb-persistence-image/common.sh
#
# build-usb-persistence-image.sh 向け非破壊モックテストハーネスの共通
# ユーティリティ。production ファイル (scripts/build-usb-persistence-image.sh)
# には一切書き込まない。作業領域はすべて mktemp -d でリポジトリ外に作成し、
# 呼び出し元スクリプトの EXIT trap で必ず削除する。
#
# tests/persistence/common.sh と同じ設計 (production整合性の二重防御、
# grep終了コードを正しく扱うカウンタ、apply_ruleによる件数確認付き置換) を
# 踏襲する。相違点は対象production ファイルが1個 (PROD_SCRIPT) である点のみ。
#
# "." (source) して使う。呼び出し元は REPO_ROOT / PROD_SCRIPT / TESTS_DIR を
# source前に設定しておくこと。
set -eu

: "${REPO_ROOT:?REPO_ROOT must be set before sourcing common.sh}"
: "${PROD_SCRIPT:?PROD_SCRIPT must be set before sourcing common.sh}"
: "${TESTS_DIR:?TESTS_DIR must be set before sourcing common.sh}"

PASS=0
FAIL=0
RESULTS=''
SCENARIO_COUNT=0

# begin_scenario は、シナリオ実行関数 (scenario_result/scenario_bool) の
# 内部からのみ呼ぶ。残存ファイル確認等の付随的なアサーションを、独立した
# シナリオとしてカウントに混ぜたい場合は、それ専用に1回だけ
# scenario_result/scenario_boolを呼ぶこと (assert_count等の内部検査は
# シナリオ数に含めない)。
begin_scenario() {
    SCENARIO_COUNT=$((SCENARIO_COUNT + 1))
}

# scenario_result NAME EXPECTED_EXIT ACTUAL_EXIT
# begin_scenario + log_result をまとめて行う。
scenario_result() {
    begin_scenario
    log_result "$1" "$2" "$3"
}

# scenario_bool NAME 0|1
scenario_bool() {
    begin_scenario
    log_bool "$1" "$2"
}

# check_scenario_totals EXPECTED_SCENARIOS EXPECTED_ASSERTIONS
# シナリオ数・アサーション数 (PASS+FAIL) が期待値と一致するかを検査する。
# 不一致の場合、PASS/FAILへは加算せず、構造検査そのものの失敗として
# 即座に非0 (exit 93) で終了する (テスト内容の追加・削除が期待値の
# 更新を伴わずに行われた場合や、シナリオが途中で異常終了した場合を
# 検知するため)。
check_scenario_totals() {
    expected_scenarios="$1"; expected_assertions="$2"
    actual_assertions=$((PASS + FAIL))
    if [ "$SCENARIO_COUNT" -ne "$expected_scenarios" ]; then
        echo "STRUCTURE CHECK FAILED: SCENARIO_COUNT=$SCENARIO_COUNT, expected=$expected_scenarios" >&2
        exit 93
    fi
    if [ "$actual_assertions" -ne "$expected_assertions" ]; then
        echo "STRUCTURE CHECK FAILED: assertions(PASS+FAIL)=$actual_assertions, expected=$expected_assertions" >&2
        exit 93
    fi
}

log_result() {
    # log_result NAME EXPECTED_EXIT ACTUAL_EXIT
    name="$1"; expected="$2"; actual="$3"
    if [ "$expected" = "$actual" ]; then
        RESULTS="${RESULTS}PASS  $name (exit=$actual)
"
        PASS=$((PASS + 1))
    else
        RESULTS="${RESULTS}FAIL  $name (expected=$expected actual=$actual)
"
        FAIL=$((FAIL + 1))
    fi
}

log_bool() {
    # log_bool NAME 0|1
    name="$1"; ok="$2"
    if [ "$ok" = '1' ]; then
        RESULTS="${RESULTS}PASS  $name
"
        PASS=$((PASS + 1))
    else
        RESULTS="${RESULTS}FAIL  $name
"
        FAIL=$((FAIL + 1))
    fi
}

# ---- grep終了コードを正しく扱うカウンタ (tests/persistence/common.sh と同じ) --
count_matches() {
    # count_matches PATTERN FILE
    pattern="$1"; file="$2"
    n="$(grep -cE -- "$pattern" "$file")" && rc=0 || rc=$?
    case "$rc" in
        0|1) printf '%s' "$n" ;;
        *)
            echo "count_matches: grep ABNORMAL EXIT ($rc) for pattern: $pattern (file: $file)" >&2
            exit 92
            ;;
    esac
}

assert_count() {
    # assert_count LABEL PATTERN FILE EXPECTED
    label="$1"; pattern="$2"; file="$3"; expected="$4"
    actual="$(count_matches "$pattern" "$file")"
    if [ "$actual" -ne "$expected" ]; then
        echo "[$label] REFUSING: matched $actual line(s), expected $expected: $pattern" >&2
        exit 91
    fi
}

count_fixed_matches() {
    # count_fixed_matches STRING FILE
    pattern="$1"; file="$2"
    n="$(grep -cF -- "$pattern" "$file")" && rc=0 || rc=$?
    case "$rc" in
        0|1) printf '%s' "$n" ;;
        *)
            echo "count_fixed_matches: grep ABNORMAL EXIT ($rc) for fixed string: $pattern (file: $file)" >&2
            exit 92
            ;;
    esac
}

assert_fixed_count() {
    # assert_fixed_count LABEL STRING FILE EXPECTED
    label="$1"; pattern="$2"; file="$3"; expected="$4"
    actual="$(count_fixed_matches "$pattern" "$file")"
    if [ "$actual" -ne "$expected" ]; then
        echo "[$label] REFUSING: matched $actual line(s), expected $expected (fixed string): $pattern" >&2
        exit 91
    fi
}

# apply_rule ID PATTERN TOKEN EXPECTED_COUNT FILE
# production由来のリテラルを、正規表現メタ文字を含まない固定トークンへ
# 置換する。sed -i は使わず、常に一時ファイルへ出力してから mv する。
# 件数が一致しない場合は即座に exit 91 (REFUSING)。
apply_rule() {
    id="$1"; pattern="$2"; token="$3"; expected="$4"; file="$5"
    assert_count "$id" "$pattern" "$file" "$expected"
    sed -E "s#${pattern}#${token}#" "$file" > "$file.next"
    mv -- "$file.next" "$file"
}

# resolve_token TOKEN VALUE FILE
# 固定トークンを実行時のsandbox実パスへ解決する。
resolve_token() {
    token="$1"; value="$2"; file="$3"
    sed "s#${token}#${value}#g" "$file" > "$file.next"
    mv -- "$file.next" "$file"
}

# ---- サンドボックス --------------------------------------------------------
SANDBOX=''
# sandbox外拒否自己テスト (test_mocked.sh) が使う使い捨てディレクトリ。
# SANDBOXと同様に、呼び出し元の環境から継承した値を無効化するため、
# ここで必ず空文字列に初期化する (呼び出し元がOUTSIDE_DIRをexportして
# いた場合でも、この初期化により無視される)。
OUTSIDE_DIR=''

create_sandbox() {
    SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/mypocketos-usb-persistence-image-tests.XXXXXXXXXX")"
    mkdir -p \
        "$SANDBOX/bin" \
        "$SANDBOX/work" \
        "$SANDBOX/input"
    # 完全モック (xorriso/mke2fs等、quoted heredocで生成するため書き込み
    # 先パスをsandbox実パスとして焼き込めない) が、実行時に自身の書き込み
    # 対象をsandbox内かどうか検証できるよう、環境変数として公開する。
    export SANDBOX
}

# ---- production整合性の二重防御 (harness自身のEXIT trap) -------------------
PRE_SHA="$(sha256sum "$PROD_SCRIPT")"

on_common_exit() {
    ec=$?
    post_sha="$(sha256sum "$PROD_SCRIPT" 2>/dev/null)" || post_sha=''
    if [ "$post_sha" != "$PRE_SHA" ]; then
        echo 'FATAL: production file changed during test run (harness self-check)' >&2
        ec=95
    fi
    # OUTSIDE_DIR (sandbox外拒否自己テスト用の使い捨てディレクトリ) を
    # 使うテスト (test_mocked.sh) は、通常経路の末尾で削除したうえで
    # OUTSIDE_DIR='' に戻すが、途中終了・シグナル時にも取りこぼさない
    # よう、ここでも削除する。
    #
    # 単に「未定義/空文字列でなく、ディレクトリとして実在する」だけを
    # 条件にすると、呼び出し元の環境から継承した無関係なOUTSIDE_DIR
    # (このテストが作ったものではない、任意の既存ディレクトリ) を
    # 誤ってrm -rfしてしまう危険がある。OUTSIDE_DIRはファイル冒頭で
    # 常に空文字列へ初期化しているため、この時点で非空なら「この実行の
    # どこかでOUTSIDE_DIRへ代入された値」のはずだが、念のため値の形
    # 自体でも自分自身が作ったパスであることを確認する: SANDBOX自身の
    # 兄弟パスとして "$SANDBOX.outside.*" というmktempテンプレートで
    # 作られたパスにのみ一致する場合だけ削除する (test_mocked.shの
    # OUTSIDE_DIR作成規約に合わせている)。SANDBOXが空の場合や、
    # OUTSIDE_DIRがこのパターンに一致しない場合は、何が渡されていても
    # 絶対に削除しない。
    case "${OUTSIDE_DIR:-}" in
        "$SANDBOX".outside.*)
            if [ -n "$SANDBOX" ] && [ -d "$OUTSIDE_DIR" ]; then
                rm -rf -- "$OUTSIDE_DIR"
            fi
            ;;
    esac
    if [ -n "$SANDBOX" ] && [ -d "$SANDBOX" ]; then
        rm -rf -- "$SANDBOX"
    fi
    exit "$ec"
}
