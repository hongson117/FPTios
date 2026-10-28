import json
import os
from PIL import Image, ImageDraw, ImageFont

LAUNCHER_PATH = r"C:\Users\ASUS\Documents\Codex\2026-10-24\b-n-h-y-d-ng\work\g2-fpt-survey\private\jadx\resources\res\mipmap-xxxhdpi\launcher.png"
WORDMARK_PATH = r"C:\Users\ASUS\Documents\Codex\2026-10-24\b-n-h-y-d-ng\work\g2-fpt-survey\private\jadx\resources\res\drawable-nodpi\image_fptplay.png"

PROJECT_ROOT = r"C:\Users\ASUS\.gemini\antigravity\scratch\FPTios"
SOURCES_DIR = os.path.join(PROJECT_ROOT, "Sources")
ASSETS_DIR = os.path.join(SOURCES_DIR, "Assets", "Assets.xcassets")
BRAND_DIR = os.path.join(ASSETS_DIR, "App Icon & Top Shelf Image.brandassets")
IOS_ICON_DIR = os.path.join(ASSETS_DIR, "AppIcon.appiconset")
LOGO_SET_DIR = os.path.join(ASSETS_DIR, "FPTLogo.imageset")

os.makedirs(BRAND_DIR, exist_ok=True)
os.makedirs(IOS_ICON_DIR, exist_ok=True)
os.makedirs(LOGO_SET_DIR, exist_ok=True)

launcher_img = Image.open(LAUNCHER_PATH).convert("RGBA")
wordmark_img = Image.open(WORDMARK_PATH).convert("RGBA")

# Extract the FPT flame droplet emblem from the left side of wordmark_img
ww, wh = wordmark_img.size
flame_crop = wordmark_img.crop((0, 0, int(wh * 0.92), wh))


def load_bold_font(size: int) -> ImageFont.FreeTypeFont:
    for font_candidate in [
        r"C:\Windows\Fonts\segoeuib.ttf",
        r"C:\Windows\Fonts\arialbd.ttf",
        r"C:\Windows\Fonts\calibrib.ttf",
        r"C:\Windows\Fonts\tahomabd.ttf",
    ]:
        if os.path.exists(font_candidate):
            return ImageFont.truetype(font_candidate, size)
    return ImageFont.load_default()


def make_ftvos_wordmark(height: int = 220) -> Image.Image:
    """Create crisp transparent wordmark: [FPT Flame Emblem] + bold orange 'FTVOS' text."""
    fw, fh = flame_crop.size
    flame_h = int(height * 0.86)
    flame_w = int(fw * (flame_h / fh))
    flame_resized = flame_crop.resize((flame_w, flame_h), Image.Resampling.LANCZOS)

    font_size = int(height * 0.68)
    font = load_bold_font(font_size)
    text = "FTVOS"

    dummy = Image.new("RGBA", (10, 10), (0, 0, 0, 0))
    ddraw = ImageDraw.Draw(dummy)
    bbox = ddraw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]

    gap = int(height * 0.14)
    pad_x = int(height * 0.10)
    total_w = pad_x * 2 + flame_w + gap + tw

    canvas = Image.new("RGBA", (total_w, height), (0, 0, 0, 0))
    flame_y = (height - flame_h) // 2
    canvas.paste(flame_resized, (pad_x, flame_y), flame_resized)

    draw = ImageDraw.Draw(canvas)
    tx = pad_x + flame_w + gap - bbox[0]
    ty = (height - th) // 2 - bbox[1]

    # Subtle dark shadow for contrast + Vibrant FPT Orange (#FF6B00) for 'FTVOS'
    draw.text((tx + 3, ty + 4), text, font=font, fill=(0, 0, 0, 150))
    draw.text((tx, ty), text, font=font, fill=(255, 107, 0, 255))
    return canvas


ftvos_logo_img = make_ftvos_wordmark(240)

# Root Assets Contents.json
with open(os.path.join(ASSETS_DIR, "Contents.json"), "w", encoding="utf-8") as f:
    json.dump({"info": {"version": 1, "author": "xcode"}}, f, indent=2)

# Save in-app header wordmark logo (FPTLogo.imageset)
ftvos_logo_img.save(os.path.join(LOGO_SET_DIR, "fpt_logo.png"), "PNG")
with open(os.path.join(LOGO_SET_DIR, "Contents.json"), "w", encoding="utf-8") as f:
    json.dump(
        {
            "images": [
                {"idiom": "universal", "filename": "fpt_logo.png", "scale": "1x"},
                {"idiom": "universal", "scale": "2x"},
                {"idiom": "universal", "scale": "3x"},
            ],
            "info": {"version": 1, "author": "xcode"},
        },
        f,
        indent=2,
    )


def make_fpt_background(w: int, h: int) -> Image.Image:
    bg = Image.new("RGB", (w, h), (12, 14, 22))
    draw = ImageDraw.Draw(bg)
    cx, cy = w // 2, h // 2
    max_r = int(min(w, h) * 0.65)
    for r in range(max_r, 0, -8):
        ratio = 1.0 - (r / max_r)
        red = min(255, int(12 + 75 * ratio))
        green = min(255, int(14 + 28 * ratio))
        blue = min(255, int(22 + 10 * ratio))
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(red, green, blue))
    return bg


def make_top_shelf(w: int, h: int) -> Image.Image:
    bg = make_fpt_background(w, h).convert("RGBA")
    lw, lh = ftvos_logo_img.size
    target_w = int(w * 0.36)
    target_h = int(lh * (target_w / lw))
    scaled = ftvos_logo_img.resize((target_w, target_h), Image.Resampling.LANCZOS)
    x = (w - target_w) // 2
    y = (h - target_h) // 2
    bg.paste(scaled, (x, y), scaled)
    return bg.convert("RGB")


top_shelf_dir = os.path.join(BRAND_DIR, "Top Shelf Image.imageset")
os.makedirs(top_shelf_dir, exist_ok=True)
make_top_shelf(1920, 720).save(os.path.join(top_shelf_dir, "top_shelf.png"), "PNG")
make_top_shelf(3840, 1440).save(os.path.join(top_shelf_dir, "top_shelf@2x.png"), "PNG")
with open(os.path.join(top_shelf_dir, "Contents.json"), "w", encoding="utf-8") as f:
    json.dump(
        {
            "images": [
                {"idiom": "tv", "filename": "top_shelf.png", "scale": "1x"},
                {"idiom": "tv", "filename": "top_shelf@2x.png", "scale": "2x"},
            ],
            "info": {"version": 1, "author": "xcode"},
        },
        f,
        indent=2,
    )


def make_tv_icon_layers(w: int, h: int):
    back = make_fpt_background(w, h)
    front = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    lw, lh = ftvos_logo_img.size
    target_w = int(w * 0.78)
    target_h = int(lh * (target_w / lw))
    if target_h > int(h * 0.65):
        target_h = int(h * 0.65)
        target_w = int(lw * (target_h / lh))
    scaled = ftvos_logo_img.resize((target_w, target_h), Image.Resampling.LANCZOS)
    px = (w - target_w) // 2
    py = (h - target_h) // 2
    front.paste(scaled, (px, py), scaled)

    flat = back.convert("RGBA")
    flat.paste(front, (0, 0), front)
    return back, front, flat.convert("RGB")


# Small tvOS App Icon (400x240 @1x, 800x480 @2x)
small_dir = os.path.join(BRAND_DIR, "App Icon.imagestack")
os.makedirs(small_dir, exist_ok=True)
with open(os.path.join(small_dir, "Contents.json"), "w", encoding="utf-8") as f:
    json.dump(
        {
            "layers": [
                {"filename": "Front.imagestacklayer"},
                {"filename": "Back.imagestacklayer"},
            ],
            "info": {"version": 1, "author": "xcode"},
        },
        f,
        indent=2,
    )

for layer_name in ["Back", "Front"]:
    ldir = os.path.join(small_dir, f"{layer_name}.imagestacklayer")
    os.makedirs(ldir, exist_ok=True)
    with open(os.path.join(ldir, "Contents.json"), "w", encoding="utf-8") as f:
        json.dump({"info": {"version": 1, "author": "xcode"}}, f, indent=2)
    cdir = os.path.join(ldir, "Content.imageset")
    os.makedirs(cdir, exist_ok=True)
    with open(os.path.join(cdir, "Contents.json"), "w", encoding="utf-8") as f:
        json.dump(
            {
                "images": [
                    {"idiom": "tv", "filename": f"{layer_name.lower()}.png", "scale": "1x"},
                    {"idiom": "tv", "filename": f"{layer_name.lower()}@2x.png", "scale": "2x"},
                ],
                "info": {"version": 1, "author": "xcode"},
            },
            f,
            indent=2,
        )

b1, f1, flat1 = make_tv_icon_layers(400, 240)
b2, f2, flat2 = make_tv_icon_layers(800, 480)
b1.save(os.path.join(small_dir, "Back.imagestacklayer", "Content.imageset", "back.png"), "PNG")
b2.save(os.path.join(small_dir, "Back.imagestacklayer", "Content.imageset", "back@2x.png"), "PNG")
f1.save(os.path.join(small_dir, "Front.imagestacklayer", "Content.imageset", "front.png"), "PNG")
f2.save(os.path.join(small_dir, "Front.imagestacklayer", "Content.imageset", "front@2x.png"), "PNG")

# Large tvOS App Icon (1280x768 @1x)
large_dir = os.path.join(BRAND_DIR, "App Icon - Large.imagestack")
os.makedirs(large_dir, exist_ok=True)
with open(os.path.join(large_dir, "Contents.json"), "w", encoding="utf-8") as f:
    json.dump(
        {
            "layers": [
                {"filename": "Front.imagestacklayer"},
                {"filename": "Back.imagestacklayer"},
            ],
            "info": {"version": 1, "author": "xcode"},
        },
        f,
        indent=2,
    )

for layer_name in ["Back", "Front"]:
    ldir = os.path.join(large_dir, f"{layer_name}.imagestacklayer")
    os.makedirs(ldir, exist_ok=True)
    with open(os.path.join(ldir, "Contents.json"), "w", encoding="utf-8") as f:
        json.dump({"info": {"version": 1, "author": "xcode"}}, f, indent=2)
    cdir = os.path.join(ldir, "Content.imageset")
    os.makedirs(cdir, exist_ok=True)
    with open(os.path.join(cdir, "Contents.json"), "w", encoding="utf-8") as f:
        json.dump(
            {
                "images": [
                    {"idiom": "tv", "filename": f"{layer_name.lower()}.png", "scale": "1x"},
                ],
                "info": {"version": 1, "author": "xcode"},
            },
            f,
            indent=2,
        )

b_lg, f_lg, flat_lg = make_tv_icon_layers(1280, 768)
b_lg.save(os.path.join(large_dir, "Back.imagestacklayer", "Content.imageset", "back.png"), "PNG")
f_lg.save(os.path.join(large_dir, "Front.imagestacklayer", "Content.imageset", "front.png"), "PNG")

with open(os.path.join(BRAND_DIR, "Contents.json"), "w", encoding="utf-8") as f:
    json.dump(
        {
            "assets": [
                {
                    "size": "400x240",
                    "idiom": "tv",
                    "filename": "App Icon.imagestack",
                    "role": "primary-app-icon",
                },
                {
                    "size": "1280x768",
                    "idiom": "tv",
                    "filename": "App Icon - Large.imagestack",
                    "role": "primary-app-icon",
                },
                {
                    "size": "1920x720",
                    "idiom": "tv",
                    "filename": "Top Shelf Image.imageset",
                    "role": "top-shelf-image",
                },
            ],
            "info": {"version": 1, "author": "xcode"},
        },
        f,
        indent=2,
    )

# Square App Icon (1024x1024) with FTVOS orange branding
ios_bg = make_fpt_background(1024, 1024).convert("RGBA")
lw, lh = ftvos_logo_img.size
sq_w = 880
sq_h = int(lh * (sq_w / lw))
scaled_sq = ftvos_logo_img.resize((sq_w, sq_h), Image.Resampling.LANCZOS)
ios_bg.paste(scaled_sq, ((1024 - sq_w) // 2, (1024 - sq_h) // 2), scaled_sq)
ios_final = ios_bg.convert("RGB")
ios_final.save(os.path.join(IOS_ICON_DIR, "AppIcon-1024.png"), "PNG")

with open(os.path.join(IOS_ICON_DIR, "Contents.json"), "w", encoding="utf-8") as f:
    json.dump(
        {
            "images": [
                {
                    "filename": "AppIcon-1024.png",
                    "idiom": "universal",
                    "platform": "ios",
                    "size": "1024x1024",
                }
            ],
            "info": {"version": 1, "author": "xcode"},
        },
        f,
        indent=2,
    )

# Save loose fallback icons in Sources/ for sideloaders (ATVLoadly / Sideloadly)
flat1.save(os.path.join(SOURCES_DIR, "AppIcon400x240.png"), "PNG")
flat2.save(os.path.join(SOURCES_DIR, "AppIcon800x480.png"), "PNG")
flat_lg.save(os.path.join(SOURCES_DIR, "AppIcon1280x768.png"), "PNG")
ios_final.resize((512, 512), Image.Resampling.LANCZOS).save(
    os.path.join(SOURCES_DIR, "AppIcon.png"), "PNG"
)
ios_final.resize((180, 180), Image.Resampling.LANCZOS).save(
    os.path.join(SOURCES_DIR, "Icon.png"), "PNG"
)

print("Generated FTVOS orange brand assets for tvOS successfully.")
