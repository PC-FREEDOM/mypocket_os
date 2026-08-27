#!/bin/sh
# tests/persistence/common.sh
#
# 非破壊モックテストハーネスの共通ユーティリティ。production ファイル
# (mypocketos-persistence-setup / mypocketos-persistence-setup-helper) には
# 一切書き込まない。作業領域はすべて mktemp -d でリポジトリ外に作成し、
# 呼び出し元スクリプトの EXIT trap で必ず削除する。
#
# このファイルは test_gui.sh / test_helper.sh / run.sh から ". " (source)
# して使う。"." はシェルの $0 を変更しないため (sourceしても、その時点の
# $0 は呼び出し元スクリプト自身の値のまま)、パス解決をこのファイル自身の
# $0 に依存させない。REPO_ROOT / PROD_GUI / PROD_HELPER / TESTS_DIR は
# 呼び出し元が source する前に必ず設定しておくこと。
set -eu

: "${REPO_ROOT:?REPO_ROOT must be set before sourcing common.sh}"
: "${PROD_GUI:?PROD_GUI must be set before sourcing common.sh}"
: "${PROD_HELPER:?PROD_HELPER must be set before sourcing common.sh}"
: "${TESTS_DIR:?TESTS_DIR must be set before sourcing common.sh}"

PASS=0
FAIL=0
RESULTS=''

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

# ---- grep終了コードを正しく扱うカウンタ -------------------------------------
# grep -c: 0=1件以上一致、1=0件一致(正常)、2以上=grep自体の異常。
# "|| actual=0" のように一律で握り潰さない。set -e 下でも安全に動くよう、
# "&&"/"||" で直接 rc を捕捉する (バラの代入文が失敗すると set -e が
# rc=$? へ到達する前にスクリプトを終了させてしまうため)。
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

# count_fixed_matches STRING FILE
# count_matches の固定文字列 (grep -F) 版。TOKEN文字列は "@@SANDBOX_DEV@@/*"
# のように "*" 等の正規表現メタ文字を含みうるため、置換後にTOKEN自体の
# 出現件数を確認する場合は正規表現ではなく固定文字列一致を使う。grep -c の
# 終了コード (0=1件以上一致、1=0件一致、2以上=grep自体の異常) の扱いは
# count_matches と同様に区別する。
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
# 置換する (段階1)。sed -i は使わず、常に一時ファイルへ出力してから
# mv する。件数が一致しない場合は即座に exit 91 (REFUSING)。
apply_rule() {
    id="$1"; pattern="$2"; token="$3"; expected="$4"; file="$5"
    assert_count "$id" "$pattern" "$file" "$expected"
    # 区切り文字には "#" を使う (トークン自体が "@@NAME@@" の形式で "@" を
    # 含むため、"@" を区切り文字にするとトークンを置換文字列側で使う際に
    # 誤って区切りとして解釈されてしまう。パターン・トークン・sandboxパスの
    # いずれも "#" を含まない前提)。
    sed -E "s#${pattern}#${token}#" "$file" > "$file.next"
    mv -- "$file.next" "$file"
}

# apply_rule_next_line ID ANCHOR_PATTERN ANCHOR_EXPECTED SUB_PATTERN TOKEN FILE
# あるリテラル (例: "/dev/*) ;;") がファイル内で複数箇所に同一テキストで
# 出現し、単純な文字列一致では一意に特定できない場合に使う。まず
# ANCHOR_PATTERN (直前の一意な行、例: case "$device" in) がちょうど
# ANCHOR_EXPECTED 件であることを確認し、その行の "次の行" だけに対して
# SUB_PATTERN -> TOKEN の置換を sed の "n;s" イディオムで適用する。
#
# アンカー件数の確認だけでは、"n;s" が対象行にマッチせず何も置換しない
# まま静かに成功してしまう欠陥を検出できない。そのため、置換の前後で
# TOKEN (固定文字列、count_fixed_matches) の出現件数を数え、置換後に
# ちょうど1件増えていることを確認する。TOKENは "*" 等の正規表現メタ文字を
# 含みうるため、この確認には grep -F を使う count_fixed_matches を用いる。
apply_rule_next_line() {
    id="$1"; anchor="$2"; anchor_expected="$3"; sub_pattern="$4"; token="$5"; file="$6"
    assert_count "$id (anchor)" "$anchor" "$file" "$anchor_expected"
    before="$(count_fixed_matches "$token" "$file")"
    sed -E "/${anchor}/{n;s#${sub_pattern}#${token}#}" "$file" > "$file.next"
    mv -- "$file.next" "$file"
    expected_after=$((before + 1))
    assert_fixed_count "$id (token after substitution)" "$token" "$file" "$expected_after"
}

# resolve_token TOKEN VALUE FILE
# 段階2: 固定トークンを実行時のsandbox実パスへ解決する。VALUE は
# mktemp -d が生成する英数字主体のパスを想定しており、sedの置換文字列に
# とって特別な意味を持つ "&"・"\"・区切り文字 "#" を含まない前提とする。
resolve_token() {
    token="$1"; value="$2"; file="$3"
    sed "s#${token}#${value}#g" "$file" > "$file.next"
    mv -- "$file.next" "$file"
}

# escape_ere STRING
# 文字列を、grep -E / sed -E のパターン中で「リテラル」として安全に
# 埋め込めるようにEREメタ文字をエスケープして出力する。mktempが生成する
# サンドボックスパス (英数字・"."・"/" 主体) をパターン側へ埋め込む際に使う
# (置換文字列側で使う場合は resolve_token のとおりエスケープ不要)。
escape_ere() {
    printf '%s' "$1" | sed -e 's/[][\.^$*+?(){}|]/\\&/g'
}

# ---- サンドボックス --------------------------------------------------------
SANDBOX=''

create_sandbox() {
    SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/mypocketos-persistence-tests.XXXXXXXXXX")"
    mkdir -p \
        "$SANDBOX/bin" \
        "$SANDBOX/dev" \
        "$SANDBOX/sys/block" \
        "$SANDBOX/sys/class/block" \
        "$SANDBOX/proc" \
        "$SANDBOX/run/lock" \
        "$SANDBOX/xdg-runtime" \
        "$SANDBOX/work"
}

# ---- production整合性の二重防御 (harness自身のEXIT trap) -------------------
PRE_SHA="$(sha256sum "$PROD_GUI" "$PROD_HELPER")"

on_common_exit() {
    ec=$?
    post_sha="$(sha256sum "$PROD_GUI" "$PROD_HELPER" 2>/dev/null)" || post_sha=''
    if [ "$post_sha" != "$PRE_SHA" ]; then
        echo 'FATAL: production files changed during test run (harness self-check)' >&2
        ec=95
    fi
    if [ -n "$SANDBOX" ] && [ -d "$SANDBOX" ]; then
        rm -rf -- "$SANDBOX"
    fi
    exit "$ec"
}
