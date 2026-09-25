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

if REL.get('pending'):
    STATUS = 'The first preview build is being finished and notarized by Apple. It will appear here very soon.'
    BUTTON = '<a class="btn oneMusic-btn" href="https://github.com/oanaunc/archi_tool">Follow on GitHub <i class="fa fa-angle-double-right" aria-hidden="true"></i></a>'
else:
    STATUS = f'Version {REL["version"]} preview · Apple silicon and Intel · {REL["size_mb"]} MB. {REL["signing"]}'
    BUTTON = f'<a class="btn oneMusic-btn" id="download-button" href="downloads/archi-tool/{REL["dmg"]}?v={REL["sha_short"]}" download>Download for Mac <i class="fa fa-angle-double-right" aria-hidden="true"></i></a>'
main = f'''<section class="contact-area section-padding-100 bg-img bg-overlay has-bg-img editor-breadcrumb" style="background-image:url(images/apps/archi-tool/breadcrumb.png?v={REL["asset_version"]})">
        <div class="container"><div class="row"><div class="col-12"><div class="section-heading white"><p>Architecture &amp; Design</p><h2>Archi Tool</h2></div></div></div></div>
    </section>
    <main class="album-catagory section-padding-100-0" id="main"><div class="container">
        <div class="photo-editor-intro">
            <img class="editor-icon" src="images/apps/archi-tool/icon.png?v={REL["asset_version"]}" alt="Oanarina Archi Tool icon" width="92" height="92">
            <h1>Oanarina Archi Tool</h1><h4>Draw it. Build it. See it.</h4>
            <p>A free, native Mac application for architecture: precise 2D drafting with an AutoCAD-style command line, intelligent building elements in the spirit of Revit, 3D views, rendering, sheets and printing — and a scripting interface that lets you, or an AI agent, design alongside you.</p>
            <div class="editor-actions"><a href="#download" class="btn oneMusic-btn">Get the app <i class="fa fa-angle-double-right" aria-hidden="true"></i></a><a href="#features" class="btn oneMusic-btn">Explore the tools</a></div>
            <p>Free and open source (GPL-3.0) · macOS 14 or later</p>
        </div>
        <img class="editor-shot" src="images/apps/archi-tool/workspace.png?v={REL["asset_version"]}" alt="The Oanarina Archi Tool workspace with a house plan in 2D next to its shaded 3D model, the ribbon, properties panel and command line" loading="lazy">
        <p class="editor-caption">Plan and model side by side: every wall, door and window you draw in 2D is a real building element in 3D.</p>
        <div class="archi-grid">
            <div><strong>{REL["commands"]}+</strong>commands</div>
            <div><strong>{REL["formats"]}</strong>file formats</div>
            <div><strong>2D + 3D</strong>in one model</div>
            <div><strong>Free</strong>no account, no subscription</div>
        </div>
        <section id="features"><div class="section-heading"><p>From the first line to the finished building</p><h2>A complete studio for architecture</h2></div><div class="row">
<article class="col-12 col-md-6 col-lg-4 editor-feature"><h3>Draft with precision</h3><p>Lines, polylines with arcs, circles, arcs, ellipses, splines, rectangles, polygons, points and revision clouds. Object snaps, polar and ortho tracking, a grid and typed coordinates — absolute, relative and polar — put every point exactly where it belongs.</p></article>
<article class="col-12 col-md-6 col-lg-4 editor-feature"><h3>Edit like a professional</h3><p>Move, copy, rotate, scale, mirror, stretch, trim, extend, offset, fillet, chamfer, break, join, explode and arrays, with grips on every object and undo for every step. Select with windows, crossings, filters and similar objects.</p></article>
<article class="col-12 col-md-6 col-lg-4 editor-feature"><h3>Speak the command line</h3><p>Type LINE, WALL, DOOR or any of the familiar commands and aliases. Prompts offer their options, autocomplete suggests as you type, Enter repeats the last command and scripts replay whole sequences.</p></article>
<article class="col-12 col-md-6 col-lg-4 editor-feature"><h3>Design with building elements</h3><p>Walls with layered wall types and clean joins, doors and windows hosted in walls, curtain walls, slabs, roofs (flat, shed, gable and hip), stairs, railings, columns, beams, grids, levels, rooms with automatic areas, and furniture.</p></article>
<article class="col-12 col-md-6 col-lg-4 editor-feature"><h3>Annotate clearly</h3><p>Text and multiline text, linear, aligned, angular, radial, diameter, ordinate, baseline and continued dimensions, leaders, tables, 18 hatch patterns, layers with colours, linetypes and lineweights, blocks with attributes.</p></article>
<article class="col-12 col-md-6 col-lg-4 editor-feature"><h3>Step into 3D</h3><p>Orbit your building in a live 3D view with wireframe, hidden-line, shaded, realistic and X-ray styles, sun shadows and a walk mode. Elevations and sections are generated from the model.</p></article>
<article class="col-12 col-md-6 col-lg-4 editor-feature"><h3>Render the light</h3><p>Produce still renders up to 4K with the sun placed for your site, date and time, then save them as PNG or JPEG or export a turntable movie.</p></article>
<article class="col-12 col-md-6 col-lg-4 editor-feature"><h3>Sheets, plots and PDF</h3><p>Lay out plans, elevations and sections at 1:50, 1:100 or 1:200 on A-series or Letter sheets with a title block, north arrow and scale bar, then print or plot vector PDF.</p></article>
<article class="col-12 col-md-6 col-lg-4 editor-feature"><h3>Script it, or let an AI help</h3><p>Automate with the JavaScript console, connect AI agents such as Claude through the built-in Model Context Protocol server or the local JSON-RPC interface, and run the headless archi-cli on your projects.</p></article>
</div></section>
        <section class="editor-section"><div class="row"><div class="col-12 col-lg-5"><h2>Start with an idea. Finish with a building.</h2><p>Sketch a plan, raise the walls and walk through the rooms — in one model.</p></div><div class="col-12 col-lg-7"><h4>1. Draw the plan</h4><p>Start a new drawing or a building template with levels, or open a DXF. Draw walls on a level and drop doors and windows into them; rooms find their own boundaries and areas.</p><h4>2. Shape it in 3D</h4><p>Add floors, a roof and stairs, switch to 3D or split the window to see plan and model together, and orbit, section or walk through the building.</p><h4>3. Share the result</h4><p>Place views on sheets and plot a PDF, render an image, or export DXF, SVG, IFC for BIM tools, OBJ, STL and glTF for 3D apps, and CSV schedules for spreadsheets.</p></div></div></section>
        <section class="editor-section"><div class="row"><div class="col-12 col-lg-5"><h2>The Cedar House</h2><p>A contemporary residence modelled in Oanarina Archi Tool: a red-cedar tower, limestone wings and a long black canopy over the entrance. It ships with the app as a sample project.</p></div><div class="col-12 col-lg-7"><img class="editor-shot" src="images/apps/archi-tool/model-front.jpg?v={REL["asset_version"]}" alt="The Cedar House sample project in the Realistic 3D view: a cedar-clad tower with a tall window strip, limestone wings, a black canopy, trees and hedges" loading="lazy"><p class="editor-caption" style="margin-bottom:0">Realistic view with materials, textures and sun shadows, straight from the modelling window.</p></div></div></section>
        <section class="editor-section"><div class="row"><div class="col-12 col-lg-5"><h2>The command line</h2><p>Everything you can click, you can type — and everything you can type, a script or an AI agent can do.</p></div><div class="col-12 col-lg-7"><div class="archi-code"><b>Command:</b> WALL<br>Specify start point [Thickness/Height/Justify/Type]: 0,0<br>Specify next point: @12000,0<br>Specify next point: @0,8000<br><b>Command:</b> DOOR<br>Select wall: pick · Width &lt;900&gt;: ↵<br><b>Command:</b> ROOF<br>Specify boundary [Walls/Kind/Pitch]: W</div><p>Connect Claude Desktop with one line in its settings: <code>archi-cli --mcp ~/Documents/house.archi</code>. The <a href="https://github.com/oanaunc/archi_tool/blob/main/docs/AGENT-API.md">agent guide</a> explains the tools.</p></div></div></section>
        <section id="download" class="editor-download"><div class="row"><div class="col-12 col-lg-6"><h2>Get Oanarina Archi Tool</h2><p>Free architecture software for your Mac.</p><p id="release-status">{STATUS}</p><p>{REL["note"]}</p>{BUTTON}</div><div class="col-12 col-lg-6"><table class="editor-specs"><caption class="sr-only">System requirements and file formats</caption><tbody><tr><th scope="row">Platform</th><td>macOS 14 or later</td></tr><tr><th scope="row">Price</th><td>Free · open source (GPL-3.0)</td></tr><tr><th scope="row">Opens</th><td>{REL["imports"]}</td></tr><tr><th scope="row">Exports</th><td>{REL["exports"]}</td></tr><tr><th scope="row">Projects</th><td>.archi</td></tr></tbody></table></div></div></section>
        <p class="text-center">{'<a href="archi-tool-guide.html">Detailed user guide</a> · ' if REL.get('guide') else ''}{'' if REL.get('pending') else '<a href="downloads/archi-tool/SHA256SUMS.txt">Download checksum</a> · '}<a href="https://github.com/oanaunc/archi_tool">Source code</a></p>
        <section class="editor-faq mb-100"><div class="section-heading"><p>A few useful details</p><h2>Before you begin</h2></div>
<details><summary>Is it really free?</summary><p>Yes. Oanarina Archi Tool is free software under the GNU General Public License 3.0: no account, no subscription and no watermark. The <a href="https://github.com/oanaunc/archi_tool">source code</a> is public.</p></details>
<details><summary>Can I open my AutoCAD drawings?</summary><p>Open and save DXF drawings, the open exchange format AutoCAD, LibreCAD, BricsCAD and most CAD tools read and write. To bring in a DWG file, save it as DXF from your CAD application first. For building models, export IFC.</p></details>
<details><summary>Does it work offline?</summary><p>Yes. Drawings and models stay on your Mac. The optional agent server listens only on your own computer and is off until you turn it on.</p></details>
<details><summary>How complete is it?</summary><p>This is an early preview of a long programme: the public <a href="https://github.com/oanaunc/archi_tool/blob/main/docs/FEATURE-REGISTER.md">feature register</a> lists more than a thousand planned capabilities and marks what is already done. New versions are published here.</p></details>
<details><summary>Who makes Oanarina Archi Tool?</summary><p>Oanarina Archi Tool is developed by Oana Rinaldi, with ideas drawn from the open-source FreeCAD, LibreCAD, IfcOpenShell, SolveSpace, OpenSCAD, BRL-CAD, Sverchok and CAD Sketcher communities. The <a href="https://github.com/oanaunc/archi_tool/blob/main/LICENSE">license</a> is included with the app.</p></details>
<details><summary>How can I share feedback?</summary><p>Report a reproducible problem or suggest an improvement through the <a href="index.html#contact">contact page</a> or as an issue on GitHub. Include your macOS version and the steps that led to the problem.</p></details></section><p class="text-center mb-100"><a href="apps.html">← Back to all apps</a></p></div></main>'''

start = page.index('<section class="contact-area section-padding-100 bg-img bg-overlay has-bg-img editor-breadcrumb"')
end = page.index('</main>', start) + len('</main>')
page = page[:start] + main + page[end:]
assert 'photo-editor/' not in page.split('<!-- ##### Footer Area Start')[0].split('</header>')[1], 'leftover photo-editor content'
open(os.path.join(SITE, 'archi-tool.html'), 'w', encoding='utf-8').write(page)
print('wrote archi-tool.html', len(page))
