#!/bin/sh
#
# MyPocketOS独自のCalamares branding
# (config/includes.chroot/etc/calamares/branding/mypocketos/) に対する
# 静的テスト。実Calamares・実ISO・実インストールは一切使用しない
# (ファイル・設定の読み取りのみ)。
#
# 背景: Calamaresは branding.desc の images に列挙した画像や slideshow の
# QMLファイルが存在しないと、起動時にFATALで終了する (Calamares 3.3.14
# Branding.cpp)。componentName とディレクトリ名の不一致も同様にFATAL。
# 本テストはその参照ミスを、インストーラーが起動できなくなる前に検出する。
#
# 確認する設計:
#   - branding component (mypocketos) の配置・componentName・settings.conf の選択
#   - strings の値 (MyPocketOS / 0.1 / 公式URL / releaseNotesUrl 空) と、
#     Calamares 3.3.14 に存在しないキーを作っていないこと
#   - images・slideshow が実在し、画像が branding/logo/final/ の正式シンボル
#     (C2、文字なし) であること (ロゴタイプ資産を使っていないこと)。
#     productLogo・productWelcome は透明キャンバスを保ったまま縮小した画像
#     (productLogo は縦方向に下寄せ) で、見かけ上のサイズと位置を確認する。
#     show.qml が使う welcome.png と productIcon は縮小なしの複製
#   - Debianの文字列・URLが残っていないこと、Debian提供のbrandingを
#     リポジトリ側で書き換え・複製していないこと
#   - style が有効な4項目のみで、文字色との可読性を満たすこと
#   - Base/Standard共通 (config/includes.chroot) であること
#
# bootloaderEntryName は、ESP上のEFIブートローダーID・NVRAMのブート
# エントリ名・GRUB_DISTRIBUTOR にも影響する。本テストは値の確認だけであり、
# UEFI・Secure Boot・Legacy BIOSでの実インストールと起動は実機での確認が別途
# 必要 (本テストの対象外)。
#
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHROOT_INC="${REPO_ROOT}/config/includes.chroot"
BRANDING_DIR="${CHROOT_INC}/etc/calamares/branding/mypocketos"
DESC="${BRANDING_DIR}/branding.desc"
SETTINGS_CONF="${CHROOT_INC}/etc/calamares/settings.conf"
LOGO_FINAL="${REPO_ROOT}/branding/logo/final"
COMMON_LIST="${REPO_ROOT}/config/package-lists.d/mypocketos-common.list.chroot"
STANDARD_LIST="${REPO_ROOT}/config/package-lists.d/mypocketos-standard.list.chroot"
BUILD_SH="${REPO_ROOT}/scripts/build.sh"

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

# branding.desc をYAMLとして読み込むPython共通前置き。
PY_HEAD="
import os, re, yaml
D = '${BRANDING_DIR}'
desc = yaml.safe_load(open('${DESC}', encoding='utf-8'))
strings = desc['strings']
"

# 標準ライブラリだけでPNG (8bit RGBA・非インターレース) を読み、不透明部分の
# 外接矩形と不透明画素の色集合を返す。
PY_PNG="
import struct, zlib
def read_png(path):
    d = open(path, 'rb').read()
    assert d[:8] == b'\\x89PNG\\r\\n\\x1a\\n', 'not a PNG'
    i = 8; idat = b''
    while i < len(d):
        n, typ = struct.unpack('>I4s', d[i:i+8]); c = d[i+8:i+8+n]
        if typ == b'IHDR':
            w, h, bd, ct, _, _, il = struct.unpack('>IIBBBBB', c)
            assert (bd, ct, il) == (8, 6, 0), (bd, ct, il)
        if typ == b'IDAT': idat += c
        i += 12 + n
    raw = zlib.decompress(idat); st = w * 4; prev = bytearray(st); pos = 0
    xs = []; ys = []; opaque = set()
    for y in range(h):
        f = raw[pos]; line = bytearray(raw[pos+1:pos+1+st]); pos += 1 + st
        for x in range(st):
            a = line[x-4] if x >= 4 else 0; b = prev[x]; c_ = prev[x-4] if x >= 4 else 0
            if f == 1: line[x] = (line[x] + a) & 255
            elif f == 2: line[x] = (line[x] + b) & 255
            elif f == 3: line[x] = (line[x] + (a + b) // 2) & 255
            elif f == 4:
                pa, pb, pc = abs(b - c_), abs(a - c_), abs(a + b - 2 * c_)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else (b if pb <= pc else c_))) & 255
        for x in range(w):
            al = line[x*4+3]
            if al > 0: xs.append(x); ys.append(y)
            if al == 255: opaque.add(bytes(line[x*4:x*4+3]))
        prev = line
    return (w, h), (min(xs), min(ys), max(xs), max(ys)), opaque
def apparent_ratio(new, ref, dy_range=(-2, 2)):
    (nw, nh), nb, no = read_png(new); (rw, rh), rb, ro = read_png(ref)
    assert (nw, nh) == (256, 256) and (rw, rh) == (256, 256), ((nw, nh), (rw, rh))
    wr = (nb[2] - nb[0] + 1) / (rb[2] - rb[0] + 1)
    hr = (nb[3] - nb[1] + 1) / (rb[3] - rb[1] + 1)
    # 横方向の中心は動かない (±2px以内)。縦方向の中心は、元の256px版に対する
    # 下方向のずれ (px) が dy_range の範囲内であること (既定は動かない)。
    assert abs((nb[0] + nb[2]) / 2 - (rb[0] + rb[2]) / 2) <= 2, (nb, rb)
    dy = (nb[1] + nb[3]) / 2 - (rb[1] + rb[3]) / 2
    assert dy_range[0] <= dy <= dy_range[1], ('dy', dy, nb, rb)
    # 縮小後の不透明画素の色は、元のシンボル (明/暗の版) に含まれる色だけ
    assert no and no <= ro, 'colours differ from the reference symbol'
    return wr, hr
"

# ---- 配置 -------------------------------------------------------------------
check "branding directory exists" test -d "${BRANDING_DIR}"
check "branding.desc exists" test -f "${DESC}"
check "branding.desc is valid YAML (a mapping)" \
	python3 -c "${PY_HEAD}
assert isinstance(desc, dict)"
check "componentName is mypocketos" \
	python3 -c "${PY_HEAD}
assert desc['componentName'] == 'mypocketos', desc['componentName']"
check "componentName equals the directory name (mismatch is FATAL in Calamares)" \
	python3 -c "${PY_HEAD}
assert desc['componentName'] == os.path.basename(D), (desc['componentName'], os.path.basename(D))"
check "settings.conf selects 'branding: mypocketos'" \
	python3 -c "
import yaml
s = yaml.safe_load(open('${SETTINGS_CONF}', encoding='utf-8'))
assert s['branding'] == 'mypocketos', s['branding']"
check "settings.conf has exactly one active branding: line" \
	sh -c '[ "$(grep -Ec "^branding:" "$1")" -eq 1 ]' _ "${SETTINGS_CONF}"

# ---- strings ----------------------------------------------------------------
check "productName / shortProductName are MyPocketOS" \
	python3 -c "${PY_HEAD}
assert strings['productName'] == 'MyPocketOS', strings['productName']
assert strings['shortProductName'] == 'MyPocketOS', strings['shortProductName']"
check "version / shortVersion are the string '0.1'" \
	python3 -c "${PY_HEAD}
assert strings['version'] == '0.1', repr(strings['version'])
assert strings['shortVersion'] == '0.1', repr(strings['shortVersion'])"
check "versionedName / shortVersionedName are 'MyPocketOS 0.1'" \
	python3 -c "${PY_HEAD}
assert strings['versionedName'] == 'MyPocketOS 0.1', strings['versionedName']
assert strings['shortVersionedName'] == 'MyPocketOS 0.1', strings['shortVersionedName']"
check "bootloaderEntryName is MyPocketOS" \
	python3 -c "${PY_HEAD}
assert strings['bootloaderEntryName'] == 'MyPocketOS', strings['bootloaderEntryName']"
check "productUrl is the official GitHub repository" \
	python3 -c "${PY_HEAD}
assert strings['productUrl'] == 'https://github.com/PC-FREEDOM/mypocket_os', strings['productUrl']"
check "supportUrl is the GitHub issues page" \
	python3 -c "${PY_HEAD}
assert strings['supportUrl'] == 'https://github.com/PC-FREEDOM/mypocket_os/issues', strings['supportUrl']"
check "knownIssuesUrl is the GitHub issues page" \
	python3 -c "${PY_HEAD}
assert strings['knownIssuesUrl'] == 'https://github.com/PC-FREEDOM/mypocket_os/issues', strings['knownIssuesUrl']"
check "releaseNotesUrl is empty (hides the welcome button; no release notes yet)" \
	python3 -c "${PY_HEAD}
assert 'releaseNotesUrl' in strings, 'key missing (intent must be explicit)'
assert strings['releaseNotesUrl'] in ('', None), repr(strings['releaseNotesUrl'])"
check "donateUrl is unused (absent or empty)" \
	python3 -c "${PY_HEAD}
assert strings.get('donateUrl') in ('', None), repr(strings.get('donateUrl'))"
# Calamares 3.3.14 (Branding.cpp) が読む strings キーだけを使うこと。
# welcomeText・bugReportUrl などは存在しないキー。
check "strings uses only keys that Calamares 3.3.14 reads" \
	python3 -c "${PY_HEAD}
valid = {'productName', 'version', 'shortVersion', 'versionedName', 'shortVersionedName',
         'shortProductName', 'bootloaderEntryName', 'productUrl', 'supportUrl',
         'knownIssuesUrl', 'releaseNotesUrl', 'donateUrl'}
extra = set(strings) - valid
assert not extra, extra"
check "strings do not use \${...} os-release expansion (would expand to Debian)" \
	python3 -c "${PY_HEAD}
for k, v in strings.items():
    assert '\$' not in str(v), (k, v)"
check "no Debian name or debian.org URL remains in branding.desc strings" \
	python3 -c "${PY_HEAD}
for k, v in strings.items():
    assert not re.search(r'debian', str(v or ''), re.I), (k, v)"
check "no 'Debian' remains anywhere in the branding directory text files" \
	sh -c '! grep -rIi "debian" "$1" | grep -v "^[^:]*branding.desc:#"' _ "${BRANDING_DIR}"
check "welcomeStyleCalamares is kept as true" \
	python3 -c "${PY_HEAD}
assert desc['welcomeStyleCalamares'] is True, desc['welcomeStyleCalamares']"

# ---- images / slideshow (参照ミスはCalamaresのFATAL) -----------------------
check "images defines productLogo, productIcon and productWelcome" \
	python3 -c "${PY_HEAD}
for k in ('productLogo', 'productIcon', 'productWelcome'):
    assert desc['images'].get(k), k"
check "images uses only known image keys and no wallpaper/banner (out of scope)" \
	python3 -c "${PY_HEAD}
assert set(desc['images']) == {'productLogo', 'productIcon', 'productWelcome'}, set(desc['images'])"
check "every file referenced in images exists in the branding directory" \
	python3 -c "${PY_HEAD}
for k, v in desc['images'].items():
    p = os.path.join(D, v)
    assert os.path.isfile(p), (k, p)"
check "every referenced image is a PNG" \
	python3 -c "${PY_HEAD}
for k, v in desc['images'].items():
    assert open(os.path.join(D, v), 'rb').read(8) == b'\x89PNG\r\n\x1a\n', (k, v)"
check "slideshow is defined, ends with .qml and exists" \
	python3 -c "${PY_HEAD}
s = desc['slideshow']
assert s.endswith('.qml'), s
assert os.path.isfile(os.path.join(D, s)), s"
check "slideshowAPI is 2" \
	python3 -c "${PY_HEAD}
assert desc['slideshowAPI'] == 2, desc['slideshowAPI']"
check "show.qml imports calamares.slideshow and defines Presentation and Slide" \
	sh -c 'grep -q "import calamares.slideshow 1.0" "$1" && grep -q "^Presentation" "$1" && grep -q "Slide {" "$1"' _ "${BRANDING_DIR}/show.qml"
check "show.qml has balanced braces" \
	python3 -c "
t = open('${BRANDING_DIR}/show.qml', encoding='utf-8').read()
assert t.count('{') == t.count('}'), (t.count('{'), t.count('}'))"
check "show.qml image sources all exist in the branding directory" \
	python3 -c "
import os, re
D = '${BRANDING_DIR}'
t = open(os.path.join(D, 'show.qml'), encoding='utf-8').read()
srcs = re.findall(r'source:\s*\"([^\"]+)\"', t)
assert srcs, 'no image source found'
for s in srcs:
    assert os.path.isfile(os.path.join(D, s)), s"
check "show.qml mentions MyPocketOS" \
	grep -q "MyPocketOS" "${BRANDING_DIR}/show.qml"

# ---- 画像資産: 正式シンボル (C2、文字なし) の複製であること ---------------
# logo.png / welcome-logo.png は、256x256の透明キャンバスを保ったまま、正式
# シンボル (SVGから描画) を中央で縮小して余白を増やした画像 (VM確認後の調整)。
# 見かけ上のサイズ (不透明部分の外接矩形の幅・高さ) を、縮小前の256px版
# PNGとの比で確認する。
check "productLogo image is logo.png and productWelcome image is welcome-logo.png" \
	python3 -c "${PY_HEAD}
assert desc['images']['productLogo'] == 'logo.png', desc['images']['productLogo']
assert desc['images']['productWelcome'] == 'welcome-logo.png', desc['images']['productWelcome']
assert desc['images']['productIcon'] == 'icon.png', desc['images']['productIcon']"
# logo.png (サイドバー) は、VM確認後の再調整で、さらに約10%縮小し (元の256px版
# の約70%)、キャンバス内で下へ約8px寄せた (サイドバー上部の上下余白を揃える
# ため)。元の256px版の外接矩形の中心に対して、縦方向に +6〜+11px 下寄りで
# あること。
check "logo.png (sidebar) is the dark-bg symbol on a 256x256 transparent canvas, apparent size 68-72%, shifted down 6-11px" \
	python3 -c "${PY_PNG}
wr, hr = apparent_ratio('${BRANDING_DIR}/logo.png', '${LOGO_FINAL}/mypocketos-logo-symbol-dark-bg-256.png', dy_range=(6, 11))
assert 0.68 <= wr <= 0.72 and 0.68 <= hr <= 0.72, (wr, hr)"
check "welcome-logo.png is the standard symbol on a 256x256 transparent canvas, apparent size 65-70%" \
	python3 -c "${PY_PNG}
wr, hr = apparent_ratio('${BRANDING_DIR}/welcome-logo.png', '${LOGO_FINAL}/mypocketos-logo-symbol-256.png')
assert 0.65 <= wr <= 0.70 and 0.65 <= hr <= 0.70, (wr, hr)"
check "productIcon (icon.png) is identical to mypocketos-logo-symbol-256.png (not shrunk)" \
	sh -c 'cmp -s "$1/icon.png" "$2/mypocketos-logo-symbol-256.png"' _ "${BRANDING_DIR}" "${LOGO_FINAL}"
# show.qml (スライドショー) は welcome.png を読む。スライドショーの見た目を
# 変えないため、welcome.png は縮小なしの標準シンボルのまま保つ。
check "welcome.png (used by show.qml) is identical to mypocketos-logo-symbol-256.png (slideshow unchanged)" \
	sh -c 'cmp -s "$1/welcome.png" "$2/mypocketos-logo-symbol-256.png"' _ "${BRANDING_DIR}" "${LOGO_FINAL}"
check "show.qml still loads welcome.png" \
	grep -q 'source: "welcome.png"' "${BRANDING_DIR}/show.qml"
# サイドバーロゴ (logo.png) だけを再調整した際に、ウェルカム画面・スライドショー
# が意図せず変わらないよう、内容をSHA-256で固定する。これらを意図して変更
# する場合は、ここのハッシュも更新すること。
check "welcome-logo.png is unchanged (SHA-256 pinned)" \
	sh -c '[ "$(sha256sum "$1/welcome-logo.png" | cut -d" " -f1)" = "25d178e8a3f69c0993c08fcc562af8d5d9f213d8c3fb1b230a0d7e37cb04f6fc" ]' _ "${BRANDING_DIR}"
check "show.qml (slideshow) is unchanged (SHA-256 pinned)" \
	sh -c '[ "$(sha256sum "$1/show.qml" | cut -d" " -f1)" = "76054673d52faa04255a3b6705c12b0f68f0a46e446ebe53f61d6268f99fd5d9" ]' _ "${BRANDING_DIR}"
check "no logotype (lockup) asset is used: no file in the branding dir equals a lockup file" \
	sh -c 'for f in "$1"/*; do for l in "$2"/mypocketos-logo-lockup*; do ! cmp -s "$f" "$l" || exit 1; done; done' _ "${BRANDING_DIR}" "${LOGO_FINAL}"
check "no file or reference named 'lockup' in the branding directory" \
	sh -c '! find "$1" -iname "*lockup*" | grep -q . && ! grep -rIiq "lockup" "$1"' _ "${BRANDING_DIR}"
check "branding directory holds only the expected files (no wallpaper/stylesheet/lang yet)" \
	sh -c '[ "$(ls -1 "$1" | sort | tr "\n" " ")" = "branding.desc icon.png logo.png show.qml welcome-logo.png welcome.png " ]' _ "${BRANDING_DIR}"

# ---- 配色: 有効な4項目のみ・可読性 ------------------------------------------
check "style uses exactly the four valid keys" \
	python3 -c "${PY_HEAD}
valid = {'SidebarBackground', 'SidebarBackgroundCurrent', 'SidebarText', 'SidebarTextCurrent'}
assert set(desc['style']) == valid, set(desc['style'])"
check "style colours are #RRGGBB" \
	python3 -c "${PY_HEAD}
for k, v in desc['style'].items():
    assert re.fullmatch(r'#[0-9A-Fa-f]{6}', v), (k, v)"
check "sidebar text contrast on background is at least 7:1 (WCAG AAA)" \
	python3 -c "${PY_HEAD}
def lum(h):
    c = [int(h[i:i+2], 16) / 255 for i in (1, 3, 5)]
    c = [x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
def cr(a, b):
    hi, lo = sorted([lum(a), lum(b)], reverse=True)
    return (hi + 0.05) / (lo + 0.05)
s = desc['style']
r = cr(s['SidebarBackground'], s['SidebarText'])
assert r >= 7, r"
check "current-item text contrast on its background is at least 4.5:1 (WCAG AA)" \
	python3 -c "${PY_HEAD}
def lum(h):
    c = [int(h[i:i+2], 16) / 255 for i in (1, 3, 5)]
    c = [x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
def cr(a, b):
    hi, lo = sorted([lum(a), lum(b)], reverse=True)
    return (hi + 0.05) / (lo + 0.05)
s = desc['style']
r = cr(s['SidebarBackgroundCurrent'], s['SidebarTextCurrent'])
assert r >= 4.5, r"

# ---- Debian提供のbrandingを書き換えていないこと ------------------------------
check "Debian branding directory (calamares-settings-debian) is not shipped by the repo" \
	test ! -e "${CHROOT_INC}/etc/calamares/branding/debian"
check "no calamares files are shipped under /usr/share/calamares by the repo" \
	test ! -e "${CHROOT_INC}/usr/share/calamares"
check "Debian 'Install Debian' launcher is not overridden here (separate task)" \
	sh -c 'test ! -e "$1/usr/share/applications/calamares-install-debian.desktop" && test ! -e "$1/usr/share/pixmaps/install-debian.png"' _ "${CHROOT_INC}"
check "no stylesheet.qss / productWallpaper yet (out of scope)" \
	sh -c '! test -e "$1/stylesheet.qss" && ! grep -q "productWallpaper" "$2"' _ "${BRANDING_DIR}" "${DESC}"

# ---- Base/Standard共通 -------------------------------------------------------
check "calamares is in the common package list exactly once" \
	sh -c '[ "$(grep -cx "calamares" "$1")" -eq 1 ]' _ "${COMMON_LIST}"
check "standard list does not add a separate calamares (no Base/Standard split)" \
	sh -c '! grep -qx "calamares" "$1"' _ "${STANDARD_LIST}"
check "no edition-specific calamares branding directory exists" \
	sh -c '! find "$1/config" -path "*calamares/branding*" -not -path "$1/config/includes.chroot/*" | grep -q .' _ "${REPO_ROOT}"
check "build.sh does not switch config/includes.chroot per edition" \
	sh -c '! grep -q "includes.chroot" "$1"' _ "${BUILD_SH}"
check "build.sh copies the common list unconditionally" \
	grep -qxF 'cp -- "${COMMON_SRC}" "${COMMON_DEST}"' "${BUILD_SH}"

echo "SCENARIOS=$((PASS + FAIL)) PASS=${PASS} FAIL=${FAIL}"
[ "${FAIL}" -eq 0 ]
