#!/bin/sh
#
# auto/config のISO/USBメディア表示名設定 (--iso-volume・--iso-application・
# --iso-publisher・--hdd-label) に対する静的テスト。
#
# 実lb・実sudo・実ISOビルドは一切行わない。config/binary・config/common・
# config/chroot・config/bootstrapは lb config が生成する成果物であり
# .gitignore対象 (リポジトリに含まれない) のため、本テストは auto/config
# の記述内容のみを検証する。ローカルに config/binary が既に生成済みの
# 場合に限り、値が auto/config と食い違っていないかを追加で確認するが、
# CI環境等で config/binary が存在しない場合はそのチェックをスキップする
# (live-buildを実行しない前提のCIでも失敗しないようにするため)。
#
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
AUTO_CONFIG="${REPO_ROOT}/auto/config"
CONFIG_BINARY="${REPO_ROOT}/config/binary"

PASS=0
FAIL=0

check() {
	desc="$1"
	shift
	if "$@"; then
		PASS=$((PASS + 1))
	else
		echo "FAIL: ${desc}" >&2
		FAIL=$((FAIL + 1))
	fi
}

extract_value() {
	# $1: auto/config内のロングオプション名 (例: --iso-volume)
	sed -n "s/.*${1} \"\\([^\"]*\\)\".*/\\1/p" "${AUTO_CONFIG}" | head -n1
}

check "auto/config exists" test -f "${AUTO_CONFIG}"

ISO_VOLUME="$(extract_value --iso-volume)"
ISO_APPLICATION="$(extract_value --iso-application)"
ISO_PUBLISHER="$(extract_value --iso-publisher)"
HDD_LABEL="$(extract_value --hdd-label)"

# ---- 1. auto/configに4設定が存在すること -----------------------------------
check "auto/config declares --iso-volume" sh -c '[ -n "$1" ]' _ "${ISO_VOLUME}"
check "auto/config declares --iso-application" sh -c '[ -n "$1" ]' _ "${ISO_APPLICATION}"
check "auto/config declares --iso-publisher" sh -c '[ -n "$1" ]' _ "${ISO_PUBLISHER}"
check "auto/config declares --hdd-label" sh -c '[ -n "$1" ]' _ "${HDD_LABEL}"

# ---- 2. Debian由来の値になっていないこと (大文字小文字を区別しない) ----------
for pair in "iso-volume:${ISO_VOLUME}" "iso-application:${ISO_APPLICATION}" \
	"iso-publisher:${ISO_PUBLISHER}" "hdd-label:${HDD_LABEL}"; do
	name="${pair%%:*}"
	value="${pair#*:}"
	check "${name} does not contain 'Debian'" \
		sh -c '! printf "%s" "$1" | grep -qi "debian"' _ "${value}"
done

# ---- 3. MyPocketOS系の値になっていること (大文字小文字を区別しない) ----------
for pair in "iso-volume:${ISO_VOLUME}" "iso-application:${ISO_APPLICATION}" \
	"iso-publisher:${ISO_PUBLISHER}" "hdd-label:${HDD_LABEL}"; do
	name="${pair%%:*}"
	value="${pair#*:}"
	check "${name} contains 'MyPocketOS' (case-insensitive)" \
		sh -c 'printf "%s" "$1" | grep -qi "mypocketos"' _ "${value}"
done

# ---- 4. ISO Volumeが展開後32文字以内に収まること ----------------------------
# @ISOVOLUME_TS@ は live-build 側で "date +%Y%m%d-%H:%M" (14文字、
# 例: 20260903-12:34) に置換される。プレースホルダ自体も14文字のため、
# テンプレートの文字数=展開後の文字数として比較できる。
ISO_VOLUME_EXPANDED="$(printf '%s' "${ISO_VOLUME}" | sed 's/@ISOVOLUME_TS@/20260903-12:34/')"
check "expanded --iso-volume value is <= 32 chars (ISO9660 limit)" \
	sh -c '[ "${#1}" -le 32 ]' _ "${ISO_VOLUME_EXPANDED}"

# ---- 5. config/binary等の生成物が誤ってGit管理下に置かれていないこと --------
for f in config/binary config/common config/chroot config/bootstrap; do
	check "${f} is not tracked by git (lb config生成物のため)" \
		sh -c '! git -C "$1" ls-files --error-unmatch "$2" >/dev/null 2>&1' _ "${REPO_ROOT}" "${f}"
done

# ---- 6. (best-effort) ローカルに生成済みのconfig/binaryがあれば整合確認 -----
# config/binaryはlb config生成物でCI上には存在しない想定のため、存在する
# 場合のみ追加確認する (存在しない場合はスキップし、FAILにはしない)。
if [ -f "${CONFIG_BINARY}" ]; then
	CONFIG_BINARY_VOLUME="$(sed -n 's/^LB_ISO_VOLUME="\(.*\)"$/\1/p' "${CONFIG_BINARY}")"
	CONFIG_BINARY_APPLICATION="$(sed -n 's/^LB_ISO_APPLICATION="\(.*\)"$/\1/p' "${CONFIG_BINARY}")"
	CONFIG_BINARY_PUBLISHER="$(sed -n 's/^LB_ISO_PUBLISHER="\(.*\)"$/\1/p' "${CONFIG_BINARY}")"
	CONFIG_BINARY_HDD_LABEL="$(sed -n 's/^LB_HDD_LABEL="\(.*\)"$/\1/p' "${CONFIG_BINARY}")"

	check "config/binary LB_ISO_VOLUME matches auto/config --iso-volume" \
		sh -c '[ "$1" = "$2" ]' _ "${CONFIG_BINARY_VOLUME}" "${ISO_VOLUME}"
	check "config/binary LB_ISO_APPLICATION matches auto/config --iso-application" \
		sh -c '[ "$1" = "$2" ]' _ "${CONFIG_BINARY_APPLICATION}" "${ISO_APPLICATION}"
	check "config/binary LB_ISO_PUBLISHER matches auto/config --iso-publisher" \
		sh -c '[ "$1" = "$2" ]' _ "${CONFIG_BINARY_PUBLISHER}" "${ISO_PUBLISHER}"
	check "config/binary LB_HDD_LABEL matches auto/config --hdd-label" \
		sh -c '[ "$1" = "$2" ]' _ "${CONFIG_BINARY_HDD_LABEL}" "${HDD_LABEL}"
else
	echo "NOTE: config/binary not present locally (lb config未実行のためスキップ)"
fi

# ---- 7. --iso-preparer は今回変更していないこと (回帰防止) ------------------
check "auto/config does not declare --iso-preparer (Preparerは今回変更しない)" \
	sh -c '! grep -q -- "--iso-preparer" "$1"' _ "${AUTO_CONFIG}"

echo "SCENARIOS=$((PASS + FAIL)) PASS=${PASS} FAIL=${FAIL}"
[ "${FAIL}" -eq 0 ]
