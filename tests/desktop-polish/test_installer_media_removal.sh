#!/bin/sh
#
# Calamaresインストール完了直後の再起動時にだけインストールメディアの
# 取り外し案内/eject試行を行う機能 (2026-09-16実装、reports/ai-review/
# 20260916-installer-media-removal-v1-implementation.md 参照) に対する
# テスト。
#
# 対象:
#   - config/includes.chroot/etc/calamares/modules/finished.conf
#   - config/includes.chroot/usr/local/bin/mypocketos-installer-reboot
#   - config/includes.chroot/usr/lib/systemd/system-shutdown/
#     mypocketos-install-media-removal
#   - config/includes.chroot/etc/calamares/modules/
#     shellprocess-livepurge.conf
#   - auto/config (noejectが残っていることの回帰確認のみ)
#
# 実sudo・実VM・実Calamares・実systemd-shutdown・実eject・実USB/CD-DVDは
# 一切使用しない。production scriptの2箇所のテスト専用環境変数
# (MYPOCKETOS_INSTALL_MARKER_DIR / MYPOCKETOS_INSTALL_MARKER_FILE /
# MYPOCKETOS_INSTALL_CONSOLE。いずれも未設定時は本番と同じパスを使う)と、
# fake PATH経由でのfindmnt/readlink/eject/systemctlのモックにより、
# 実システムの /run・/dev・/sys へ一切副作用を与えずに検証する。
#
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FINISHED_CONF="${REPO_ROOT}/config/includes.chroot/etc/calamares/modules/finished.conf"
REBOOT_WRAPPER="${REPO_ROOT}/config/includes.chroot/usr/local/bin/mypocketos-installer-reboot"
SHUTDOWN_HOOK="${REPO_ROOT}/config/includes.chroot/usr/lib/systemd/system-shutdown/mypocketos-install-media-removal"
LIVEPURGE_CONF="${REPO_ROOT}/config/includes.chroot/etc/calamares/modules/shellprocess-livepurge.conf"
AUTO_CONFIG="${REPO_ROOT}/auto/config"

PASS=0
FAIL=0

TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT

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

#==========================================================
# fake PATH (findmnt/readlink/eject/df/systemctlのモック) の準備
#==========================================================
FAKE_BIN="${TMPDIR}/fakebin"
mkdir -p "${FAKE_BIN}"

# systemctl: 呼ばれた引数をログへ記録して正常終了する。
cat > "${FAKE_BIN}/systemctl" <<'EOF'
#!/bin/sh
printf 'systemctl %s\n' "$*" >> "${SYSTEMCTL_LOG}"
exit 0
EOF

# findmnt: FAKE_FINDMNT_OUTPUT の内容をそのまま出力する
# (呼び出し引数の内容は問わない。本テストでは常に1回目のfindmnt呼び出し
# で解決させ、systemd>=253向けのフォールバック経路は対象外とする)。
cat > "${FAKE_BIN}/findmnt" <<'EOF'
#!/bin/sh
printf '%s\n' "${FAKE_FINDMNT_OUTPUT:-}"
EOF

# readlink: FAKE_READLINK_OUTPUT の内容をそのまま出力する
# (USB判定用の /sys/block/<dev> リンク先を偽装する)。
cat > "${FAKE_BIN}/readlink" <<'EOF'
#!/bin/sh
printf '%s\n' "${FAKE_READLINK_OUTPUT:-}"
EOF

# eject: 呼ばれたことと引数をログへ記録し、FAKE_EJECT_EXIT
# (既定0)で終了する。
cat > "${FAKE_BIN}/eject" <<'EOF'
#!/bin/sh
printf 'eject %s\n' "$*" >> "${EJECT_LOG}"
exit "${FAKE_EJECT_EXIT:-0}"
EOF

# df: shutdown hookのsystemd>=253フォールバック経路が今回のテストでは
# 使われないことを保証するため、常に空を返す。
cat > "${FAKE_BIN}/df" <<'EOF'
#!/bin/sh
printf ''
EOF

chmod +x "${FAKE_BIN}"/*

# 実ホスト上で「sd*」パターンにマッチする実在のブロックデバイスを
# 動的に探す(USB/非USB分岐のテストには、/dev/<name> が実際に
# ブロックデバイスとして存在している必要があるため。名前そのものに
# 意味はなく、readlinkの出力をモックすることでUSB/非USBを制御する)。
REAL_SD_DEVICE=""
for _d in /sys/block/sd*; do
	[ -e "${_d}" ] || continue
	_name="$(basename "${_d}")"
	if [ -b "/dev/${_name}" ]; then
		REAL_SD_DEVICE="${_name}"
		break
	fi
done

#==========================================================
# A. finished.conf が wrapper を指定している
#==========================================================
check "finished.conf override exists" test -f "${FINISHED_CONF}"

check "finished.conf is valid YAML" \
	python3 -c "
import yaml
with open('${FINISHED_CONF}', encoding='utf-8') as f:
    yaml.safe_load(f)
"

check "finished.conf restartNowCommand points to mypocketos-installer-reboot" \
	python3 -c "
import yaml
data = yaml.safe_load(open('${FINISHED_CONF}', encoding='utf-8'))
assert data.get('restartNowCommand') == '/usr/local/bin/mypocketos-installer-reboot', data.get('restartNowCommand')
"

check "finished.conf restartNowEnabled/restartNowChecked remain true (unrelated defaults untouched)" \
	python3 -c "
import yaml
data = yaml.safe_load(open('${FINISHED_CONF}', encoding='utf-8'))
assert data.get('restartNowEnabled') is True, data.get('restartNowEnabled')
assert data.get('restartNowChecked') is True, data.get('restartNowChecked')
"

#==========================================================
# 2〜4. mypocketos-installer-reboot (wrapper)
#==========================================================
check "reboot wrapper exists" test -f "${REBOOT_WRAPPER}"
check "reboot wrapper is executable" test -x "${REBOOT_WRAPPER}"
check "reboot wrapper syntax is valid (sh -n)" sh -n "${REBOOT_WRAPPER}"

# B. wrapperが正しいmarker pathを使用する (静的確認)
check "reboot wrapper uses /run/mypocketos as the default marker directory" \
	grep -q '/run/mypocketos' "${REBOOT_WRAPPER}"
check "reboot wrapper uses /run/mypocketos/install-complete-reboot as the marker file" \
	grep -q '/run/mypocketos/install-complete-reboot' "${REBOOT_WRAPPER}"

# C. wrapperが最終的にsystemctl -i rebootを実行する
c_marker_dir="${TMPDIR}/run-ok/mypocketos"
c_systemctl_log="${TMPDIR}/systemctl-c.log"
: > "${c_systemctl_log}"
PATH="${FAKE_BIN}:${PATH}" \
	MYPOCKETOS_INSTALL_MARKER_DIR="${c_marker_dir}" \
	SYSTEMCTL_LOG="${c_systemctl_log}" \
	"${REBOOT_WRAPPER}"
check "reboot wrapper invoked systemctl exactly once" \
	sh -c '[ "$(wc -l < "$1")" -eq 1 ]' _ "${c_systemctl_log}"
check "reboot wrapper invoked systemctl with '-i reboot'" \
	grep -qx 'systemctl -i reboot' "${c_systemctl_log}"
check "reboot wrapper created the marker file when the directory is writable" \
	test -f "${c_marker_dir}/install-complete-reboot"

# D. marker作成に失敗してもrebootへ進む設計
# (marker directoryの親を通常ファイルにすることで mkdir -p を必ず
# 失敗させる)
d_blocker="${TMPDIR}/blocker-file"
: > "${d_blocker}"
d_marker_dir="${d_blocker}/mypocketos"
d_systemctl_log="${TMPDIR}/systemctl-d.log"
: > "${d_systemctl_log}"
PATH="${FAKE_BIN}:${PATH}" \
	MYPOCKETOS_INSTALL_MARKER_DIR="${d_marker_dir}" \
	SYSTEMCTL_LOG="${d_systemctl_log}" \
	"${REBOOT_WRAPPER}"
check "reboot wrapper still invokes systemctl even when marker creation is impossible" \
	grep -qx 'systemctl -i reboot' "${d_systemctl_log}"

#==========================================================
# 3〜4. mypocketos-install-media-removal (shutdown hook)
#==========================================================
check "shutdown hook exists" test -f "${SHUTDOWN_HOOK}"
check "shutdown hook is executable" test -x "${SHUTDOWN_HOOK}"
check "shutdown hook syntax is valid (sh -n)" sh -n "${SHUTDOWN_HOOK}"
check "shutdown hook checks for the 'reboot' argument before doing anything else" \
	grep -q '"${1:-}" = "reboot"' "${SHUTDOWN_HOOK}"

# E. markerが無ければ何もしない
e_marker_file="${TMPDIR}/no-such-marker/install-complete-reboot"
e_console="${TMPDIR}/console-e.txt"
: > "${e_console}"
e_eject_log="${TMPDIR}/eject-e.log"
: > "${e_eject_log}"
PATH="${FAKE_BIN}:${PATH}" \
	MYPOCKETOS_INSTALL_MARKER_FILE="${e_marker_file}" \
	MYPOCKETOS_INSTALL_CONSOLE="${e_console}" \
	EJECT_LOG="${e_eject_log}" \
	FAKE_FINDMNT_OUTPUT="/dev/${REAL_SD_DEVICE:-sda}" \
	"${SHUTDOWN_HOOK}" reboot
check "shutdown hook without marker: exits without any eject attempt" \
	sh -c '[ ! -s "$1" ]' _ "${e_eject_log}"
check "shutdown hook without marker: exits without writing to console" \
	sh -c '[ ! -s "$1" ]' _ "${e_console}"

# F. reboot以外なら、markerがあっても何もしない
f_marker_dir="${TMPDIR}/marker-f"
mkdir -p "${f_marker_dir}"
f_marker_file="${f_marker_dir}/install-complete-reboot"
: > "${f_marker_file}"
f_console="${TMPDIR}/console-f.txt"
: > "${f_console}"
f_eject_log="${TMPDIR}/eject-f.log"
: > "${f_eject_log}"
for f_action in poweroff halt kexec; do
	PATH="${FAKE_BIN}:${PATH}" \
		MYPOCKETOS_INSTALL_MARKER_FILE="${f_marker_file}" \
		MYPOCKETOS_INSTALL_CONSOLE="${f_console}" \
		EJECT_LOG="${f_eject_log}" \
		FAKE_FINDMNT_OUTPUT="/dev/${REAL_SD_DEVICE:-sda}" \
		"${SHUTDOWN_HOOK}" "${f_action}"
done
check "shutdown hook with marker but action != reboot (poweroff/halt/kexec): no eject attempted" \
	sh -c '[ ! -s "$1" ]' _ "${f_eject_log}"
check "shutdown hook with marker but action != reboot: no console message" \
	sh -c '[ ! -s "$1" ]' _ "${f_console}"

if [ -n "${REAL_SD_DEVICE}" ]; then

	# G. reboot + markerありでのみ処理へ進む(かつ、デバイスが解決できる場合)
	g_marker_dir="${TMPDIR}/marker-g"
	mkdir -p "${g_marker_dir}"
	g_marker_file="${g_marker_dir}/install-complete-reboot"
	: > "${g_marker_file}"
	g_console="${TMPDIR}/console-g.txt"
	: > "${g_console}"
	g_eject_log="${TMPDIR}/eject-g.log"
	: > "${g_eject_log}"
	PATH="${FAKE_BIN}:${PATH}" \
		MYPOCKETOS_INSTALL_MARKER_FILE="${g_marker_file}" \
		MYPOCKETOS_INSTALL_CONSOLE="${g_console}" \
		EJECT_LOG="${g_eject_log}" \
		FAKE_FINDMNT_OUTPUT="/dev/${REAL_SD_DEVICE}" \
		FAKE_READLINK_OUTPUT="../../devices/pci0000:00/0000:00:1f.2/ata1/host0/target0:0:0/0:0:0:0/block/${REAL_SD_DEVICE}" \
		"${SHUTDOWN_HOOK}" reboot
	check "shutdown hook with reboot+marker+resolvable device: writes a console message" \
		sh -c '[ -s "$1" ]' _ "${g_console}"

	# H. USB判定時にejectを呼ばない (案内メッセージは表示する。
	#    Debian標準live-medium-ejectとの意図的な差異。script内コメント参照)
	h_marker_dir="${TMPDIR}/marker-h"
	mkdir -p "${h_marker_dir}"
	h_marker_file="${h_marker_dir}/install-complete-reboot"
	: > "${h_marker_file}"
	h_console="${TMPDIR}/console-h.txt"
	: > "${h_console}"
	h_eject_log="${TMPDIR}/eject-h.log"
	: > "${h_eject_log}"
	PATH="${FAKE_BIN}:${PATH}" \
		MYPOCKETOS_INSTALL_MARKER_FILE="${h_marker_file}" \
		MYPOCKETOS_INSTALL_CONSOLE="${h_console}" \
		EJECT_LOG="${h_eject_log}" \
		FAKE_FINDMNT_OUTPUT="/dev/${REAL_SD_DEVICE}" \
		FAKE_READLINK_OUTPUT="../../devices/pci0000:00/0000:00:14.0/usb1/1-1/1-1:1.0/host0/target0:0:0/0:0:0:0/block/${REAL_SD_DEVICE}" \
		"${SHUTDOWN_HOOK}" reboot
	check "shutdown hook: USB device (sd*+usb sysfs link) is not ejected" \
		sh -c '[ ! -s "$1" ]' _ "${h_eject_log}"
	check "shutdown hook: USB device still gets the removal message (v1 deliberate divergence from upstream)" \
		sh -c '[ -s "$1" ]' _ "${h_console}"

	# I. CD/DVD (非USB) 判定時にejectを試す
	i_marker_dir="${TMPDIR}/marker-i"
	mkdir -p "${i_marker_dir}"
	i_marker_file="${i_marker_dir}/install-complete-reboot"
	: > "${i_marker_file}"
	i_console="${TMPDIR}/console-i.txt"
	: > "${i_console}"
	i_eject_log="${TMPDIR}/eject-i.log"
	: > "${i_eject_log}"
	PATH="${FAKE_BIN}:${PATH}" \
		MYPOCKETOS_INSTALL_MARKER_FILE="${i_marker_file}" \
		MYPOCKETOS_INSTALL_CONSOLE="${i_console}" \
		EJECT_LOG="${i_eject_log}" \
		FAKE_FINDMNT_OUTPUT="/dev/${REAL_SD_DEVICE}" \
		FAKE_READLINK_OUTPUT="../../devices/pci0000:00/0000:00:1f.2/ata1/host0/target0:0:0/0:0:0:0/block/${REAL_SD_DEVICE}" \
		"${SHUTDOWN_HOOK}" reboot
	check "shutdown hook: non-USB device gets an eject attempt" \
		sh -c '[ -s "$1" ]' _ "${i_eject_log}"
	check "shutdown hook: eject was called with -p -m and the resolved device" \
		grep -qx "eject -p -m /dev/${REAL_SD_DEVICE}" "${i_eject_log}"

	# J. eject失敗でも致命的失敗にしない
	j_marker_dir="${TMPDIR}/marker-j"
	mkdir -p "${j_marker_dir}"
	j_marker_file="${j_marker_dir}/install-complete-reboot"
	: > "${j_marker_file}"
	j_console="${TMPDIR}/console-j.txt"
	: > "${j_console}"
	j_eject_log="${TMPDIR}/eject-j.log"
	: > "${j_eject_log}"
	j_exit=0
	PATH="${FAKE_BIN}:${PATH}" \
		MYPOCKETOS_INSTALL_MARKER_FILE="${j_marker_file}" \
		MYPOCKETOS_INSTALL_CONSOLE="${j_console}" \
		EJECT_LOG="${j_eject_log}" \
		FAKE_FINDMNT_OUTPUT="/dev/${REAL_SD_DEVICE}" \
		FAKE_READLINK_OUTPUT="../../devices/pci0000:00/0000:00:1f.2/ata1/host0/target0:0:0/0:0:0:0/block/${REAL_SD_DEVICE}" \
		FAKE_EJECT_EXIT=1 \
		"${SHUTDOWN_HOOK}" reboot || j_exit=$?
	check "shutdown hook still exits 0 even when the underlying eject command fails" \
		sh -c '[ "$1" -eq 0 ]' _ "${j_exit}"
else
	echo "NOTE: no /dev/sd* block device found on this host; skipping G/H/I/J scenarios (device-dependent)" >&2
fi

#==========================================================
# K. shellprocess-livepurge.conf に新規2ファイルが削除対象として
#    追加されていること
#==========================================================
check "shellprocess-livepurge.conf is valid YAML" \
	python3 -c "
import yaml
with open('${LIVEPURGE_CONF}', encoding='utf-8') as f:
    yaml.safe_load(f)
"

check "shellprocess-livepurge.conf removes mypocketos-installer-reboot on the installed system" \
	python3 -c "
import yaml
data = yaml.safe_load(open('${LIVEPURGE_CONF}', encoding='utf-8'))
script = ' '.join(data.get('script', []))
assert '/usr/local/bin/mypocketos-installer-reboot' in script, script
assert 'rm -f' in script, script
"

check "shellprocess-livepurge.conf removes the new shutdown hook on the installed system" \
	python3 -c "
import yaml
data = yaml.safe_load(open('${LIVEPURGE_CONF}', encoding='utf-8'))
script = ' '.join(data.get('script', []))
assert '/usr/lib/systemd/system-shutdown/mypocketos-install-media-removal' in script, script
"

check "shellprocess-livepurge.conf still removes the original live-* packages (unrelated existing behavior untouched)" \
	python3 -c "
import yaml
data = yaml.safe_load(open('${LIVEPURGE_CONF}', encoding='utf-8'))
script = ' '.join(data.get('script', []))
assert 'apt-get --purge -q -y remove' in script, script
assert 'live-tools' in script, script
"

#==========================================================
# L. auto/config に noeject が残っていること (回帰確認)
#==========================================================
check "auto/config still specifies noeject in --bootappend-live (normal Live reboot behavior must be unchanged)" \
	grep -q 'bootappend-live.*noeject' "${AUTO_CONFIG}"

#==========================================================
# M. Debian標準ファイル (live-medium-eject / live-tools.shutdown) への
#    上書き・変更を一切追加していないこと
#==========================================================
check "no MyPocketOS override was added for /usr/bin/live-medium-eject" \
	sh -c '[ ! -e "$1" ]' _ "${REPO_ROOT}/config/includes.chroot/usr/bin/live-medium-eject"
check "no MyPocketOS override was added for /usr/lib/systemd/system-shutdown/live-tools.shutdown" \
	sh -c '[ ! -e "$1" ]' _ "${REPO_ROOT}/config/includes.chroot/usr/lib/systemd/system-shutdown/live-tools.shutdown"

echo "SCENARIOS=$((PASS + FAIL)) PASS=${PASS} FAIL=${FAIL}"
[ "${FAIL}" -eq 0 ]
