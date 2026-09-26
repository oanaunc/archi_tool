#!/usr/bin/env python3
"""Turns the app's SVG plan export of the Cedar House into a compact, animatable SVG for the website.
Usage: make_plan_anim.py in.svg out.svg"""
import re, sys, xml.etree.ElementTree as ET
NS = {'svg': 'http://www.w3.org/2000/svg', 'ink': 'http://www.inkscape.org/namespaces/inkscape'}
ET.register_namespace('', NS['svg'])
tree = ET.parse(sys.argv[1]); root = tree.getroot()
KEEP = ['L-PLNT', 'A-ELEMENTS', 'A-AREA', 'A-WALL', 'A-GLAZ', 'A-DOOR', 'A-ANNO-DIMS']
LABEL = '{%s}label' % NS['ink']
layers = {g.get(LABEL): g for g in root.iter('{%s}g' % NS['svg']) if g.get(LABEL)}
xs, ys = [], []
out = ['<svg xmlns="http://www.w3.org/2000/svg" class="plan-anim" role="img" aria-label="Floor plan of the Cedar House sample project, drawn in Oanarina Archi Tool" viewBox="VIEWBOX">']
order = 0
def num_pairs(d):
    n = [float(v) for v in re.findall(r'-?\d+(?:\.\d+)?', d)]
    return list(zip(n[0::2], n[1::2]))
for name in KEEP:
    g = layers.get(name)
    if g is None: continue
    out.append(f'<g class="lyr lyr-{name.lower()}">')
    for el in g.iter():
        tag = el.tag.split('}')[1]
        if tag == 'path':
            d = el.get('d'); fill = el.get('fill', 'none'); stroke = el.get('stroke', 'none')
            pts = num_pairs(d)
            if name not in ('L-PLNT',):
                for x, y in pts: xs.append(x); ys.append(y)
            order += 1
            if fill not in ('none', None) and stroke in ('none', None):
                out.append(f'<path class="pf" style="--i:{order}" d="{d}"/>')
            else:
                sw = el.get('stroke-width', '20')
                dash = el.get('stroke-dasharray')
                extra = f' stroke-dasharray="{dash}"' if dash else ''
                if dash:
                    out.append(f'<path class="ps dashed" style="--i:{order}"{extra} d="{d}"/>')
                else:
                    out.append(f'<path class="ps" pathLength="1" style="--i:{order}" d="{d}"/>')
        elif tag == 'text':
            t = ''.join(el.itertext()).strip()
            if not t: continue
            tr = el.get('transform', ''); fs = el.get('font-size', '200'); anc = el.get('text-anchor', 'start')
            span = el.find('svg:tspan', NS); y = span.get('y', '0') if span is not None else '0'
            order += 1
            out.append(f'<text class="pt" style="--i:{order}" transform="{tr}" font-size="{fs}" text-anchor="{anc}" y="{y}">{t}</text>')
    out.append('</g>')
out.append('</svg>')
x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys); m = 900
svg = '\n'.join(out).replace('VIEWBOX', f'{x0-m:.0f} {y0-m:.0f} {x1-x0+2*m:.0f} {y1-y0+2*m:.0f}')
open(sys.argv[2], 'w').write(svg)
print('elements', order, 'bytes', len(svg))
