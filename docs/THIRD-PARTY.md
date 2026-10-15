# Third-party credits

Oanarina Archi Tool is licensed GPL-3.0-or-later. The native ArchiCore has no third-party library dependencies. The
Windows shell uses the dependencies recorded in `windows/package-lock.json` and their upstream licences.
Where an algorithm or file-format convention was studied in another open-source project, the source file names it in
its header comment, and it is listed here.

| Where | Credit | Licence | How it is used |
|---|---|---|---|
| `windows/packaging/prepare-nsis.cjs` | [electron-builder](https://github.com/electron-userland/electron-builder), Copyright (c) 2015 Loopline Systems | MIT | Adapts the per-user install path lookup in the pinned 25.1.8 NSIS template to read only the allocated Unicode string. Copyright is preserved in the patch and generated template; the full MIT notice is bundled as `resources/electron-builder-LICENSE.txt`. |
| `app/Sources/ArchiCore/Modeling/CSG.swift` | [csg.js](https://github.com/evanw/csg.js) by Evan Wallace | MIT | The BSP-tree boolean algorithm (union, subtract, intersect) is reimplemented in Swift; no code was copied. |
| `app/Sources/ArchiCore/Modeling/SolidOps.swift` (MESHSMOOTH) | Loop subdivision, C. Loop, *Smooth Subdivision Surfaces Based on Triangles* (M.S. thesis, University of Utah, 1987) | Published algorithm | Vertex/edge masks (β = 3/16 or 3/(8n), 3/8–1/8 edge rule, boundary crease rules) implemented from the paper; no code was copied. |
| `app/Sources/ArchiCore/IO/DXFWriter.swift`, `IO/DXFReader.swift` | [LibreCAD](https://librecad.org) libdxfrw / rs_filterdxfrw, © LibreCAD team | GPL-2.0-or-later | DXF section layout, group codes and hatch edge conventions were cross-checked against it. |
| `app/Sources/ArchiCore/IO/DXFACIPalette.swift` | [ezdxf colors.py](https://github.com/mozman/ezdxf/blob/7c64bce52c9d60b9db2dad4d2793c1168c8d3f64/src/ezdxf/colors.py), Copyright (c) 2020–2023 Manfred Moitzi | MIT | The default AutoCAD 2020 model-space ACI palette replaces the previously copied GPL table. Full MIT notice is preserved in the Swift file and included by both Mac and Windows packaging as `ThirdPartyLicenses/ezdxf-MIT.txt`. The library itself is not linked. |
| `app/Sources/ArchiCore/Modeling/SCAD.swift` | [OpenSCAD](https://openscad.org), © Clifford Wolf, Marius Kintel and contributors | GPL-2.0-or-later | The OpenSCAD language (syntax, built-in modules) and its tessellation rules (`$fn`/`$fa`/`$fs` fragment count, sphere ring layout, clockwise polyhedron faces) are followed so scripts give the same meshes; the interpreter is an independent implementation, no code was copied. |
| `app/Sources/ArchiCore/Modeling/MeshOps.swift` (SURFCV) | Clamped B-spline basis (Cox–de Boor recursion), L. Piegl & W. Tiller, *The NURBS Book* | Published algorithm | Basis functions and tensor-product surface evaluation implemented from the book; no code was copied. |
| `app/Sources/ArchiCore/IO/IFCExporter.swift` | [IfcOpenShell](https://ifcopenshell.org) `ifcopenshell.guid`, © IfcOpenShell contributors | LGPL-3.0 | The IFC GlobalId compression (22-character base-64) matches its algorithm. |

The reference checkouts in `other_projects/` (LibreCAD, IfcOpenShell, SolveSpace, OpenSCAD, BRL-CAD, CAD_Sketcher,
Sverchok) are used for study only. They are not part of this repository's published source or of the app.

## Removed material

The former ACI table in `DXFExtras.swift`, from LibreCAD libdxfrw `drw_objects.h` (Copyright © 2011–2015 José F. Soriano, 2016–2022 A. Stebich; GPL-2.0-or-later), was removed on 15 October 2026 at the owner’s request. Its original notices remain in Git history. Current source uses the separately licensed ezdxf palette instead. ACI indices and file structures are unchanged; some indexed shades follow the newer default display palette. Previously released website installers have not been replaced.
