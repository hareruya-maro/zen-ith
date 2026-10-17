#!/usr/bin/env python3
"""Export the approved 1024px artwork to macOS and Xcode icon formats."""

import json
from pathlib import Path
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "design" / "app-icon"
MASTER = OUTPUT / "Zen-ith-1024.png"
ICONSET = OUTPUT / "Zen-ith.iconset"
ASSETS = ROOT / "Zen-ith" / "Assets.xcassets" / "AppIcon.appiconset"


def main():
    if not MASTER.is_file():
        raise SystemExit(f"Missing master artwork: {MASTER}")
    ICONSET.mkdir(parents=True, exist_ok=True)
    ASSETS.mkdir(parents=True, exist_ok=True)
    images = []
    for size in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            suffix = "@2x" if scale == 2 else ""
            name = f"icon_{size}x{size}{suffix}.png"
            pixels = size * scale
            target = ICONSET / name
            if pixels == 1024:
                shutil.copyfile(MASTER, target)
            else:
                subprocess.run(
                    ["sips", "-z", str(pixels), str(pixels), str(MASTER), "--out", str(target)],
                    check=True, stdout=subprocess.DEVNULL,
                )
            shutil.copyfile(target, ASSETS / name)
            images.append({"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{size}x{size}"})
    (ASSETS / "Contents.json").write_text(
        json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n"
    )
    with tempfile.TemporaryDirectory(prefix="zen-ith-app-icon-") as directory:
        subprocess.run([
            "xcrun", "actool", str(ASSETS.parent), "--compile", directory,
            "--platform", "macosx", "--minimum-deployment-target", "13.0",
            "--app-icon", "AppIcon", "--output-partial-info-plist",
            str(Path(directory) / "icon-info.plist"),
        ], check=True, stdout=subprocess.DEVNULL)
        shutil.copyfile(Path(directory) / "AppIcon.icns", OUTPUT / "Zen-ith.icns")
    print(f"Exported macOS icon assets to {OUTPUT} and {ASSETS}")


if __name__ == "__main__":
    main()
