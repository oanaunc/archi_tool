#!/usr/bin/env python3
"""Exports the completed features from docs/features.json for the website's feature explorer."""
import json, sys, collections
f = json.load(open(sys.argv[1]))
areas = collections.OrderedDict()
for x in f:
    if x['status'] != 'done': continue
    a = x['id'].split('-')[0]
    areas.setdefault(a, {'name': x['area'], 'items': []})['items'].append(
        [x['name'], x.get('command') or '', x['description']])
out = {'total': sum(1 for x in f if x['status'] == 'done'), 'areas': areas}
json.dump(out, open(sys.argv[2], 'w'), separators=(',', ':'))
print(out['total'], len(json.dumps(out)))
