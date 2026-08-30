#!/usr/bin/env bash
#
# rebuild-fluent-yellow-subset.sh - MyPocketOS-Fluent-yellow アーカイブの再生成
#
# 固定されたupstream tarball (vinceliuice/Fluent-icon-theme, タグ
# 2026-07-27, コミット c70c2441bcf2ab8bbc267e55635c76d69f659a8b) だけを
# 入力として受け付け、MyPocketOS向けFluent派生サブセット
# (テーマ名 MyPocketOS-Fluent-yellow) を単一の再現可能なtar.gzとして
# 生成し、config/includes.chroot/usr/share/mypocketos/icon-themes/ へ
# 出力する。
#
# 使い方:
#   ./scripts/rebuild-fluent-yellow-subset.sh /path/to/fluent-icon-theme-2026-07-27.tar.gz
#
# 設計方針:
# - このスクリプト自身はネットワーク接続を一切行わない。curl/wget/
#   git clone/gh api等は使用しない。
# - 入力は指定タグのtarball1つのみ。SHA-256が一致しない場合は処理を
#   中断する (このtarball以外を入力として受け付けない)。
# - upstreamのinstall.sh (tarball内に同梱) はローカルで実行するが、
#   install.sh自体もネットワークアクセスを行わないことを事前に
#   ソース確認済みである (MyPocketOSリポジトリREADME.md参照)。
# - 作業はすべてmktemp -dで作成した一時ディレクトリ内で完結させ、
#   終了時 (成功・失敗いずれも) にtrapで必ず削除する。
# - 出力先が既に存在する場合は上書きしない (手動削除を促す)。
# - Fluent本体 (SVG本体) は改変しない。削除 (不要ディレクトリ・不正
#   ファイル名3件) とindex.thameの書き換えのみを行う。
#
# 終了コード:
#   0   成功
#   2   引数エラー
#   10  必要なコマンドが見つからない
#   11  入力tarballが存在しない、または通常ファイルでない
#   12  入力tarballのSHA-256が不一致
#   13  出力先アーカイブが既に存在する (上書きしない)
#   14  tarball展開に失敗、またはtarball内の構造が想定と異なる
#   15  install.shの実行に失敗
#   16  install.sh実行後に想定するFluent-yellowディレクトリが見つからない
#   17  シンボリックリンクの自己完結化 (実体化) に失敗
#   18  生成したMyPocketOS-Fluent-yellowの検証に失敗
#   19  最終tar.gzの生成に失敗
#
set -euo pipefail

readonly EXPECTED_INPUT_SHA256="7fdd60faa543b297ef2d4f3d083d8b382e59a9b0933cbb1dfc042539d45036e2"
readonly UPSTREAM_PROJECT="Fluent Icon Theme"
readonly UPSTREAM_URL="https://github.com/vinceliuice/Fluent-icon-theme"
readonly UPSTREAM_TAG="2026-07-27"
readonly UPSTREAM_COMMIT="c70c2441bcf2ab8bbc267e55635c76d69f659a8b"
readonly THEME_NAME="MyPocketOS-Fluent-yellow"
# 再現可能なtar.gz生成のための固定mtime (このサブセットの生成日)。
# 入力tarballを再取得しても、この値を変えない限り出力は同一SHA-256になる。
readonly ARCHIVE_MTIME="2026-08-29 00:00:00 UTC"
# 削除するupstream生成ディレクトリ (固定サイズ・HiDPI・アイコンキャッシュ)。
readonly -a PRUNE_DIRS=(
	16 16@2x 16@3x
	22 22@2x 22@3x
	24 24@2x 24@3x
	32 32@2x 32@3x
	256 256@2x 256@3x
	scalable@2x scalable@3x
)
# ファイル名が不正なため除外するファイル (upstream生成結果に存在するが、
# 拡張子欠落・破損しているためアイコン名として解決されない)。
readonly -a EXCLUDE_FILES=(
	"scalable/apps/cinnamon-virtual-keyboard"
	"scalable/apps/org.gnome.Weather.Application.svg}"
	"scalable/apps/page.kramo.Cartridges"
)

die() {
	echo "ERROR: $*" >&2
	exit "${2:-20}"
}

log() {
	echo "==> $*"
}

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly REPO_ROOT
readonly OUTPUT_DIR="${REPO_ROOT}/config/includes.chroot/usr/share/mypocketos/icon-themes"
readonly OUTPUT_ARCHIVE="${OUTPUT_DIR}/${THEME_NAME}.tar.gz"

#==========================
# 1. 引数確認
#==========================
if [ "$#" -ne 1 ]; then
	echo "Usage: $0 /path/to/fluent-icon-theme-${UPSTREAM_TAG}.tar.gz" >&2
	exit 2
fi
readonly INPUT_TARBALL="$1"

#==========================
# 必要なコマンドの確認
#==========================
for cmd in sha256sum tar gzip cp find sed mktemp; do
	command -v "${cmd}" >/dev/null 2>&1 || die "required command not found: ${cmd}" 10
done

#==========================
# 2. 入力tarball存在確認
#==========================
[ -f "${INPUT_TARBALL}" ] || die "input tarball not found or not a regular file: ${INPUT_TARBALL}" 11

#==========================
# 3. SHA-256確認
#==========================
log "Verifying input tarball SHA-256..."
actual_sha256="$(sha256sum "${INPUT_TARBALL}" | awk '{print $1}')"
if [ "${actual_sha256}" != "${EXPECTED_INPUT_SHA256}" ]; then
	die "input tarball SHA-256 mismatch (this script accepts only the pinned ${UPSTREAM_TAG} tarball).
  expected: ${EXPECTED_INPUT_SHA256}
  actual:   ${actual_sha256}" 12
fi
log "SHA-256 OK: ${actual_sha256}"

#==========================
# 出力先の事前確認 (上書きしない)
#==========================
if [ -e "${OUTPUT_ARCHIVE}" ]; then
	die "output archive already exists, refusing to overwrite: ${OUTPUT_ARCHIVE}
  (regenerate intentionally by removing it first)" 13
fi

#==========================
# 4. 一時ディレクトリ作成
#==========================
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mypocketos-fluent-rebuild.XXXXXXXXXX")"
readonly WORK_DIR
cleanup() {
	rm -rf --one-file-system "${WORK_DIR}"
}
trap cleanup EXIT

readonly EXTRACT_DIR="${WORK_DIR}/src"
readonly INSTALL_OUT_DIR="${WORK_DIR}/out"
readonly STAGE_DIR="${WORK_DIR}/stage"
mkdir -p "${EXTRACT_DIR}" "${INSTALL_OUT_DIR}" "${STAGE_DIR}"

#==========================
# 5. tarball展開
#==========================
log "Extracting input tarball..."
tar -xzf "${INPUT_TARBALL}" -C "${EXTRACT_DIR}" --strip-components=1 ||
	die "failed to extract input tarball" 14

[ -x "${EXTRACT_DIR}/install.sh" ] || [ -f "${EXTRACT_DIR}/install.sh" ] ||
	die "install.sh not found in extracted tarball (unexpected upstream structure)" 14
[ -f "${EXTRACT_DIR}/COPYING" ] ||
	die "COPYING not found in extracted tarball (unexpected upstream structure)" 14

#==========================
# 6-7. install.shをローカルで実行し、Fluent-yellow標準明度を生成
#==========================
log "Running upstream install.sh (offline, yellow color only)..."
(
	cd "${EXTRACT_DIR}"
	bash install.sh -d "${INSTALL_OUT_DIR}" yellow
) || die "install.sh failed" 15

[ -d "${INSTALL_OUT_DIR}/Fluent-yellow" ] ||
	die "expected directory not found after install.sh: ${INSTALL_OUT_DIR}/Fluent-yellow" 16

#==========================
# 8. シンボリックリンクを自己完結化 (実体化)
#==========================
log "Dereferencing symlinks (self-containing the standard-brightness variant)..."
cp --dereference --recursive --preserve=mode --no-target-directory \
	"${INSTALL_OUT_DIR}/Fluent-yellow" "${STAGE_DIR}/Fluent-yellow" 2>"${WORK_DIR}/cp.stderr" || true

# upstream生成結果には、既知の壊れたシンボリックリンク (廃止された
# app名エイリアス等) が含まれており、cp --dereferenceはそれらを
# コピーせずスキップする (エラーではなく、対象ファイルが単に生成物へ
# 含まれない)。これは事前に確認済みの想定内の挙動である。
[ -d "${STAGE_DIR}/Fluent-yellow/scalable" ] ||
	die "dereferenced tree missing scalable/ (symlink materialization failed)" 17
[ -d "${STAGE_DIR}/Fluent-yellow/symbolic" ] ||
	die "dereferenced tree missing symbolic/ (symlink materialization failed)" 17
if find "${STAGE_DIR}/Fluent-yellow" -type l | grep -q .; then
	die "dereferenced tree still contains symlinks (materialization incomplete)" 17
fi

#==========================
# 9. 不要ディレクトリ削除
#==========================
log "Removing fixed-size / HiDPI directories and icon-theme.cache..."
for d in "${PRUNE_DIRS[@]}"; do
	rm -rf --one-file-system -- "${STAGE_DIR}/Fluent-yellow/${d}"
done
rm -f -- "${STAGE_DIR}/Fluent-yellow/icon-theme.cache"

#==========================
# 10. 不正3ファイル削除
#==========================
log "Removing malformed filenames inherited from upstream..."
for f in "${EXCLUDE_FILES[@]}"; do
	rm -f -- "${STAGE_DIR}/Fluent-yellow/${f}"
done

#==========================
# 11. MyPocketOS-Fluent-yellow へ名称変更
#==========================
log "Renaming to ${THEME_NAME}..."
mv "${STAGE_DIR}/Fluent-yellow" "${STAGE_DIR}/${THEME_NAME}"
readonly THEME_DIR="${STAGE_DIR}/${THEME_NAME}"

#==========================
# 12. index.theme修正
#==========================
log "Writing MyPocketOS-derived index.theme..."
cat >"${THEME_DIR}/index.theme" <<'EOF'
[Icon Theme]
Name=MyPocketOS Fluent yellow
Comment=MyPocketOS-derived subset of the Fluent icon theme (yellow variant); not the full upstream distribution
Inherits=hicolor
Example=folder

# MyPocketOS: このindex.themeはupstream (vinceliuice/Fluent-icon-theme) の
# 生成結果を元にした派生サブセットです。詳細な変更点は同梱の
# MODIFICATIONS.md、および取得元・ライセンスはCOPYINGを参照してください。

KDE-Extensions=.svg

# Directory list (MyPocketOSでは scalable/symbolic のみを同梱)
Directories=scalable/applets,scalable/apps,scalable/devices,scalable/places,scalable/mimetypes,symbolic/apps,symbolic/actions,symbolic/categories,symbolic/devices,symbolic/emblems,symbolic/emotes,symbolic/mimetypes,symbolic/places,symbolic/status

# Scalable
[scalable/apps]
Context=Applications
Size=64
MinSize=16
MaxSize=512
Type=Scalable

[scalable/applets]
Size=64
Context=Status
Type=Scalable
MinSize=32
MaxSize=256

[scalable/devices]
Context=Devices
Size=64
MinSize=22
MaxSize=512
Type=Scalable

[scalable/places]
Context=Places
Size=64
MinSize=22
MaxSize=512
Type=Scalable

[scalable/mimetypes]
Context=MimeTypes
Size=64
MinSize=24
MaxSize=512
Type=Scalable

# Symbolic
[symbolic/actions]
Context=Actions
Size=16
MinSize=16
MaxSize=512
Type=Scalable

[symbolic/apps]
Context=Applications
Size=16
MinSize=16
MaxSize=512
Type=Scalable

[symbolic/categories]
Context=Categories
Size=16
MinSize=16
MaxSize=512
Type=Scalable

[symbolic/devices]
Context=Devices
Size=16
MinSize=16
MaxSize=512
Type=Scalable

[symbolic/emblems]
Context=Emblems
Size=16
MinSize=16
MaxSize=512
Type=Scalable

[symbolic/emotes]
Context=Emotes
Size=16
MinSize=16
MaxSize=512
Type=Scalable

[symbolic/mimetypes]
Context=MimeTypes
Size=16
MinSize=16
MaxSize=512
Type=Scalable

[symbolic/places]
Context=Places
Size=16
MinSize=16
MaxSize=512
Type=Scalable

[symbolic/status]
Context=Status
Size=16
MinSize=16
MaxSize=512
Type=Scalable
EOF

#==========================
# 13. COPYING確認 (upstream原文のまま、無改変でコピー)
#==========================
log "Verifying and placing upstream COPYING (unmodified)..."
grep -q "GNU GENERAL PUBLIC LICENSE" "${EXTRACT_DIR}/COPYING" ||
	die "extracted COPYING does not look like a GPL license text" 18
cp --preserve=mode "${EXTRACT_DIR}/COPYING" "${THEME_DIR}/COPYING"

#==========================
# 14. MODIFICATIONS.md生成
#==========================
log "Writing MODIFICATIONS.md..."
generated_date="$(date -u +%Y-%m-%d)"
prune_list="$(printf '  - `%s`\n' "${PRUNE_DIRS[@]}")"
exclude_list="$(printf -- '  - `%s`\n' "${EXCLUDE_FILES[@]}")"
cat >"${THEME_DIR}/MODIFICATIONS.md" <<EOF
# MODIFICATIONS

このディレクトリ (\`${THEME_NAME}\`) は、以下upstreamプロジェクトの
生成結果を元にした **MyPocketOS向け派生サブセット** です。
upstreamの完全版をそのまま収録したものではありません。

## upstream

- Project: ${UPSTREAM_PROJECT}
- URL: ${UPSTREAM_URL}
- Tag: \`${UPSTREAM_TAG}\`
- Commit: \`${UPSTREAM_COMMIT}\`
- upstream tarball SHA-256 (このサブセットの生成に使用した入力): \`${EXPECTED_INPUT_SHA256}\`
- License: GPL-3.0 (同梱の \`COPYING\` に全文。upstream原文のまま無改変)

## このサブセットの生成日

${generated_date}

## MyPocketOSによる変更点

- \`install.sh yellow\` の生成結果 (標準明度の \`Fluent-yellow\`) のみを対象とした。
  light/dark明度バリエーションは対象外。
- テーマ名を \`Fluent-yellow\` から **\`${THEME_NAME}\`** へ変更した
  (\`index.theme\` の \`Name=\`、ディレクトリ名とも)。
- \`index.theme\` を書き換えた。\`Directories=\` および各セクションを、
  実際に収録する \`scalable/\`・\`symbolic/\` 配下のディレクトリのみに
  限定した (存在しない固定サイズ・HiDPIディレクトリへの参照を削除)。
- 色共通アイコンを指す隠しディレクトリ (\`.Fluent-base\` 等) への
  シンボリックリンクを、実ファイルへ実体化 (dereference) し、単体で
  自己完結するようにした。
- 以下の固定サイズ・HiDPIディレクトリを削除した
  (\`scalable\`/\`symbolic\` は Type=Scalable のため、削除したサイズと
  同じアイコンを任意の解像度で描画できる)。

${prune_list}

- 生成過程で作られる \`icon-theme.cache\` を削除した
  (MyPocketOSのビルドパイプラインは配布物へアイコンキャッシュを
  含めない方針のため。ビルド時に別途生成されない)。
- 以下、ファイル名が不正 (拡張子欠落・破損) なためアイコン名として
  解決されず、実質的に無効なファイル3件をサブセットから除外した
  (upstream生成結果の時点で既にこの名前であり、MyPocketOSが破損
  させたものではない)。

${exclude_list}

## 変更していないもの

- \`scalable/\`・\`symbolic/\` 配下のSVGファイル自体の内容 (上記3件の
  除外を除き、upstream生成結果とバイト完全一致)。
- \`COPYING\` (upstream原文のまま)。
EOF

#==========================
# 生成結果の内部検証 (パッケージング前)
#==========================
log "Verifying generated subset before packaging..."
for f in index.theme COPYING MODIFICATIONS.md; do
	[ -f "${THEME_DIR}/${f}" ] || die "generated subset missing required file: ${f}" 18
done
for d in scalable symbolic; do
	[ -d "${THEME_DIR}/${d}" ] || die "generated subset missing required directory: ${d}" 18
done
for icon in muted low medium high; do
	[ -f "${THEME_DIR}/symbolic/status/audio-volume-${icon}-symbolic.svg" ] ||
		die "generated subset missing audio-volume-${icon}-symbolic.svg" 18
done
for f in "${EXCLUDE_FILES[@]}"; do
	[ -e "${THEME_DIR}/${f}" ] && die "excluded file is still present: ${f}" 18
done
for d in "${PRUNE_DIRS[@]}"; do
	[ -e "${THEME_DIR}/${d}" ] && die "pruned directory is still present: ${d}" 18
done
if find "${THEME_DIR}" -type l | grep -q .; then
	die "generated subset still contains symlinks" 18
fi
log "Internal verification OK."

#==========================
# 15. 再現可能なtar.gz生成
#==========================
log "Building reproducible tar.gz..."
mkdir -p "${OUTPUT_DIR}"
TMP_ARCHIVE="${WORK_DIR}/${THEME_NAME}.tar.gz"
(
	cd "${STAGE_DIR}"
	tar \
		--sort=name \
		--owner=0 \
		--group=0 \
		--numeric-owner \
		--mtime="${ARCHIVE_MTIME}" \
		-cf - "${THEME_NAME}"
) | gzip -n -9 >"${TMP_ARCHIVE}" || die "failed to build tar.gz" 19

[ -s "${TMP_ARCHIVE}" ] || die "generated tar.gz is empty" 19

# 展開検証: 生成したアーカイブ自体を読み取り専用で展開して検証する
VERIFY_DIR="${WORK_DIR}/verify"
mkdir -p "${VERIFY_DIR}"
tar -xzf "${TMP_ARCHIVE}" -C "${VERIFY_DIR}" || die "failed to verify generated tar.gz (extraction failed)" 19
[ -d "${VERIFY_DIR}/${THEME_NAME}" ] || die "generated tar.gz does not contain expected top-level directory" 19
top_level_count="$(find "${VERIFY_DIR}" -mindepth 1 -maxdepth 1 | wc -l)"
[ "${top_level_count}" -eq 1 ] || die "generated tar.gz contains unexpected top-level entries" 19

mv "${TMP_ARCHIVE}" "${OUTPUT_ARCHIVE}"

#==========================
# 16. 生成アーカイブのSHA-256表示
#==========================
output_sha256="$(sha256sum "${OUTPUT_ARCHIVE}" | awk '{print $1}')"
output_size="$(stat -c %s "${OUTPUT_ARCHIVE}")"
log "Done."
echo
echo "OUTPUT_ARCHIVE=${OUTPUT_ARCHIVE}"
echo "OUTPUT_SIZE_BYTES=${output_size}"
echo "OUTPUT_SHA256=${output_sha256}"

#==========================
# 17. 一時ディレクトリ削除 (trapにより自動実行される)
#==========================
