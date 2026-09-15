#!/bin/sh
#
# MyPocketOS独自のCalamares partition.confオーバーライド
# (config/includes.chroot/etc/calamares/modules/partition.conf)に対する
# 静的テスト。実Calamares・実パーティション操作は一切使用しない。
#
# 背景: Debian公式calamares-settings-debianが提供するpartition.confは
# EFI System Partitionのrecommended sizeを300MiBとしている
# (2026-09-14 UEFI VM検証で実際に300MiBのESPが作成されることを確認、
# reports/ai-review/20260913-calamares-spike-desktop-fixes.md 14.5節)。
# MyPocketOSの標準ESPサイズ方針は512MiBであるため、このファイルの
# 上書きによってrecommendedSizeのみを512MiBへ変更している。
#
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PARTITION_CONF="${REPO_ROOT}/config/includes.chroot/etc/calamares/modules/partition.conf"

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

check "partition.conf override exists" test -f "${PARTITION_CONF}"

# YAMLとして正しくパースできること、およびefiブロックの値を構造的に
# 検証する(文字列grepではなく実際のYAML構造で確認する)。
check "YAML parses and efi.recommendedSize is 512MiB (MyPocketOS standard ESP size)" \
	python3 -c "
import yaml
with open('${PARTITION_CONF}', encoding='utf-8') as f:
    data = yaml.safe_load(f)
efi = data.get('efi')
assert isinstance(efi, dict), 'no efi: block found'
assert efi.get('recommendedSize') == '512MiB', f\"recommendedSize={efi.get('recommendedSize')!r}, want '512MiB'\"
"

check "efi.mountPoint is unchanged (/boot/efi)" \
	python3 -c "
import yaml
data = yaml.safe_load(open('${PARTITION_CONF}', encoding='utf-8'))
assert data['efi']['mountPoint'] == '/boot/efi', data['efi']['mountPoint']
"

# minimumSize (EFI仕様上の絶対最小値) は今回の変更対象ではなく、
# Debian公式既定の32MiBのまま維持していることを確認する(要件は
# 「標準(推奨)サイズを512MiBにする」であり、絶対最小値の変更は
# 求められていないため)。
check "efi.minimumSize is unchanged (32MiB, EFI spec minimum, not part of this change)" \
	python3 -c "
import yaml
data = yaml.safe_load(open('${PARTITION_CONF}', encoding='utf-8'))
assert data['efi']['minimumSize'] == '32MiB', data['efi']['minimumSize']
"

# 意図しない追加変更が紛れ込んでいないことを確認する。今回の変更範囲は
# efi.recommendedSizeのみであり、BIOS自動レイアウトやパーティション
# テーブル種別・ファイルシステム既定値・LVM/LUKS設定等、他の既存の
# Debian公式既定値には一切手を加えていないことを固定値で確認する。
check "unrelated existing defaults are still untouched (defaultFileSystemType/lvm/initial choices)" \
	python3 -c "
import yaml
data = yaml.safe_load(open('${PARTITION_CONF}', encoding='utf-8'))
assert data['defaultFileSystemType'] == 'ext4', data['defaultFileSystemType']
assert data['lvm']['enable'] is False, data['lvm']
assert data['initialPartitioningChoice'] == 'none', data['initialPartitioningChoice']
assert data['initialSwapChoice'] == 'none', data['initialSwapChoice']
"

# BIOS(non-EFI)自動レイアウトへの影響がないことのドキュメント面の
# 確認: このファイル自体がBIOS Boot Partitionのサイズ・作成条件に
# 言及する設定キー(defaultPartitionTableType等)を新規に追加していない
# ことを確認する(コメントアウトされた例示行は既存のDebian公式ファイル
# 由来でありコメント行なので対象外、実際に有効なキーとしては
# 存在しないことを確認する)。
check "no defaultPartitionTableType override was introduced (BIOS auto-layout untouched)" \
	python3 -c "
import yaml
data = yaml.safe_load(open('${PARTITION_CONF}', encoding='utf-8'))
assert 'defaultPartitionTableType' not in data, data.get('defaultPartitionTableType')
"

echo "SCENARIOS=$((PASS + FAIL)) PASS=${PASS} FAIL=${FAIL}"
[ "${FAIL}" -eq 0 ]
