#!/bin/sh
# tests/usb-persistence-image/test_direct.sh
#
# build-usb-persistence-image.sh の引数検証・パス検証・サイズ検証 (xorriso/
# mke2fs等を一切呼び出さない段階) を、production スクリプト本体を一切
# 改変せず直接実行して検証する。この段階はstat/realpath/grep等の軽量な
# 読み取り専用判定のみで完結するため、instrument/mockは不要かつ不適切
# (実コードをそのまま検証できる利点を活かす)。
#
# **実xorriso・実mke2fs・実e2fsck・実debugfsによるIMG生成は一切行わない**
# (このスイートの全シナリオは、check_required_commands直後〜
# --persistence-size検証までの間に必ずexitする)。最小値境界を通過した後の
# 挙動確認はtest_mocked.sh (instrumented+モック環境) 側で行う。
#
set -eu

TESTS_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$TESTS_DIR/../.." && pwd)"
PROD_SCRIPT="$REPO_ROOT/scripts/build-usb-persistence-image.sh"

# shellcheck source=tests/usb-persistence-image/common.sh
. "$TESTS_DIR/common.sh"
trap on_common_exit EXIT

create_sandbox

# ---- フィクスチャ準備 --------------------------------------------------------
FAKE_ISO="$SANDBOX/input/fake.iso"
head -c 1000000 /dev/zero > "$FAKE_ISO"

FAKE_BINARY_DIR="$SANDBOX/input/binary"
mkdir -p "$FAKE_BINARY_DIR/isolinux" "$FAKE_BINARY_DIR/boot/grub" "$FAKE_BINARY_DIR/live"
printf 'dummy-isolinux-bin' > "$FAKE_BINARY_DIR/isolinux/isolinux.bin"
printf 'dummy-efi-img' > "$FAKE_BINARY_DIR/boot/grub/efi.img"
printf 'dummy-squashfs' > "$FAKE_BINARY_DIR/live/filesystem.squashfs"

OUT_DIR="$SANDBOX/work/out"
mkdir -p "$OUT_DIR"

run_prod() {
    # run_prod ARGS... の後、EXIT_CODE にproduction scriptの終了コードを
    # 格納する。set -e下でも安全に捕捉する。
    ( "$PROD_SCRIPT" "$@" >"$SANDBOX/work/stdout" 2>"$SANDBOX/work/stderr" ) && EXIT_CODE=0 || EXIT_CODE=$?
}

# ---- シナリオ1: 引数なし (exit 2) -------------------------------------------
run_prod
scenario_result 'no-args' 2 "$EXIT_CODE"

# ---- シナリオ2: 未知フラグ (exit 2) -----------------------------------------
run_prod --bogus foo
scenario_result 'unknown-flag' 2 "$EXIT_CODE"

# ---- シナリオ3: 重複指定 (exit 2) -------------------------------------------
run_prod --iso "$FAKE_ISO" --iso "$FAKE_ISO" --binary-dir "$FAKE_BINARY_DIR" \
    --persistence-size 256M --output "$OUT_DIR/o1.img"
scenario_result 'duplicate-flag' 2 "$EXIT_CODE"

# ---- シナリオ4: --iso が存在しない (exit 11) --------------------------------
run_prod --iso "$SANDBOX/input/nonexistent.iso" --binary-dir "$FAKE_BINARY_DIR" \
    --persistence-size 256M --output "$OUT_DIR/o2.img"
scenario_result 'iso-missing' 11 "$EXIT_CODE"

# ---- シナリオ5: --iso がディレクトリ (exit 11) ------------------------------
run_prod --iso "$FAKE_BINARY_DIR" --binary-dir "$FAKE_BINARY_DIR" \
    --persistence-size 256M --output "$OUT_DIR/o3.img"
scenario_result 'iso-is-directory' 11 "$EXIT_CODE"

# ---- シナリオ6: --iso がsymlink (exit 11) -----------------------------------
ln -s "$FAKE_ISO" "$SANDBOX/input/iso_symlink.iso"
run_prod --iso "$SANDBOX/input/iso_symlink.iso" --binary-dir "$FAKE_BINARY_DIR" \
    --persistence-size 256M --output "$OUT_DIR/o4.img"
scenario_result 'iso-is-symlink' 11 "$EXIT_CODE"

# ---- シナリオ7: --binary-dir が存在しない (exit 12) -------------------------
run_prod --iso "$FAKE_ISO" --binary-dir "$SANDBOX/input/nonexistent-binary" \
    --persistence-size 256M --output "$OUT_DIR/o5.img"
scenario_result 'binary-dir-missing' 12 "$EXIT_CODE"

# ---- シナリオ8: --binary-dir がsymlink (exit 12) ----------------------------
ln -s "$FAKE_BINARY_DIR" "$SANDBOX/input/binary_symlink"
run_prod --iso "$FAKE_ISO" --binary-dir "$SANDBOX/input/binary_symlink" \
    --persistence-size 256M --output "$OUT_DIR/o6.img"
scenario_result 'binary-dir-is-symlink' 12 "$EXIT_CODE"

# ---- シナリオ9〜11: 必須3ファイルの欠落 (各exit 12) -------------------------
for missing in isolinux/isolinux.bin boot/grub/efi.img live/filesystem.squashfs; do
    tmp_binary_dir="$SANDBOX/input/binary-missing-$(echo "$missing" | tr '/' '-')"
    mkdir -p "$tmp_binary_dir/isolinux" "$tmp_binary_dir/boot/grub" "$tmp_binary_dir/live"
    printf 'dummy' > "$tmp_binary_dir/isolinux/isolinux.bin"
    printf 'dummy' > "$tmp_binary_dir/boot/grub/efi.img"
    printf 'dummy' > "$tmp_binary_dir/live/filesystem.squashfs"
    rm -f "$tmp_binary_dir/$missing"
    run_prod --iso "$FAKE_ISO" --binary-dir "$tmp_binary_dir" \
        --persistence-size 256M --output "$OUT_DIR/o-missing-$(echo "$missing" | tr '/' '-').img"
    scenario_result "binary-dir-missing-file:$missing" 12 "$EXIT_CODE"
done

# ---- シナリオ12: --output が既に存在 (通常ファイル、exit 13) ---------------
printf 'existing' > "$OUT_DIR/already-exists.img"
run_prod --iso "$FAKE_ISO" --binary-dir "$FAKE_BINARY_DIR" \
    --persistence-size 256M --output "$OUT_DIR/already-exists.img"
scenario_result 'output-already-exists' 13 "$EXIT_CODE"

# ---- シナリオ13: --output が既にsymlink (exit 13) ---------------------------
ln -s "$FAKE_ISO" "$OUT_DIR/already-exists-symlink.img"
run_prod --iso "$FAKE_ISO" --binary-dir "$FAKE_BINARY_DIR" \
    --persistence-size 256M --output "$OUT_DIR/already-exists-symlink.img"
scenario_result 'output-already-exists-symlink' 13 "$EXIT_CODE"

# ---- シナリオ14: --output の親ディレクトリが存在しない (exit 14) ----------
run_prod --iso "$FAKE_ISO" --binary-dir "$FAKE_BINARY_DIR" \
    --persistence-size 256M --output "$OUT_DIR/nonexistent-parent/o.img"
scenario_result 'output-parent-missing' 14 "$EXIT_CODE"

# ---- シナリオ15: --iso と --output が同一パス ------------------------------
# --output は「既存パスなら拒否」(exit 13) を同一性検査 (exit 15) より先に
# 判定するため、--iso (既存の通常ファイル) をそのまま --output に指定した
# 場合は必ずexit 13が先に出る (同一性検査exit 15へは構造的に到達しない、
# --iso=通常ファイル必須・--output=非存在必須という互いに排他的な制約から
# 導かれる)。この優先順位そのものを検証する。
run_prod --iso "$FAKE_ISO" --binary-dir "$FAKE_BINARY_DIR" \
    --persistence-size 256M --output "$FAKE_ISO"
scenario_result 'iso-equals-output-hits-exists-check-first' 13 "$EXIT_CODE"

# ---- シナリオ16: --binary-dir と --output が同一パス ------------------------
# 同様に、既存ディレクトリを --output に指定した場合もexit 13が先に出る。
run_prod --iso "$FAKE_ISO" --binary-dir "$FAKE_BINARY_DIR" \
    --persistence-size 256M --output "$FAKE_BINARY_DIR"
scenario_result 'binary-dir-equals-output-hits-exists-check-first' 13 "$EXIT_CODE"

# ---- シナリオ17: --output が --binary-dir の内側 (exit 15) -----------------
# こちらは --output 自体は非存在パスなので exit 13 では捕捉されず、
# 同一性検査 (exit 15) が実際に機能することを確認できる。
run_prod --iso "$FAKE_ISO" --binary-dir "$FAKE_BINARY_DIR" \
    --persistence-size 256M --output "$FAKE_BINARY_DIR/isolinux/sneaky.img"
scenario_result 'output-inside-binary-dir' 15 "$EXIT_CODE"

# ---- シナリオ18: --iso と --binary-dir が同一パス ---------------------------
# --iso は通常ファイル必須・--binary-dir はディレクトリ必須という互いに
# 排他的な型制約により、同一パスを指定した場合は --iso 側の型検査
# (exit 11、「通常ファイルではありません」) が先に出る。
run_prod --iso "$FAKE_BINARY_DIR" --binary-dir "$FAKE_BINARY_DIR" \
    --persistence-size 256M --output "$OUT_DIR/o7.img"
scenario_result 'iso-equals-binary-dir-hits-type-check-first' 11 "$EXIT_CODE"

# ---- シナリオ19: --persistence-size 形式不正 (各exit 16) -------------------
# 空文字列は「値なし」(exit 2、usage) と区別できないため、別シナリオとして
# 明示的にexit 2を期待する (このループの対象外とする)。
for bad_size in 256 256K 0M 256m 256MB 1.5G '-256M' '256 M'; do
    run_prod --iso "$FAKE_ISO" --binary-dir "$FAKE_BINARY_DIR" \
        --persistence-size "$bad_size" --output "$OUT_DIR/o-badsize-$(echo "$bad_size" | tr -c 'A-Za-z0-9' '_').img"
    scenario_result "bad-size-format:[$bad_size]" 16 "$EXIT_CODE"
done

run_prod --iso "$FAKE_ISO" --binary-dir "$FAKE_BINARY_DIR" \
    --persistence-size '' --output "$OUT_DIR/o-badsize-empty.img"
scenario_result 'size-empty-string-treated-as-missing' 2 "$EXIT_CODE"

# ---- シナリオ: --persistence-size が最小値未満 (exit 17) -------------------
run_prod --iso "$FAKE_ISO" --binary-dir "$FAKE_BINARY_DIR" \
    --persistence-size 255M --output "$OUT_DIR/o8.img"
scenario_result 'size-below-minimum' 17 "$EXIT_CODE"

# ---- シナリオ: 合計サイズ上限超過 (exit 18) ---------------------------------
# --persistence-size単体 (7630M = 8,000,532,480 bytes) だけで既に上限
# 8,000,000,000 bytesを超えるようにし、FAKE_ISOの実サイズに依存せず
# 確実にこのシナリオを再現する。
run_prod --iso "$FAKE_ISO" --binary-dir "$FAKE_BINARY_DIR" \
    --persistence-size 7630M --output "$OUT_DIR/o9.img"
scenario_result 'total-size-cap-exceeded' 18 "$EXIT_CODE"

# 最小値ちょうど (256M) が早期検証を通過した後の挙動 (空き容量検査以降、
# xorriso/mke2fs等の実コマンドを伴う段階) は、このスイートの対象外とする
# (test_mocked.sh のinstrumented+モック環境で検証する)。

# ---- 結果表示 (構造検査より先に表示し、失敗時も内訳を確認できるようにする) --
printf '%s' "$RESULTS"
echo "SCENARIOS=$SCENARIO_COUNT PASS=$PASS FAIL=$FAIL"

# ---- 構造検査: シナリオ数・アサーション数の期待値一致 -----------------------
check_scenario_totals 29 29

[ "$FAIL" -eq 0 ]
