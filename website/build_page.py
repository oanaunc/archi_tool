#!/usr/bin/env python3
"""Generates oanarina_website/archi-tool.html from the Photo Editor page's shared layout
(header, full menu, footer, motion scripts) and the Archi Tool content below."""
import re, sys, json, hashlib, os
SITE = sys.argv[1]
REL = json.load(open(os.path.join(os.path.dirname(__file__), 'release.json')))
src = open(os.path.join(SITE, 'photo-editor.html'), encoding='utf-8').read()

def sub1(pattern, repl, s):
    out, n = re.subn(pattern, lambda m: repl, s, count=1, flags=re.S)
    assert n == 1, pattern
    return out

page = src
page = sub1(r'<meta name="description" content="[^"]*">',
            '<meta name="description" content="Oanarina Archi Tool: a free native Mac app for architectural drafting, building design (BIM), 3D modelling, rendering and printing, with an AutoCAD-style command line and scripting for AI agents.">', page)
page = page.replace('js/motion-manifest.js?v=20260921-midjourney', f'js/motion-manifest.js?v={REL["asset_version"]}-archi')
page = sub1(r'<title>.*?</title>', '<title>Oanarina Archi Tool — Oana Rinaldi</title>', page)
page = sub1(r'<link rel="canonical" href="[^"]*">', '<link rel="canonical" href="https://oanarinaldi.com/archi-tool.html">', page)
page = page.replace('</style>\n<link rel="canonical"', '''.archi-accent { color:#d9a400; }
.archi-grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(150px,1fr)); gap:14px; margin:10px 0 60px; }
.archi-grid div { background:#f5f5f5; padding:18px; text-align:center; }
.archi-grid strong { display:block; font-size:28px; color:#d9a400; }
.archi-code { background:#1e1f22; color:#e6e6e6; padding:18px 22px; font-family:Menlo,monospace; font-size:13px; overflow:auto; margin:18px 0; }
.archi-code b { color:#f5c518; font-weight:normal; }
</style>
<link rel="canonical"''', 1)


HERE = os.path.dirname(__file__)
if REL.get('pending'):
    STATUS = 'The first preview build is being finished and notarized by Apple. It will appear here very soon.'
    BUTTON = '<a class="btn oneMusic-btn" href="https://github.com/oanaunc/archi_tool">Follow on GitHub <i class="fa fa-angle-double-right" aria-hidden="true"></i></a>'
else:
    STATUS = f'Version {REL["version"]} · Apple silicon and Intel · {REL["size_mb"]} MB. {REL["signing"]}'
    BUTTON = f'<a class="btn oneMusic-btn" id="download-button" href="downloads/archi-tool/{REL["dmg"]}?v={REL["sha_short"]}" download>Download for Mac <i class="fa fa-angle-double-right" aria-hidden="true"></i></a>'
links = []
if REL.get('guide'): links.append('<a href="archi-tool-guide.html">Detailed user guide</a>')
if not REL.get('pending'): links.append('<a href="downloads/archi-tool/SHA256SUMS.txt">Download checksum</a>')
if REL.get('source_public'): links.append('<a href="https://github.com/oanaunc/archi_tool">Source code</a>')
gallery = ''.join(f'<figure><img src="{g["src"]}?v={REL["asset_version"]}" alt="{g["alt"]}" loading="lazy"><figcaption>{g["caption"]}</figcaption></figure>' for g in REL.get('gallery', []))
gallery = f'<div class="at-gallery">{gallery}</div>' if gallery else ''
TITLES = REL.get('tutorial_titles', [])
tut_cards = []
vids = {t['n']: t for t in REL.get('tutorials', [])}
for i, (title, desc) in enumerate(TITLES, 1):
    t = vids.get(i)
    if t:
        media = f'<video controls preload="none" playsinline poster="{t["poster"]}?v={REL["asset_version"]}"><source src="{t["src"]}?v={REL["asset_version"]}" type="video/mp4"></video>'
        meta = f'{desc} · {t["duration"]}'
    else:
        media = f'<div class="at-tut-soon">{i:02d}</div>'
        meta = f'{desc} · coming soon'
    tut_cards.append(f'<article class="at-tut">{media}<div class="t"><h5>{i:02d} · {title}</h5><p>{meta}</p></div></article>')
tpl = open(os.path.join(HERE, 'page_main.html'), encoding='utf-8').read()
for k, v in {'V': REL['asset_version'], 'FEATURES': str(REL['features']), 'TOTALFEATURES': str(REL['total_features']),
             'COMMANDS': str(REL['commands']), 'TESTS': str(REL['tests']), 'FORMATS': str(REL['formats']),
             'STATUS': STATUS, 'NOTE': REL['note'], 'BUTTON': BUTTON, 'IMPORTS': REL['imports'], 'EXPORTS': REL['exports'],
             'LINKS': ' · '.join(links), 'GALLERY': gallery, 'TUTORIALS': ''.join(tut_cards)}.items():
    tpl = tpl.replace('{{' + k + '}}', v)
main = tpl
page = page.replace('</head>', open(os.path.join(HERE, 'page_assets.html'), encoding='utf-8').read().replace('{{V}}', REL['asset_version']) + '\n</head>', 1)

start = page.index('<section class="contact-area section-padding-100 bg-img bg-overlay has-bg-img editor-breadcrumb"')
end = page.index('</main>', start) + len('</main>')
page = page[:start] + main + page[end:]
assert 'photo-editor/' not in page.split('<!-- ##### Footer Area Start')[0].split('</header>')[1], 'leftover photo-editor content'
open(os.path.join(SITE, 'archi-tool.html'), 'w', encoding='utf-8').write(page)
print('wrote archi-tool.html', len(page))
