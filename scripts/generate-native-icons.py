from pathlib import Path
import json
from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "public" / "logo-original.webp"
image = Image.open(SOURCE).convert("RGBA")
if image.width != image.height:
    image = ImageOps.fit(image, (max(image.size), max(image.size)), method=Image.Resampling.LANCZOS)

def save_icon(path: Path, size: int):
    path.parent.mkdir(parents=True, exist_ok=True)
    ImageOps.fit(image, (size, size), method=Image.Resampling.LANCZOS).save(path, "PNG", optimize=True)

android = ROOT / "android" / "app" / "src" / "main" / "res"
if android.exists():
    for density, icon_size, adaptive_size in [
        ("mdpi", 48, 108),
        ("hdpi", 72, 162),
        ("xhdpi", 96, 216),
        ("xxhdpi", 144, 324),
        ("xxxhdpi", 192, 432),
    ]:
        folder = android / f"mipmap-{density}"
        save_icon(folder / "ic_launcher.png", icon_size)
        save_icon(folder / "ic_launcher_round.png", icon_size)

        # Adaptive foreground artwork stays inside Android's two-thirds safe zone.
        safe_size = round(adaptive_size * 2 / 3)
        foreground_art = ImageOps.contain(image, (safe_size, safe_size), method=Image.Resampling.LANCZOS)
        foreground = Image.new("RGBA", (adaptive_size, adaptive_size), (0, 0, 0, 0))
        foreground.alpha_composite(foreground_art, ((adaptive_size - foreground_art.width) // 2,
                                                     (adaptive_size - foreground_art.height) // 2))
        foreground.save(folder / "ic_launcher_foreground.png", "PNG", optimize=True)

    adaptive_dir = android / "mipmap-anydpi-v26"
    adaptive_dir.mkdir(parents=True, exist_ok=True)
    adaptive = """<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@android:color/black" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
"""
    (adaptive_dir / "ic_launcher.xml").write_text(adaptive, encoding="utf-8")
    (adaptive_dir / "ic_launcher_round.xml").write_text(adaptive, encoding="utf-8")

# A single 1024px universal icon is supported by modern Xcode asset catalogs.
ios_icons = ROOT / "ios" / "App" / "App" / "Assets.xcassets" / "AppIcon.appiconset"
if ios_icons.exists():
    ios_icons.mkdir(parents=True, exist_ok=True)
    save_icon(ios_icons / "AppIcon-1024.png", 1024)
    contents = {
        "images": [{
            "filename": "AppIcon-1024.png",
            "idiom": "universal",
            "platform": "ios",
            "size": "1024x1024"
        }],
        "info": {"author": "xcode", "version": 1}
    }
    (ios_icons / "Contents.json").write_text(json.dumps(contents, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
