#!/usr/bin/env python3
"""Builds the 'Cedar House' demo project (contemporary: cedar tower, limestone wings, black canopy) as an .archi file.
Usage: make_cedar_house.py template.archi out.archi   (template = any saved empty project)"""
import json, sys, math
tpl = json.load(open(sys.argv[1])); doc = tpl['document']
nid = [1]
def new_id():
    i = nid[0]; nid[0] += 1; return i
P = lambda x, y: {"x": float(x), "y": float(y)}
doc['info'].update(name="Cedar House", author="Oana Rinaldi", address="Contemporary residence", number="CH-01", latitude=47.6, longitude=-122.3)
doc['levels'] = [{"id": 0, "name": "Ground Floor", "elevation": 0.0, "height": 3200.0},
                 {"id": 1, "name": "Upper Floor", "elevation": 3200.0, "height": 3000.0}]
doc['currentLevel'] = 0
mats = {m['name']: m for m in doc['materials']}
base = dict(next(iter(mats.values())))
def mat(name, rgb, rough=0.8, metal=0.0, cut="SOLID", transp=0.0, tex=None, tile=1000):
    m = dict(base); m.update(name=name, color={"r": rgb[0], "g": rgb[1], "b": rgb[2], "a": 1.0}, roughness=rough, metalness=metal,
                             transparency=transp, cutPattern=cut, textureScale=float(tile)); m.pop('texture', None)
    if tex: m['texture'] = "textures/" + tex
    mats[name] = m
mat("Cedar", (0.46, 0.21, 0.12), 0.55, cut="ANSI32", tex="cedar.jpg", tile=1200)
mat("Limestone", (0.87, 0.84, 0.77), 0.88, tex="limestone.jpg", tile=1200)
mat("Black Fascia", (0.07, 0.07, 0.08), 0.4, 0.5)
mat("Black Metal", (0.06, 0.06, 0.07), 0.35, 0.6)
mat("Concrete Paving", (0.80, 0.78, 0.74), 0.85, tex="concrete.jpg", tile=3000)
mat("Hedge", (0.13, 0.24, 0.11), 0.95, tex="hedge.jpg", tile=800)
mat("Young Leaves", (0.62, 0.70, 0.30), 0.9, tex="leaves.jpg", tile=2200)
mat("Bark", (0.33, 0.27, 0.22), 0.95)
mat("Lawn", (0.33, 0.47, 0.22), 1.0, tex="lawn.jpg", tile=2500)
mat("Oak Floor", (0.76, 0.62, 0.45), 0.55)
mat("White Soffit", (0.93, 0.93, 0.91), 0.7)
mat("Lamp", (1.0, 0.82, 0.58), 0.3)
mat("Glass", (0.55, 0.68, 0.70), 0.03, transp=0.72)
doc['materials'] = list(mats.values())
# PBR maps (normal + roughness) from make_textures.py, and glowing lamp lenses
doc.setdefault('variables', {})
for mname, tex, k in [("Cedar", "cedar", 1.0), ("Limestone", "limestone", 0.8), ("Concrete Paving", "concrete", 0.7), ("Lawn", "lawn", 0.9),
                      ("Hedge", "hedge", 1.0), ("Young Leaves", "leaves", 1.0)]:
    doc['variables']["MATMAPS:" + mname.upper()] = json.dumps({"normal": "textures/%s_n.jpg" % tex, "roughness": "textures/%s_r.jpg" % tex,
                                                              "normalStrength": k}, sort_keys=True)
doc['variables']["MATEMIT:LAMP"] = "3"
elements, entities = [], []
def el(geom, layer, material=None, name="", level=0):
    i = new_id(); e = {"id": i, "level": level, "name": name, "layer": layer, "geometry": geom, "props": {}}
    if material: e["material"] = material
    elements.append(e); return i
def wall(a, b, h, material, t=300):
    return el({"type": "wall", "start": P(*a), "end": P(*b), "thickness": float(t), "height": float(h), "baseOffset": 0.0,
               "justification": "center", "bulge": 0.0, "sweeps": []}, "A-WALL", material)
def op(kind, host, off, w, h, sill=0.0, door="single", material="Black Metal", flip=False, mullions=None, transoms=0):
    if mullions is None:  # slender black mullions every ~1.2 m on wide glazing
        mullions = max(0, int(round(w / 1200.0)) - 1) if kind == "window" else 0
    return el({"type": kind, "kind": kind, "hostWall": host, "offset": float(off), "width": float(w), "height": float(h), "sill": float(sill),
               "flipHand": flip, "flipFacing": False, "doorStyle": door, "windowStyle": "fixed", "frameWidth": 60.0,
               "mullions": mullions, "transoms": transoms},
              "A-GLAZ" if kind == "window" else "A-DOOR", material)
def slab(pts, thick, top, material, layer="A-ELEMENTS", name="", level=0):
    return el({"type": "slab", "boundary": [P(*p) for p in pts], "holes": [], "thickness": float(thick), "topOffset": float(top)}, layer, material, name, level)
def rect(x0, y0, x1, y1): return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
def roof(pts, kind, pitch, base_off, overhang, material="Black Fascia", thick=320, eave=0):
    return el({"type": "roof", "boundary": [P(*p) for p in pts], "kind": kind, "pitch": float(pitch), "thickness": float(thick),
               "overhang": float(overhang), "baseOffset": float(base_off), "eaveEdge": eave}, "A-ELEMENTS", material)
def room(pts, name, num, level=0):
    return el({"type": "space", "boundary": [P(*p) for p in pts], "name": name, "number": num, "height": 2800.0}, "A-AREA", None, name, level)
def comp(cat, x, y, sx, sy, sz, name, material, rot=0.0):
    return el({"type": "component", "category": cat, "position": P(x, y), "rotation": rot, "size": {"x": float(sx), "y": float(sy), "z": float(sz)}, "baseOffset": 0.0}, "A-ELEMENTS", material, name)

# --- Left limestone wing (two storeys, flat roof with black fascia)
L = [wall((0, 1500), (6000, 1500), 6200, "Limestone"), wall((6000, 1500), (6000, 10000), 6200, "Limestone"),
     wall((6000, 10000), (0, 10000), 6200, "Limestone"), wall((0, 10000), (0, 1500), 6200, "Limestone")]
op("window", L[0], 1500, 2400, 1100, 900); op("window", L[0], 4300, 2400, 1500, 3800)
op("window", L[3], 3500, 2200, 1100, 900); op("window", L[3], 6000, 1800, 1500, 3800)
op("window", L[2], 3000, 3000, 2400, 300, material="Black Metal", transoms=1)
roof(rect(0, 1500, 6000, 10000), "flat", 0, 6200, 700)

# --- Cedar tower (two storeys, thin shed roof plate with deep overhang)
T = [wall((6000, 0), (11000, 0), 7200, "Cedar"), wall((11000, 0), (11000, 7500), 7200, "Cedar"),
     wall((11000, 7500), (6000, 7500), 7200, "Cedar"), wall((6000, 7500), (6000, 0), 7200, "Cedar")]
op("window", T[0], 1650, 1300, 5300, 1600, transoms=2)  # tall vertical window strip, floor-line transoms
op("window", T[2], 2500, 1600, 1400, 4200)
roof(rect(6000, 0, 11000, 7500), "shed", 4, 7200, 1300, eave=2, thick=300)

# --- Entry wing: recessed glazed entry under a long black canopy, cedar panel, limestone
e1 = wall((11000, 3200), (17600, 3200), 3300, "Limestone")
e2 = wall((17600, 3200), (21000, 3200), 3300, "Cedar")
op("window", e1, 700, 900, 2900, 0)                    # narrow full-height glazing beside the tower
op("door", e1, 5300, 1100, 2700, 0, door="single")     # pivot entrance door
op("window", e1, 6250, 600, 2700, 0)                   # sidelight
op("window", e2, 900, 1500, 2800, 200)                 # corner glazing box
wall((21000, 3200), (21000, 10000), 3300, "Limestone"); wall((21000, 10000), (11000, 10000), 3300, "Limestone")
wall((11000, 7500), (11000, 10000), 3300, "Limestone")
slab([(11000, -400), (21600, -400), (21600, 10300), (11000, 10300)], 450, 3750, "Black Fascia", name="Canopy roof")
# upper limestone box rising above the canopy
U = [wall((11200, 5600), (16200, 5600), 6400, "Limestone"), wall((16200, 5600), (16200, 10000), 6400, "Limestone")]
op("window", U[0], 3900, 1400, 1400, 4300)
roof(rect(11200, 5600, 16200, 10000), "flat", 0, 6400, 350)
# partitions
p = wall((14600, 3200), (14600, 10000), 3000, "Limestone", 120); op("opening", p, 3400, 1800, 2400, 0, material=None)
# porch, steps and forecourt
slab(rect(11600, 0, 17600, 3200), 200, 180, "Concrete Paving", name="Porch")
slab(rect(12900, -700, 17100, 0), 160, 120, "Concrete Paving", name="Upper step")
slab(rect(12600, -1400, 17400, -700), 160, 0, "Concrete Paving", name="Lower step")
# white soffits under the overhangs (flat roofs and the entrance canopy)
def grow(r, d): return [(r[0][0] - d, r[0][1] - d), (r[1][0] + d, r[1][1] - d), (r[2][0] + d, r[2][1] + d), (r[3][0] - d, r[3][1] + d)]
def soffit(r, overhang, underside):
    el({"type": "slab", "boundary": [P(*p) for p in grow(r, overhang - 5)], "holes": [[P(*p) for p in grow(r, 140)]],
        "thickness": 25.0, "topOffset": float(underside - 2)}, "A-ELEMENTS", "White Soffit", "Soffit")
soffit(rect(0, 1500, 6000, 10000), 700, 6200)
soffit(rect(11200, 5600, 16200, 10000), 350, 6400)
el({"type": "slab", "boundary": [P(*p) for p in [(11005, -395), (21595, -395), (21595, 10295), (11005, 10295)]], "holes": [],
    "thickness": 25.0, "topOffset": 3298.0}, "A-ELEMENTS", "White Soffit", "Canopy soffit")
slab(rect(-4000, -12000, 26000, -1100), 120, 0, "Concrete Paving", "C-TOPO", "Forecourt")
slab(rect(-10000, -18000, 32000, 20000), 60, -130, "Lawn", "C-TOPO", "Lawn")
# floors
slab(rect(-150, 1350, 6150, 10150), 250, 0, "Oak Floor"); slab(rect(5850, -150, 11150, 7650), 250, 0, "Oak Floor")
slab(rect(11000, 3050, 21150, 10150), 250, 0, "Oak Floor")
slab(rect(0, 1500, 11000, 10000), 250, 0, "Oak Floor", name="Upper floor", level=1)
el({"type": "stair", "start": P(10200, 1300), "direction": math.pi / 2, "width": 1100.0, "totalRise": 3200.0, "riserCount": 18,
    "treadDepth": 280.0, "kind": "straight"}, "A-ELEMENTS", "Oak Floor")
# hedges
comp("Planting", 3200, 700, 5600, 700, 750, "Hedge", "Hedge")
comp("Planting", 8500, -700, 5200, 700, 650, "Hedge", "Hedge")
comp("Planting", 19300, 2500, 3600, 700, 650, "Hedge", "Hedge")
comp("Planting", 11400, 1600, 700, 2600, 800, "Hedge", "Hedge")
# rooms
room(rect(150, 1650, 5850, 9850), "Living", "01"); room(rect(6150, 150, 10850, 7350), "Stair Hall", "02")
room(rect(11150, 3350, 14540, 9850), "Entry", "03"); room(rect(14660, 3350, 20850, 9850), "Kitchen & Dining", "04")
room(rect(11600, 150, 17600, 3150), "Porch", "05")
room(rect(150, 1650, 10850, 9850), "Upper Lounge", "11", level=1)
comp("Furniture", 3000, 5200, 2600, 950, 780, "Sofa", "Oak Floor"); comp("Furniture", 17800, 6600, 2400, 1000, 750, "Dining table", "Oak Floor")
comp("Furniture", 19800, 8900, 2200, 650, 900, "Kitchen", "Limestone")

# --- slender trees (entities: trunk + tall narrow crowns)
def solid(kind, x, y, z, size, material):
    entities.append({"id": new_id(), "layer": "L-PLNT", "color": "ByLayer", "props": {"material": material},
        "geometry": {"type": "solid", "kind": kind, "origin": {"x": float(x), "y": float(y), "z": float(z)},
                     "size": {"x": float(size[0]), "y": float(size[1]), "z": float(size[2])}, "profile": [], "height": 0.0, "rotation": 0.0,
                     "meshVertices": [], "meshTriangles": []}})
def tree(x, y, s=1.0, seed=1):
    """Slender deciduous tree: tapered trunk and an irregular ovoid crown of leaf clusters (inner dark mass + outer tufts)."""
    import random
    rnd = random.Random(seed)
    solid("cone", x, y, 0, (95 * s, 45 * s, 3400 * s), "Bark")
    base, top, rx = 2300 * s, 6500 * s, 1250 * s
    cz = (base + top) / 2; rz = (top - base) / 2
    solid("sphere", x, y, cz, (rx * 0.62, rx * 0.62, rx * 0.62), "Young Leaves")                  # inner mass
    solid("sphere", x, y, cz + rz * 0.45, (rx * 0.5, rx * 0.5, rx * 0.5), "Young Leaves")
    solid("sphere", x, y, cz - rz * 0.4, (rx * 0.55, rx * 0.55, rx * 0.55), "Young Leaves")
    for k in range(44):
        # points on the crown ellipsoid shell, clusters sized smaller towards the top
        u = rnd.uniform(-0.85, 0.95); a = rnd.uniform(0, 2 * math.pi)
        rr = math.sqrt(max(0.0, 1 - u * u)) * rnd.uniform(0.8, 1.0)
        px, py, pz = x + math.cos(a) * rx * rr, y + math.sin(a) * rx * rr, cz + u * rz * 0.92
        r = rx * rnd.uniform(0.2, 0.3) * (1.05 - 0.35 * (u + 1) / 2)
        solid("sphere", px, py, pz, (r, r, r), "Young Leaves")
for i, (x, y, s) in enumerate([(4900, 400, 0.95), (11500, 2300, 0.85), (-2500, 3500, 1.05), (23500, 5000, 1.0), (-3000, 12000, 1.15), (24500, 13000, 1.1),
                                (-7500, 7000, 1.2), (29000, -2000, 1.1)]):
    tree(x, y, s, seed=11 + i)
# --- outdoor lights: wall lights at the entrance, bollards along the steps (glowing lenses + light sources)
def light(kind, x, y, z, lumens, cct=2700, beam=None, target=None):
    props = {"light": kind, "z": "%g" % z, "lumens": "%g" % lumens, "cct": "%g" % cct}
    if beam: props["beam"] = "%g" % beam
    if target: props.update(targetX="%g" % target[0], targetY="%g" % target[1], targetZ="%g" % target[2])
    entities.append({"id": new_id(), "layer": "LIGHTS", "color": "ByLayer", "props": props, "geometry": {"type": "point", "p": P(x, y)}})
for lx in (15550, 17150):
    solid("box", lx - 55, 2935, 1960, (110, 115, 320), "Black Metal")   # wall light housing
    solid("box", lx - 45, 2925, 2085, (90, 20, 40), "Lamp")
    light("spot", lx, 2900, 2080, 700, beam=100, target=(lx, 2700, 0))
for (bx, by) in [(12300, -500), (17700, -500), (12300, -3800), (17700, -3800)]:
    solid("cylinder", bx, by, 0, (70, 70, 700), "Black Metal")
    solid("cylinder", bx, by, 600, (74, 74, 90), "Lamp")
    solid("cylinder", bx, by, 690, (80, 80, 30), "Black Metal")
    light("point", bx, by, 640, 250)
doc['layers'] += [dict(doc['layers'][0], name="L-PLNT", color={"r": 0.4, "g": 0.72, "b": 0.35, "a": 1.0}, lineweight=0.18),
                  dict(doc['layers'][0], name="LIGHTS", color={"r": 1.0, "g": 0.85, "b": 0.3, "a": 1.0}, lineweight=0.13),
                  dict(doc['layers'][0], name="C-TOPO", color={"r": 0.5, "g": 0.55, "b": 0.45, "a": 1.0}, linetype="Hidden", lineweight=0.13)]
def dim(a, b, loc, rot):
    entities.append({"id": new_id(), "layer": "A-ANNO-DIMS", "color": "ByLayer", "props": {},
        "geometry": {"type": "dimension", "kind": "linear", "points": [P(*a), P(*b), P(*loc)], "style": "Architectural 1:100", "rotation": rot}})
dim((0, 1500), (21000, 1500), (10500, 12500), 0.0); dim((0, 1500), (0, 10000), (-2000, 5750), math.pi / 2)
V = lambda x, y, z: {"x": float(x), "y": float(y), "z": float(z)}
def cam(name, eye, target, fov=42):
    doc['namedViews'].append({"name": name, "center": P(target[0], target[1]), "height": 20000.0,
                              "camera": {"eye": V(*eye), "target": V(*target), "fov": float(fov), "orthographic": False}})
doc['namedViews'] = []
cam("Front", (5200, -18500, 1500), (10800, 3500, 3200), 38)
cam("Aerial", (-9000, -19000, 13000), (10500, 4500, 1500), 40)
cam("Corner", (-9500, -11500, 2200), (9000, 4000, 3200), 42)
doc['elements'] = elements; doc['entities'] = entities; doc['nextID'] = nid[0]
json.dump(tpl, open(sys.argv[2], 'w'), indent=1, sort_keys=True)
print('elements', len(elements), 'entities', len(entities))
