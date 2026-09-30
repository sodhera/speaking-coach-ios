"""App Store screenshots in the Domtos layout, in Speaking Coach's colours.

    python3 artifacts/appstore-2026-09-30/make.py

Big two-line headline (first line deep coral), one grey line under it, the
iPhone frame from Domtos's Tools/store_screenshots (~/Desktop/Domtos), and
popped-out cards cut from the raw captures in artifacts/raw-app-screenshots.
White ground with a soft blue glow behind the phone. 1320x2868 (6.9").
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, str(Path.home() / "Desktop/Domtos/Tools/store_screenshots"))
from frames import handheld, rrect_mask, IPHONE  # noqa: E402

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
RAW = ROOT / "artifacts/raw-app-screenshots"
FONT = str(ROOT / "SpeakingCoach/Resources/Fonts/DMSans.ttf")

W, H = 1320, 2868
INK = (35, 26, 27)
DIM = (107, 90, 91)
CORAL_DEEP = (210, 65, 74)
# White at the top, easing to a faint blue at the bottom, with a soft blue
# glow behind the phone. One hue, no shapes.
TOP, BOTTOM, GLOW = (255, 255, 255), (238, 244, 255), (212, 226, 255)
SHADOW = (20, 34, 90)

# (file, headline lines, line under it, phone screen, popouts)
# A popout is (source image, crop box in raw pixels, centre in phone-screen
# pixels, scale[, whiten]). Whitening turns the app's paper white.
CARDS = [
    ("1-ai-mock-interviews", ["AI Mock", "Interviews"], "Upload CV and instructions",
     "10-practice-conversation.png",
     [("10-practice-conversation.png", (40, 900, 1166, 1680), (603, 1290), 1.22)]),
    ("2-small-talk-training", ["Small Talk", "Training"], "Based on real scenarios",
     "16-progress.png",
     [("16-progress.png", (72, 1287, 1134, 1483), (603, 1385), 1.22),
      ("16-progress.png", (72, 1979, 1134, 2171), (603, 2075), 1.22)]),
    ("3-presentation-practice", ["Presentation", "Practice"], "With slides & follow-up Q&A",
     "13-presentation-slides.png",
     [("15-presentation-questions.png", (72, 989, 1134, 2062), (603, 1700), 1.18)]),
    ("4-instant-feedback", ["Instant", "Feedback"], "Retry the moment you missed",
     "06-feedback-practice-review.png",
     [("06-feedback-practice-review.png", (40, 905, 1166, 1712), (603, 1308), 1.14)]),
    ("5-any-situation", ["Any", "Situation"], "Describe it. Then practice it.",
     "22-custom-situation.png",
     [("22-custom-situation.png", (72, 440, 1134, 1070), (603, 800), 1.16)]),
    ("6-interview-prep-plan", ["Interview", "Prep Plan"], "5 sessions before the big day",
     "07-preparation-plan.png",
     [("07-preparation-plan.png", (72, 590, 1134, 1043), (603, 816), 1.18)]),
    ("7-daily-practice", ["Daily", "Practice"], "Keep your streak going",
     "05-homepage.png",
     # Its calendar's empty days are grey dots, so it keeps its own colours.
     [("05-homepage.png", (72, 362, 1134, 888), (603, 640), 1.18, False)]),
]


def font(size, weight):
    f = ImageFont.truetype(FONT, int(size))
    f.set_variation_by_axes([40, weight])
    return f


def ground():
    g = Image.new("RGB", (1, H))
    for y in range(H):
        # Stays white behind the headline, then eases down.
        t = max(0.0, (y / (H - 1) - 0.2) / 0.8) ** 1.4
        g.putpixel((0, y), tuple(int(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3)))
    bg = g.resize((W, H))
    cx, cy = W / 2, H * 0.64
    m = Image.new("L", (W, H), 0)
    ImageDraw.Draw(m).ellipse([cx - W * 0.66, cy - H * 0.3, cx + W * 0.66, cy + H * 0.34], fill=255)
    bg.paste(Image.new("RGB", (W, H), GLOW), (0, 0), m.filter(ImageFilter.GaussianBlur(W * 0.15)))
    return bg


def centred(img, y, text, f, colour):
    ImageDraw.Draw(img).text((W / 2, y), text, font=f, fill=colour, anchor="ms")


def whiten(crop):
    """The app's paper and its dot grid become white, so the card reads as lifted."""
    px = crop.load()
    for y in range(crop.height):
        for x in range(crop.width):
            r, g, b = px[x, y][:3]
            # Neutral light pixels only (paper and its dots), so the
            # coral-tinted note keeps its tint.
            if r > 206 and abs(r - g) < 12 and abs(g - b) < 12:
                px[x, y] = (255, 255, 255)
    return crop


def popout(canvas, src, box, centre, scale, to_canvas, s, white=True):
    crop = Image.open(RAW / src).convert("RGB").crop(box)
    if white:
        crop = whiten(crop)
    w, h = int(crop.width * s * scale), int(crop.height * s * scale)
    crop = crop.resize((w, h), Image.LANCZOS)
    cx, cy = to_canvas(*centre)
    x, y = int(cx - w / 2), int(cy - h / 2)
    r = int(46 * s * scale)
    shadow = Image.new("L", canvas.size, 0)
    ImageDraw.Draw(shadow).rounded_rectangle([x + 10, y + 34, x + w - 10, y + h + 34], r, fill=80)
    layer = Image.new("RGBA", canvas.size, SHADOW + (0,))
    layer.putalpha(shadow.filter(ImageFilter.GaussianBlur(38)))
    canvas.alpha_composite(layer)
    piece = crop.convert("RGBA")
    piece.putalpha(rrect_mask((w, h), r))
    canvas.alpha_composite(piece, (x, y))


def card(lines, sub, shot, pops):
    img = ground().convert("RGBA")
    t = W * 0.145
    y = H * 0.035
    head = font(t, 800)
    for i, line in enumerate(lines):
        y += t
        centred(img, y, line, head, CORAL_DEEP if i == 0 else INK)
    y += t * 0.22 + t * 0.44 * 1.18
    centred(img, y, sub, font(t * 0.44, 700), DIM)

    dimg = handheld(Image.open(RAW / shot), IPHONE)
    mx, my = IPHONE["margin"]
    s = W * 0.84 / (dimg.width - 2 * mx)
    top = y + H * 0.045
    dimg = dimg.resize((int(dimg.width * s), int(dimg.height * s)), Image.LANCZOS)
    x0, y0 = (W - dimg.width) // 2, int(top - my * s)
    img.alpha_composite(dimg, (x0, y0))

    inset = IPHONE["rim"] + IPHONE["bezel"]
    def to_canvas(sx, sy):
        return x0 + (mx + inset + sx) * s, y0 + (my + inset + sy) * s
    for src, box, centre, scale, *white in pops:
        popout(img, src, box, centre, scale, to_canvas, s, *white)
    return img.convert("RGB")


if __name__ == "__main__":
    for name, lines, sub, shot, pops in CARDS:
        path = HERE / f"{name}.png"
        card(lines, sub, shot, pops).save(path)
        print(path.relative_to(ROOT))
