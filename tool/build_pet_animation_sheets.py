"""Normalize the generated Scout cycle and derive the unlockable coat variants.

The source is an eight-pose transparent strip: four walk poses, then four run
poses.  Each output uses fixed 320px cells so gameplay can select frames
without carrying generated-image geometry into Dart.
"""

from __future__ import annotations

import colorsys
import sys
from collections import deque
from pathlib import Path

from PIL import Image


FRAME_SIZE = 320
COATS = {
    "scout": ((240, 168, 104), (201, 127, 68)),
    "ember": ((255, 154, 107), (196, 82, 46)),
    "frost": ((182, 220, 242), (110, 156, 196)),
    "moss": ((168, 220, 168), (94, 156, 102)),
    "dusk": ((200, 174, 240), (138, 110, 196)),
}


def _mix(dark: tuple[int, int, int], light: tuple[int, int, int], t: float):
    return tuple(round(a + (b - a) * t) for a, b in zip(dark, light))


def _recoat(image: Image.Image, light: tuple[int, int, int], dark: tuple[int, int, int]):
    pixels = image.load()
    for y in range(image.height):
        for x in range(image.width):
            red, green, blue, alpha = pixels[x, y]
            if alpha == 0:
                continue
            hue, saturation, value = colorsys.rgb_to_hsv(red / 255, green / 255, blue / 255)
            # Select the golden fur while leaving the red collar, cream muzzle,
            # eyes, nose and brown ink intact.
            if 0.055 <= hue <= 0.145 and saturation >= 0.42 and value >= 0.34:
                tone = max(0.0, min(1.0, (value - 0.34) / 0.66))
                nr, ng, nb = _mix(dark, light, tone)
                pixels[x, y] = (nr, ng, nb, alpha)


def _keep_largest_component(image: Image.Image) -> Image.Image:
    """Remove slivers of neighbouring poses that enter an uneven source crop."""
    alpha = image.getchannel("A")
    width, height = image.size
    alpha_bytes = alpha.tobytes()
    visible = bytearray(1 if value > 12 else 0 for value in alpha_bytes)
    seen = bytearray(width * height)
    largest: list[int] = []
    for seed, present in enumerate(visible):
        if not present or seen[seed]:
            continue
        seen[seed] = 1
        queue = deque([seed])
        component: list[int] = []
        while queue:
            current = queue.popleft()
            component.append(current)
            x, y = current % width, current // width
            for neighbour in (
                current - 1 if x else -1,
                current + 1 if x + 1 < width else -1,
                current - width if y else -1,
                current + width if y + 1 < height else -1,
            ):
                if neighbour >= 0 and visible[neighbour] and not seen[neighbour]:
                    seen[neighbour] = 1
                    queue.append(neighbour)
        if len(component) > len(largest):
            largest = component
    keep = bytearray(width * height)
    for index in largest:
        keep[index] = alpha_bytes[index]
    image.putalpha(Image.frombytes("L", image.size, bytes(keep)))
    return image


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: build_pet_animation_sheets.py SOURCE OUTPUT_DIR")
    source = Image.open(sys.argv[1]).convert("RGBA")
    output_dir = Path(sys.argv[2])
    output_dir.mkdir(parents=True, exist_ok=True)

    sheet = Image.new("RGBA", (FRAME_SIZE * 8, FRAME_SIZE))
    # The generated poses have deliberately different stride lengths. Overlap
    # the source windows so wide tails and airborne paws remain intact; the
    # connected-component pass above discards the neighbouring pose.
    windows = (
        (0.000, 0.157),
        (0.101, 0.286),
        (0.216, 0.405),
        (0.336, 0.516),
        (0.456, 0.649),
        (0.575, 0.755),
        (0.668, 0.884),
        (0.829, 1.000),
    )
    for index, (start, end) in enumerate(windows):
        left = round(start * source.width)
        right = round(end * source.width)
        frame = _keep_largest_component(source.crop((left, 0, right, source.height)))
        alpha_box = frame.getchannel("A").getbbox()
        if alpha_box is None:
            raise ValueError(f"frame {index} has no visible pixels")
        frame = frame.crop(alpha_box)
        frame.thumbnail((292, 252), Image.Resampling.LANCZOS)
        x = index * FRAME_SIZE + (FRAME_SIZE - frame.width) // 2
        y = 298 - frame.height
        sheet.alpha_composite(frame, (x, y))

    for pet_id, (light, dark) in COATS.items():
        coat = sheet.copy()
        if pet_id != "scout":
            _recoat(coat, light, dark)
        coat.save(output_dir / f"{pet_id}_move.png", optimize=True)


if __name__ == "__main__":
    main()
