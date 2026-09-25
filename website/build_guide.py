#!/usr/bin/env python3
"""Generates oanarina_website/archi-tool-guide.html from docs/USER-GUIDE.md using the Photo Editor guide's layout."""
import re, sys, os, markdown
SITE, GUIDE = sys.argv[1], sys.argv[2]
src = open(os.path.join(SITE, 'photo-editor-guide.html'), encoding='utf-8').read()
md = open(GUIDE, encoding='utf-8').read()
md = re.sub(r'^# .*\n', '', md, count=1)  # page supplies its own H1
body = markdown.markdown(md, extensions=['tables', 'fenced_code', 'toc', 'sane_lists'])
body = body.replace('<table>', '<table class="table table-sm">')
page = re.sub(r'<meta name="description" content="[^"]*">', '<meta name="description" content="User guide for Oanarina Archi Tool, the free Mac app for architectural drafting, BIM, 3D and rendering.">', src, count=1)
page = re.sub(r'<title>.*?</title>', '<title>Oanarina Archi Tool Guide — Oana Rinaldi</title>', page, count=1, flags=re.S)
page = re.sub(r'<link rel="canonical" href="[^"]*">', '<link rel="canonical" href="https://oanarinaldi.com/archi-tool-guide.html">', page, count=1)
page = page.replace('</style>\n<link rel="canonical"', '.editor-manual table{width:100%;margin-bottom:24px;font-size:14px}.editor-manual code{color:#b58900}.editor-manual pre{background:#1e1f22;color:#e6e6e6;padding:16px;overflow:auto}\n</style>\n<link rel="canonical"', 1)
start = page.index('<section class="contact-area section-padding-100 bg-img bg-overlay has-bg-img editor-breadcrumb"')
end = page.index('</main>', start) + len('</main>')
main = f'''<section class="contact-area section-padding-100 bg-img bg-overlay has-bg-img editor-breadcrumb" style="background-image:url(images/apps/archi-tool/breadcrumb.png?v=20260925)">
        <div class="container"><div class="row"><div class="col-12"><div class="section-heading white"><p>Architecture &amp; Design</p><h2>Archi Tool Guide</h2></div></div></div></div>
    </section>
    <main class="section-padding-100" id="main"><article class="container editor-manual"><h1>Oanarina Archi Tool guide</h1>
{body}
<p class="text-center mb-100"><a href="archi-tool.html">← Back to Oanarina Archi Tool</a></p></article></main>'''
page = page[:start] + main + page[end:]
open(os.path.join(SITE, 'archi-tool-guide.html'), 'w', encoding='utf-8').write(page)
print('wrote archi-tool-guide.html', len(page))
