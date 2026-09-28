# Oanarina Archi Tool for Windows — GPL-3.0-or-later
# Material regions of the Cedar House renders (fractions of the frame: x0, y0, x1, y1), used by render-match.py.
REGIONS = {
    'front': {'sky': (0.62, 0.03, 0.95, 0.16), 'lawn': (0.75, 0.93, 1.0, 1.0), 'paving': (0.30, 0.82, 0.70, 0.95),
              'cedar': (0.44, 0.30, 0.52, 0.60), 'limestone': (0.04, 0.35, 0.17, 0.58), 'glass': (0.39, 0.20, 0.42, 0.30)},
    'corner': {'sky': (0.62, 0.05, 0.90, 0.18), 'lawn': (0.0, 0.80, 0.15, 0.95), 'paving': (0.40, 0.80, 0.80, 0.95),
               'cedar': (0.54, 0.30, 0.56, 0.60), 'limestone': (0.28, 0.34, 0.33, 0.54), 'glass': (0.572, 0.30, 0.582, 0.56)},
    'aerial': {'sky': (0.0, 0.0, 1.0, 0.02), 'lawn': (0.0, 0.80, 0.16, 0.97), 'paving': (0.50, 0.66, 0.80, 0.82),
               'cedar': (0.54, 0.40, 0.58, 0.60), 'limestone': (0.28, 0.44, 0.31, 0.62), 'glass': (0.32, 0.64, 0.365, 0.66)},
}
