#!/bin/sh
#
# MyPocketOS既定のFcitx5プロファイル (~/.config/fcitx5/profile へ
# /etc/skel経由で配布) に対する静的テスト。実Fcitx5・実X11は一切使用しない。
#
# 背景: Fcitx5はプロファイル未設置の状態で初回起動すると、
# /etc/default/keyboardのXKBLAYOUT (MyPocketOSでは "us,jp") の順序に
# 沿って自身でプロファイルを自動生成する。この自動生成された内容は
# グループ1=us (既定でアクティブ)・グループ2=jp という順序になり、
# 初回ログイン直後は日本語配列・日本語入力が使えない状態になっていた
# (2026-09-13実機VM検証で確認)。本ファイルをあらかじめ配布することで、
# Fcitx5の自動生成を待たず、最初からグループ1=jp (既定でアクティブ)と
# なるようにする。us配列は削除せず、グループ2として引き続き切替可能に
# しておく。
#
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROFILE="${REPO_ROOT}/config/includes.chroot/etc/skel/.config/fcitx5/profile"

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

check "profile file exists" test -f "${PROFILE}"

# グループ0 (GroupOrderの先頭、Fcitx5実機観測で「既定でアクティブになる
# グループ」と確認済み) がjp配列+mozcであること。
check "Groups/0 (default/active group) has Default Layout=jp" \
	sh -c '
	awk "/^\[Groups\/0\]/{f=1;next} /^\[/{f=0} f && /^Default Layout=jp\$/{found=1} END{exit !found}" "$1"
	' _ "${PROFILE}"

check "Groups/0/Items/0 is keyboard-jp" \
	sh -c '
	awk "/^\[Groups\/0\/Items\/0\]/{f=1;next} /^\[/{f=0} f && /^Name=keyboard-jp\$/{found=1} END{exit !found}" "$1"
	' _ "${PROFILE}"

check "Groups/0 has mozc as an input method item" \
	sh -c '
	awk "/^\[Groups\/0\/Items\/1\]/{f=1;next} /^\[/{f=0} f && /^Name=mozc\$/{found=1} END{exit !found}" "$1"
	' _ "${PROFILE}"

check "GroupOrder position 0 is the jp group (グループ 1)" \
	grep -qF '0="グループ 1"' "${PROFILE}"

# us配列は削除せず、切替可能な副グループとして残す (要件どおり)。
check "us layout is kept as a secondary group (Groups/1), not removed" \
	sh -c '
	awk "/^\[Groups\/1\]/{f=1;next} /^\[/{f=0} f && /^Default Layout=us\$/{found=1} END{exit !found}" "$1"
	' _ "${PROFILE}"

check "Groups/1/Items/0 is keyboard-us" \
	sh -c '
	awk "/^\[Groups\/1\/Items\/0\]/{f=1;next} /^\[/{f=0} f && /^Name=keyboard-us\$/{found=1} END{exit !found}" "$1"
	' _ "${PROFILE}"

# DefaultIMは両グループともmozcであること (US配列選択中でも変換キーで
# 日本語入力に切替できる、既存の実機観測結果と同じ挙動を維持する)。
check "both groups default to mozc as the input method" \
	sh -c '[ "$(grep -c "^DefaultIM=mozc$" "$1")" -eq 2 ]' _ "${PROFILE}"

echo "SCENARIOS=$((PASS + FAIL)) PASS=${PASS} FAIL=${FAIL}"
[ "${FAIL}" -eq 0 ]
