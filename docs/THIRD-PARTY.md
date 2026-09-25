# Third-party credits

Oanarina Archi Tool is licensed GPL-3.0-or-later. It ships no third-party libraries: all code is written for this project.
Where an algorithm or file-format convention was studied in another open-source project, the source file names it in
its header comment, and it is listed here.

| Where | Credit | Licence | How it is used |
|---|---|---|---|
| `app/Sources/ArchiCore/Modeling/CSG.swift` | [csg.js](https://github.com/evanw/csg.js) by Evan Wallace | MIT | The BSP-tree boolean algorithm (union, subtract, intersect) is reimplemented in Swift; no code was copied. |
| `app/Sources/ArchiCore/Modeling/SolidOps.swift` (MESHSMOOTH) | Loop subdivision, C. Loop, *Smooth Subdivision Surfaces Based on Triangles* (M.S. thesis, University of Utah, 1987) | Published algorithm | Vertex/edge masks (β = 3/16 or 3/(8n), 3/8–1/8 edge rule, boundary crease rules) implemented from the paper; no code was copied. |
| `app/Sources/ArchiCore/IO/DXFWriter.swift`, `IO/DXFReader.swift` | [LibreCAD](https://librecad.org) libdxfrw / rs_filterdxfrw, © LibreCAD team | GPL-2.0-or-later | DXF section layout, group codes and hatch edge conventions were cross-checked against it. |
| `app/Sources/ArchiCore/IO/IFCExporter.swift` | [IfcOpenShell](https://ifcopenshell.org) `ifcopenshell.guid`, © IfcOpenShell contributors | LGPL-3.0 | The IFC GlobalId compression (22-character base-64) matches its algorithm. |

The reference checkouts in `other_projects/` (LibreCAD, IfcOpenShell, SolveSpace, OpenSCAD, BRL-CAD, CAD_Sketcher,
Sverchok) are used for study only. They are not part of this repository's published source or of the app.
