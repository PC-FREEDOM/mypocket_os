"""MyPocketOS ロゴ資産の生成スクリプト。

3×3ドットグリッドのロゴ候補3案(A/B/C)と、推奨案の正式資産 (SVG原本・透過PNG・
単色版・ロゴタイプ付き・明暗背景向け) を、同じ幾何定義から一括生成する。
SVGは手続きで書き出した純粋なベクター (円・角丸長方形・文字のアウトライン) で、
参考画像 (branding/reference/) のピクセルは一切使っていない。

必要なもの: Python 3、PyGObject (gi) 経由の Rsvg 2.0、pycairo。
ロゴタイプの文字は Liberation Sans Bold (SIL OFL 1.1) のアウトラインを cairo で
パス化して埋め込む (生成後のSVGはフォントに依存しない)。

使い方 (正式ロゴは候補C2):
    python3 generate_logo_assets.py --task all --final C2 --out <branding/logo のパス> --tmp <作業用ディレクトリ>
    python3 generate_logo_assets.py --task c-refinement --out <branding/logo のパス> --tmp <作業用ディレクトリ>
"""
import argparse
import math
import os
import sys

import cairo
import gi

gi.require_version("Rsvg", "2.0")
from gi.repository import Rsvg  # noqa: E402

FONT_FAMILY = "Liberation Sans"
BRAND = "MyPocketOS"

# ---- 色 (青〜シアン系 + ごく控えめなバイオレットのアクセント) -------------------
# 色数値は仮 (人間の最終確認前)。参考画像のパレットの方向性を、数値で独自に定義した。
DIAG_LIGHT = ["#0057D9", "#1573EA", "#2F8CFF", "#22A6FF", "#19C3FF"]
DIAG_DARK = ["#4A90FF", "#4FA0FF", "#55B2FF", "#3CC8FF", "#2FE0FF"]
A_LIGHT = [
    ["#0057D9", "#2F8CFF", "#74BEFF"],
    ["#14B5FF", "#2F8CFF", "#8F7BFF"],
    ["#74BEFF", "#74BEFF", "#7048F0"],
]
A_DARK = [
    ["#3D8BFF", "#5AA3FF", "#8FCBFF"],
    ["#2FD0FF", "#5AA3FF", "#A08CFF"],
    ["#8FCBFF", "#8FCBFF", "#8A63FF"],
]
ACCENT_LIGHT = "#8A6CFF"
ACCENT_DARK = "#A58BFF"

MONO_BLUE = "#0057D9"
MONO_WHITE = "#FFFFFF"
TEXT_NAVY = "#0A1F5C"   # ロゴタイプ (明背景) の "MyPocket"
TEXT_OS_LIGHT = "#0057D9"
TEXT_WHITE = "#FFFFFF"  # ロゴタイプ (暗背景) の "MyPocket"
TEXT_OS_DARK = "#5BB2FF"

# 候補Cの半径パラメータ (r0=左上の半径, step=対角線1段ごとの減少量)。中心位置・間隔(34)は全案共通。
#   C  : 初版      14.6 -> 11.0 (段差0.9)
#   C2 : 少し強めた 15.0 ->  9.0 (段差1.5)  <- 推奨候補
#   C3 : さらに強め 15.4 ->  6.6 (段差2.2)  <- 比較用
C_PARAMS = {"C": (14.6, 0.9), "C2": (15.0, 1.5), "C3": (15.4, 2.2)}

VIEW = 100.0  # 記号の描画領域 (正方形)
PAD = 4.0     # viewBoxに含める余白 (記号の周囲)


def f(v):
    s = ("%.2f" % v).rstrip("0").rstrip(".")
    return s if s else "0"


# ---- 候補の幾何定義 -----------------------------------------------------------
def dots(cand):
    """[(cx, cy, size_param, i(row), j(col))] を返す。"""
    out = []
    if cand == "A":  # 円・均一・標準間隔
        pitch, r0 = 34.0, 13.5
        for i in range(3):
            for j in range(3):
                out.append((16.0 + pitch * j, 16.0 + pitch * i, r0, i, j))
    elif cand == "B":  # 角丸正方形・均一・やや詰める
        pitch, half = 33.5, 14.0
        for i in range(3):
            for j in range(3):
                out.append((16.5 + pitch * j, 16.5 + pitch * i, half, i, j))
    elif cand in C_PARAMS:  # 円・左上から右下へ半径を段階的に小さく (r = r0 - step*(i+j))
        pitch = 34.0
        r0, step = C_PARAMS[cand]
        for i in range(3):
            for j in range(3):
                out.append((16.0 + pitch * j, 16.0 + pitch * i, r0 - step * (i + j), i, j))
    else:
        raise ValueError(cand)
    return out


def color_of(cand, i, j, mode):
    """mode: light / dark / mono-blue / mono-white"""
    if mode == "mono-blue":
        return MONO_BLUE
    if mode == "mono-white":
        return MONO_WHITE
    dark = mode == "dark"
    if cand == "A":
        return (A_DARK if dark else A_LIGHT)[i][j]
    diag = DIAG_DARK if dark else DIAG_LIGHT
    if cand in C_PARAMS and (i, j) == (2, 2):
        return ACCENT_DARK if dark else ACCENT_LIGHT
    return diag[i + j]


def symbol_elements(cand, mode, dx=0.0, dy=0.0):
    els = []
    for cx, cy, s, i, j in dots(cand):
        col = color_of(cand, i, j, mode)
        if cand == "B":
            els.append(
                '<rect x="%s" y="%s" width="%s" height="%s" rx="8.5" fill="%s"/>'
                % (f(cx - s + dx), f(cy - s + dy), f(2 * s), f(2 * s), col)
            )
        else:
            els.append('<circle cx="%s" cy="%s" r="%s" fill="%s"/>' % (f(cx + dx), f(cy + dy), f(s), col))
    return els


def symbol_svg(cand, mode, title):
    body = "\n  ".join(symbol_elements(cand, mode))
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="%s %s %s %s" width="512" height="512">\n'
        "  <title>%s</title>\n  %s\n</svg>\n" % (f(-PAD), f(-PAD), f(VIEW + 2 * PAD), f(VIEW + 2 * PAD), title, body)
    )


# ---- ロゴタイプ (文字をアウトライン化) ---------------------------------------
def text_path_d(text, x, baseline, size, tracking=0.0):
    """文字列をアウトライン化したSVGパスと、送り幅を返す (1文字ずつ配置・トラッキング付き)。"""
    surf = cairo.ImageSurface(cairo.FORMAT_ARGB32, 10, 10)
    cr = cairo.Context(surf)
    cr.select_font_face(FONT_FAMILY, cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
    cr.set_font_size(size)
    parts = []
    cx = x
    for ch in text:
        cr.new_path()
        cr.move_to(cx, baseline)
        cr.text_path(ch)
        for kind, pts in cr.copy_path():
            if kind == cairo.PATH_MOVE_TO:
                parts.append("M%s %s" % (f(pts[0]), f(pts[1])))
            elif kind == cairo.PATH_LINE_TO:
                parts.append("L%s %s" % (f(pts[0]), f(pts[1])))
            elif kind == cairo.PATH_CURVE_TO:
                parts.append("C%s %s %s %s %s %s" % tuple(f(v) for v in pts))
            elif kind == cairo.PATH_CLOSE_PATH:
                parts.append("Z")
        cx += cr.text_extents(ch).x_advance + tracking
    return "".join(parts), cx - x


def lockup_svg(cand, mode, title):
    """記号 + 'MyPocketOS'。mode: light / dark / mono-blue / mono-white"""
    size = 68.0
    cap = 0.729 * size  # Liberation Sans の大文字高さ (約0.729em)
    gap = 22.0
    tx = VIEW + gap
    baseline = VIEW / 2 + cap / 2
    if mode == "light":
        c1, c2 = TEXT_NAVY, TEXT_OS_LIGHT
    elif mode == "dark":
        c1, c2 = TEXT_WHITE, TEXT_OS_DARK
    elif mode == "mono-blue":
        c1 = c2 = MONO_BLUE
    else:
        c1 = c2 = MONO_WHITE
    d1, adv1 = text_path_d("MyPocket", tx, baseline, size, 2.0)
    d2, adv2 = text_path_d("OS", tx + adv1, baseline, size, 2.0)
    width = tx + adv1 + adv2 - 2.0
    sym = "\n  ".join(symbol_elements(cand, mode))
    vb_w, vb_h = width + 2 * PAD, VIEW + 2 * PAD
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="%s %s %s %s" width="%s" height="%s">\n'
        "  <title>%s</title>\n  %s\n"
        '  <path d="%s" fill="%s"/>\n  <path d="%s" fill="%s"/>\n</svg>\n'
        % (f(-PAD), f(-PAD), f(vb_w), f(vb_h), f(vb_w * 5.12), f(vb_h * 5.12), title, sym, d1, c1, d2, c2)
    ), width


# ---- PNG化 (書き出したSVGをRsvgで描画 = SVG自体の検証を兼ねる) --------------------
def svg_to_png(svg_path, png_path, width_px, bg=None):
    handle = Rsvg.Handle.new_from_file(svg_path)
    dim = handle.get_intrinsic_size_in_pixels()
    w0, h0 = (dim[1], dim[2]) if len(dim) == 3 else dim
    scale = width_px / w0
    w, h = int(round(w0 * scale)), int(round(h0 * scale))
    surf = cairo.ImageSurface(cairo.FORMAT_ARGB32, w, h)
    cr = cairo.Context(surf)
    if bg:
        cr.set_source_rgb(*bg)
        cr.paint()
    rect = Rsvg.Rectangle()
    rect.x, rect.y, rect.width, rect.height = 0, 0, w, h
    handle.render_document(cr, rect)
    surf.write_to_png(png_path)
    return w, h


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[k:k + 2], 16) / 255.0 for k in (0, 2, 4))


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)


# ---- 比較シート (レビュー用。ロゴ資産そのものではない) ------------------------------
def sheet(out_png, cands, tmpdir, title_lines):
    W, H = 1500, 1000
    surf = cairo.ImageSurface(cairo.FORMAT_RGB24, W, H)
    cr = cairo.Context(surf)
    cr.set_source_rgb(1, 1, 1)
    cr.paint()
    cr.select_font_face("DejaVu Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)

    def label(x, y, s, size=20, rgb=(0.1, 0.1, 0.2)):
        cr.set_source_rgb(*rgb)
        cr.set_font_size(size)
        cr.move_to(x, y)
        cr.show_text(s)

    label(30, 42, title_lines[0], 26)
    col_w = 480
    for n, (name, desc) in enumerate(cands):
        x0 = 30 + n * col_w
        label(x0, 92, "Candidate " + name, 22)
        label(x0, 118, desc, 14, (0.3, 0.3, 0.4))
        # 明背景/暗背景/単色(青)/単色(白) の大サイズ
        panels = [("light", (1, 1, 1), "light"), ("dark", hex_rgb("#0B1F4A"), "dark"),
                  ("mono", (1, 1, 1), "mono-blue"), ("mono", hex_rgb("#0B1F4A"), "mono-white")]
        for k, (_, bg, mode) in enumerate(panels):
            px, py = x0 + (k % 2) * 230, 140 + (k // 2) * 230
            cr.set_source_rgb(*bg)
            cr.rectangle(px, py, 215, 215)
            cr.fill()
            cr.set_source_rgb(0.85, 0.87, 0.92)
            cr.set_line_width(1)
            cr.rectangle(px + .5, py + .5, 214, 214)
            cr.stroke()
            p = os.path.join(tmpdir, "sheet_%s_%s.png" % (name, mode))
            svg_to_png(os.path.join(tmpdir, "sheet_%s_%s.svg" % (name, mode)), p, 170)
            img = cairo.ImageSurface.create_from_png(p)
            cr.set_source_surface(img, px + 22, py + 22)
            cr.paint()
        # 小サイズ列 (16/24/32/48px) 明・暗
        for row, (bg, mode) in enumerate([((1, 1, 1), "light"), (hex_rgb("#0B1F4A"), "dark"),
                                          ((1, 1, 1), "mono-blue")]):
            py = 610 + row * 110
            cr.set_source_rgb(*bg)
            cr.rectangle(x0, py, 440, 96)
            cr.fill()
            cr.set_source_rgb(0.85, 0.87, 0.92)
            cr.rectangle(x0 + .5, py + .5, 439, 95)
            cr.stroke()
            px = x0 + 14
            for size in (16, 24, 32, 48, 64):
                p = os.path.join(tmpdir, "sheet_%s_%s_%d.png" % (name, mode, size))
                svg_to_png(os.path.join(tmpdir, "sheet_%s_%s.svg" % (name, mode)), p, size)
                img = cairo.ImageSurface.create_from_png(p)
                cr.set_source_surface(img, px, py + (96 - size) / 2)
                cr.paint()
                px += size + 22
    label(30, 960, "small sizes: 16 / 24 / 32 / 48 / 64 px (rows: light bg, dark bg, mono blue)", 14, (0.3, 0.3, 0.4))
    surf.write_to_png(out_png)



# ---- 小サイズ確認シート (レビュー用。ロゴ資産そのものではない) ---------------------------
def preview(out_png, final_dir, tmpdir, wallpaper):
    W, H = 1500, 760
    surf = cairo.ImageSurface(cairo.FORMAT_RGB24, W, H)
    cr = cairo.Context(surf)
    cr.set_source_rgb(1, 1, 1)
    cr.paint()
    cr.select_font_face("DejaVu Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
    wp = cairo.ImageSurface.create_from_png(wallpaper) if wallpaper else None

    def panel(x, y, w, h, kind):
        if kind == "white":
            cr.set_source_rgb(1, 1, 1)
            cr.rectangle(x, y, w, h)
            cr.fill()
        elif kind == "navy":
            cr.set_source_rgb(*hex_rgb("#0B1F4A"))
            cr.rectangle(x, y, w, h)
            cr.fill()
        elif wp is not None:
            sx, sy = (0, 470) if kind == "wall-light" else (480, 60)
            cr.save()
            cr.rectangle(x, y, w, h)
            cr.clip()
            cr.set_source_surface(wp, x - sx, y - sy)
            cr.paint()
            cr.restore()
        cr.set_source_rgb(0.8, 0.83, 0.9)
        cr.set_line_width(1)
        cr.rectangle(x + .5, y + .5, w - 1, h - 1)
        cr.stroke()

    def put(svg_name, width_px, x, cy, key):
        """中心のy座標cyに合わせて配置する。"""
        p = os.path.join(tmpdir, "prev_%s_%d.png" % (key, width_px))
        w, h = svg_to_png(os.path.join(final_dir, svg_name), p, width_px)
        img = cairo.ImageSurface.create_from_png(p)
        cr.set_source_surface(img, x, cy - h / 2.0)
        cr.paint()
        return w, h

    def label(x, y, s, size=15):
        cr.set_source_rgb(0.1, 0.1, 0.2)
        cr.set_font_size(size)
        cr.move_to(x, y)
        cr.show_text(s)

    label(30, 36, "MyPocketOS logo small-size check (review sheet, not a final asset)", 22)
    rows = [
        ("white", "mypocketos-logo-symbol.svg", "mypocketos-logo-lockup.svg", "symbol/lockup on white (color)"),
        ("navy", "mypocketos-logo-symbol-dark-bg.svg", "mypocketos-logo-lockup-dark-bg.svg", "on navy #0B1F4A (dark-bg color)"),
        ("wall-light", "mypocketos-logo-symbol-dark-bg.svg", "mypocketos-logo-lockup-dark-bg.svg",
         "on the approved wallpaper, LIGHT area (dark-bg color: low contrast is expected - shows the limit)"),
        ("wall-deep", "mypocketos-logo-symbol-dark-bg.svg", "mypocketos-logo-lockup-dark-bg.svg",
         "on the approved wallpaper, deep-blue area (dark-bg color)"),
    ]
    y = 56
    for kind, sym, lock, cap in rows:
        label(30, y + 14, cap, 14)
        panel(30, y + 22, 1440, 140, kind)
        x = 50
        for size in (16, 24, 32, 48, 64, 96):
            w, h = put(sym, size, x, y + 22 + 70, kind + "s")
            x += size + 26
        x += 30
        for wpx in (150, 260, 380):
            w, h = put(lock, wpx, x, y + 22 + 70, kind + "l")
            x += wpx + 30
        y += 176
    surf.write_to_png(out_png)


# ---- 候補C改良版 (サイズグラデーションの強さの比較) ------------------------------
def c_metrics(cand):
    """半径・間隔・各表示サイズでのドット直径(px)を計算して返す(推測でなく幾何から算出)。"""
    ds = dots(cand)
    radii = sorted({round(d[2], 2) for d in ds}, reverse=True)
    gaps = []
    for a in ds:
        for b in ds:
            if (b[3], b[4]) in ((a[3], a[4] + 1), (a[3] + 1, a[4])):
                gaps.append(math.hypot(a[0] - b[0], a[1] - b[1]) - a[2] - b[2])
    r0, step = C_PARAMS[cand]
    out = {"radii": radii, "ratio_small_to_large": radii[-1] / radii[0], "min_gap_units": min(gaps),
           "step_units": step, "px": {}}
    for size in (16, 24, 32, 48, 64):
        ppu = size / (VIEW + 2 * PAD)
        out["px"][size] = {"largest_diam": 2 * radii[0] * ppu, "smallest_diam": 2 * radii[-1] * ppu,
                           "step_diff": 2 * step * ppu, "gap_min": min(gaps) * ppu}
    return out


def small_size_check(out_png, variants, tmpdir):
    """16/24/32/48/64px の実寸表示と、16/24pxの画素拡大 (最近傍・10倍) を並べる。"""
    W = 1500
    block_h = 292
    H = 70 + block_h * len(variants)
    surf = cairo.ImageSurface(cairo.FORMAT_RGB24, W, H)
    cr = cairo.Context(surf)
    cr.set_source_rgb(1, 1, 1)
    cr.paint()
    cr.select_font_face("DejaVu Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)

    def label(x, y, s, size=15, rgb=(0.1, 0.1, 0.2)):
        cr.set_source_rgb(*rgb)
        cr.set_font_size(size)
        cr.move_to(x, y)
        cr.show_text(s)

    label(30, 38, "MyPocketOS candidate C refinement - small size check (review sheet, not a final asset)", 22)
    navy = hex_rgb("#0B1F4A")
    for n, (name, desc) in enumerate(variants):
        y0 = 62 + n * block_h
        label(30, y0 + 16, "%s  %s" % (name, desc), 18)
        strips = [("light", (1, 1, 1), "light"), ("dark", navy, "dark"), ("mono", (1, 1, 1), "mono-blue")]
        for k, (_, bg, mode) in enumerate(strips):
            py = y0 + 30 + k * 80
            cr.set_source_rgb(*bg)
            cr.rectangle(30, py, 640, 72)
            cr.fill()
            cr.set_source_rgb(0.82, 0.85, 0.92)
            cr.set_line_width(1)
            cr.rectangle(30.5, py + .5, 639, 71)
            cr.stroke()
            svg = os.path.join(tmpdir, "sheet_%s_%s.svg" % (name, mode))
            x = 50
            for size in (16, 24, 32, 48, 64):
                p = os.path.join(tmpdir, "ss_%s_%s_%d.png" % (name, mode, size))
                svg_to_png(svg, p, size)
                img = cairo.ImageSurface.create_from_png(p)
                cr.set_source_surface(img, x, py + (72 - size) / 2.0)
                cr.paint()
                label(x, py + 68, "%d" % size, 10, (0.5, 0.5, 0.6) if bg == (1, 1, 1) else (0.7, 0.75, 0.85))
                x += size + 44
        # 画素拡大 (最近傍・10倍): 16px と 24px。実際にどの画素になるかを見る
        zx = 700
        for size, lab in ((16, "16px x10 (nearest)"), (24, "24px x10 (nearest)")):
            p = os.path.join(tmpdir, "ss_%s_zoom_%d.png" % (name, size))
            svg_to_png(os.path.join(tmpdir, "sheet_%s_light.svg" % name), p, size)
            img = cairo.ImageSurface.create_from_png(p)
            zoom = 10
            cr.set_source_rgb(1, 1, 1)
            cr.rectangle(zx, y0 + 30, size * zoom + 12, size * zoom + 12)
            cr.fill()
            cr.set_source_rgb(0.82, 0.85, 0.92)
            cr.rectangle(zx + .5, y0 + 30.5, size * zoom + 11, size * zoom + 11)
            cr.stroke()
            cr.save()
            cr.translate(zx + 6, y0 + 36)
            cr.scale(zoom, zoom)
            pat = cairo.SurfacePattern(img)
            pat.set_filter(cairo.FILTER_NEAREST)
            cr.set_source(pat)
            cr.paint()
            cr.restore()
            label(zx, y0 + 30 + size * zoom + 28, lab, 12, (0.4, 0.4, 0.5))
            zx += size * zoom + 40
    surf.write_to_png(out_png)


def refine(a):
    """候補C改良版: C (初版) / C2 (少し強め) / C3 (さらに強め) の比較。final/ は生成しない。"""
    variants = [("C", "v1 (current): r 14.6 -> 11.0"),
                ("C2", "moderate+: r 15.0 -> 9.0"),
                ("C3", "strong: r 15.4 -> 6.6")]
    for name, _ in variants:
        for mode in ("light", "dark", "mono-blue", "mono-white"):
            write(os.path.join(a.tmp, "sheet_%s_%s.svg" % (name, mode)), symbol_svg(name, mode, "sheet"))
    for name in ("C2", "C3"):
        write(os.path.join(a.out, "candidates", "mypocketos-logo-candidate-%s.svg" % name.lower()),
              symbol_svg(name, "light", "MyPocketOS logo candidate %s" % name))
    sheet(os.path.join(a.out, "candidates", "mypocketos-logo-candidate-c-refinement-overview.png"),
          variants, a.tmp, ["MyPocketOS candidate C refinement (review sheet, not a final asset)"])
    small_size_check(os.path.join(a.out, "preview", "mypocketos-logo-candidate-c-small-size-check.png"),
                     variants, a.tmp)
    for name, _ in variants:
        m = c_metrics(name)
        print(name, "radii", m["radii"], "ratio %.3f" % m["ratio_small_to_large"],
              "min_gap_units %.2f" % m["min_gap_units"])
        for size, v in m["px"].items():
            print("   %2dpx: largest %.2f smallest %.2f step %.2f min_gap %.2f" %
                  (size, v["largest_diam"], v["smallest_diam"], v["step_diff"], v["gap_min"]))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True, help="branding/logo ディレクトリ")
    ap.add_argument("--final", choices=["A", "B", "C", "C2", "C3"],
                    help="task=all のとき必須。最終案として正式資産一式 (final/) を生成する候補")
    ap.add_argument("--task", choices=["all", "c-refinement"], default="all",
                    help="all: 候補A/B/Cの比較+final/の生成。c-refinement: 候補C改良版(C/C2/C3)の比較シートと"
                         "小サイズ確認のみ (final/ には一切触れない)")
    ap.add_argument("--tmp", required=True, help="作業用ディレクトリ (成果物ではない)")
    ap.add_argument("--wallpaper", help="承認済み壁紙PNG (小サイズ確認シートの背景用。任意)")
    a = ap.parse_args()
    os.makedirs(a.tmp, exist_ok=True)
    os.makedirs(os.path.join(a.out, "preview"), exist_ok=True)

    if a.task == "c-refinement":
        refine(a)
        return
    if not a.final:
        ap.error("--final is required when --task all")

    descs = {
        "A": "round, uniform, blue + violet",
        "B": "rounded squares, tight, blue-cyan",
        "C": "round, size steps, 1 accent dot",
    }
    # 候補 (記号のみ・明背景用カラー)
    for c in "ABC":
        write(os.path.join(a.out, "candidates", "mypocketos-logo-candidate-%s.svg" % c.lower()),
              symbol_svg(c, "light", "MyPocketOS logo candidate %s" % c))
        for mode in ("light", "dark", "mono-blue", "mono-white"):
            write(os.path.join(a.tmp, "sheet_%s_%s.svg" % (c, mode)),
                  symbol_svg(c, mode, "sheet"))
    sheet(os.path.join(a.out, "candidates", "mypocketos-logo-candidates-overview.png"),
          [(c, descs[c]) for c in "ABC"], a.tmp,
          ["MyPocketOS logo candidates (review sheet, not a final asset)"])

    # 最終推奨案の正式資産
    c = a.final
    fin = os.path.join(a.out, "final")
    names = {"light": "", "dark": "-dark-bg", "mono-blue": "-mono", "mono-white": "-mono-white"}
    for mode, suf in names.items():
        write(os.path.join(fin, "mypocketos-logo-symbol%s.svg" % suf),
              symbol_svg(c, mode, "MyPocketOS logo symbol"))
        svg, width = lockup_svg(c, mode, "MyPocketOS logo")
        write(os.path.join(fin, "mypocketos-logo-lockup%s.svg" % suf), svg)
    for mode, suf in names.items():
        svg_to_png(os.path.join(fin, "mypocketos-logo-symbol%s.svg" % suf),
                   os.path.join(fin, "mypocketos-logo-symbol%s-1024.png" % suf), 1024)
        svg_to_png(os.path.join(fin, "mypocketos-logo-symbol%s.svg" % suf),
                   os.path.join(fin, "mypocketos-logo-symbol%s-256.png" % suf), 256)
        svg_to_png(os.path.join(fin, "mypocketos-logo-lockup%s.svg" % suf),
                   os.path.join(fin, "mypocketos-logo-lockup%s-2400.png" % suf), 2400)
    preview(os.path.join(a.out, "preview", "mypocketos-logo-small-size-check.png"), fin, a.tmp, a.wallpaper)
    print("done; final candidate =", c)


if __name__ == "__main__":
    sys.exit(main())
