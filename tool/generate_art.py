#!/usr/bin/env python3
"""Generates the line-art assets in assets/art/.

The art is built from primitives rather than hand-written path data. Ten
animals of hand-authored beziers is ten chances to typo a coordinate into
a shape nobody notices is wrong until a child is looking at it, and the
whole set has to share one visual language — chunky closed shapes, no
thin detail — or the trace guide is followable on some drawings and not
others.

Parts are listed big-to-small. `Artwork.regionAt` searches last-first, so
that ordering is also what makes a tap on an eye hit the eye and not the
head behind it.

Run:  python3 tool/generate_art.py
"""

import json
import math
import os

K = 0.5522847498307933  # circle-to-bezier constant


def ellipse(cx, cy, rx, ry):
    ox, oy = rx * K, ry * K
    return (
        f"M {cx - rx:.1f} {cy:.1f} "
        f"C {cx - rx:.1f} {cy - oy:.1f} {cx - ox:.1f} {cy - ry:.1f} {cx:.1f} {cy - ry:.1f} "
        f"C {cx + ox:.1f} {cy - ry:.1f} {cx + rx:.1f} {cy - oy:.1f} {cx + rx:.1f} {cy:.1f} "
        f"C {cx + rx:.1f} {cy + oy:.1f} {cx + ox:.1f} {cy + ry:.1f} {cx:.1f} {cy + ry:.1f} "
        f"C {cx - ox:.1f} {cy + ry:.1f} {cx - rx:.1f} {cy + oy:.1f} {cx - rx:.1f} {cy:.1f} Z"
    )


def circle(cx, cy, r):
    return ellipse(cx, cy, r, r)


def poly(points):
    """A closed polygon."""
    head = f"M {points[0][0]:.1f} {points[0][1]:.1f}"
    rest = " ".join(f"L {x:.1f} {y:.1f}" for x, y in points[1:])
    return f"{head} {rest} Z"


def rounded(cx, cy, w, h, r):
    """A rounded rectangle, centred."""
    x0, y0, x1, y1 = cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2
    o = r * K
    return (
        f"M {x0 + r:.1f} {y0:.1f} L {x1 - r:.1f} {y0:.1f} "
        f"C {x1 - r + o:.1f} {y0:.1f} {x1:.1f} {y0 + r - o:.1f} {x1:.1f} {y0 + r:.1f} "
        f"L {x1:.1f} {y1 - r:.1f} "
        f"C {x1:.1f} {y1 - r + o:.1f} {x1 - r + o:.1f} {y1:.1f} {x1 - r:.1f} {y1:.1f} "
        f"L {x0 + r:.1f} {y1:.1f} "
        f"C {x0 + r - o:.1f} {y1:.1f} {x0:.1f} {y1 - r + o:.1f} {x0:.1f} {y1 - r:.1f} "
        f"L {x0:.1f} {y0 + r:.1f} "
        f"C {x0:.1f} {y0 + r - o:.1f} {x0 + r - o:.1f} {y0:.1f} {x0 + r:.1f} {y0:.1f} Z"
    )


def leg(cx, top, w, h):
    return rounded(cx, top + h / 2, w, h, w * 0.4)


def star_back(x0, x1, y_base, y_peak, spikes):
    """A zig-zag ridge — a stegosaurus's plates, a rooster's comb."""
    pts = []
    span = (x1 - x0) / spikes
    for i in range(spikes):
        bx = x0 + i * span
        pts.append((bx, y_base))
        pts.append((bx + span / 2, y_peak))
    pts.append((x1, y_base))
    return poly(pts)


# Each animal: (id, title, category, [(region id, path, colour), ...])
# Colours are the art's own suggestion — a starting point a child is free
# to ignore entirely.
ANIMALS = []


def add(aid, title, category, parts, symmetry=None):
    ANIMALS.append((aid, title, category, parts, symmetry))


# ---------------------------------------------------------------- dinosaurs

add("dino_trex", "T-Rex", "dinosaurs", [
    ("tail", poly([(300, 560), (90, 470), (70, 530), (300, 650)]), "#7CB342"),
    ("body", ellipse(430, 570, 190, 150), "#8BC34A"),
    ("leg_back", leg(360, 690, 90, 190), "#7CB342"),
    ("leg_front", leg(490, 700, 84, 180), "#8BC34A"),
    ("neck", poly([(560, 470), (640, 330), (700, 360), (620, 520)]), "#8BC34A"),
    ("head", ellipse(700, 330, 130, 96), "#8BC34A"),
    ("jaw", poly([(600, 350), (810, 360), (800, 418), (610, 400)]), "#AED581"),
    ("belly", ellipse(430, 630, 130, 78), "#FFE0B2"),
    ("arm", poly([(560, 560), (620, 600), (600, 636), (545, 600)]), "#7CB342"),
    ("eye", circle(724, 300, 26), "#FFFFFF"),
])

add("dino_stego", "Stegosaurus", "dinosaurs", [
    ("tail", poly([(250, 540), (60, 600), (80, 660), (260, 620)]), "#66BB6A"),
    ("body", ellipse(480, 580, 220, 140), "#81C784"),
    ("plates", star_back(330, 640, 450, 300, 4), "#EF9A9A"),
    ("leg_back", leg(390, 690, 88, 180), "#66BB6A"),
    ("leg_front", leg(560, 690, 88, 180), "#81C784"),
    ("neck", poly([(650, 500), (740, 400), (790, 440), (700, 550)]), "#81C784"),
    ("head", ellipse(790, 410, 100, 76), "#81C784"),
    ("belly", ellipse(480, 650, 150, 66), "#FFE0B2"),
    ("eye", circle(812, 392, 22), "#FFFFFF"),
])

add("dino_bronto", "Brontosaurus", "dinosaurs", [
    ("tail", poly([(280, 600), (60, 520), (50, 580), (285, 665)]), "#4DB6AC"),
    ("body", ellipse(470, 620, 210, 140), "#4DD0E1"),
    ("leg_back", leg(370, 730, 96, 160), "#4DB6AC"),
    ("leg_front", leg(560, 730, 96, 160), "#4DD0E1"),
    ("neck", poly([(620, 540), (700, 250), (770, 260), (700, 570)]), "#4DD0E1"),
    ("head", ellipse(750, 230, 96, 72), "#4DD0E1"),
    ("belly", ellipse(470, 690, 140, 60), "#FFE0B2"),
    ("eye", circle(772, 212, 22), "#FFFFFF"),
])

add("dino_trike", "Triceratops", "dinosaurs", [
    ("tail", poly([(280, 580), (110, 540), (100, 600), (285, 640)]), "#FFB74D"),
    ("body", ellipse(450, 600, 200, 145), "#FFCC80"),
    ("leg_back", leg(370, 710, 92, 175), "#FFB74D"),
    ("leg_front", leg(530, 710, 92, 175), "#FFCC80"),
    ("frill", ellipse(710, 480, 150, 160), "#FFAB91"),
    ("head", ellipse(760, 520, 120, 100), "#FFCC80"),
    ("horn_top", poly([(720, 410), (760, 300), (790, 420)]), "#FFF3E0"),
    ("horn_nose", poly([(840, 500), (890, 450), (860, 540)]), "#FFF3E0"),
    ("belly", ellipse(450, 665, 140, 66), "#FFE0B2"),
    ("eye", circle(770, 500, 22), "#FFFFFF"),
])

add("dino_ptero", "Pterodactyl", "dinosaurs", [
    ("wing_left", poly([(460, 430), (120, 300), (170, 470), (430, 520)]), "#9575CD"),
    ("wing_right", poly([(580, 430), (910, 300), (870, 470), (610, 520)]), "#9575CD"),
    ("body", ellipse(520, 500, 90, 130), "#B39DDB"),
    ("head", ellipse(520, 330, 92, 72), "#B39DDB"),
    ("beak", poly([(560, 310), (760, 330), (570, 370)]), "#FFCC80"),
    ("crest", poly([(490, 280), (400, 210), (520, 258)]), "#FFAB91"),
    ("legs", poly([(480, 610), (470, 700), (570, 700), (556, 610)]), "#9575CD"),
    ("eye", circle(546, 316, 20), "#FFFFFF"),
], symmetry={"type": "vertical", "x": 516})

# ------------------------------------------------------------ farm animals

add("farm_cow", "Cow", "farm", [
    ("body", ellipse(470, 560, 220, 150), "#FFFFFF"),
    ("leg_back", leg(360, 690, 84, 190), "#ECEFF1"),
    ("leg_front", leg(560, 690, 84, 190), "#FFFFFF"),
    ("tail", poly([(680, 470), (760, 520), (742, 640), (700, 640), (716, 530)]), "#ECEFF1"),
    ("head", ellipse(270, 430, 140, 120), "#FFFFFF"),
    ("ear_left", ellipse(160, 370, 52, 32), "#ECEFF1"),
    ("ear_right", ellipse(380, 370, 52, 32), "#ECEFF1"),
    ("snout", ellipse(250, 490, 88, 56), "#F8BBD0"),
    ("patch_a", ellipse(420, 520, 74, 56), "#616161"),
    ("patch_b", ellipse(560, 600, 60, 46), "#616161"),
    ("eye", circle(300, 400, 22), "#FFFFFF"),
])

add("farm_pig", "Pig", "farm", [
    ("body", ellipse(500, 570, 210, 150), "#F8BBD0"),
    ("leg_back", leg(400, 700, 80, 170), "#F48FB1"),
    ("leg_front", leg(590, 700, 80, 170), "#F8BBD0"),
    ("tail", poly([(700, 500), (770, 480), (760, 560), (712, 545)]), "#F48FB1"),
    ("head", ellipse(300, 470, 130, 118), "#F8BBD0"),
    ("ear_left", poly([(210, 380), (250, 300), (290, 390)]), "#F48FB1"),
    ("ear_right", poly([(320, 385), (370, 305), (392, 390)]), "#F48FB1"),
    ("snout", ellipse(270, 520, 70, 50), "#F48FB1"),
    ("belly", ellipse(500, 640, 140, 60), "#FCE4EC"),
    ("eye", circle(322, 442, 22), "#FFFFFF"),
])

add("farm_sheep", "Sheep", "farm", [
    ("wool_a", circle(420, 540, 130), "#FAFAFA"),
    ("wool_b", circle(560, 520, 118), "#FAFAFA"),
    ("wool_c", circle(500, 630, 120), "#FAFAFA"),
    ("leg_back", leg(420, 720, 60, 150), "#616161"),
    ("leg_front", leg(560, 720, 60, 150), "#616161"),
    ("head", ellipse(690, 490, 96, 108), "#424242"),
    ("ear_left", ellipse(610, 440, 46, 28), "#616161"),
    ("ear_right", ellipse(772, 440, 46, 28), "#616161"),
    ("eye", circle(700, 466, 20), "#FFFFFF"),
])

add("farm_chicken", "Chicken", "farm", [
    ("body", ellipse(500, 560, 170, 150), "#FFF9C4"),
    ("wing", ellipse(540, 560, 90, 70), "#FFF59D"),
    ("tail", poly([(660, 480), (800, 400), (810, 520), (670, 560)]), "#FFE082"),
    ("leg_left", leg(455, 700, 34, 110), "#FFB74D"),
    ("leg_right", leg(545, 700, 34, 110), "#FFB74D"),
    ("head", circle(380, 400, 96), "#FFF9C4"),
    ("comb", star_back(330, 440, 310, 240, 3), "#EF5350"),
    ("beak", poly([(300, 400), (210, 430), (300, 448)]), "#FFB74D"),
    ("wattle", ellipse(320, 470, 34, 44), "#EF5350"),
    ("eye", circle(370, 378, 22), "#FFFFFF"),
])

add("farm_duck", "Duck", "farm", [
    ("body", ellipse(480, 580, 200, 140), "#FFF59D"),
    ("wing", ellipse(510, 580, 104, 76), "#FFF176"),
    ("tail", poly([(660, 520), (770, 480), (760, 580), (668, 590)]), "#FFF176"),
    ("leg_left", leg(440, 700, 34, 90), "#FB8C00"),
    ("leg_right", leg(530, 700, 34, 90), "#FB8C00"),
    ("neck", poly([(320, 540), (300, 380), (378, 372), (392, 546)]), "#FFF59D"),
    ("head", ellipse(340, 350, 100, 88), "#FFF59D"),
    ("beak", poly([(260, 340), (150, 366), (262, 396)]), "#FB8C00"),
    ("eye", circle(358, 326, 22), "#FFFFFF"),
])


def build(aid, title, category, parts, symmetry):
    # The outline is every part's path concatenated, so the trace guide
    # follows the whole drawing rather than only its silhouette — the
    # inner lines are what make it read as a cow rather than a blob.
    outline = " ".join(p for _, p, _ in parts)
    asset = {
        "id": aid,
        "category": category,
        "title": title,
        "canvas": {"width": 1024, "height": 1024},
        "outline": outline,
        "regions": [
            {"id": rid, "path": path, "suggestedColor": colour}
            for rid, path, colour in parts
        ],
    }
    if symmetry:
        asset["symmetryAxis"] = symmetry
    return asset


def main():
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = os.path.join(here, "assets", "art")
    os.makedirs(out, exist_ok=True)

    index = []
    for aid, title, category, parts, symmetry in ANIMALS:
        asset = build(aid, title, category, parts, symmetry)
        with open(os.path.join(out, f"{aid}.json"), "w") as f:
            json.dump(asset, f, indent=2)
            f.write("\n")
        index.append({"id": aid, "category": category, "title": title})
        print(f"  {aid:16s} {len(parts):2d} regions  {category}")

    # An explicit manifest: Flutter can list a bundled asset directory, but
    # only via AssetManifest, and reading one small file is both faster at
    # startup and the place to state category order.
    manifest = {
        "categories": [
            {"id": "dinosaurs", "title": "Dinosaurs", "icon": "dinosaur"},
            {"id": "farm", "title": "Farm", "icon": "farm"},
        ],
        "assets": index,
    }
    with open(os.path.join(out, "index.json"), "w") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")
    print(f"\n{len(index)} assets + index.json")


if __name__ == "__main__":
    main()
