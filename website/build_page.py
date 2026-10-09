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
            '<meta name="description" content="Oanarina Archi Tool: a free app for Mac and Windows for architectural drafting, building design (BIM), 3D modelling, rendering and printing, with an AutoCAD-style command line and scripting for AI agents.">' if REL.get('windows') else
            '<meta name="description" content="Oanarina Archi Tool: a free native Mac app for architectural drafting, building design (BIM), 3D modelling, rendering and printing, with an AutoCAD-style command line and scripting for AI agents.">', page)
page = page.replace('js/motion-manifest.js?v=20260921-midjourney', f'js/motion-manifest.js?v={REL["asset_version"]}-archi')
page = sub1(r'<title>.*?</title>', '<title>Oanarina Archi Tool — Oana Rinaldi</title>', page)
page = sub1(r'<link rel="canonical" href="[^"]*">', '<link rel="canonical" href="https://www.oanarinaldi.com/archi-tool.html">', page)
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
DL_SVG = '<svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true"><path d="M12 3v12m0 0-5-5m5 5 5-5M4 20h16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>'
if REL.get('pending'):
    HEROBUTTON = FINALBUTTON = '<a class="pe-btn pe-btn-primary" href="#studio"><span>Download coming soon<small>Notarization in progress</small></span></a>'
else:
    href = f'downloads/archi-tool/{REL["dmg"]}?v={REL["sha_short"]}'
    HEROBUTTON = f'<a class="pe-btn pe-btn-primary" id="download-button" href="{href}" download>{DL_SVG}<span>Download for Mac<small>Free · {REL["size_mb"]} MB · notarized by Apple</small></span></a>'
    FINALBUTTON = f'<a class="pe-btn pe-btn-primary" href="{href}" download><span>Download for Mac<small>Free · {REL["size_mb"]} MB</small></span></a>'
WIN = REL.get('windows')
if WIN and not REL.get('pending'):
    whref = f'downloads/archi-tool/{WIN["exe"]}?v={WIN["sha_short"]}'
    HEROBUTTON += f'<a class="pe-btn pe-btn-primary" id="download-button-windows" href="{whref}" download>{DL_SVG}<span>Download for Windows<small>Free · {WIN["size_mb"]} MB · Windows 10 and 11</small></span></a>'
    FINALBUTTON += f'<a class="pe-btn pe-btn-primary" href="{whref}" download><span>Download for Windows<small>Free · {WIN["size_mb"]} MB</small></span></a>'
    FINALBUTTON = f'<div class="at-final-buttons">{FINALBUTTON}</div>'
    STATUS = (f'Version {REL["version"]}. Mac: Apple silicon and Intel, notarized by Apple. '
              'Windows 10 and 11 (64-bit): the installer is not code-signed yet, so if Windows shows “Windows protected your PC”, click More info, then Run anyway.')
    EYEBROW = 'Free for Mac and Windows · open source · no account'
    CHIPS = '<li>macOS 14 or later</li><li>Windows 10 &amp; 11</li><li>DXF · IFC · PDF</li><li>GPL-3.0</li>'
    PLATFORM = 'macOS 14 or later (Apple silicon and Intel) · Windows 10 and 11 (64-bit)'
    DEVICE = 'computer'
    OSVERSION = 'macOS or Windows version'
else:
    EYEBROW = 'Free for Mac · open source · no account'
    CHIPS = '<li>macOS 14 or later</li><li>Apple silicon &amp; Intel</li><li>DXF · IFC · PDF</li><li>GPL-3.0</li>'
    PLATFORM = 'macOS 14 or later · Apple silicon and Intel'
    DEVICE = 'Mac'
    OSVERSION = 'macOS version'
ICONS = {
 'Start': '<rect x="3" y="4" width="18" height="16" rx="2" fill="none" stroke="currentColor" stroke-width="1.7"/><path d="M10 9.5v5l4.5-2.5z" fill="currentColor"/>',
 'Command': '<path d="m5 8 4 4-4 4M11 16h8" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>',
 'Draw': '<path d="M4 20 20 4M4 20h6M4 20v-6" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/>',
 'Walls': '<path d="M3 5h18v14H3zM3 12h18M9 5v7M15 12v7" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/>',
 'Openings': '<path d="M4 20V4h16v16M4 20h16M12 4v16M4 12h16" fill="none" stroke="currentColor" stroke-width="1.7"/>',
 'Roofs': '<path d="M2 12 12 4l10 8M5 10v10h14V10M9 20v-5h6v5" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/>',
 'Rooms': '<path d="M3 3h18v18H3zM3 12h9V3M12 12v9" fill="none" stroke="currentColor" stroke-width="1.7"/>',
 '3D': '<path d="M12 2 3 7v10l9 5 9-5V7l-9-5zm0 0v20M3 7l9 5 9-5" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/>',
 'Render': '<circle cx="12" cy="12" r="4" fill="none" stroke="currentColor" stroke-width="1.7"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3M4.9 4.9l2.1 2.1M17 17l2.1 2.1M4.9 19.1 7 17M17 7l2.1-2.1" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/>',
 'Sheets': '<rect x="3" y="4" width="18" height="16" rx="1" fill="none" stroke="currentColor" stroke-width="1.7"/><path d="M13 14h8M13 14v6" fill="none" stroke="currentColor" stroke-width="1.7"/>',
 'Exchange': '<path d="M4 8h14l-4-4M20 16H6l4 4" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/>',
 'Script': '<path d="m8 8-5 4 5 4M16 8l5 4-5 4M14 5l-4 14" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/>'}
LABELS = list(ICONS)
TUT = json.load(open(os.path.join(HERE, 'tutorials.json'), encoding='utf-8'))
for t in TUT:
    t['video'] = f'videos/archi-tool/{t["slug"]}.mp4?v={REL["asset_version"]}'
    t['poster'] = f'images/apps/archi-tool/tutorials/{t["slug"]}.jpg?v={REL["asset_version"]}'
TOOLS = ''.join(f'<button type="button" class="pe-tool{" is-active" if i == 0 else ""}" role="tab" aria-selected="{"true" if i == 0 else "false"}" aria-controls="pe-stage" data-index="{i}" title="{t["n"]:02d} · {t["title"]}"><svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true">{ICONS[LABELS[i % 12]]}</svg><span>{LABELS[i % 12]}</span></button>' for i, t in enumerate(TUT))
TUTDATA = json.dumps(TUT, ensure_ascii=False).replace('&', '&amp;').replace("'", '&#39;').replace('<', '&lt;')
links = ([ '<a href="archi-tool-guide.html">User guide</a>'] if REL.get('guide') else []) + \
        ([] if REL.get('pending') else ['<a href="downloads/archi-tool/SHA256SUMS.txt">Checksum</a>']) + \
        (['<a href="https://github.com/oanaunc/archi_tool">Source code</a>'] if REL.get('source_public') else []) + ['<a href="#faq">FAQ</a>']
tpl = open(os.path.join(HERE, 'page_main.html'), encoding='utf-8').read()
for k, v in {'V': REL['asset_version'], 'FEATURES': str(REL['features']), 'TOTALFEATURES': str(REL['total_features']),
             'COMMANDS': str(REL['commands']), 'TESTS': str(REL['tests']), 'FORMATS': str(REL['formats']),
             'STATUS': STATUS, 'NOTE': REL['note'], 'BUTTON': BUTTON, 'IMPORTS': REL['imports'], 'EXPORTS': REL['exports'],
             'LINKS': ' · '.join(links), 'GALLERY': gallery, 'TUTORIALS': ''.join(tut_cards), 'HEROBUTTON': HEROBUTTON, 'FINALBUTTON': FINALBUTTON,
             'TOOLS': TOOLS, 'EYEBROW': EYEBROW, 'CHIPS': CHIPS, 'PLATFORM': PLATFORM, 'DEVICE': DEVICE, 'OSVERSION': OSVERSION, 'TUTDATA': TUTDATA, 'FIRSTVIDEO': TUT[0]['video'], 'FIRSTPOSTER': TUT[0]['poster']}.items():
    tpl = tpl.replace('{{' + k + '}}', v)
assert '{{' not in tpl, re.findall(r'\{\{\w+\}\}', tpl)
main = tpl
page = page.replace('</head>', open(os.path.join(HERE, 'page_assets.html'), encoding='utf-8').read().replace('{{V}}', REL['asset_version']) + '\n</head>', 1)

start = page.index('<section class="contact-area section-padding-100 bg-img bg-overlay has-bg-img editor-breadcrumb"')
end = page.index('</main>', start) + len('</main>')
page = page[:start] + main + page[end:]
assert 'photo-editor/' not in page.split('<!-- ##### Footer Area Start')[0].split('</header>')[1], 'leftover photo-editor content'
open(os.path.join(SITE, 'archi-tool.html'), 'w', encoding='utf-8').write(page)
print('wrote archi-tool.html', len(page))
