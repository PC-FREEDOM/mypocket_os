#!/bin/sh
# tests/usb-persistence-image/run.sh
#
# build-usb-persistence-image.sh 向け非破壊モックテストハーネスの単一
# エントリポイント。直接実行スイート・モックスイートを順に実行し、両方の
# 結果を集約する。production ファイルへの書き込み、実xorriso・実mke2fs・
# 実e2fsck・実debugfs・sudo・loop・mount・USB/block device操作はいずれも
# 行わない。
#
# 使い方: tests/usb-persistence-image/run.sh
set -eu

TESTS_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$TESTS_DIR/../.." && pwd)"
PROD_SCRIPT="$REPO_ROOT/scripts/build-usb-persistence-image.sh"

PRE_SHA_RUN="$(sha256sum "$PROD_SCRIPT")"

overall_rc=0

echo "############################################"
echo "# direct test suite (引数・パス・サイズ検証)"
echo "############################################"
sh "$TESTS_DIR/test_direct.sh" && direct_rc=0 || direct_rc=$?
if [ "$direct_rc" -ne 0 ]; then
    overall_rc=1
fi

echo
echo "############################################"
echo "# mocked test suite (xorriso/mke2fs/e2fsck/debugfs)"
echo "############################################"
sh "$TESTS_DIR/test_mocked.sh" && mocked_rc=0 || mocked_rc=$?
if [ "$mocked_rc" -ne 0 ]; then
    overall_rc=1
fi

echo
echo "############################################"
echo "# production integrity (post-run)"
echo "############################################"
POST_SHA_RUN="$(sha256sum "$PROD_SCRIPT")"
if [ "$POST_SHA_RUN" != "$PRE_SHA_RUN" ]; then
    echo 'FATAL: production file changed during the full test run' >&2
    overall_rc=1
else
    echo 'production build-usb-persistence-image.sh SHA-256: unchanged'
fi

echo
echo "direct suite exit=$direct_rc / mocked suite exit=$mocked_rc / overall=$overall_rc"
exit "$overall_rc"
