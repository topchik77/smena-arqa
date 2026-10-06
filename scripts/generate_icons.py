"""Rasterize the app's own route mark for launcher sizes (requires Pillow)."""

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]


def icon(size: int) -> Image.Image:
    scale = 4
    image = Image.new("RGB", (size * scale, size * scale), "#1B211D")
    draw = ImageDraw.Draw(image)
    unit = size * scale
    # Same route as _RouteMark in client/lib/src/theme.dart, in its 34px grid.
    points = [(11, 23), (20, 23)]
    for start, control, end in [((20, 23), (24, 23), (24, 19)), ((24, 19), (24, 15), (20, 15))]:
        for step in range(1, 21):
            t = step / 20
            points.append(tuple((1-t)**2*a + 2*(1-t)*t*b + t*t*c for a,b,c in zip(start,control,end)))
    points.append((14, 15))
    for step in range(1, 21):
        t = step / 20
        points.append(((1-t)**2*14 + 2*(1-t)*t*10 + t*t*10, (1-t)**2*15 + 2*(1-t)*t*15 + t*t*11))
    path = [(round(x * unit / 34), round(y * unit / 34)) for x, y in points]
    width = round(unit * 2.4 / 34)
    draw.line(path, fill="#D4F568", width=width, joint="curve")
    for x, y in path:
        radius = width / 2
        draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill="#D4F568")
    center, radius = unit * 10 / 34, unit * 2.4 / 34
    draw.ellipse((center-radius, center-radius, center+radius, center+radius), fill="#D4F568")
    return image.resize((size, size), Image.Resampling.LANCZOS)


if __name__ == "__main__":
    web = ROOT / "client" / "web"
    icon(32).save(web / "favicon.png")
    for size in (192, 512):
        for name in (f"Icon-{size}.png", f"Icon-maskable-{size}.png"):
            icon(size).save(web / "icons" / name)
    for density, size in [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)]:
        icon(size).save(ROOT / f"client/android/app/src/main/res/mipmap-{density}/ic_launcher.png")
