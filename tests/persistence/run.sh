#!/bin/sh
# tests/persistence/run.sh
#
# 非破壊モックテストハーネスの単一エントリポイント。GUI本体・helperの
# テストスイートを順に実行し、両方の結果を集約する。production ファイルへ
# の書き込み、実sudo・実helper・実parted・実mkfs・実mount・実umount・
# VM/ISO/qcow2操作はいずれも行わない。
#
# 使い方: tests/persistence/run.sh
set -eu

TESTS_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$TESTS_DIR/../.." && pwd)"
PROD_GUI="$REPO_ROOT/config/includes.chroot/usr/local/bin/mypocketos-persistence-setup"
PROD_HELPER="$REPO_ROOT/config/includes.chroot/usr/local/libexec/mypocketos-persistence-setup-helper"

PRE_SHA_RUN="$(sha256sum "$PROD_GUI" "$PROD_HELPER")"

overall_rc=0

echo "############################################"
echo "# GUI test suite"
echo "############################################"
sh "$TESTS_DIR/test_gui.sh" && gui_rc=0 || gui_rc=$?
if [ "$gui_rc" -ne 0 ]; then
    overall_rc=1
fi

echo
echo "############################################"
echo "# helper test suite"
echo "############################################"
sh "$TESTS_DIR/test_helper.sh" && helper_rc=0 || helper_rc=$?
if [ "$helper_rc" -ne 0 ]; then
    overall_rc=1
fi

echo
echo "############################################"
echo "# helper failure-matrix test suite"
echo "############################################"
sh "$TESTS_DIR/test_helper_failure_matrix.sh" && matrix_rc=0 || matrix_rc=$?
if [ "$matrix_rc" -ne 0 ]; then
    overall_rc=1
fi

echo
echo "############################################"
echo "# production integrity (post-run)"
echo "############################################"
POST_SHA_RUN="$(sha256sum "$PROD_GUI" "$PROD_HELPER")"
if [ "$POST_SHA_RUN" != "$PRE_SHA_RUN" ]; then
    echo 'FATAL: production files changed during the full test run' >&2
    overall_rc=1
else
    echo 'production GUI/helper SHA-256: unchanged'
fi

echo
echo "GUI suite exit=$gui_rc / helper suite exit=$helper_rc / failure-matrix suite exit=$matrix_rc / overall=$overall_rc"
exit "$overall_rc"
