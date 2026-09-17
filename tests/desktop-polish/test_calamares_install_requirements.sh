#!/bin/sh
#
# MyPocketOS独自のCalamares welcome.confオーバーライド
# (config/includes.chroot/etc/calamares/modules/welcome.conf)に対する
# 静的テスト。実Calamares・実ネットワーク接続は一切使用しない。
#
# 背景: MyPocketOS初回版では、通常インストール時にインターネット接続を
# 必須とする(2026-09-15、実機FMVU1400MPでのオフライン環境における
# Calamares自動インストール失敗を確認。UEFI時のbootloader-configが
# grub-efiのapt取得に失敗し、後続のupdate-grub不在でexit code 127に
# なることを確認した。詳細はreports/ai-review/20260915-calamares-
# install-requirements-investigation.md参照)。本テストは、Debian公式
# calamares-settings-debianが提供するwelcome.confの既定値(internetを
# 一切チェックしない、requiredStorage=15GiB、requiredRam=1.0GiB)を、
# MyPocketOS仕様(internet必須・storage 16GiB以上・RAM 2GiB以上)へ
# 変更したオーバーライドが正しく配置されていることを確認する。
#
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WELCOME_CONF="${REPO_ROOT}/config/includes.chroot/etc/calamares/modules/welcome.conf"
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

check "welcome.conf override exists" test -f "${WELCOME_CONF}"

# YAMLとして正しくパースできることをまず確認する(以降の各checkの前提)。
check "welcome.conf is valid YAML" \
	python3 -c "
import yaml
with open('${WELCOME_CONF}', encoding='utf-8') as f:
    yaml.safe_load(f)
"

check "requirements.requiredStorage is 16 (GiB, MyPocketOS minimum storage requirement)" \
	python3 -c "
import yaml
data = yaml.safe_load(open('${WELCOME_CONF}', encoding='utf-8'))
req = data.get('requirements')
assert isinstance(req, dict), 'no requirements: block found'
assert req.get('requiredStorage') == 16, f\"requiredStorage={req.get('requiredStorage')!r}, want 16\"
"

check "requirements.requiredRam is 2.0 (GiB)" \
	python3 -c "
import yaml
data = yaml.safe_load(open('${WELCOME_CONF}', encoding='utf-8'))
assert data['requirements'].get('requiredRam') == 2.0, f\"requiredRam={data['requirements'].get('requiredRam')!r}, want 2.0\"
"

check "requirements.check is exactly [storage, ram, power, internet, root]" \
	python3 -c "
import yaml
data = yaml.safe_load(open('${WELCOME_CONF}', encoding='utf-8'))
assert data['requirements'].get('check') == ['storage', 'ram', 'power', 'internet', 'root'], data['requirements'].get('check')
"

check "requirements.required is exactly [storage, ram, internet, root] (power is check-only, not required)" \
	python3 -c "
import yaml
data = yaml.safe_load(open('${WELCOME_CONF}', encoding='utf-8'))
assert data['requirements'].get('required') == ['storage', 'ram', 'internet', 'root'], data['requirements'].get('required')
"

# powerがcheckには含まれるがrequiredには含まれないこと(表示・警告のみ、
# デスクトップPC等バッテリーなし機種を誤ってブロックしないため)を
# 明示的に確認する。
check "power is in check but not in required" \
	python3 -c "
import yaml
data = yaml.safe_load(open('${WELCOME_CONF}', encoding='utf-8'))
req = data['requirements']
assert 'power' in req['check'], 'power missing from check'
assert 'power' not in req['required'], 'power must not be in required (display/warning only)'
"

# screenは今回の方針で追加しない(調査report・製品方針どおり)。
check "screen is not added to check or required (out of scope for v1)" \
	python3 -c "
import yaml
data = yaml.safe_load(open('${WELCOME_CONF}', encoding='utf-8'))
req = data['requirements']
assert 'screen' not in req['check'], 'screen unexpectedly added to check'
assert 'screen' not in req['required'], 'screen unexpectedly added to required'
"

check "internetCheckUrl is the selected HTTPS Debian-official URL (https://deb.debian.org/)" \
	python3 -c "
import yaml
data = yaml.safe_load(open('${WELCOME_CONF}', encoding='utf-8'))
url = data['requirements'].get('internetCheckUrl')
assert url == 'https://deb.debian.org/', f\"internetCheckUrl={url!r}, want 'https://deb.debian.org/'\"
assert url.startswith('https://'), 'internetCheckUrl must use HTTPS'
"

# 意図しない追加変更が紛れ込んでいないことを確認する。今回の変更範囲は
# requirementsブロックのみであり、表示設定(showSupportUrl等)は
# Debian公式既定のまま変更していないことを固定値で確認する。
check "unrelated existing defaults (showSupportUrl etc.) are still untouched" \
	python3 -c "
import yaml
data = yaml.safe_load(open('${WELCOME_CONF}', encoding='utf-8'))
assert data.get('showSupportUrl') is True, data.get('showSupportUrl')
assert data.get('showKnownIssuesUrl') is True, data.get('showKnownIssuesUrl')
assert data.get('showReleaseNotesUrl') is True, data.get('showReleaseNotesUrl')
"

# 既存のCalamares設定(settings.conf)との整合性: welcomeモジュールが
# 暗黙インスタンス(instance key = welcome)としてsequenceのshowフェーズ
# に含まれたままであること。welcome.confを新規追加したことで、
# settings.conf側の変更が必要になっていないことを確認する。
check "settings.conf still references the implicit 'welcome' module instance (no settings.conf change needed)" \
	python3 -c "
import yaml
data = yaml.safe_load(open('${SETTINGS_CONF}', encoding='utf-8'))
show_phases = [phase['show'] for phase in data['sequence'] if 'show' in phase]
assert any('welcome' in show for show in show_phases), 'welcome not found in any show phase'
"

echo "SCENARIOS=$((PASS + FAIL)) PASS=${PASS} FAIL=${FAIL}"
[ "${FAIL}" -eq 0 ]
