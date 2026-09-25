#!/usr/bin/env python3
"""Builds the 'Nordic House' demo project (Scandinavian contemporary) as an .archi file.
Usage: make_nordic_house.py template.archi out.archi   (template = any saved empty project)"""
import json, sys, math
tpl = json.load(open(sys.argv[1]))
doc = tpl['document']
nid = [1]
def new_id():
    i = nid[0]; nid[0] += 1; return i
P = lambda x, y: {"x": float(x), "y": float(y)}

doc['info'].update(name="Nordic House", author="Oana Rinaldi", address="Oslofjord, Norway", latitude=59.91, longitude=10.75, number="ND-01")
doc['levels'] = [{"id": 0, "name": "Ground Floor", "elevation": 0.0, "height": 3400.0}]
doc['currentLevel'] = 0
mats = {m['name']: m for m in doc['materials']}
def mat(name, rgb, rough=0.8, metal=0.0, cut="SOLID"):
    m = dict(next(iter(mats.values())))
    m.update(name=name, color={"r": rgb[0], "g": rgb[1], "b": rgb[2], "a": 1.0}, roughness=rough, metalness=metal, transparency=0.0, cutPattern=cut)
    m.pop('texture', None)
    mats[name] = m
mat("Charred Timber", (0.22, 0.20, 0.18), 0.9, cut="ANSI32")
mat("Spruce", (0.86, 0.74, 0.56), 0.7, cut="ANSI32")
mat("Black Standing Seam", (0.16, 0.16, 0.17), 0.42, 0.55)
mat("Black Metal", (0.07, 0.07, 0.08), 0.35, 0.6)
mat("Oak Floor", (0.76, 0.62, 0.45), 0.55)
mat("White Plaster", (0.95, 0.94, 0.91), 0.9)
mat("Pine Needles", (0.10, 0.22, 0.13), 0.95)
mat("Birch Leaves", (0.42, 0.55, 0.22), 0.95)
mat("Bark", (0.30, 0.22, 0.16), 0.95)
mat("Birch Bark", (0.88, 0.86, 0.80), 0.8)
mat("Meadow", (0.36, 0.47, 0.25), 1.0)
doc['materials'] = list(mats.values())

elements, entities = [], []
def el(geom, layer, material=None, name="", props=None):
    i = new_id()
    e = {"id": i, "level": 0, "name": name, "layer": layer, "geometry": geom, "props": props or {}}
    if material: e["material"] = material
    elements.append(e); return i

H = 3400.0
def wall(a, b, t=300, h=H, material="Charred Timber"):
    return el({"type": "wall", "start": P(*a), "end": P(*b), "thickness": float(t), "height": h, "baseOffset": 0.0,
               "justification": "center", "bulge": 0.0, "sweeps": []}, "A-WALL", material)
def opening(kind, host, off, w, h, sill=0.0, door="single", win="fixed", flip=False, material=None, facing=False):
    return el({"type": kind, "kind": kind, "hostWall": host, "offset": float(off), "width": float(w), "height": float(h), "sill": float(sill),
               "flipHand": flip, "flipFacing": facing, "doorStyle": door, "windowStyle": win, "frameWidth": 60.0},
              "A-GLAZ" if kind == "window" else "A-DOOR", material)
def slab(pts, thick=300, top=0.0, material="Oak Floor", holes=()):
    return el({"type": "slab", "boundary": [P(*p) for p in pts], "holes": [[P(*p) for p in h] for h in holes],
               "thickness": float(thick), "topOffset": float(top)}, "A-ELEMENTS", material)
def roof(pts, eave=0, pitch=42, material="Black Standing Seam", kind="gable"):
    return el({"type": "roof", "boundary": [P(*p) for p in pts], "kind": kind, "pitch": float(pitch), "thickness": 260.0,
               "overhang": 450.0, "baseOffset": H, "eaveEdge": eave}, "A-ELEMENTS", material)
def room(pts, name, num):
    return el({"type": "space", "boundary": [P(*p) for p in pts], "name": name, "number": num, "height": 2700.0}, "A-AREA", None, name)
def comp(cat, x, y, sx, sy, sz, rot=0.0, name="", material="Spruce"):
    return el({"type": "component", "category": cat, "position": P(x, y), "rotation": rot, "size": {"x": sx, "y": sy, "z": sz}, "baseOffset": 0.0}, "A-ELEMENTS", material, name)

# --- Volume A: living (18 x 7.2 m, ridge east-west)
aS = wall((0, 0), (18000, 0)); aE = wall((18000, 0), (18000, 7200)); aN = wall((18000, 7200), (0, 7200)); aW = wall((0, 7200), (0, 0))
for off in (1900, 8300):
    opening("window", aS, off, 2600, 2700, 250, material="Black Metal")
opening("door", aS, 5100, 2600, 2700, 0, door="sliding", material="Black Metal")
opening("door", aS, 15200, 1100, 2400, 0, door="single", material="Spruce")
opening("window", aS, 17100, 700, 1800, 600, material="Black Metal")
opening("window", aW, 3600, 2600, 2900, 200, material="Black Metal")
opening("window", aE, 5400, 900, 1200, 1100, material="Black Metal")
opening("opening", aN, 8500, 3000, 2700, 0)                       # glass link to volume B
opening("window", aN, 14600, 2200, 1100, 1000, material="Black Metal")
opening("window", aN, 3000, 800, 800, 1500, material="Black Metal")
p1 = wall((12000, 0), (12000, 7200), 120, material="White Plaster"); opening("door", p1, 5400, 900, 2150, flip=True, material="Spruce")
p2 = wall((12000, 3600), (18000, 3600), 120, material="White Plaster"); opening("door", p2, 3000, 800, 2150, material="Spruce")
slab([(-150, -150), (18150, -150), (18150, 7350), (-150, 7350)])
roof([(0, 0), (18000, 0), (18000, 7200), (0, 7200)], eave=0)

# --- Glass link
wall((8000, 7200), (8000, 9500), 60, 2900, "Black Metal")
el({"type": "curtainWall", "start": P(8000, 7350), "end": P(8000, 9350), "height": 2900.0, "baseOffset": 0.0, "gridU": 1000.0, "gridV": 1450.0, "mullionSize": 50.0}, "A-WALL", "Glass")
el({"type": "curtainWall", "start": P(11000, 9350), "end": P(11000, 7350), "height": 2900.0, "baseOffset": 0.0, "gridU": 1000.0, "gridV": 1450.0, "mullionSize": 50.0}, "A-WALL", "Glass")
elements.pop(-3)  # keep the link fully glazed (drop the helper wall)
slab([(7900, 7200), (11100, 7200), (11100, 9500), (7900, 9500)])
slab([(7750, 7100), (11250, 7100), (11250, 9600), (7750, 9600)], 250, 3150, "Black Standing Seam")

# --- Volume B: bedrooms (7 x 12 m, ridge north-south)
bS = wall((6000, 9500), (13000, 9500)); bE = wall((13000, 9500), (13000, 21500)); bN = wall((13000, 21500), (6000, 21500)); bW = wall((6000, 21500), (6000, 9500))
opening("opening", bS, 3500, 3000, 2700, 0)
for off in (2000, 6000, 10000):
    opening("window", bE, off, 1800, 2200, 500, material="Black Metal")
opening("window", bN, 3500, 4600, 3000, 200, material="Black Metal")
for off in (2000, 10000):
    opening("window", bW, off, 1200, 1500, 900, material="Black Metal")
q1 = wall((6000, 13500), (13000, 13500), 120, material="White Plaster"); opening("door", q1, 1400, 900, 2150, material="Spruce")
q2 = wall((6000, 17500), (13000, 17500), 120, material="White Plaster"); opening("door", q2, 1400, 900, 2150, flip=True, material="Spruce")
slab([(5850, 9350), (13150, 9350), (13150, 21650), (5850, 21650)])
roof([(13000, 9500), (13000, 21500), (6000, 21500), (6000, 9500)], eave=0)

# --- Spruce deck and entrance step
slab([(-600, -3400), (11600, -3400), (11600, -150), (-600, -150)], 180, 0.0, "Spruce")
slab([(14400, -1500), (16600, -1500), (16600, -150), (14400, -150)], 180, 0.0, "Spruce")

# --- Rooms
room([(150, 150), (11940, 150), (11940, 7050), (150, 7050)], "Living & Kitchen", "01")
room([(12060, 150), (17850, 150), (17850, 3540), (12060, 3540)], "Entrance", "02")
room([(12060, 3660), (17850, 3660), (17850, 7050), (12060, 7050)], "Bath", "03")
room([(8030, 7350), (10970, 7350), (10970, 9350), (8030, 9350)], "Glass Link", "04")
room([(6150, 9650), (12850, 9650), (12850, 13440), (6150, 13440)], "Study", "05")
room([(6150, 13560), (12850, 13560), (12850, 17440), (6150, 17440)], "Bedroom", "06")
room([(6150, 17560), (12850, 17560), (12850, 21350), (6150, 21350)], "Main Bedroom", "07")

# --- Furniture
comp("Furniture", 3000, 2300, 2800, 950, 780, 0, "Sofa", "Spruce")
comp("Furniture", 3000, 3900, 1200, 700, 420, 0, "Coffee table", "Oak Floor")
comp("Furniture", 7600, 3600, 2400, 1000, 750, 0, "Dining table", "Oak Floor")
comp("Furniture", 5500, 6700, 4200, 650, 900, 0, "Kitchen", "White Plaster")
comp("Furniture", 9900, 15500, 1800, 2100, 500, 0, "Bed", "Spruce")
comp("Furniture", 9900, 19400, 2000, 2200, 500, 0, "Bed", "Spruce")
comp("Furniture", 9500, 11200, 1600, 750, 740, 0, "Desk", "Oak Floor")
comp("Fixture", 16900, 5400, 800, 1700, 550, math.pi / 2, "Bath tub", "White Plaster")

# --- Site: meadow and trees (stylized pines and birches)
el({"type": "slab", "boundary": [P(-9000, -9000), P(27000, -9000), P(27000, 28000), P(-9000, 28000)], "holes": [], "thickness": 60.0, "topOffset": -200.0},
   "C-TOPO", "Meadow", "Meadow")
def solid(kind, x, y, z, size, material):
    entities.append({"id": new_id(), "layer": "L-PLNT", "color": "ByLayer", "props": {"material": material},
                     "geometry": {"type": "solid", "kind": kind, "origin": {"x": float(x), "y": float(y), "z": float(z)},
                                  "size": {"x": float(size[0]), "y": float(size[1]), "z": float(size[2])}, "profile": [], "height": 0.0,
                                  "rotation": 0.0, "meshVertices": [], "meshTriangles": []}})
def pine(x, y, s=1.0):
    solid("cylinder", x, y, -200, (180 * s, 180 * s, 1800 * s), "Bark")
    solid("cone", x, y, 900 * s, (1700 * s, 0, 4200 * s), "Pine Needles")
    solid("cone", x, y, 3300 * s, (1250 * s, 0, 3600 * s), "Pine Needles")
def birch(x, y, s=1.0):
    solid("cylinder", x, y, -200, (130 * s, 130 * s, 3200 * s), "Birch Bark")
    solid("sphere", x, y, 4200 * s, (1500 * s, 1500 * s, 1500 * s), "Birch Leaves")
for (x, y, sc) in [(-5200, 12000, 1.3), (-3000, 17500, 1.1), (1200, 22500, 1.4), (-6500, 4200, 1.2), (19500, 24000, 1.25),
                   (22500, 16500, 1.15), (24000, 9800, 1.35), (3000, 15000, 1.0), (16800, 26000, 1.05), (-7000, 23500, 1.2)]:
    pine(x, y, sc)
for (x, y, sc) in [(21500, -3000, 1.0), (-4200, -5200, 0.9), (17000, 12500, 1.1), (1500, 11000, 0.85)]:
    birch(x, y, sc)
doc['layers'] += [dict(doc['layers'][0], name="L-PLNT", color={"r": 0.35, "g": 0.7, "b": 0.35, "a": 1.0}, lineweight=0.18),
                  dict(doc['layers'][0], name="C-TOPO", color={"r": 0.45, "g": 0.55, "b": 0.35, "a": 1.0}, linetype="Hidden", lineweight=0.13)]

# --- Dimensions (architectural style)
def dim(a, b, loc, rot=None):
    g = {"type": "dimension", "kind": "linear", "points": [P(*a), P(*b), P(*loc)], "style": "Architectural 1:100"}
    if rot is not None: g["rotation"] = rot
    entities.append({"id": new_id(), "layer": "A-ANNO-DIMS", "color": "ByLayer", "geometry": g, "props": {}})
dim((0, 0), (18000, 0), (9000, -4600), 0.0)
dim((0, 0), (0, 7200), (-1600, 3600), math.pi / 2)
dim((6000, 21500), (13000, 21500), (9500, 23100), 0.0)
dim((13000, 9500), (13000, 21500), (14600, 15500), math.pi / 2)

doc['elements'] = elements
doc['entities'] = entities
doc['nextID'] = nid[0]
doc['currentLayer'] = "0"
json.dump(tpl, open(sys.argv[2], 'w'), indent=1, sort_keys=True)
print('elements', len(elements), 'entities', len(entities))
