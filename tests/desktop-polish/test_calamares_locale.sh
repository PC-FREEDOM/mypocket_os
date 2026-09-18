#!/bin/sh
#
# MyPocketOS独自のCalamares locale.confオーバーライド
# (config/includes.chroot/etc/calamares/modules/locale.conf)に対する
# 静的テスト。実Calamares・実タイムゾーン変更は一切使用しない。
#
# 背景: calamares本体・calamares-settings-debianパッケージのいずれも
# locale.confを提供しておらず、Calamaresの「locale」モジュール
# (タイムゾーン選択画面)は本体ソースコードにハードコードされた既定値
# "America/New_York" を初期表示に使っていた(2026-09-17調査、
# reports/ai-review/20260917-calamares-timezone-new-york-investigation
# .md参照)。MyPocketOSは日本語向け・Asia/Tokyoを正式な初期仕様とする
# ため、region/zoneを明示的にAsia/Tokyoへ固定する新規locale.confを
# 追加した(useSystemTimezone・GeoIP設定はいずれも意図的に含めない)。
#
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LOCALE_CONF="${REPO_ROOT}/config/includes.chroot/etc/calamares/modules/locale.conf"
SETTINGS_CONF="${REPO_ROOT}/config/includes.chroot/etc/calamares/settings.conf"

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

check "locale.conf override exists" test -f "${LOCALE_CONF}"

check "YAML parses and region/zone are Asia/Tokyo" \
	python3 -c "
import yaml
with open('${LOCALE_CONF}', encoding='utf-8') as f:
    data = yaml.safe_load(f)
assert data.get('region') == 'Asia', f\"region={data.get('region')!r}, want 'Asia'\"
assert data.get('zone') == 'Tokyo', f\"zone={data.get('zone')!r}, want 'Tokyo'\"
"

# useSystemTimezoneは意図的に含めない(Live環境の実行時timezoneに
# よって、明示指定したAsia/Tokyoが上書きされてしまうことを避けるため)。
check "useSystemTimezone is not set (Asia/Tokyo must not be overridden by live runtime timezone)" \
	python3 -c "
import yaml
data = yaml.safe_load(open('${LOCALE_CONF}', encoding='utf-8'))
assert 'useSystemTimezone' not in data, data.get('useSystemTimezone')
"

# GeoIP設定も意図的に追加しない(ネットワーク依存を増やさない方針)。
check "no geoip configuration was introduced" \
	python3 -c "
import yaml
data = yaml.safe_load(open('${LOCALE_CONF}', encoding='utf-8'))
assert 'geoip' not in data, data.get('geoip')
"

# ファイルの内容がregion/zoneの2キーのみであることを確認する
# (keyboard設定等、範囲外のキーが紛れ込んでいないことの確認)。
check "locale.conf contains exactly region and zone (no unrelated keys)" \
	python3 -c "
import yaml
data = yaml.safe_load(open('${LOCALE_CONF}', encoding='utf-8'))
assert set(data.keys()) == {'region', 'zone'}, sorted(data.keys())
"

# 既存のCalamares設定(settings.conf)との整合性: localeモジュールが
# show/execフェーズに含まれたままであること。locale.confを新規追加
# したことで、settings.conf側の変更が必要になっていないことを確認する。
check "settings.conf still references the 'locale' module in show and exec phases" \
	python3 -c "
import yaml
data = yaml.safe_load(open('${SETTINGS_CONF}', encoding='utf-8'))
show_phases = [phase['show'] for phase in data['sequence'] if 'show' in phase]
exec_phases = [phase['exec'] for phase in data['sequence'] if 'exec' in phase]
assert any('locale' in show for show in show_phases), 'locale not found in any show phase'
assert any('locale' in ex for ex in exec_phases), 'locale not found in any exec phase'
"

echo "SCENARIOS=$((PASS + FAIL)) PASS=${PASS} FAIL=${FAIL}"
[ "${FAIL}" -eq 0 ]
