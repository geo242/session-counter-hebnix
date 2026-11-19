"""Render listing/banner.png (1600x900) for the Hebnix plugin portal.

    python -m pip install pillow
    python tools/make_banner.py

Uses Segoe UI from C:/Windows/Fonts, the same face the overlay uses. The counter on the right
follows the plugin's layout (LAYOUT in session_counter/main.lua) and default colors, scaled up.
Matches the style of the Lobby Ranks banner.
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "listing" / "banner.png"
FONTS = Path("C:/Windows/Fonts")

W, H = 1600, 900
BG = (17, 24, 39)
WHITE = (243, 244, 246)
MUTED = (156, 163, 175)

# plugin defaults
LABEL = (184, 176, 200)
WINS = (74, 222, 128)
LOSSES = (248, 113, 113)
DASH = (91, 83, 104)
STREAK = (145, 70, 255)

LINE = 1.33  # Segoe UI line box per px of font size
_fonts = {}


def font(name: str, size: float) -> ImageFont.FreeTypeFont:
    key = (name, round(size, 2))
    if key not in _fonts:
        _fonts[key] = ImageFont.truetype(str(FONTS / name), size)
    return _fonts[key]


def bold(size: float) -> ImageFont.FreeTypeFont:
    return font("segoeuib.ttf", size)


def measure(d: ImageDraw.ImageDraw, text: str, size: float) -> float:
    return d.textlength(text, font=bold(size))


def text_in_line(d, x, y, line_h, text, size, fill):
    """Like the plugin: the text's line box starts at y and is line_h tall."""
    d.text((x, y + (line_h - size * LINE) / 2), text, font=bold(size), fill=fill, anchor="la")


def counter(d: ImageDraw.ImageDraw, ox: float, oy: float, s: float, mode: str, w: int, l: int, streak: str):
    """Draw the counter with its top-left at (ox, oy) at scale s. Returns (width, height)."""
    pad_x, pad_y = 10 * s, 4 * s
    label_size, spacing = 17 * s, 2.5 * s
    num_size, dash_size, streak_size = 58 * s, 40 * s, 16 * s
    gap = 10 * s
    label_h = label_size * LINE
    num_h = num_size * 1.05
    dash_h = dash_size * LINE
    streak_lh = streak_size * 1.15
    row_h = max(num_h, dash_h, streak_lh * 2)

    x, y = ox + pad_x, oy + pad_y
    for ch in mode.upper():
        text_in_line(d, x, y, label_h, ch, label_size, LABEL)
        x += measure(d, ch, label_size) + spacing
    label_w = x - (ox + pad_x)
    y += label_h

    mid = y + row_h / 2
    x = ox + pad_x
    for text, size, h, color in ((str(w), num_size, num_h, WINS), ("\u2013", dash_size, dash_h, DASH),
                                 (str(l), num_size, num_h, LOSSES)):
        text_in_line(d, x, mid - h / 2, h, text, size, color)
        x += measure(d, text, size) + gap
    x += 6 * s

    lines, current = [], None
    for word in streak.split():
        candidate = f"{current} {word}" if current else word
        if current and measure(d, candidate, streak_size) > 70 * s:
            lines.append(current)
            current = word
        else:
            current = candidate
    if current:
        lines.append(current)
    top = mid - len(lines) * streak_lh / 2
    for i, line in enumerate(lines):
        text_in_line(d, x, top + i * streak_lh, streak_lh, line, streak_size, STREAK)

    row_w = x + 70 * s - (ox + pad_x)
    return pad_x * 2 + max(label_w, row_w), pad_y * 2 + label_h + row_h


def main() -> None:
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img, "RGBA")

    # left: title + tagline (same placement as the Lobby Ranks banner)
    title = font("segoeuib.ttf", 96)
    x, y = 100, 300
    d.text((x, y), "Session", font=title, fill=WHITE)
    d.text((x + d.textlength("Session ", font=title), y), "Counter", font=title, fill=STREAK)
    tag = font("segoeui.ttf", 34)
    d.text((x + 4, y + 160), "Your win/loss record for each game mode,", font=tag, fill=MUTED)
    d.text((x + 4, y + 206), "right on your screen while you play.", font=tag, fill=MUTED)
    d.text((x + 4, 250), "ROCKET LEAGUE  \u2022  HEBNIX PLUGIN", font=font("segoeuib.ttf", 24), fill=(107, 114, 128))

    # right: the counter on a dark panel, plus a second mode underneath
    scale = 2.0
    probe = ImageDraw.Draw(Image.new("RGB", (1, 1)))
    cw, ch = counter(probe, 0, 0, scale, "Ranked Snow Day", 7, 3, "3 win streak")
    small = 1.1
    sw, sh = counter(probe, 0, 0, small, "Ranked 2v2", 4, 2, "2 loss streak")
    pad, between = 34, 30
    pw = max(cw, sw) + pad * 2
    ph = ch + between + sh + pad * 2
    px = W - 110 - pw
    py = (H - ph) / 2
    d.rounded_rectangle((px - 14, py - 14, px + pw + 14, py + ph + 14), radius=26, fill=(0, 0, 0, 90))
    d.rounded_rectangle((px, py, px + pw, py + ph), radius=18, fill=(26, 23, 32, 255))
    counter(d, px + pad, py + pad, scale, "Ranked Snow Day", 7, 3, "3 win streak")
    d.line((px + pad, py + pad + ch + between / 2, px + pw - pad, py + pad + ch + between / 2),
           fill=(255, 255, 255, 22), width=2)
    counter(d, px + pad, py + pad + ch + between, small, "Ranked 2v2", 4, 2, "2 loss streak")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT)
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
