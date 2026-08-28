#!/bin/sh
# tests/usb-persistence-image/instrument_script.sh
#
# instrument_script SANDBOX_BIN OUT_FILE
#
# production スクリプト (scripts/build-usb-persistence-image.sh) のコピーを
# OUT_FILE へ生成し、CMD_* の絶対パス定義だけを SANDBOX_BIN 配下のモックへ
# 差し替える。tests/persistence/instrument_helper.sh と同じ2段階方式
# (apply_rule で固定トークンへ、resolve_token でsandbox実パスへ) を使う。
#
# production ファイル自体は一切変更しない (sed -i不使用、常にコピー先へ
# 新規出力するだけ)。
#
# CMD_* は現在20個 (CMD_MVは最終公開をhard link方式へ変更したため
# production側で不使用・未定義。CMD_LN/CMD_CAT/CMD_DIFF/CMD_DFが新規)。
set -eu

TESTS_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=tests/usb-persistence-image/common.sh
. "$TESTS_DIR/common.sh"

instrument_script() {
    sandbox_bin="$1"; out_file="$2"

    cp -- "$PROD_SCRIPT" "$out_file"

    # ---- 段階1: CMD_* の絶対パス定義を固定トークンへ置換 -------------------
    apply_rule 'CMD_XORRISO'  '^CMD_XORRISO=/usr/bin/xorriso$'   'CMD_XORRISO=@@SANDBOX_BIN@@/xorriso'   1 "$out_file"
    apply_rule 'CMD_MKE2FS'   '^CMD_MKE2FS=/usr/sbin/mke2fs$'    'CMD_MKE2FS=@@SANDBOX_BIN@@/mke2fs'     1 "$out_file"
    apply_rule 'CMD_E2FSCK'   '^CMD_E2FSCK=/usr/sbin/e2fsck$'    'CMD_E2FSCK=@@SANDBOX_BIN@@/e2fsck'     1 "$out_file"
    apply_rule 'CMD_DEBUGFS'  '^CMD_DEBUGFS=/usr/sbin/debugfs$'  'CMD_DEBUGFS=@@SANDBOX_BIN@@/debugfs'   1 "$out_file"
    apply_rule 'CMD_SHA256SUM' '^CMD_SHA256SUM=/usr/bin/sha256sum$' 'CMD_SHA256SUM=@@SANDBOX_BIN@@/sha256sum' 1 "$out_file"
    apply_rule 'CMD_STAT'     '^CMD_STAT=/usr/bin/stat$'         'CMD_STAT=@@SANDBOX_BIN@@/stat'         1 "$out_file"
    apply_rule 'CMD_DD'       '^CMD_DD=/usr/bin/dd$'             'CMD_DD=@@SANDBOX_BIN@@/dd'             1 "$out_file"
    apply_rule 'CMD_CMP'      '^CMD_CMP=/usr/bin/cmp$'           'CMD_CMP=@@SANDBOX_BIN@@/cmp'           1 "$out_file"
    apply_rule 'CMD_DIFF'     '^CMD_DIFF=/usr/bin/diff$'         'CMD_DIFF=@@SANDBOX_BIN@@/diff'         1 "$out_file"
    apply_rule 'CMD_MKTEMP'   '^CMD_MKTEMP=/usr/bin/mktemp$'     'CMD_MKTEMP=@@SANDBOX_BIN@@/mktemp'     1 "$out_file"
    apply_rule 'CMD_MKDIR'    '^CMD_MKDIR=/usr/bin/mkdir$'       'CMD_MKDIR=@@SANDBOX_BIN@@/mkdir'       1 "$out_file"
    apply_rule 'CMD_RM'       '^CMD_RM=/usr/bin/rm$'             'CMD_RM=@@SANDBOX_BIN@@/rm'             1 "$out_file"
    apply_rule 'CMD_LN'       '^CMD_LN=/usr/bin/ln$'             'CMD_LN=@@SANDBOX_BIN@@/ln'             1 "$out_file"
    apply_rule 'CMD_CAT'      '^CMD_CAT=/usr/bin/cat$'           'CMD_CAT=@@SANDBOX_BIN@@/cat'           1 "$out_file"
    apply_rule 'CMD_DF'       '^CMD_DF=/usr/bin/df$'             'CMD_DF=@@SANDBOX_BIN@@/df'             1 "$out_file"
    apply_rule 'CMD_GREP'     '^CMD_GREP=/usr/bin/grep$'         'CMD_GREP=@@SANDBOX_BIN@@/grep'         1 "$out_file"
    apply_rule 'CMD_SED'      '^CMD_SED=/usr/bin/sed$'           'CMD_SED=@@SANDBOX_BIN@@/sed'           1 "$out_file"
    apply_rule 'CMD_AWK'      '^CMD_AWK=/usr/bin/awk$'           'CMD_AWK=@@SANDBOX_BIN@@/awk'           1 "$out_file"
    apply_rule 'CMD_REALPATH' '^CMD_REALPATH=/usr/bin/realpath$' 'CMD_REALPATH=@@SANDBOX_BIN@@/realpath' 1 "$out_file"
    apply_rule 'CMD_DIRNAME'  '^CMD_DIRNAME=/usr/bin/dirname$'   'CMD_DIRNAME=@@SANDBOX_BIN@@/dirname'   1 "$out_file"

    # ---- 段階2: 固定トークンをsandbox実パスへ解決 ---------------------------
    resolve_token '@@SANDBOX_BIN@@' "$sandbox_bin" "$out_file"

    # ---- 不変条件の検証 (いずれか1つでも満たさなければ失敗) ----------------
    assert_count 'no unresolved tokens' '@@[A-Z_]+@@' "$out_file" 0

    cmd_var_count="$(count_matches '^CMD_[A-Z0-9_]+=' "$out_file")"
    [ "$cmd_var_count" -eq 20 ] || {
        echo "instrument_script: unexpected CMD_* definition count: $cmd_var_count (expected 20)" >&2
        exit 91
    }

    remaining_abs="$(count_matches "^CMD_[A-Z0-9_]+=/usr" "$out_file")"
    [ "$remaining_abs" -eq 0 ] || {
        echo "instrument_script: found CMD_* definitions still pointing at /usr: $remaining_abs" >&2
        exit 91
    }

    # instrumented productionが作るWORKROOT (mktempのtemplate引数) は
    # 常にOUTPUT_DIRNAME_ABS配下になる設計であり、テストではOUTPUT_ABS
    # 自体をsandbox内のパスとして与えるため、WORKROOTも構造的にsandbox
    # 内になる。ここではmktemp呼び出し自体がsandbox外のtemplateを拒否する
    # モック (mock_command.sh) 側の自己検証で担保する。

    chmod 755 "$out_file"
}
