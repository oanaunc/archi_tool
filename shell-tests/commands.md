# Oanarina Archi Tool — command reference

1043 commands. Every command also runs from the command line, scripts (`archi.run`) and the agent server.

## 3D

| Command | Aliases | Summary | Where |
|---|---|---|---|
| `3DALIGN` | ALIGN3D, 3DAL | Aligns solids in 3D by up to three source and destination points (translation, then direction, then plane); optional scaling. | Tools ▸ Mesh & Procedural 3D |
| `3DARRAY` | ARRAY3D, 3A | Creates rectangular (rows × columns × levels) or polar 3D arrays of objects. | Model |
| `CHAMFEREDGE` | CHAMFER3D, CHE | Bevels the edges of boxes and extruded solids (all, vertical, top or bottom edges). | Modeling ▸ Surfaces |
| `COMPONENTTOBIM` | GROUPTOBIM, TOBIM, CONVERTTOBIM | Converts component / group instances or solids into schedulable BIM component elements (category and name). | Tools ▸ Components & Surfaces |
| `CONVTOMESH` | TOMESH, SOLIDTOMESH | Converts parametric solids (box, cylinder, extrusion, revolve…) into editable triangle meshes. | Tools ▸ 3D Primitives & Solid Tools |
| `CONVTOSOLID` | TOSOLID, MESHTOSOLID | Converts closed meshes into solids (cleaned and oriented); open meshes are refused (MESHREPAIR can close them). | Tools ▸ 3D Primitives & Solid Tools |
| `CSGTREE` | COMB, REGION3D, CSGCOMB | BRL-CAD style combination: 'u #1 - #2 + #3 u #4' (u union, - subtract, + intersect); the result regenerates when a member changes. List / Edit existing trees. | Tools ▸ Feature Modelling |
| `CUSTOMIZERPANEL` | PARAMPANEL, SCADPANEL | Customizer panel: sliders, check boxes and choices for the parameters of the selected scripted object (OpenSCAD customizer comments), regenerating it on change. | Tools ▸ Render, Materials & Environment |
| `DATUM` | DATUMPLANE, DATUMAXIS, DATUMPOINT, REFGEOMETRY, WORKPLANEREF | Reference geometry that follows its source: datum Plane (through a line, offset from a solid Face, or at a Level), Axis (along a line, through a circle centre or a cylinder) or Point (centre, start, end or midpoint). | Tools ▸ Components & Surfaces |
| `EDGESURF` | EDGESURFACE, COONS | Coons patch mesh bounded by four edge curves that touch end to end (SURFTAB1 × SURFTAB2). | Modeling ▸ Surfaces |
| `FILLETEDGE` | FILLET3D, FE | Rounds the edges of boxes and extruded solids (all, vertical, top or bottom edges). | Modeling ▸ Surfaces |
| `FOLLOWME` | FOLLOW | SketchUp-style follow me: sweeps a profile along a path keeping its position relative to the path start (x = offset left of the path, y = height); associative. | Tools ▸ Feature Modelling |
| `GFUSE` | GENERALFUSE, FRAGMENT | General fuse: cuts overlapping solids into non-overlapping pieces (overlaps become their own solids). | Tools ▸ Feature Modelling |
| `GIZMO3D` | GIZMO, 3DGIZMO | Shows a move (X/Y/Z arrows), rotate (ring) or uniform scale gizmo on the selection in the 3D view; drag it to transform (one undo step). | View ▸ Presentation |
| `GROOVE` | GROOVEFEATURE, REVOLVECUT | PartDesign groove: revolves a sketch profile about an axis and subtracts it from a body (follows the sketch). | Tools ▸ Feature Modelling |
| `HOLE` | HOLEFEATURE, DRILL | Hole features at sketch points or circles: diameter, depth or Through, Simple / Counterbore / Countersink, optional thread designation; follow their sketch. | Tools ▸ Feature Modelling |
| `HULL` | CONVEXHULL, HULL3D | Convex hull solid of the selected solids (and points/curves at their elevation), like OpenSCAD hull(). | Tools ▸ 3D Primitives & Solid Tools |
| `IMPRINT` | IMPRINTEDGES | Imprints curves (lines, polylines, arcs, circles, 3D polylines) onto a planar face of a solid: the face is split along them, the solid stays closed. | Tools ▸ Components & Surfaces |
| `INTERFERE` | INF, CLASH | Finds overlapping volumes between two sets of solids and can create them as new solids. | Model |
| `INTERSECT` | INTERSECTSOLIDS | Keeps only the common volume of the selected solids. | Model |
| `INTERSECTFACES` | INTERSECTWITHMODEL, INTERSECTEDGES | SketchUp intersect faces: draws 3D edges (polylines) where the selected solids cut each other, or cut the rest of the Model. | Tools ▸ Feature Modelling |
| `LINEAREXTRUDE` | TWISTEXTRUDE, LEXTRUDE | OpenSCAD-style linear extrude of closed profiles: height, twist angle and top scale (slices follow the twist). | Tools ▸ 3D Primitives & Solid Tools |
| `LOFT` |  | Creates a solid through closed cross-sections at given heights (in selection order). | Model |
| `MAKECOMPONENT` | COMPONENTMAKE, SKCOMPONENT, MAKECOMP | SketchUp-style component: the selected objects become a named definition and are replaced by an instance; every instance updates when the definition is edited (BEDIT/REFEDIT). | Tools ▸ Components & Surfaces |
| `MAKEGROUP` | SKGROUP, GROUP3D, GROUPSOLIDS | SketchUp-style group: the selected objects become one unique (unnamed) object that moves and copies as a whole. | Tools ▸ Components & Surfaces |
| `MAKEUNIQUE` | UNIQUECOMPONENT | Gives a component or group instance its own copy of the definition so it can be edited without changing the other instances. | Tools ▸ Components & Surfaces |
| `MESH` | MESHPRIMITIVE, MESHBOX | Faceted mesh primitives with divisions (MESHDIVISIONS): Box, Cylinder, Cone, Sphere, Torus, Wedge, Pyramid. | Tools ▸ 3D Primitives & Solid Tools |
| `MESHDECIMATE` | DECIMATE, MESHREDUCE, SIMPLIFYMESH | Reduces the triangle count of meshes/solids to a percentage (vertex clustering). | Modeling ▸ Surfaces |
| `MESHEXTRUDE` | EXTRUDEFACE, FACEEXTRUDE, MESHFACEEXTRUDE | Extrudes faces of a solid or mesh (the faces facing Top/Bottom/Front/Back/Left/Right under a picked point, or All facing that way) by a distance along their normal; the result stays closed. | Tools ▸ Mesh & Procedural 3D |
| `MESHREPAIR` | REPAIRMESH, FIXMESH, MESHCLEAN | Repairs meshes/solids: welds vertices, removes degenerate and duplicate faces, fixes orientation, fills holes. | Modeling ▸ Surfaces |
| `MESHSECTION` | CROSSSECTIONS, SLICESECTIONS, SECTIONCURVES | Cross-sections of solids and meshes: section curves at one elevation or every interval between two elevations (for contours, ribs, waffle models). | Tools ▸ Mesh & Procedural 3D |
| `MESHSMOOTH` | SMOOTHMESH, SUBDIVIDE, MESHREFINE | Smooths solids and meshes by Loop subdivision (1–4 levels). | Model |
| `MINKOWSKI` | MINKOWSKISUM | Minkowski sum of two solids (e.g. a box and a sphere for rounded edges); exact for convex solids. | Tools ▸ Mesh & Procedural 3D |
| `MIRROR3D` | 3DMIRROR | Mirrors solids about the XY, YZ or ZX plane through a point, or a vertical plane through two points. | Model |
| `MIRRORFEATURE` | FEATUREMIRROR, MIRRORED | Mirrors a feature (or the whole body) about a vertical plane through two points or the XY plane at a height; stays parametric. | Tools ▸ Feature Modelling |
| `MOVEZ` | ZMOVE, MOVEUP | Moves objects up or down: element base/top offsets and door/window sills change, solids move (one undo step). | Tools ▸ Families, Views & Panels |
| `OFFSETFACE` | OFFSETEDGES, FACEOFFSET, INSETFACE | SketchUp-style Offset: imprints a copy of a planar face's edges offset into the face (then SUBOBJECT Extrude pushes or pulls the inner face). | Tools ▸ Components & Surfaces |
| `OFFSETSOLID` | SOLIDOFFSET, OFFSETBODY | Offsets solids: every face moves outwards (or inwards, negative) by the distance. | Tools ▸ Feature Modelling |
| `OUTLINER` | OUTLINE, HIERARCHY | Outliner: lists the hierarchy of groups, components and model groups; Select instances by name (wildcards), Rename an instance, or Convert it to a BIM element. | Tools ▸ Components & Surfaces |
| `OUTLINERPANEL` | OUTLINERWINDOW, SHOWOUTLINER | Outliner window: the tree of groups, components, blocks and model groups; click selects, double-click zooms, filter by name. | Tools ▸ Components & Surfaces |
| `PAD` | BOSS, PADFEATURE | PartDesign pad: extrudes a sketch profile (optionally tapered) and adds it to a solid, or creates a new body; regenerates when the sketch changes. | Model |
| `PAINT` | PAINTBUCKET, APPLYMATERIAL | Paint bucket: applies a material to objects and building elements by clicking them; Sample picks up an object's material; List shows the materials. | Tools ▸ Feature Modelling |
| `PATTERNFEATURE` | LINEARPATTERN, POLARPATTERN, FEATUREPATTERN | Repeats a feature (or the whole body) in a Linear (columns × rows) or Polar pattern; instances follow the feature's sketch. | Tools ▸ Feature Modelling |
| `PIPE` | TUBE | Creates a round pipe (optionally hollow) along a path. | Model |
| `PLANESURF` | PLANARSURFACE, PSURF | Planar surface from a closed boundary (Object, with inner loops as holes) or from two corners of a rectangle. | Tools ▸ 3D Primitives & Solid Tools |
| `POCKET` | POCKETFEATURE, CUTEXTRUDE | PartDesign pocket: cuts a sketch profile into a solid by a depth (downwards from the sketch) or Through all; regenerates when the sketch changes. | Tools ▸ Feature Modelling |
| `POLYHEDRON` | POLYHEDRA | Solid from points (x,y,z) and faces (point numbers from 1, e.g. 1,2,3,4) like OpenSCAD polyhedron(). | Tools ▸ 3D Primitives & Solid Tools |
| `POLYSOLID` | PSOLID | Draws a wall-like solid along points or converts a line/polyline/arc (Object); Height, Width, Justify. | Tools ▸ 3D Primitives & Solid Tools |
| `PRESSPULL` | PP, PUSHPULL | Extrudes the area around a picked point (with islands as holes), a closed object, or changes an extrusion's height. | Model |
| `PRESSPULLFACE` | PPFACE, PUSHPULLFACE, FACEPULL | Pushes or pulls a planar face (top, bottom or side) of any 3D solid along its normal. | Modeling ▸ Surfaces |
| `PRISM` | REGULARPRISM, HOLLOWPRISM | Regular prism (N sides) or tube (inner radius > 0): centre, circumradius, height. | Tools ▸ 3D Primitives & Solid Tools |
| `PROJECTGEOMETRY` | PROJECTEDGES, EXTERNALGEOMETRY, FLATOUTLINE | Projects the outline of solids onto the sketch plane as closed polylines that follow the solids when they change (use them as sketch profiles). | Tools ▸ Feature Modelling |
| `PYRAMID` | PYR | Creates a pyramid or frustum with N sides: base centre, base radius, height (Top radius for a frustum). | Tools ▸ 3D Primitives & Solid Tools |
| `REVOLUTION` | REVOLUTIONFEATURE, REVOLVEADD | PartDesign revolution: revolves a sketch profile about an axis and adds it to a body (follows the sketch). | Tools ▸ Feature Modelling |
| `REVSURF` | REVOLVEDSURFACE | Revolved mesh surface: rotates a path curve about an axis line (start angle, included angle; SURFTAB1 segments). | Modeling ▸ Surfaces |
| `ROTATE3D` | 3DROTATE | Rotates solids about an axis parallel to X, Y or Z through a point. | Model |
| `RULESURF` | RULEDSURFACE | Ruled mesh surface between two curves (SURFTAB1 rulings). | Modeling ▸ Surfaces |
| `SCAD` | OPENSCAD, CSGSCRIPT | Evaluates an OpenSCAD-language script (cube, sphere, cylinder, polyhedron, extrudes, transforms, union/difference/intersection/hull/minkowski, modules, loops) into a solid. | Tools ▸ Mesh & Procedural 3D |
| `SCADFILE` | SCADIN, IMPORTSCAD | Imports an OpenSCAD .scad file (with include / use of neighbouring files) as a solid. | Tools ▸ Mesh & Procedural 3D |
| `SCADOBJECT` | SCRIPTOBJECT, CUSTOMIZER, GDLOBJECT | Scripted parametric objects (OpenSCAD language, GDL-like): New from a script or File, list Params (Customizer ranges and choices), Set a parameter to regenerate. | Tools ▸ Feature Modelling |
| `SCALE3D` | SCALENU, SCALEXYZ | Non-uniform scale of solids about a base point: separate X, Y and Z factors (negative factors mirror), or Handles: drag a bounding-box handle (corner, edge midpoint, Top/Bottom) about the opposite side or the Center, optionally Uniform. | Tools ▸ Feature Modelling |
| `SECTIONOBJECT` | SECTIONPLANEOBJ, SPOBJECT, SECTIONPLANES | Section plane objects: Add a named vertical plane (its plan trace can be moved), make it Live (clips the 3D view with caps), Flip, Generate/update its 2D section block, Slice solids into closed halves, List, Off, Delete. | Tools ▸ 3D Primitives & Solid Tools |
| `SECTIONSOLIDS` | GENERATESECTION, SECTIONBLOCK, SOLIDSECTION | Cuts 3D solids with a vertical section plane (two points) and places the 2D section (cut poché + projection) as a block; Plan cuts them horizontally. | Modeling ▸ Surfaces |
| `SEPARATE` | SOLIDSEPARATE, SOLIDCLEAN | Separates solids into their disjoint bodies and cleans them (duplicate/degenerate faces, consistent outward orientation). | Tools ▸ 3D Primitives & Solid Tools |
| `SHAPEBINDER` | BINDER, SUBSHAPEBINDER | Sub-shape binder: an associative copy of another body (Solid) or of one of its faces (Face, as a surface), optionally displaced; it follows the source when that changes. | Tools ▸ Feature Modelling |
| `SHELL` | SOLIDSHELL, HOLLOW | Hollows boxes and extrusions to a wall thickness, optionally removing the top face (SOLIDEDIT Shell). | Model |
| `SKETCHPAD` | PADSKETCH, SKETCHEXTRUDE | Pads a sketch: its closed profile (with holes) extruded along the work-plane normal; the solid follows every change of the sketch. | Tools ▸ Adaptive, Corners & Roofs |
| `SLICE` | SL3D | Cuts solids with a vertical plane through two points or a horizontal plane (XY) at a height. | Model |
| `SOFTEN` | SOFTENEDGES, SMOOTHEDGES | Softens and smooths the edges of solids/meshes whose faces meet at less than an angle (0 = sharp again); display only. | Tools ▸ Feature Modelling |
| `SOLIDCHECK` | CHECKSOLID, VALIDATESOLID, CHECKGEOMETRY | Validates solids: open or non-manifold edges, inconsistent orientation, degenerate faces, volume and bodies. | Tools ▸ 3D Primitives & Solid Tools |
| `SOLIDEDIT` | SOLED | Edits solid faces: Extrude, Move, Offset, Taper or Copy a face (picked Top/Bottom/Side in plan); Body Offset or Separate. | Tools ▸ Feature Modelling |
| `SOLIDHIST` | RECORDHISTORY | Turns recording of the CSG feature history of solids on or off (booleans on solids with a history always record). | Modeling ▸ Surfaces |
| `SOLIDHISTORY` | FEATURES, FEATURETREE, SHISTORY | Feature list of a solid: list, suppress/unsuppress, delete or move a boolean feature (the solid regenerates), or flatten the history. | Modeling ▸ Surfaces |
| `SPLITSOLID` | SPLITBODY, BOOLEANFRAGMENTS | Splits solids by other solids into the parts inside and outside the tools (separate bodies). | Tools ▸ Feature Modelling |
| `SPRING` | COILSPRING, HELIXSOLID | Creates a helical coil spring solid (coil radius, wire radius, pitch, turns). | Tools ▸ Mesh & Procedural 3D |
| `SUBOBJECT` | SUBSELECT, SOEDIT, SUBOBJ | Sub-object editing (Ctrl-click in the viewport): pick a Face, Edge or Vertex of a solid and Move it, Extrude a face, or list Info. | Tools ▸ Components & Surfaces |
| `SUBTRACT` | SU | Subtracts solids from other solids. | Model |
| `SURFANALYSIS` | ANALYSISZEBRA, ANALYSISCURVATURE, ANALYSISDRAFT, SURFACEANALYSIS, ZEBRA | Surface analysis: Zebra stripes, Curvature (Gaussian or mean, colour bands), Draft angle against a pull direction, Continuity between two surfaces, or Clear the analysis overlays. | Tools ▸ Components & Surfaces |
| `SURFBLEND` | BLENDSURFACE, BLENDSRF | Blend surface between the edges of two surfaces with G0 (position), G1 (tangent) or G2 (curvature) continuity and a bulge factor. | Tools ▸ Components & Surfaces |
| `SURFCV` | NURBSSURF, CVSURFACE, SURFCVEDIT | B-spline (NURBS) surface from a grid of control vertices: New over a rectangle, Edit moves a CV (row, column, height), Display the CV grid. | Tools ▸ Mesh & Procedural 3D |
| `SURFEXTEND` | EXTENDSURFACE | Extends the outer edges of surfaces tangentially by a distance. | Tools ▸ Freeform Surfaces |
| `SURFNETWORK` | NETWORKSURFACE, GORDON | Network surface through curves in the U and V directions (Gordon surface: passes through every curve). | Tools ▸ Freeform Surfaces |
| `SURFOFFSET` | OFFSETSURFACE | Offset copy of surfaces along their normals. | Tools ▸ Freeform Surfaces |
| `SURFPATCH` | PATCHSURFACE, FILLSURFACE | Patch surface filling a closed boundary (one closed curve or curves meeting end to end; 3D polylines with vertexZ or elevations): planar boundaries exactly, others as a Coons patch. | Tools ▸ Freeform Surfaces |
| `SURFSCULPT` | SCULPT, SURFTOSOLID | Joins surfaces that enclose a watertight volume into a solid (the surfaces are replaced). | Tools ▸ Freeform Surfaces |
| `SURFTRIM` | TRIMSURFACE | Trims surfaces with a closed plan curve (projected vertically), keeping the part Inside or Outside. | Tools ▸ Freeform Surfaces |
| `SWEEP` |  | Sweeps closed profiles along a path (profile X to the left of travel, Y up). | Model |
| `SWEEP3D` | HELIXSWEEP, SWEEPHELIX | Sweeps a closed profile (centred on the path) along a 3D path such as a helix (or a new Helix); associative with profile and path. | Tools ▸ Feature Modelling |
| `TABSURF` | TABULATEDSURFACE | Tabulated mesh surface: sweeps a path curve along a direction vector (a line) or straight up by a height. | Modeling ▸ Surfaces |
| `TAPEMEASURE` | TAPE, GUIDE, PROTRACTOR | Tape measure: Measure between two points, create a Guide parallel to an edge at a distance or through a point, or a Protractor guide at an angle. | Tools ▸ Feature Modelling |
| `TEXT3D` | 3DTEXT, EXTRUDETEXT | Creates extruded 3D text (single-line font strokes as solid bars). | Tools ▸ Mesh & Procedural 3D |
| `THICKEN` | THICK | Turns surfaces into solids by offsetting them along their normals (negative = other side). | Tools ▸ 3D Primitives & Solid Tools |
| `TORUS` | TOR | Creates a torus: centre, radius of the torus, radius of the tube. | Tools ▸ 3D Primitives & Solid Tools |
| `UNFOLD` | MESHUNFOLD, FLATTENMESH, PAPERMODEL | Unfolds a solid or mesh into a flat net for fabrication (cut lines solid, fold lines dashed), placed at a point. | Tools ▸ Mesh & Procedural 3D |
| `UNION` | UNI | Combines selected 3D solids into one. | Model |
| `WEDGE` | WE | Creates a wedge solid: base rectangle by two corners (or Length), height; the top slopes down along X. | Tools ▸ 3D Primitives & Solid Tools |
| `WIREFRAME` | MESHWIREFRAME, WIREFRAMEMOD, LATTICE | Wireframe modifier: turns the edges of a solid or mesh into struts of a given thickness (Solidify: THICKEN). | Tools ▸ Mesh & Procedural 3D |

## Analysis

| Command | Aliases | Summary | Where |
|---|---|---|---|
| `ACCESSIBILITY` | A11Y, ACCESSCHECK, ADACHECK | Accessibility check: door clear widths (A11YDOORWIDTH, default 850 mm) and Ø1500 mm wheelchair turning circles in bathrooms clear of fixtures (A11YTURNING). | Analyze ▸ Checks |
| `BOQ` | BILLOFQUANTITIES, BILLQ | Bill of quantities: takeoff items priced with unit rates (UNITPRICE rates or a JSON table), numbered by trade with subtotals, contingency (BOQCONTINGENCY %) and VAT (BOQVAT %); CSV or XLSX. | Analyze ▸ Checks |
| `CARBON` | EMBODIEDCARBON, LCA, CO2 | Embodied carbon (A1–A3, kgCO2e) of the model's materials from takeoff volumes, densities and carbon factors (CARBON:/DENSITY: overrides); optional CSV. | Analyze ▸ Building Physics |
| `CFDEXPORT` | WINDCASE, OPENFOAMOUT, WINDSTUDY | Writes an OpenFOAM wind-study case (simpleFoam, atmospheric boundary layer inlet, snappyHexMesh around the building, pedestrian-level sampling) for the given wind speed and direction. | Tools ▸ Analysis & Generative |
| `CHECKMODEL` | MODELCHECK, AUDITMODEL, BIMAUDIT | Checks the model: walls without height, openings wider than or outside their host, overlapping/duplicate walls and rooms, unnamed or duplicate rooms, missing levels. | Analyze |
| `CLASHDETECT` | CLASHES, CLASHTEST | Finds hard clashes between elements and 3D solids (touching and hosted/joined elements are ignored); lists, selects and zooms. | Analyze |
| `CLASHMANAGE` | CLASHMANAGER, CLASHGROUPS, CLASHSTATUS | Manages clash results kept in the drawing: Run (detect; disappeared clashes become resolved), List, Group (Type/Level/Proximity), Status, Assign, Zoom to a clash (selects both elements), Csv export. | Tools ▸ Analysis & Generative |
| `CODECHECK` | CHECKCODE, COMPLIANCE, RULECHECK | Checks rooms (area, height, width, window-to-floor ratio), stairs (riser, tread, 2R+T, width, flight), ramps and doors against JSON code rules (CODERULES or a file); lists, selects and zooms. | Analyze ▸ Building Physics |
| `CODERULES` | RULES | Stores code rules in the drawing from a JSON file (Load), writes the current rules to a file (Save) or restores the defaults. | Analyze ▸ Building Physics |
| `COLORBLINDCHECK` | CVDCHECK, COLOURBLINDCHECK, ACCESSIBLECOLORS | Checks layer colours for colour-blind safety (protanopia, deuteranopia, tritanopia; CIEDE2000) against the background; Fix re-colours the conflicting layers from the Okabe–Ito palette. | Tools ▸ Studies, Signatures & Publishing |
| `COSTESTIMATE` | COST, ESTIMATE | Cost estimate from the takeoff and unit rates (UNITPRICE drawing rates or a JSON table); optional CSV. | Analyze |
| `DAYLIGHT` | DAYLIGHTFACTOR, DF | Average daylight factor of each room from its windows (BRE formula: T·Aw·θ·M / A(1−R²)) and the window-to-floor ratio; optional CSV. | Analyze ▸ Building Physics |
| `DAYLIGHTANNUAL` | SDA, ASE, CLIMATEDAYLIGHT, LM83 | Climate-based daylight per room from an EPW weather file (or a clear-sky year): spatial daylight autonomy sDA300/50% and annual sunlight exposure ASE1000,250h (IES LM-83), optionally drawing the work-plane grid coloured by autonomy. | Tools ▸ Analysis & Generative |
| `DAYLIGHTRADIANCE` | RADIANCEDAYLIGHT, RADIANCEEXPORT, SDARADIANCE | Climate-based daylight with Radiance: Export a Radiance study (scene, materials, room sensors, sky, run.sh for the daylight-coefficient method with an EPW) or Import its results as sDA300/50% and ASE1000,250h per room (IES LM-83). | Tools ▸ Studies, Signatures & Publishing |
| `EGRESS` | TRAVELDISTANCE, ESCAPEROUTES, EGRESSCHECK | Egress check: longest walking distance from each room to the nearest exit (exterior or exit=1 doors, stairs on upper levels) around walls and columns, against the limit (EGRESSMAX, m). Draws the routes on EGRESS-ROUTES. | Analyze ▸ Checks |
| `ENERGYBALANCE` | HEATINGNEED, ENERGYNEED, SOLARGAINS | Seasonal heating energy balance: losses from degree days (latitude table or HDD), solar gains per window orientation, internal gains, utilisation factor; optional CSV. | Analyze ▸ Checks |
| `FIRECOMPARTMENTS` | FIRECHECK, COMPARTMENTS | Fire compartments: room areas grouped by prop fireCompartment (else per level) against FIREMAXAREA (doubled with FIRESPRINKLERS=1), and walls between compartments below FIRERATINGREQ minutes; selects failing walls. | Analyze ▸ Checks |
| `HEATLOSS` | HEATLOAD, ENERGY, ENERGYCALC | Design heat loss of the envelope (U·A·ΔT of exterior walls, windows, doors, roofs, ground floor) plus ventilation, and annual heating demand; optional CSV. | Analyze ▸ Building Physics |
| `IFCVALIDATE` | IFCCHECK, VALIDATEIFC | Validates an IFC file (or the model's own IFC export): syntax, schema header, references, GlobalIds, attribute counts, project/units, spatial containment. | Analyze ▸ Building Physics |
| `ISOVIST` | VIEWSHED, VISIBILITY | Draws the isovist (area visible from a point at eye height, walls block, doors and openings are see-through) and reports its area. | Analyze ▸ Building Physics |
| `LEVELAREAS` | AREABYLEVEL, GFA, FLOORAREAS | Area schedule by level: gross floor area (slabs, a 'gross' area plan or rooms) and net room area with the net/gross ratio; optional CSV. | Analyze ▸ Building Physics |
| `LOADTAKEDOWN` | TAKEDOWN, COLUMNLOADS | Structural load takedown per column: tributary slab areas, dead (self weight + LOADSDL) and imposed loads by room usage, accumulated down the stacked columns, ULS 1.35G+1.5Q, SLS and axial stress; optional CSV. | Analyze ▸ Checks |
| `PARKINGCHECK` | PARKINGCOUNT, PARKINGREQ | Parking provision check: required spaces from room usage and area (PARKINGRULES, e.g. office=35;apartment=unit:1) against the parking spaces placed, including accessible spaces. | Analyze ▸ Checks |
| `RAINWATER` | RAINCALC, DOWNPIPES | Rainwater from roofs: plan area incl. overhangs, runoff coefficient, design flow Q = C·i·A, downpipes (EN 12056-3 capacities), gutter length and annual harvest; optional CSV. | Analyze ▸ Checks |
| `REVERB` | RT60, REVERBERATION, ACOUSTICS | Reverberation time (Sabine RT60 at 500 Hz) of each room from its volume and surface absorption; optional CSV. | Analyze ▸ Building Physics |
| `ROOMSCHEDULE` | ROOMAREAS, AREASCHEDULE | Room area schedule with net (minus columns) and gross (to wall centre lines) areas, perimeter and volume; optional CSV. | Analyze |
| `SHADOWDIAGRAM` | SHADOWPLAN, SHADOWANALYSIS, PLANSHADOWS | Shadow study for a date and times at the project location: hatched ground shadows per time on A-SHADOW-hhmm layers and/or an SVG image sequence with an animated HTML page; prints the shadow areas. | Tools ▸ Studies, Signatures & Publishing |
| `SOLARRADIATION` | INSOLATION, IRRADIATION, SOLARGAIN | Clear-sky solar irradiation (kWh/m² per day) on exterior walls, windows and roofs for a date at the project location; optional CSV. | Analyze ▸ Building Physics |
| `STANDARDSCHECK` | CHECKSTANDARDS, DRAWINGSTANDARDS, CADSTANDARDS | Checks layers (naming pattern, required layers, objects on layer 0), ByLayer properties, text heights/styles and linetypes against a JSON drawing standard (DRAWINGSTANDARDS variable or a file); lists, selects and zooms. | Analyze ▸ Building Physics |
| `SUNPATH` | SUNPATHDIAGRAM, SUNCHART | Draws a polar sun path diagram (altitude rings, compass, the day's path with hours, solstices/equinox) for a date at the project location. | Analyze ▸ Building Physics |
| `SUNPOSITION` | SUNPOS, SUNCALC | Sun azimuth/altitude, sunrise and sunset for a date, time and the project location; stores SUNAZIMUTH/SUNALTITUDE. | Analyze |
| `TAKEOFF` | QTO, QUANTITIES | Quantity takeoff: wall areas/volumes (net of openings) per type and material, slabs, roofs, columns, beams, door/window counts; optional CSV. | Analyze |
| `TAKEOFFPHASE` | QTOPHASE, PHASEQUANTITIES, TAKEOFFLEVEL | Quantity takeoff split by construction phase (new work and demolition) and level; optional CSV. | Analyze ▸ Checks |
| `UNITPRICE` | COSTRATE, RATE | Stores a unit rate in the drawing (COST:<category>[:<type>]:<measure>) used by COSTESTIMATE. | Analyze |
| `UVALUE` | UVAL, THERMAL, LAMBDA | U-value (EN ISO 6946) of selected walls, slabs, roofs and openings from their layers; Lambda sets a material's conductivity, Set a type's U-value. | Analyze ▸ Building Physics |
| `WINDRESULTS` | CFDRESULTS, WINDIMPORT | Imports an OpenFOAM pedestrian-level velocity sample (raw x y z Ux Uy Uz) as wind arrows coloured by speed with Lawson comfort classes (the case's wind direction is taken from WINDDIRECTION); the Solve option runs the built-in 2D lattice Boltzmann solver instead (no external CFD needed). | Tools ▸ Analysis & Generative |

## Analyze

| Command | Aliases | Summary | Where |
|---|---|---|---|
| `ENERGYPLUS` | EPLUS, IDFEXPORT, ENERGYSIM | EnergyPlus simulation: Export an IDF (rooms as zones, envelope surfaces, windows, layered constructions, ideal-loads HVAC, location) or Run an installed EnergyPlus on it with an EPW weather file: site energy, EUI, end uses, unmet hours and per-room heating/cooling energy and peak loads (written to the rooms). | Tools ▸ Analysis & Design Assist |
| `QAASSIST` | MODELQA, EXPLAINWARNINGS, FIXMODEL | Model QA assistant: explains each model-checker finding (why it matters, what to do), Zoom to one, or Fix one / all fixable issues automatically after confirmation (one undo step). | Tools ▸ Analysis & Design Assist |
| `THERMALBRIDGES` | THERMALBRIDGE, PSIVALUES, TBHINT | Finds geometric linear thermal bridges of the envelope (wall corners, ground and intermediate floor edges, balconies, eaves, window/door reveals, columns in exterior walls) with lengths, ψ values (PSI:<kind> overrides) and H_TB = Σψ·L; selects the elements. | Tools ▸ Analysis & Design Assist |
| `WORKSCHEDULE` | SCHEDULE4D, 4D, GANTT, CONSTRUCTIONSEQUENCE | Construction sequencing (4D) and resources: Generate tasks from the model (by level and trade, quantity-based durations, crews), List with dates and critical path, Duration/Link to edit tasks, Simulate a date (selects the elements built by then), Resources (histogram, over-allocation, cost), Level (resource levelling), Gantt (SVG), Csv. | Tools ▸ Analysis & Design Assist |

## Annotate

| Command | Aliases | Summary | Where |
|---|---|---|---|
| `ANNOTATIVE` | ANNO | Makes text, leaders and tables annotative (height follows CANNOSCALE) or turns it off. | Annotate ▸ More |
| `ARCTEXT` |  | Places text along an arc (convex or concave side, height, offset), one character per text object, grouped. | Annotate ▸ More |
| `AUTODIMGRIDS` | GRIDDIMS, DIMGRIDS | Associative dimension string across parallel grid lines (bay dimensions and overall), updated when grids move. | Annotate ▸ More |
| `AUTODIMPLAN` | DIMPLAN, PLANDIMS, AUTODIMOVERALL | Dimensions the current level's plan automatically: exterior chains on all four sides (openings, walls, overall) on layer A-ANNO-DIMS; asks before adding them (one undo step). | Tools ▸ Analysis & Design Assist |
| `AUTODIMWALLS` | AUTODIMENSION, WALLDIMS, DIMWALLS | Automatic dimension strings along wall faces through wall ends and openings, with an overall dimension. | Annotate ▸ More |
| `AUTOSTACK` | TEXTSTACK, STACK | Stacks typed fractions in text (1/2, 3#4, 1^2) or unstacks them. | Tools ▸ BIM Grids, Zones & Data |
| `BREAKLINE` | BREAKLINESYMBOL | Draws a break line with a zig-zag symbol (size, extension). | Annotate ▸ More |
| `DATALINKUPDATE` | DLU | Updates linked tables from their CSV/XLSX files (Update) or writes table cells back to the files (Write). | Annotate ▸ More |
| `DETAILCOMPONENT` | DETAILCOMP, DC, COMPONENT2D | Places a 2D detail component (lumber, studs, brick, CMU, plywood, gypsum, steel sections) in the current view. | Tools ▸ Detailing & Tags |
| `DETAILMARK` | DETMARK, DETAILSYMBOL | Places a 2D detail bubble (number / sheet attributes) with an optional leader to the detail. | Tools ▸ Detailing & Tags |
| `DIM` |  | Smart dimension: picks an object (line → linear/aligned, arc → radius, circle → diameter) or two points. | Annotate ▸ More |
| `DIMALIGNED` | DAL, DIMALI | Creates a dimension aligned with its extension line origins. | Annotate |
| `DIMALTUNITS` | DIMALTU, DUALUNITS | Shows alternate units on dimensions, e.g. mm [in]: factor, decimals, suffix (Off removes them). | Tools ▸ Annotation & Data |
| `DIMANGULAR` | DAN, DIMANG | Dimensions the angle between lines, of an arc, or of three points. | Annotate |
| `DIMARC` | DAR | Dimensions the length of an arc. | Annotate ▸ More |
| `DIMBASELINE` | DBA, DIMBASE | Creates dimensions from the baseline of the last dimension. | Annotate ▸ More |
| `DIMBREAK` |  | Breaks dimension and extension lines where objects cross them (Auto, chosen objects or Manual gaps; associative). | Annotate ▸ More |
| `DIMCONTINUE` | DCO, DIMCONT | Continues a chain of dimensions from the last one. | Annotate ▸ More |
| `DIMDIAMETER` | DDI, DIMDIA | Dimensions the diameter of a circle or arc. | Annotate |
| `DIMDISASSOCIATE` | DDA | Removes associativity from selected dimensions. | Annotate ▸ More |
| `DIMEDIT` | DED, DIMED | Edits dimension text: Home (measured value), New text (<> = measurement). | Annotate ▸ More |
| `DIMINSPECT` | INSPECTDIM | Adds or removes an inspection frame (label / value / rate, round or angular ends) on dimensions. | Tools ▸ Annotation & Data |
| `DIMJOGGED` | DJO, JOG | Creates a jogged radius dimension for large arcs and circles (overridden centre, jog). | Annotate ▸ More |
| `DIMJOGLINE` | DJL | Adds or removes a jog line on a linear or aligned dimension (the value is not to scale). | Annotate ▸ More |
| `DIMLINEAR` | DLI, DIMLIN | Creates a horizontal, vertical or rotated linear dimension. | Annotate |
| `DIMORDINATE` | DOR, DIMORD | Creates X or Y ordinate dimensions from the origin (0,0). | Annotate ▸ More |
| `DIMOVERRIDE` | DOV, -DIMOVERRIDE | Overrides dimension style variables (DIMTXT, DIMASZ, DIMDEC, DIMSCALE, DIMPOST…) on selected dimensions, or Clear overrides. | Annotate ▸ More |
| `DIMRADIUS` | DRA, DIMRAD | Dimensions the radius of an arc or circle. | Annotate |
| `DIMREASSOCIATE` | DRE | Associates dimensions with the objects at their definition points (automatic within a tolerance) so they follow edits. | Annotate ▸ More |
| `DIMREBASE` | ORDINATEREBASE, ORDREBASE | Changes the datum (origin) of ordinate dimensions. | Annotate ▸ More |
| `DIMREGEN` |  | Updates associative dimensions, dimension breaks and overrides. | Annotate ▸ More |
| `DIMSPACE` |  | Evenly spaces parallel linear/aligned dimensions from a base dimension (0 aligns them). | Annotate ▸ More |
| `DIMSTYLE` | D, DST, DDIM, -DIMSTYLE | Creates, edits, lists and sets dimension styles. | Annotate ▸ More |
| `DIMTEDIT` | DIMTED | Moves the text / dimension line of a dimension to a new location. | Annotate ▸ More |
| `DIMTOLERANCE` | DIMTOLS, DTOL | Adds tolerances to dimensions: Symmetrical ±t, Deviation +u/−l, Limits (upper/lower values), Basic (boxed) or None. | Tools ▸ Annotation & Data |
| `ELEVATIONMARK` | ELEVMARK, ELEVATIONSYMBOL | Places a 2D elevation marker (bubble with a pointer in the view direction; 4 for an interior elevation set). | Tools ▸ Detailing & Tags |
| `EQDIM` | EQUALITYDIM, EQCONSTRAINT | Equality dimensions: a chain of EQ dimensions that keeps three or more objects equally spaced (Create/Toggle EQ-value/Remove). | Tools ▸ BIM Graphics & Systems |
| `FIELD` |  | Inserts text containing a field (area, length, property, variable, count, date) that updates automatically. | Annotate ▸ More |
| `FILLEDREGION` | FR, REGIONFILL | View-specific filled region on the current level: solid colour or a drafting / model pattern, with optional boundary lines; associative to its boundary. | Tools ▸ Detailing & Tags |
| `FIND` |  | Finds (and optionally replaces) text in texts, leaders, dimensions, tables and attributes. | Annotate ▸ More |
| `FLOORPATTERN` | FLOORPAT, SURFACEPATTERN | Shows the surface pattern of floor materials in plan: select slabs (or All on the current level); Remove deletes the patterns. The patterns follow slab, wall and material changes. | Tools ▸ Styles, Patterns & Occlusion |
| `HATCHTYPE` | HPTYPE, PATTERNTYPE | Sets hatches to Model patterns (real size, scale with the model) or Drafting patterns (fixed size on paper at the annotation scale). | Tools ▸ Detailing & Tags |
| `HYPERLINK` | LINK, URL, -HYPERLINK | Attaches a URL (web page or file) to objects; exported PDFs make them clickable. Empty removes the link. | Tools ▸ Navigate, Light & Publish |
| `INSULATION` | BATT, INSUL, BATTINSULATION | Draws the batt insulation symbol along a line at a given width (associative: stretch the line to extend it). | Tools ▸ Detailing & Tags |
| `JUSTIFYTEXT` | TEXTALIGN | Changes the justification of text without moving it. | Annotate ▸ More |
| `KEYNOTE` | KN | Keynotes: define keys, assign them to elements with a keynote tag, and place a keynote legend table. | Architecture ▸ Documentation |
| `LEADER` | LE, LEAD, QLEADER | Creates a leader line with annotation text. | Annotate |
| `MARKS` | RENUMBER, NUMBEROPENINGS | Renumbers door and window marks per level in reading order (D01…, W01…), or sets a mark. | Architecture ▸ Documentation |
| `MASKINGREGION` | MASKREGION | View-specific masking region on the current level: hides the model and drafting beneath it. | Tools ▸ Detailing & Tags |
| `MATERIALTAG` | MATTAG, TAGMATERIAL | Tags the material under a picked point (the layer of a compound wall, a slab's finish, or the element material); the tag follows material changes. | Tools ▸ Detailing & Tags |
| `MATHATCH` | MATERIALHATCH, HATCHMATERIAL | Binds hatches to a material: they show its cut or surface pattern (and optionally its colour) and follow later pattern changes. | Tools ▸ Images, Links & Structure |
| `MATPATTERN` | MATERIALPATTERN, FILLPATTERNS | Sets the cut or surface fill pattern of a material; walls and bound hatches update everywhere. | Tools ▸ Images, Links & Structure |
| `MATPATTERNDIALOG` | MATERIALPATTERNSDIALOG, FILLPATTERNSDIALOG | Material Fill Patterns dialog: cut and surface pattern of every material; bound hatches and floor patterns update. | Tools ▸ Styles, Patterns & Occlusion |
| `MLEADER` | MLD | Creates a multileader (arrowhead, landing, text). | Annotate |
| `MLEADERALIGN` | MLA | Aligns the landings (text) of leaders with a reference leader, vertically or horizontally. | Annotate ▸ More |
| `MLEADERCOLLECT` | MLC | Collects several leaders into one: the first leader's arrow with all texts stacked (Vertical) or in a row (Horizontal) at a new landing. | Annotate ▸ More |
| `MLEADERSTYLE` | MLS | Creates, edits, lists and sets multileader styles (text height, annotative, layer, arrowhead, landing, text frame). | Annotate ▸ More |
| `MTEXT` | MT, T | Creates paragraph (multiline) text inside a width. | Annotate |
| `MTEXTCOLUMNS` | TEXTCOLUMNS | Sets columns on multiline text: Static (count, balanced), Dynamic (fixed column height) or No columns. | Tools ▸ Annotation & Data |
| `NORTHARROW` | NORTH | Places a north arrow symbol (defaults to project north). | Annotate ▸ More |
| `OBJECTSCALE` | -OBJECTSCALE, AISCALEADD | Adds or deletes annotation scales of annotative objects (shown only at their scales when ANNOALLVISIBLE is 0). | Annotate ▸ More |
| `QDIM` |  | Quickly dimensions selected objects: Continuous, Staggered, Baseline, Ordinate, Radius, Diameter, datumPoint. | Annotate ▸ More |
| `REPEATDETAIL` | REPEATINGDETAIL, RDETAIL | Repeating detail: a component arrayed along a path (brick courses, blocking); editing the path or spacing regenerates it. | Tools ▸ Detailing & Tags |
| `REVCLOUDLIST` | REVISIONCLOUDS | Lists revision clouds by revision, selects the clouds of one revision, and adds missing revisions to the revision table. | Tools ▸ Detailing & Tags |
| `REVSTAMP` | REVTRIANGLE, REVTAG, REVISION | Revision stamps: a numbered revision triangle, or a new row in the revision table; advances the drawing revision (REVNUMBER). | Collaborate ▸ Review |
| `SCALEBAR` |  | Places a graphic scale bar (segments, segment length, labels in m or drawing units). | Annotate ▸ More |
| `SCALELISTEDIT` | SCALELIST | Edits the list of annotation scales (Add/Delete/Reset/List). | Annotate ▸ More |
| `SCALETEXT` |  | Changes the height of text objects (new height or scale factor) keeping their insertion points. | Annotate ▸ More |
| `SCHEDULECELLS` | SCHEDULEHIGHLIGHT, CONDITIONALFORMAT | Conditional formatting of schedules: highlight the Row or only the Cell of a field when "field op value" holds (shown in placed schedules); Clear. | Tools ▸ Detailing & Tags |
| `SECTIONSYMBOL` | SECMARK, SECTIONHEAD | Draws a 2D section symbol: cut line with section heads (number / sheet attributes) looking to the picked side. | Tools ▸ Detailing & Tags |
| `SPELL` | SPELLCHECK | Checks the spelling of text, leaders, tables, dimension text and attributes (Change / Ignore / Add to the drawing dictionary). | Annotate ▸ More |
| `SPELLDIALOG` | SPELLING, CHECKSPELLING | Spelling dialog: lists misspelled words in text, leaders, tables and attributes with suggestions (Change / Ignore / Add). | Annotate ▸ More |
| `SPOTCOORD` | SPOTCOORDINATE, COORDLABEL | Labels the coordinates (N/E) of a point with a leader that updates when it is moved. | Annotate ▸ More |
| `SPOTELEV` | SPOTELEVATION, SPOTLEVEL | Places live spot elevations (slab tops, roofs, toposurface) with a leader. | Annotate ▸ More |
| `SPOTSLOPE` | SLOPELABEL | Places live spot slopes (arrow pointing downhill with % and 1:n) on sloped slabs, ramps, roofs and toposurfaces. | Annotate ▸ More |
| `TABLEEDIT` | TABEDIT, TABLEDIT | Edits a table: cell text or =formula (SUM, AVERAGE…), insert/delete rows and columns, column widths. | Annotate ▸ More |
| `TABLEEXPORT` | TABLEEXP | Exports a table to a CSV file. | Annotate ▸ More |
| `TABLELINK` | DATALINK, TABLEFROMCSV | Inserts a table linked to a CSV or Excel (.xlsx) file (update with DATALINKUPDATE when the file changes). | Annotate ▸ More |
| `TABLESTYLE` | TS | Table styles: New / Edit title, header and data cells (height, alignment, colour, fill), Current, Apply to tables, List, Delete. | Tools ▸ Detailing & Tags |
| `TAG` | TAGBYCATEGORY, ELEMENTTAG | Tags a door, window, room or element with a live label (mark, type, name, area, keynote…). | Architecture ▸ Documentation |
| `TAGALL` | TAGALLNOTTAGGED | Tags every untagged door, window and/or room on the current level. | Architecture ▸ Documentation |
| `TAGLABEL` | EDITLABEL, TAGFORMAT | Tag labels linked to element parameters: Label template with {Parameter} fields, single Field, Annotative paper height, List. | Tools ▸ Images, Links & Structure |
| `TEXT` | DT, DTEXT | Creates single-line text objects. | Annotate |
| `TEXTEDIT` | ED, DDEDIT | Edits text, leader, dimension text, table cells or attribute values. | Annotate ▸ More |
| `TEXTEDITINPLACE` | MTEDIT, INPLACETEXT, TEXTFORMAT | In-place text editor on the canvas: bold, italic, underline, font, height and colour (also opened by double-clicking text); exported to PDF and DXF MTEXT. | Tools ▸ Styles, Patterns & Occlusion |
| `TEXTFRAME` | TFRAME, TEXTBORDER | Draws or removes a frame around text. | Annotate ▸ More |
| `TEXTLIST` | BULLETS, NUMBERING, MTEXTLIST | Adds bullets, numbers or letters to the paragraphs of multiline text (or removes them). | Tools ▸ Annotation & Data |
| `TEXTMASK` | BACKGROUNDMASK, TMASK | Hides objects behind text with a background mask (offset factor, background or a colour). | Annotate ▸ More |
| `TEXTREADABLE` | TEXTFLIP | Turns upside-down text (rotated between 90° and 270°) by 180° so it reads left-to-right, keeping its position. | Annotate ▸ More |
| `TEXTSTYLE` | STYLE, ST, -STYLE | Creates or modifies a text style and makes it current. | Annotate ▸ More |
| `TEXTSTYLEDIALOG` | TEXTSTYLEMANAGER, STYLEDIALOG | Text Style manager: font, height, width factor and oblique angle with a live preview; renaming a style updates its text. | Tools ▸ Styles, Patterns & Occlusion |
| `TEXTUNMASK` | TUNMASK | Removes background masks from text. | Annotate ▸ More |
| `TOLERANCE` | TOL, GDT | Creates a GD&T feature control frame: characteristic symbol, tolerance value, datums. | Annotate ▸ More |
| `TXT2MTXT` | TEXTTOMTEXT | Combines single-line texts into one multiline text (top to bottom). | Annotate ▸ More |
| `UPDATEFIELD` | UPDFIELD | Updates fields (including date fields) in the selected text. | Annotate ▸ More |

## Architecture

| Command | Aliases | Summary | Where |
|---|---|---|---|
| `ADAPTIVE` | ADAPTIVECOMPONENT, ADAPTIVEPOINTS | Adaptive components driven by placement points: Place a Strut, Panel, Frame or a family using P1x…P1z, P2x… values (points typed x,y,z or picked point objects the component follows); Move a point to flex it. | Tools ▸ Adaptive, Corners & Roofs |
| `AREAPLAN` | AREABOUNDARY, GROSSAREA | Creates area plan boundaries (Gross, Rentable or custom schemes) and reports totals per scheme. | Architecture ▸ Rooms & Areas |
| `AREASCHEME` | AREASCHEMES, GIA, NIA, GEA, DIN277 | Area schemes (GEA, GIA, NIA, DIN 277 BGF/NRF, Gross, Rentable): places associative area boundaries that follow the walls, lists schemes and reports totals. | Architecture ▸ More |
| `ASSEMBLY` | ASSEMBLIES, CREATEASSEMBLY, AGGREGATE | Assemblies (element aggregation): Create from selected elements, Add, Remove, Disassemble, Views (isolated plan and 3D views), List. | Tools ▸ BIM Types & Parameters |
| `AUTONAMEROOMS` | ROOMNAMING, AUTOTAGROOMS, NAMEROOMS | Names and numbers rooms of the current level from their fixtures (toilet, bath, bed, kitchen…), shape, windows and doors; Unnamed only or All; lists the suggestions and asks before applying (one undo step). | Tools ▸ Analysis & Design Assist |
| `BEAM` |  | Draws structural beams between points, or between picked columns (Columns: top of beam at the column tops). | Architecture |
| `BIMUPDATE` | REGENASSOC, UPDATEASSOCIATIVE | Regenerates associative content: area boundaries, automatic dimensions, associative sweeps and family instances. | Architecture ▸ More |
| `BUILDING` | MASS, QUICKBUILDING | Quick massing: a rectangle becomes walls, floor slabs and a roof on one or more storeys; Mass turns 3D solids (conceptual masses) into mass floors or walls/floors/roofs by face. | Architecture |
| `CEILING` | CEIL | Creates a ceiling from points, a closed object or the walls around a point. | Architecture |
| `COLORFILL` | COLORSCHEME, ROOMCOLORS, AREACOLORS | Colours rooms/areas by a parameter (name, department, area range, level, any property) and places a colour legend. | Architecture ▸ More |
| `COLUMN` | COLUMNS | Places structural columns (rectangular or round); Grids places one at every grid intersection, hosted so it follows the grids. | Architecture |
| `COMPONENT` | FURNITURE, COMP, FURN | Places parametric furniture, fixtures, casework, cars and plants from the library (or a custom box); size flexes the family. | Architecture |
| `COPYTOLEVEL` | PASTEALIGNED, COPYLEVELS, CTL | Copies selected building elements to other levels, aligned in plan (hosted doors and windows follow their walls). | Architecture ▸ More Building Tools |
| `CORNERWINDOW` | CORNERWIN, WRAPWINDOW | Corner window wrapping the corner of two walls: widths along each wall from the corner, height and sill; the walls are cut through the corner and the glazing meets at a slim post. | Tools ▸ Adaptive, Corners & Roofs |
| `CURTAINSYSTEM` | CURTAINBYFACE, CWBYFACE | Curtain system by face: curtain walls on every vertical face of mass solids (grid spacing and mullion size). | Tools ▸ BIM Graphics & Systems |
| `CURTAINWALL` | CW, CURTAIN | Draws glazed curtain walls with mullion grids. | Architecture |
| `CWGRID` | CURTAINGRID | Edits a curtain wall grid: add/remove grid lines, panels (glass, solid, spandrel, louvre, empty, door, double door), mullion types, uniform spacing. | Architecture ▸ More Building Tools |
| `DOOR` | DOORS | Places doors in walls (default 900×2100). | Architecture |
| `DORMER` | DORMERS, ROOFDORMER | Builds a dormer on a sloped roof: front and cheek walls, a gable or shed dormer roof, and the opening in the main roof. | Architecture ▸ More |
| `ELEVATOR` | LIFT, ELEVATORSHAFT | Places an elevator: car, shaft walls up to a top level and a shaft opening through the floors. | Architecture ▸ More |
| `ESCALATOR` | ESCALATORS, MOVINGSTAIR | Places an escalator from its bottom comb in a travel direction up to the level above (30°/35°, step width 600/800/1000), checks EN 115 rise/inclination/speed rules and cuts the upper floor; Check re-validates existing escalators. | Tools ▸ BIM Grids, Zones & Data |
| `FAMILY` | FAMILYEDIT, FAMILIES, FAM | Family editor: new family, parameters and formulas, forms (box, cylinder, extrusion, sweep, revolve, void, nested, arrays), types, place instances, set instance values, flex, door/window builder, assign to openings. | Architecture ▸ More |
| `FAMILYPANEL` | FAMPANEL, FAMILYWINDOW | Family Editor panel: families list, parameters and formulas, forms, types table, reference planes, profiles, live 3D preview and flex; Apply is one undo step. | Tools ▸ Families, Views & Panels |
| `FLOORFINISH` | FINISHFLOOR, TILEFLOOR | Places a floor finish layer in rooms (material, thickness, tile pattern in plan). | Architecture ▸ More |
| `GENDESIGN` | GENERATIVEDESIGN, OPTIMIZELAYOUT, LAYOUTOPT | Generative design: optimises floor layouts for a room programme and gross area with a genetic algorithm (daylight, proportions, adjacencies, orientation, compactness); lists the Pareto-optimal designs and builds the chosen one after confirmation. | Tools ▸ Analysis & Generative |
| `GRID` | GRIDLINE, GR | Places structural grid lines (straight, Arc through 3 points or Multi-segment), auto-labelled 1,2,3 (vertical) and A,B,C (horizontal). | Architecture |
| `GRIDSYSTEM` | GRIDGEN, RECTGRID, GRIDARRAY | Creates a rectangular grid system from spacing lists (e.g. 3*6000 4500): numbered grids along X, lettered along Y. | Tools ▸ BIM Grids, Zones & Data |
| `INPLACE` | INPLACEMODEL, GENERICMODEL, MODELINPLACE | In-place generic model: turns solids modelled in context into a schedulable component (Create), or back into solids to edit (Edit). | Tools ▸ BIM Graphics & Systems |
| `LEVEL` | LEVELS, LV | Lists, creates, sets, renames and deletes levels; sets elevation and height. | Architecture ▸ More |
| `MODELGROUP` | BIMGROUP, FURNITUREGROUP, GROUPBIM | Model groups: create a named group of elements, place instances, update all instances from an edited one, list, or ungroup. | Architecture ▸ More |
| `NICHE` | RECESS | Cuts a recess of a given depth into one face of a wall. | Architecture ▸ More Building Tools |
| `OPENING` | WALLOPENING | Cuts empty openings in walls. | Architecture |
| `OPENINGFLIP` | FLIPDOOR, FLIPWINDOW, DOORFLIP, FLIPOPENING | Flips doors and windows: Hand (hinge side), Facing (swing / exterior side) or Both. | Tools ▸ BIM Grids, Zones & Data |
| `OPENINGPARTS` | GLAZINGBARS, WINDOWPARTS, DOORPARTS | Sets window mullions/transoms and door fanlights/thresholds on selected openings. | Architecture ▸ More |
| `OPENINGTRIM` | CASING, ARCHITRAVE, LINTEL, SILLBOARD | Sets door/window casings (architraves), an interior window board and a lintel with bearings on selected openings. | Architecture ▸ More |
| `OPENINGTYPE` | DOORTYPE, WINDOWTYPE, TYPECATALOG | Door/window type catalog: list, new, set type parameters and sub-parts (mullions, transoms, threshold), formulas, apply to openings, delete, import CSV. | Architecture ▸ More Building Tools |
| `PARTS` | CREATEPARTS, DIVIDEPARTS | Divides compound walls into parts (one per layer, cut by the host's openings), Merge restores the wall, Material overrides a part, Show Parts/Original. | Tools ▸ BIM Types & Parameters |
| `PHASE` | PHASES, PHASING | Manages construction phases: list, new, current phase, filter, created/demolished phase of objects. | Architecture ▸ Documentation |
| `PLANGEN` | PLANFROMBRIEF, GENERATEPLAN, SPACEPLAN | Generates floor plan options from a room programme ("Living 25, Kitchen 12, Bedroom 14 x2, Bath 6, Hall 8" in m²) inside a W × D footprint: lists scored options, builds the chosen one (walls, rooms, doors, windows) after confirmation, one undo step. | Tools ▸ Analysis & Design Assist |
| `PROFILE` | PROFILES, PROFILEFAMILY | Profile families for sweeps, handrails, gutters and mullions: list, create from a closed polyline (flexes with Width/Height), or delete. | Architecture ▸ More |
| `PROPERTIES` | PR, PROPS, GETPROP | Shows the properties of the selected object(s). | Architecture ▸ More |
| `RADIALGRID` | GRIDRADIAL, POLARGRID | Creates a radial grid system: centre, start angle, angular spacings (e.g. 6*15), inner radius and radial spacings; numbered radial grids and lettered arc grids. | Tools ▸ BIM Grids, Zones & Data |
| `RAILING` | RAIL | Draws a railing along a path, or on both sides of a Stair's flights (sloped, following the stair). | Architecture |
| `RAILINGTYPE` | RAILTYPE, BALUSTERS, HANDRAIL | Sets the railing type of selected railings: preset (Balusters, Glass, Cable, Bars, Wooden, Handrail) or handrail profile, baluster spacing and extensions. | Architecture ▸ More |
| `RAILTYPEDEF` | RAILINGTYPES, RAILTYPEBUILDER | Named railing types (height, handrail profile and size, infill, balusters, posts, extensions): New / Edit (railings of the type follow), Assign, List, Delete. | Tools ▸ BIM Types & Parameters |
| `RAMP` |  | Creates a sloped ramp (straight or along a path with turns), with landings between flights; warns above 1:12. | Architecture ▸ More Building Tools |
| `ROOF` | RF | Creates a flat, shed, gable or hip roof from a footprint. | Architecture |
| `ROOFEDGE` | FASCIA, GUTTER, SOFFIT, ROOFEDGES | Adds fascia boards, gutters (profile) and soffits along the eaves of roofs. | Architecture ▸ More |
| `ROOFEXTRUSION` | ROOFBYEXTRUSION, EXTRUDEDROOF, ROOFEXTRUDE | Roof by extrusion: pick an open polyline drawn as the roof profile (x = across, y = height), then the start, direction and length of the extrusion and the eave height. | Tools ▸ BIM Types & Parameters |
| `ROOFJOIN` | JOINROOF, UNJOINROOF, ROOFJOINS | Joins a roof to another: the picked edge is extended until the roof meets the other roof and the part below it is cut away (Unjoin restores it). | Tools ▸ Adaptive, Corners & Roofs |
| `ROOFSHAPE` | ROOFFORM, MANSARD, GAMBREL, DOMEROOF, BARRELROOF | Changes roofs into Mansard or Gambrel (two pitches with a break) forms, a Dome or a Barrel vault, or back to Plain. | Tools ▸ BIM Grids, Zones & Data |
| `ROOFSHAPEPOINTS` | SHAPEEDIT, DRAINAGEPOINTS, ROOFFALLS, SUBELEMENTS | Shape editing of flat roofs: Add points with a height (drainage falls, ridges) or raise the corners, List, Reset; the roof top becomes a triangulated surface. | Tools ▸ BIM Types & Parameters |
| `ROOM` | SPACE, RM | Places rooms bounded by walls (pick inside) or by points; reports area. | Architecture |
| `ROOMBOUNDING` | ROOMBOUND, RBOUND | Sets whether walls, curtain walls and columns bound rooms (used by ROOM, ROOMUPDATE and SLAB Walls). | Architecture ▸ Rooms & Areas |
| `ROOMFINISH` | ROOMFINISHES, FINISHSCHEDULE | Sets room floor/base/wall/ceiling finishes and places the room finish schedule. | Architecture ▸ More |
| `ROOMSEPARATOR` | ROOMSEP, RSL | Draws room separation lines (virtual room boundaries used by ROOM, SLAB Walls, ROOMUPDATE). | Architecture ▸ Rooms & Areas |
| `ROOMUPDATE` | UPDATEROOMS, RU | Recomputes the boundaries and areas of rooms placed by picking, after walls or separation lines changed. | Architecture ▸ Rooms & Areas |
| `SCANTOBIM` | PCFITWALLS, PLANEFIT, SCANFIT | Detects planes in the point cloud (RANSAC) and creates walls from vertical planes and floor slabs from horizontal planes. | Tools ▸ Import, Export & Collaboration |
| `SCATTER` | SCATTERPLANTS, VEGETATION, GRASSSCATTER | Scatters Grass, Flowers, Shrubs or Trees over closed boundaries with Poisson-disk spacing at a density per m² (reproducible seed); shown in the viewport and renders. | Tools ▸ Render, Materials & Environment |
| `SCHEDULE` | SCH | Creates a schedule table (walls, doors, windows, rooms, slabs…) or prints it; Define/Edit/Export/Import/Place manage stored schedules (fields, filters, sorting, grouping, totals, round-trip editing, CSV/XLSX, sheets). | Architecture ▸ More |
| `SCRIPTCOMPONENT` | SCRIPTFAMILY, SCRIPTEDOBJECT, SCRIPTOBJ, GDLCOMPONENT | GDL-like scripted BIM objects: Place a component from an OpenSCAD script (file, or a script solid) whose Customizer parameters become instance parameters; Set a parameter (range-checked) to flex it; List its parameters. | Tools ▸ Adaptive, Corners & Roofs |
| `SETPROP` | SP, SETPROPERTY | Sets any property of objects: SETPROP #12 height 2800. | Architecture ▸ More |
| `SHAFT` | SHAFTOPENING, VERTICALSHAFT | Creates a shaft that cuts every floor and roof between a base and a top level (associative: move it and the holes follow). | Architecture ▸ More |
| `SKETCHTOWALLS` | IMAGETOWALLS, TRACEWALLS, PHOTOTOMODEL | Converts a scanned or photographed plan image (PNG/BMP/PGM) into walls: dark strokes within a thickness range become wall centre lines at a given scale; asks for confirmation before creating them (one undo step). | Tools ▸ Analysis & Generative |
| `SKYLIGHT` | ROOFWINDOW, ROOFLIGHT | Places a skylight / roof window in a roof: framed glazing in the roof plane that cuts the roof. | Architecture ▸ More |
| `SLAB` | FLOOR, SB | Creates a floor slab from points, a closed object or the walls around a point. | Architecture |
| `SLABEDGE` | SLABEDGES, CURB, UPSTAND, BALCONYEDGE | Slab edges: an Upstand (curb, balcony upstand) or Fascia profile along a picked slab edge or All edges; Clear removes them. | Tools ▸ BIM Types & Parameters |
| `SLABOPENING` | FLOOROPENING, ROOFOPENING, VERTICALOPENING | Cuts a vertical opening in one floor or roof (sketched outline; associative with its host). | Architecture ▸ More |
| `SLABSLOPE` | SLOPEARROW, SLOPE | Slopes a slab by a slope arrow (low point, high point, rise) or angle; Flat resets. | Architecture ▸ More Building Tools |
| `SLABTYPE` | FLOORTYPE, ROOFTYPE, FLOORTYPES | Layered floor/roof types: list, create (plies top-down), assign to slabs and roofs (thickness follows the build-up), or delete. | Architecture ▸ More |
| `SPLITWALL` | WALLSPLIT, SPLITELEMENT | Splits a wall at a picked point (repeatable) or by Levels into one wall per storey; hosted openings follow their piece. | Tools ▸ BIM Grids, Zones & Data |
| `STACKEDWALL` | STACKWALL, WALLSTACK | Makes walls stacked walls: segments of wall types bottom-up ("Type:height; Type:*"), regenerated when the base wall changes; Off removes the stack. | Tools ▸ BIM Types & Parameters |
| `STAIR` | STAIRS | Creates straight, L, U or spiral stairs between levels (width, rise or top level, risers, tread, landings). | Architecture |
| `STAIRCHECK` | CHECKSTAIRS, STAIRRULES | Checks stairs against riser, going, 2R+G, width, flight-length and landing rules. | Architecture ▸ More Building Tools |
| `STAIRSKETCH` | STAIRBYSKETCH, SKETCHSTAIR | Stair by sketch: select riser lines (bottom to top by the walking line), give the total rise; the riser/going rules are checked (max riser, min going, 2R+G). | Tools ▸ BIM Types & Parameters |
| `STAIRTYPE` | STAIRTYPES | Stair types (max riser, min going, width, landing, material, railing type): New / Edit (every stair of the type follows), Assign to stairs, List, Delete. | Tools ▸ BIM Types & Parameters |
| `STOREFRONT` | SHOPFRONT, GLAZEDPARTITION, PARTITIONGLASS | Storefront curtain walls (bays, transom, capped mullions, entrance door) or glazed Partitions (slim mullions, full-height door). | Tools ▸ BIM Types & Parameters |
| `STORY` | STOREY, STORYSETTINGS, STOREYSETTINGS | Storey settings: Height (moves the storeys above), Insert above / below, Delete, Computation height (walls that bound rooms), Elevation display (project / survey / relative), List. | Tools ▸ BIM Types & Parameters |
| `WALL` | WA | Draws a chain of joined walls (thickness, height, justification, type, arcs). | Architecture |
| `WALLATTACH` | ATTACHWALL, WALLDETACH | Attaches the top of walls to a roof or slab soffit, or the base to a slab top; Detach removes the attachment. | Architecture ▸ Documentation |
| `WALLBYLINES` | WALLFROMLINES, WBL | Converts selected lines, arcs, polylines, splines and ellipses into walls (curves become chains of arc walls). | Architecture ▸ More Building Tools |
| `WALLFLIP` | FLIPWALL, WALLREVERSE | Flips walls: swaps the interior and exterior faces (layer order) keeping the wall, its openings and door swings in place. | Tools ▸ BIM Grids, Zones & Data |
| `WALLJOIN` | WJ, WALLCLEANUP | Joins wall ends that nearly meet (extends/trims them to their intersection). | Architecture ▸ More Building Tools |
| `WALLJOINEDIT` | EDITWALLJOINS, JOINTYPE, WALLJOINTYPE | Edits a wall join: pick near a wall end, then Miter, Butt (this wall stops at the other), Square off, or Disallow the join. | Architecture ▸ More |
| `WALLPOLYGON` | POLYWALL, WALLPOLY, WALLLOOP | Draws a closed loop of joined walls: a regular polygon (centre, sides, radius), points, or a picked closed polyline. | Tools ▸ BIM Types & Parameters |
| `WALLRECT` | WALLRECTANGLE, RECTWALL, WALLBOX | Draws four joined walls around a rectangle (two corners; Justify sets whether the rectangle is the inside, centre or outside face). | Tools ▸ BIM Types & Parameters |
| `WALLSWEEP` | SWEEPWALL, CORNICE, SKIRTING | Adds cornices, skirting boards or string courses along wall faces, Reveals (grooves cut into the faces), or removes them. | Architecture ▸ More Building Tools |
| `WALLTOP` | WALLCONSTRAINT, TOPCONSTRAINT, WT | Sets the top constraint of walls (a level with offset, the next level, or an unconnected height) and their shape: elevation Profile or Gable, Slant, Taper, Reset. | Architecture ▸ More Building Tools |
| `WALLWRAP` | LAYERWRAP, WRAPINSERTS | Wraps the finish layers of compound walls into door/window openings (all walls or selected walls) and around free wall Ends. | Architecture ▸ More |
| `WATER` | WATERSURFACE, POND, POOLWATER | Water surface with animated waves (viewport and renders) inside a closed polyline or picked points, at a surface elevation and depth. | Tools ▸ Render, Materials & Environment |
| `WINDOW` | WIN | Places windows in walls (default 1200×1200, sill 900). | Architecture |
| `ZONE` | ZONES, ROOMZONE | Zones: Assign rooms to a named fire/HVAC/department/security zone, Remove, List zone areas, or draw zone Outlines (rooms merged across the walls). | Tools ▸ BIM Grids, Zones & Data |

## Blocks

| Command | Aliases | Summary | Where |
|---|---|---|---|
| `ATTDEF` | ATT, -ATTDEF | Defines an attribute (modes Invisible/Constant/Verify/Preset/Lock, tag, prompt, default) to include in a block. | Insert ▸ Block & Reference |
| `ATTEDIT` | ATE, -ATTEDIT, EATTEDIT | Changes attribute values of a block reference. | Insert ▸ More |
| `ATTEXT` | -ATTEXT, ATTEXTRACT | Extracts block reference attributes to a CSV file (or the command line). | Insert ▸ More |
| `ATTSYNC` |  | Updates block references with the current attribute definitions of their block. | Insert ▸ More |
| `BASE` |  | Sets the drawing's insertion base point (INSBASE), used when it is inserted as a block. | Insert ▸ More |
| `BATTMAN` | -BATTMAN | Edits the attribute definitions of a block (prompt, default, tag, modes, order, delete) and syncs references. | Insert ▸ More |
| `BCLOSE` |  | Closes the block editor, saving or discarding the changes. | Tools ▸ Block & Reference Editing |
| `BCOUNT` | BLOCKCOUNT | Counts block references (including nested ones) in the drawing or a selection. | Insert ▸ More |
| `BEDIT` | BE, BLOCKEDITOR | Opens a block definition in the block editor (only its objects are shown; new objects join the block). BCLOSE saves. | Tools ▸ Block & Reference Editing |
| `BFLIP` | FLIP, BLOCKFLIP | Flips block references about their insertion point (dynamic flip parameter, state kept in the reference). | Insert ▸ More |
| `BLOCK` | B, -BLOCK, BMAKE | Creates a block definition from selected objects. | Insert ▸ Block & Reference |
| `BLOCKBASE` | BBASE, BASEPOINT | Changes a block definition's base point; references stay where they are. | Insert ▸ More |
| `BLOCKLIBRARY` | BLIB, CONTENTBROWSER | Browses a folder of drawings as a block library: List, Search, Insert (files and the blocks inside them). | Insert ▸ More |
| `BLOCKPALETTE` | BLOCKSPANEL, CONTENTLIBRARY | Block library panel: library folders with thumbnails, search, favourites and recents; drag blocks onto the drawing. | Tools ▸ Review Panels |
| `BLOCKREPLACE` | BREPLACE | Replaces all references of one block with another (keeps attributes with matching tags). | Insert ▸ More |
| `BPARAMETER` | BPARAM, DYNPARAM | Adds dynamic parameters to a block: Stretch (a length that stretches the objects in a frame) or Array (a count repeating objects); List, Delete. | Insert ▸ More |
| `BSAVE` |  | Saves the block editor content into the block definition. | Tools ▸ Block & Reference Editing |
| `BTABLE` | BLOCKTABLE, BLOOKUP, LOOKUPTABLE | Block properties table: named sets of dynamic parameter values (Add/Delete/List) applied to references by name (Apply). | Tools ▸ Annotation & Data |
| `BVSTATE` | BVISIBILITY, VISIBILITYSTATE | Dynamic block visibility states: New, Set (on references), Hide/Show objects in a state, List, Delete, Rename. | Insert ▸ More |
| `COPYMONITOR` | COPYMON, COORDINATIONREVIEW | Copy/monitor levels and grids from a linked model: Copy, Check (coordination review), Update, Release. | Tools ▸ Images, Links & Structure |
| `DATAEXTRACTION` | DX, EATTEXT | Extracts block counts or attributes into a table in the drawing (or a CSV file). | Insert ▸ More |
| `DYNPROP` | BDYNSET, DYNVALUE | Sets dynamic parameter values of block references (stretch lengths, array counts). | Insert ▸ More |
| `GROUP` | G, -GROUP | Creates and manages named groups (Create/Add/Remove/Explode/REName/List); picking a member selects the group (PICKSTYLE). | Home ▸ Groups |
| `IMAGEADJUST` | IAD, -IMAGEADJUST | Adjusts the brightness, contrast and fade (0–100) of images; Reset restores the defaults. | Tools ▸ Images, Links & Structure |
| `IMAGEADJUSTDIALOG` | IMAGEADJUSTDLG, IADDIALOG | Image Adjust dialog: brightness, contrast and fade of the selected raster images with a preview (exact on screen and in PDF plots). | Tools ▸ Styles, Patterns & Occlusion |
| `IMAGEATTACH` | IAT, IMAGE | Places a raster image reference (path, insertion point, width, rotation). | Insert ▸ Block & Reference |
| `IMAGECLIP` | ICL, CLIPIMAGE | Clips an image to a rectangular or polygonal boundary: ON/OFF, Delete, New boundary, Invert. | Tools ▸ Images, Links & Structure |
| `IMAGEFRAME` |  | Image clip frames: 0 hidden, 1 shown and plotted, 2 shown but not plotted. | Tools ▸ Images, Links & Structure |
| `INSERT` | I, -INSERT, DDINSERT | Inserts a block reference (scale, rotation, attributes). | Insert ▸ Block & Reference |
| `LIBRARYINSTALL` | BUNDLEDLIBRARY, INSTALLLIBRARY | Installs the free bundled block library (furniture, sanitary, kitchen, vehicles, people, trees, annotation symbols) into a folder and makes it the block library. | Tools ▸ Block & Reference Editing |
| `REFCLOSE` |  | Ends in-place reference editing: Save writes the changes to the block definition, Discard restores it. | Tools ▸ Block & Reference Editing |
| `REFEDIT` | -REFEDIT | Edits a block reference in place; REFSET adds or removes objects, REFCLOSE saves or discards. | Tools ▸ Block & Reference Editing |
| `REFSET` |  | Adds drawing objects to, or removes objects from, the in-place reference working set. | Tools ▸ Block & Reference Editing |
| `RESETBLOCK` | BRESET | Resets block references to their block definition (dynamic values and visibility state). | Insert ▸ More |
| `RVTLINK` | LINKMODEL, LINKIFC, MANAGELINKS, MODELLINK | Linked BIM models (.archi/IFC): list, Attach (origin-to-origin, shared coordinates or a point), Reload, Unload, Detach, Position, Notify. | Tools ▸ Images, Links & Structure |
| `UNGROUP` | UNG | Dissolves the groups of the selected objects. | Home ▸ Groups |
| `WBLOCK` | W, -WBLOCK | Writes a block, selected objects or the whole drawing to a new .archi file. | Insert ▸ More |
| `XATTACH` | ATTACH, XA | Attaches a drawing (.archi/.dxf) as an external reference and places it. | Insert ▸ Block & Reference |
| `XBIND` | -XBIND | Binds external references into the drawing as ordinary blocks (Bind: X$0$name, Insert: merged names). | Insert ▸ More |
| `XCLIP` | XC, CLIPBLOCK, BCLIP | Clips block references and xrefs to a rectangular or polygonal boundary (New/ON/OFF/Delete/Polyline). | Tools ▸ Annotation & Data |
| `XREF` | XR, -XREF, EXTERNALREFERENCES, ERHIGHLIGHT | External references: list, Attach/Overlay a drawing (.archi/.dxf), Reload, Unload, Detach, Bind, Path, Notify (changed files). | Insert ▸ Block & Reference |

## Collaborate

| Command | Aliases | Summary | Where |
|---|---|---|---|
| `BCFIN` | BCFIMPORT, IMPORTBCF | Imports BCF 2.x topics (.bcfzip) as markups: comments, status, viewpoint camera and selection mapped to elements by IFC GlobalId. | Collaborate ▸ Review |
| `BCFOUT` | BCFEXPORT, EXPORTBCF | Exports the markups as BCF 2.1 topics (.bcfzip) with comments, status, camera and selected elements by IFC GlobalId. | Collaborate ▸ Review |
| `BCFSERVER` | BCFAPI, OPENCDE, BCFCONNECT | Connects to a BCF API (OpenCDE) server: Connect (URL, bearer token), Projects, Pull (topics → markups with comments, cameras and selections) and Push (markups → topics, comments and viewpoints). The server URL and project are saved in the drawing (BCFSERVER, BCFPROJECT); the token is kept only for the session. | Tools ▸ Analysis & Generative |
| `CENTRAL` | WORKSHARING, SYNCCENTRAL, STC | Work sharing with a central model: Create (make this drawing the central file), Local (open a local copy of a central file), Sync (synchronise with central, optionally keeping borrowed elements), Borrow / Relinquish selected elements, Owners (who owns what), Permissions (signed access policy: viewer/editor/admin roles and protected layers, enforced on Sync; refused changes are saved beside the local copy). | Tools ▸ Import, Export & Collaboration |
| `COEDIT` | COLLABORATE, LIVESHARE, COEDITSYNC | Co-editing through a shared folder: Join (folder, your name), Sync (send your edits, receive the others'; also after each command with AUTOSYNC), Status, Leave. Edits of different objects merge; concurrent edits of one object keep the latest and are reported. | Tools ▸ Analysis & Generative |
| `COMPARE` | DWGCOMPARE, DRAWINGCOMPARE, MODELDIFF | Compares the drawing with another version (.archi, .dxf, .ifc…) by object id and geometry: added, removed and modified objects; optional colour-coded overlay file (green added, red removed, yellow modified) and CSV report. | Collaborate ▸ Review |
| `COMPAREPANEL` | COMPAREOVERLAY | Compares with another version and draws the differences over the plan (added green, removed red, modified yellow). | Tools ▸ Review Panels |
| `GITVERSION` | GIT, GITCOMMIT, GITLOG | Git versioning of the drawing as a line-per-object .archit file next to it: Commit (with message), Log, Diff two revisions (or a revision and the drawing) object by object, Checkout a revision (undoable). | Tools ▸ Import, Export & Collaboration |
| `ISSUETRACKER` | ISSUELIST, TRACKISSUES | Issue tracker stored in the drawing: Add (linked to the selection), List, Show, Status, Assign, Priority, Comment, Zoom, Delete and Csv export. | Collaborate ▸ Versions & Issues |
| `MARKUP` | MARKUPS, REVCOMMENT, COMMENT, ISSUE | Review markups stored in the drawing: Add (cloud + comment with author/date, linked to selected elements and the view), List, Resolve, Reopen, Reply, Zoom, Delete. | Collaborate ▸ Review |
| `MARKUPPANEL` | ISSUES, MARKUPMANAGER | Opens the markup/issue panel: filter open/resolved, reply, resolve, zoom to, link to the selection, BCF. | Tools ▸ Review Panels |
| `MODELMERGE` | MERGE3, MERGEBRANCH | Three-way merge: combines another branch of the drawing (theirs) into this one using their common ancestor (base); non-conflicting changes of both sides are kept, conflicts keep ours and are listed. | Collaborate ▸ Versions & Issues |
| `PDFMARKUPS` | MARKUPIMPORT, PDFCOMMENTS | Imports the comments of a PDF page (notes, clouds/rectangles, ink, lines, highlights) as review markups with author and date, placed with the plot scale and origin and linked to the elements under them. | Tools ▸ Import, Export & Collaboration |
| `RESOLVECONFLICTS` | SYNCCONFLICTS, MERGECONFLICTS, CONFLICTCOPIES | Finds the sync-conflict copies of the drawing (iCloud Drive, Dropbox, OneDrive…) and merges them in (three-way, nothing lost; true conflicts keep yours and are listed); merged copies move to <name>.archi-conflicts/. | Tools ▸ Analysis & Generative |
| `SHARE` | SHAREDRAWING, SENDTO | Shares the drawing through the Windows share sheet (Mail, Teams, Nearby Sharing…): Project (.archi), Pdf of the drawing or active sheet, or Both. | Collaborate ▸ Share |
| `SHAREVIEW` | VIEWEREXPORT, EXPORTVIEWER, HTMLVIEWER | Exports a read-only, self-contained HTML viewer (all level plans as vectors with pan/zoom, element info on click, room schedule, layer toggles) to share with people without the app. | Tools ▸ Import, Export & Collaboration |
| `SIGNFILE` | SIGNDOC, DIGITALSIGN, SIGN | Signs a file (PDF, DWG, IFC, the drawing…) with your key: writes a detached <file>.sig with the signer, time, SHA-256 and Ed25519 signature. | Tools ▸ Studies, Signatures & Publishing |
| `SIGNKEY` | SIGNINGKEY, NEWSIGNKEY | Creates (or shows) your Ed25519 signing key, kept in Application Support; prints the public key others add to TRUSTEDSIGNERS. | Tools ▸ Studies, Signatures & Publishing |
| `STANDARDS` | STANDARDSPACKAGE, OFFICESTANDARDS | Office standards package (.archistd): Export this drawing's layers, linetypes, styles, materials, types, view templates and hatch patterns; Import (add, optionally overwrite); Check deviations. | Collaborate ▸ Versions & Issues |
| `TRACEREVIEW` | TRACES, TRACEOVERLAY, REVIEWTRACE | Trace review overlays: New (named overlay layer over the drawing, linked to the view and selected elements), Enter/Exit (draw on it), Show/Hide, Zoom (restores its view and selects its elements), List, Close, Import (merge its sketches into the drawing), Delete. | Tools ▸ Import, Export & Collaboration |
| `TRUSTSIGNER` | TRUSTKEY, TRUSTEDSIGNERS | Adds a signer's public key (or the key of a .sig file) to the drawing's trusted signers. | Tools ▸ Studies, Signatures & Publishing |
| `VERIFYSIGNATURE` | CHECKSIGNATURE, SIGVERIFY | Checks a file against its <file>.sig: valid signature, unchanged content, and whether the signer is trusted (TRUSTEDSIGNERS). | Tools ▸ Studies, Signatures & Publishing |
| `VERSIONS` | CHECKPOINT, DOCVERSIONS, VERSIONHISTORY | Version history saved next to the drawing: Save a named checkpoint, List, Restore a version (undoable), Diff two versions (or a version and the current drawing), Delete, Prune. | Collaborate ▸ Versions & Issues |

## Documentation

| Command | Aliases | Summary | Where |
|---|---|---|---|
| `ROOMDATASHEET` | ROOMDATA, RDS | Room data sheets: Show per-room reports, Export (CSV/HTML/text), Import an edited CSV back into the rooms, or Set one field. | Tools ▸ BIM Graphics & Systems |

## Draw

| Command | Aliases | Summary | Where |
|---|---|---|---|
| `ARC` | A | Draws an arc (3 points, start-center-end, start-end-radius, center-start-angle, continue). | Draw |
| `ARC2PH` | ARCHEIGHT | Draws an arc through two end points with a given height (sagitta); pick or type the height. | Home ▸ More |
| `ARC2PL` | ARCBYLENGTH | Draws an arc through two end points with a given arc length (longer than the chord). | Home ▸ More |
| `ARCTOCIRCLE` | CIRCLEFROMARC, ARC2CIRCLE | Completes arcs into full circles (keeps layer and properties). | Home ▸ More |
| `BLEND` | BLENDCURVES, BL | Creates a tangent (or smooth) spline joining the ends of two open curves. | Home ▸ More |
| `BOUNDARY` | BO, BPOLY | Creates closed polylines from the area enclosed around a picked point. | Home ▸ More |
| `BOUNDINGBOX` | BBOX | Draws the rectangle bounding the selected objects. | Home ▸ More |
| `BOX` |  | Creates a 3D solid box (on the face under the first corner when DUCS is on). | Model |
| `CENTERLINE` | CL | Creates an associative centre line between two lines. | Home ▸ More |
| `CENTERMARK` | CM, DIMCENTER, DCE | Adds associative centre marks to circles and arcs. | Home ▸ More |
| `CIRCLE` | C | Draws a circle (center/radius, diameter, 2P, 3P, tangent-tangent-radius, tangent-tangent-tangent). | Draw |
| `CIRCLE2PR` | C2PR | Draws a circle through two points with a given radius (pick the side of the centre). | Home ▸ More |
| `CIRCLETPP` | CTPP | Draws a circle tangent to one object through two points. | Home ▸ More |
| `CIRCLETTP` | CTTP | Draws a circle tangent to two objects through one point. | Home ▸ More |
| `CIRCLETTT` | CTTT | Draws a circle tangent to three objects (lines, circles, arcs). | Home ▸ More |
| `CONE` |  | Creates a 3D solid cone or frustum. | Model |
| `CYLINDER` | CYL | Creates a 3D solid cylinder: centre, 3P, 2P or Elliptical base; height, 2Point or Axis endpoint. | Model |
| `DLINE` | DL, DOUBLELINE | Draws double lines (two parallel polylines with end caps). | Home ▸ More |
| `DONUT` | DO, DOUGHNUT | Draws filled rings or solid dots. | Home ▸ More |
| `ELLIPSE` | EL | Draws an ellipse or elliptical arc. | Draw |
| `ELLIPSE4P` | EL4P | Draws an ellipse through four points with its axes at a given angle (default 0). | Home ▸ More |
| `ELLIPSEC3P` | ELC3P | Draws an ellipse from its centre and three points on the curve. | Home ▸ More |
| `ELLIPSEFOCI` | ELFOCI | Draws an ellipse from its two foci and a point on the curve. | Home ▸ More |
| `ELLIPSEQUAD` | ELQ, ELLIPSEPARALLELOGRAM, ISOCIRCLE, ELLIPSE4 | Draws the largest ellipse inscribed in a quadrilateral (tangent to its four sides): four corners, a 4-sided closed polyline, or four lines. | Home ▸ More |
| `EXTRUDE` | EXT | Extrudes closed 2D objects into 3D solids: height, Direction (oblique), Path, Taper angle, Both sides (symmetric). | Model |
| `GRADIENT` | GD | Fills an enclosed area or selected objects with a gradient fill (linear, cylinder, spherical, curved; one or two colours). | Home ▸ More |
| `HATCH` | H, BHATCH, BH | Fills an enclosed area or selected objects with a hatch pattern or solid fill. | Draw |
| `HELIX` |  | Draws a 2D/3D helix or spiral: base and top radius, turns, height and twist direction. | Tools ▸ 3D Primitives & Solid Tools |
| `HYPERBOLA` |  | Draws a hyperbola branch from centre, vertex, conjugate semi-axis and half-height (as a smooth polyline). | Home ▸ More |
| `INCIRCLE` | CIRCLEINSCRIBED | Draws the circle inscribed in the triangle formed by three lines. | Home ▸ More |
| `LINE` | L | Draws straight line segments. | Draw |
| `LINEANG` | LANG, LINEBYANGLE | Draws a line from a point at a fixed angle and length. | Home ▸ More |
| `LINEBISECT` | LBIS, BISECTOR | Draws the bisector of the angle between two lines from their intersection. | Home ▸ More |
| `LINEHV` | HVLINE, LHV | Draws horizontal or vertical lines (end points are projected). | Home ▸ More |
| `LINEPAR` | LPAR, PARALLELLINE | Draws a line parallel to a picked line through a point. | Home ▸ More |
| `LINEPERP` | LPERP, PERPLINE | Draws a line from a point perpendicular to a picked line (to its foot). | Home ▸ More |
| `LINEREL` | LREL, LINERELANGLE | Draws a line at an angle relative to a picked line or segment. | Home ▸ More |
| `LINETAN` | LTAN, TANLINE | Draws a line from a point tangent to a circle or arc. | Home ▸ More |
| `LINETAN2` | LTAN2, TANGENTLINE2 | Draws a common tangent of two circles (Outer or Inner), picked near the tangent points. | Home ▸ More |
| `LINETANORTHO` | LTANO | Draws a line tangent to a circle and perpendicular to a line (from the tangent point to the line). | Home ▸ More |
| `MLINE` | ML | Draws multiple parallel lines (multiline style, scale, Top/Zero/Bottom justification), grouped. | Home ▸ More |
| `MLSTYLE` | -MLSTYLE | Multiline styles: New (element offsets, caps), Set current, List, Delete. | Home ▸ More |
| `PARABOLA` |  | Draws a parabola from its vertex, focus and half-width (as a smooth polyline). | Home ▸ More |
| `PATLOAD` | HATCHPATLOAD, LOADPAT | Loads hatch patterns from an AutoCAD .pat file into the drawing (saved with it). | Insert ▸ Images & Geo |
| `PLINE` | PL | Draws a 2D polyline of line and arc segments. | Draw |
| `POINT` | PO | Creates point objects (style: PDMODE/PDSIZE). | Home ▸ More |
| `POINTLATTICE` | PTLATTICE, POINTGRID | Places a lattice of points (columns × rows at given spacings, optional angle). | Home ▸ More |
| `POINTSLINE` | PTLINE, POINTSONLINE | Places a number of evenly spaced points between two points (both ends included). | Home ▸ More |
| `POLYGON` | POL | Draws an equilateral closed polyline. | Draw |
| `POLYGONSS` | POLSS, POLYGONSIDES | Draws a regular polygon from the midpoint of one side and the opposite side (odd sides: opposite vertex). | Home ▸ More |
| `PTYPE` | DDPTYPE | Sets the point display style (PDMODE) and size (PDSIZE). | Home ▸ More |
| `RAY` |  | Draws semi-infinite construction lines from a start point through each given point. | Home ▸ More |
| `RECTANG` | REC, RECTANGLE | Draws a rectangular polyline (optionally filleted or chamfered). | Draw |
| `REGION` | REG | Converts closed chains of lines/arcs into closed polylines (regions). | Home ▸ More |
| `REVCLOUD` |  | Draws a revision cloud: polygonal, rectangular, freehand, from an object or enclosing objects (attached: it moves with them); tagged with the current revision. | Home ▸ More |
| `REVOLVE` | REV | Revolves closed 2D objects about an axis into 3D solids (associative: the solid regenerates when the profile is edited; DELOBJ 1 deletes profiles). | Model |
| `SKETCH` |  | Freehand sketch: records the points of a drag (record increment, Type polyline/line/spline) until Enter. | Home ▸ More |
| `SNAKE` | SNAKELINE | Draws a polyline from relative moves: R500 L200 U300 D100 (right/left/up/down), @dx,dy or @d<angle; Close/Undo. | Home ▸ More |
| `SOLID` | SO | Creates solid-filled triangles and quadrilaterals (AutoCAD point order 1-2-3-4). | Home ▸ More |
| `SPHERE` |  | Creates a 3D solid sphere. | Model |
| `SPLINE` | SPL | Draws a smooth curve through fit points, or by control vertices (Method CV, Degree 1-5). | Draw |
| `STAR` |  | Draws a star-shaped closed polyline. | Home ▸ More |
| `TABLE` | TB | Inserts an empty table. | Annotate |
| `TRACE` |  | Draws solid lines of a given width (a wide polyline). | Home ▸ More |
| `WIPEOUT` |  | Creates a masking area (solid background fill) that covers objects beneath. | Home ▸ More |
| `XLINE` | XL | Draws infinite construction lines: through two points, Horizontal, Vertical, at an Angle (or relative to a Reference line), Bisecting an angle, or Offset from a line. | Home ▸ More |

## Edit

| Command | Aliases | Summary | Where |
|---|---|---|---|
| `COPYBASE` |  | Copies objects to the clipboard with a base point. | Home ▸ More |
| `COPYCLIP` |  | Copies objects to the clipboard. | Home ▸ More |
| `COPYPICTURE` | COPYASPDF, COPYIMAGE, COPYPDF | Copies the selected objects (or the whole drawing) to the clipboard as a vector PDF and a PNG picture for other apps. | Tools ▸ Files, Clipboard & Access |
| `CUTCLIP` |  | Moves objects to the clipboard (removes them from the drawing). | Home ▸ More |
| `PASTEBLOCK` |  | Pastes the clipboard as a block reference. | Home ▸ More |
| `PASTECLIP` |  | Pastes the clipboard at an insertion point. | Home ▸ More |
| `PASTEORIG` |  | Pastes the clipboard at its original coordinates. | Insert ▸ Block & Reference |
| `PASTESPECIAL` | PASTESPEC, PASTEEXTERNAL, PASTEFROMAPP | Pastes what another app copied — SVG or PDF vectors, pictures, DXF text, plain text or Explorer files — at an insertion point. | Tools ▸ Files, Clipboard & Access |
| `PASTETOPOINTS` | COPYTOPOINTS, PASTEMULTI | Pastes the clipboard at several picked points (one undo step). | Home ▸ More |
| `REDO` | MREDO | Reverses the last undo. | Home ▸ More |
| `U` |  | Reverses the most recent action. | Home ▸ More |
| `UNDO` |  | Reverses actions: a count, or Mark/Back (to a mark) and BEgin/End (group several commands into one step). | Home ▸ More |

## File

| Command | Aliases | Summary | Where |
|---|---|---|---|
| `BREPIN` | BREPIMPORT, IMPORTBREP, OCCTIN | Imports an OpenCASCADE BREP file (FreeCAD .brep/.brp) as mesh solids: stored triangulations are used, other faces are triangulated from their edges. | Tools ▸ File Tools & Exchange |
| `BREPOUT` | BREPEXPORT, EXPORTBREP, OCCTOUT | Exports the 3D model as an OpenCASCADE BREP file (shells of planar faces, millimetres) for FreeCAD, Salome and other OCCT tools. | Tools ▸ File Tools & Exchange |
| `CITYJSONIMPORT` | CITYJSONIN, CITYMODELIMPORT, IMPORTCITYJSON | Imports a CityJSON city model (buildings, terrain, roads … at their highest LoD) as mesh solids per city object with attributes. | Insert ▸ More |
| `CLOSE` |  | Closes the current drawing. | Insert ▸ More |
| `COBIEOUT` | COBIEEXPORT, EXPORTCOBIE, COBIE | Exports a COBie 2.4 spreadsheet (.xlsx): contact, facility, floors, spaces, types, components (doors, windows, equipment) and attributes. | Insert ▸ More |
| `DAEOUT` | COLLADAOUT, COLLADAEXPORT, EXPORTDAE | Exports the 3D model as COLLADA 1.4.1 (.dae, metres, Z up, Phong materials). | Insert ▸ More |
| `DGNEXPORT` | DGNOUT, EXPORTDGN | Exports the drawing's 2D objects as a MicroStation V7 .dgn file (one level per layer, master units m, resolution 0.1 mm). | Tools ▸ Import, Export & Collaboration |
| `DRAWINGRECOVERY` | DRM | Shows documents recovered from autosave after a crash. | Insert ▸ More |
| `DWGCONVERTER` | DWGSETUP, ODACONVERTER | Shows or sets the DWG converter used by DWGIN/DWGOUT (path to ODAFileConverter or dwg2dxf; stored in the drawing). | Insert ▸ More |
| `DWGIN` | DWGIMPORT, IMPORTDWG | Imports a DWG drawing through an installed converter (ODA File Converter or LibreDWG); explains how to get one if none is installed. | Insert ▸ More |
| `DWGOUT` | DWGEXPORT, SAVEASDWG | Writes a DWG file (DXF converted by the installed ODA File Converter or LibreDWG). | Insert ▸ More |
| `DXFOUTVERSION` | DXFSAVEAS, DXFVERSIONOUT, DXF2018OUT | Writes an ASCII DXF of a chosen version: R12, R2000, R2004, R2007, R2010, R2013 or R2018 (AC1032, UTF-8 text). | Tools ▸ Exchange Options |
| `DXFR12OUT` | DXFOUTR12, SAVEASR12, DXF12 | Writes a DXF R12 (AC1009) file for older CAD/CAM software (splines, ellipses, hatches and MText are converted). | Insert ▸ Export |
| `E57IN` | E57IMPORT, IMPORTE57 | Imports an ASTM E57 point cloud (all scans, poses applied, colour and intensity) as points. | Tools ▸ File Tools & Exchange |
| `E57OUT` | E57EXPORT, EXPORTE57 | Exports the drawing's points (with their z, colour and intensity) as an ASTM E57 point cloud. | Tools ▸ File Tools & Exchange |
| `ETRANSMIT` | PACKANDGO, TRANSMIT, ARCHIVEPACKAGE | Packs the drawing with its referenced images, material textures and external references (paths rewritten) and a transmittal report into a ZIP. | Collaborate ▸ Share |
| `EXCHANGECHECK` | GBXMLCHECK, COBIECHECK, VALIDATEEXPORT | Checks the gbXML or COBie export (or a given file) against the schema's required elements, enumerations and references. | Collaborate ▸ Share |
| `EXPORT` | EXP | Exports the drawing (PDF, DXF, SVG, OBJ, STL, GLB, IFC, CSV, PNG). | Insert ▸ More |
| `EXPORT3MF` | 3MFOUT, 3MFEXPORT | Exports the 3D model as a 3MF package (millimetres, one object per element). | Insert ▸ Export |
| `FILEMETADATA` | SPOTLIGHTINFO, MDITEMS | Lists the Spotlight metadata of the drawing or a file (title, authors, layers, levels, rooms, searchable text). | Tools ▸ File Tools & Exchange |
| `FILEPREVIEW` | FINDERPREVIEW, SPOTLIGHTINFO, FILEMETADATA | Finder preview icon and Spotlight metadata of the saved drawing: Update now, Icons on/off, Versions on/off, Show the indexed metadata. | Tools ▸ Files, Clipboard & Access |
| `FILEVERSIONS` | BROWSEVERSIONS, MACVERSIONS, REVERTTO | Versions of the saved file (every save keeps one): Browse window, List, Restore a version, Open a copy, Save a version now, Keep count. | Tools ▸ Files, Clipboard & Access |
| `GBXMLOUT` | GBXMLEXPORT, EXPORTGBXML, ENERGYMODELOUT | Exports the energy model as gbXML 0.37: spaces, exterior/interior walls with windows and doors, roofs, floors, constructions with U-values. | Insert ▸ More |
| `GEOJSONEXPORT` | GEOJSONOUT | Exports 2D entities (selection or all) as GeoJSON in WGS84 or local metres. | Insert ▸ Export |
| `GEOJSONIMPORT` | GEOJSONIN | Imports GeoJSON features (WGS84 lon/lat are projected around the project location; projected metres are used as-is). | Insert ▸ Import |
| `HPGLOUT` | PLTOUT, HPGLEXPORT, HPGL | Writes the current level's plan as HP-GL/2 (.plt) for plotters and cutters, at a plot scale. | Insert ▸ More |
| `IDSCHECK` | IDSVALIDATE, CHECKIDS | Checks the model's IFC export (or an IFC file) against an Information Delivery Specification (.ids): entity, attribute, property and material requirements. | Analyze ▸ Building Physics |
| `IFCIMPORT` | IFCIN, -IFCIMPORT | Imports an IFC (IFC2x3/IFC4) model: walls, slabs, columns, beams, doors, windows and spaces become BIM elements; other products become meshes. | Insert ▸ Import |
| `IFCMAP` | IFCMAPPING, IFCCLASSMAP | IFC class mapping for export: Set a component category or element type to an IFC class and predefined type (e.g. Plumbing → IfcSanitaryTerminal.WASHHANDBASIN), List, Remove, Clear. Element props IfcExportAs override the table. | Tools ▸ Import, Export & Collaboration |
| `IFCOPTIONS` | IFCEXPORTOPTIONS, IFCSETTINGS | IFC export settings saved in the drawing: schema (IFC2X3 Coordination View 2.0, IFC4 or IFC4X3), model view definition (ReferenceView = tessellated or DesignTransferView), base quantities (Qto_*) and georeferencing (IfcMapConversion). | Collaborate ▸ Share |
| `IFCXMLOUT` | IFCXMLEXPORT, EXPORTIFCXML | Exports the building model as ifcXML (IFC4, ISO 10303-28 XML encoding); a .zip or .ifczip name writes an IfcZIP holding the ifcXML. | Tools ▸ Exchange Options |
| `IFCZIPOUT` | IFCZIPEXPORT, EXPORTIFCZIP | Exports the model as IfcZIP (compressed IFC4). | Insert ▸ More |
| `IMPORT` | IMP | Imports a DXF, SVG or .archi file into the drawing. | Insert ▸ More |
| `IMPORTFILE` | FILEIMPORT, IMPORTANY | Imports a file by extension: .archi, .dxf, .ifc, .svg, .obj, .stl, .3mf, .geojson, .csv/.txt/.xyz points. | Insert ▸ Import |
| `JOURNAL` | AUTOSAVEJOURNAL, CHANGEJOURNAL | Change journal for crash recovery: On (record every change every n seconds to the recovery folder), Off, Now (record immediately), Status. | Collaborate ▸ Versions & Issues |
| `KMLOUT` | KMZOUT, KMLEXPORT, KMZEXPORT, GOOGLEEARTH | Exports KML or KMZ placed at the project location (GEOGRAPHICLOCATION / project latitude, longitude, north angle): extruded walls, slabs, roofs and rooms by level, linework by layer; KMZ also carries the 3D model (COLLADA). | Insert ▸ Images & Geo |
| `LASEREXPORT` | CNCSVG, LASERSVG, MAKERCAM | Exports outlines for laser cutters / CNC as a true-size SVG in mm: joined continuous paths, red = cut, blue = engrave (layers *ENGRAV*/*SCORE*/*ETCH* or blue objects), optional model scale and kerf compensation. | Tools ▸ Import, Export & Collaboration |
| `LAZCONVERTER` | LAZSETUP, LASZIP | Shows or sets the LAZ decompressor used to import .laz point clouds (laszip, pdal or las2las; stored in the drawing). | Tools ▸ Studies, Signatures & Publishing |
| `MESHIMPORT` | OBJIMPORT, STLIMPORT, 3MFIMPORT, OBJIN, STLIN, GLTFIMPORT, GLBIMPORT, PLYIMPORT, OFFIMPORT, AMFIMPORT, DAEIMPORT, COLLADAIMPORT | Imports an OBJ, STL, 3MF, glTF/GLB, PLY, OFF, AMF or COLLADA (.dae) file as mesh solids (choose the file's units where the format has none). | Insert ▸ Import |
| `NEW` | QNEW | Creates a new drawing. | Insert ▸ More |
| `NEWFROMTEMPLATE` | NEWTEMPLATE, QNEW | Starts a new drawing from a template (built-in or from the templates folder). | Tools ▸ Start & Templates |
| `OPEN` |  | Opens a drawing (.archi, .dxf). | Insert ▸ More |
| `OSMIMPORT` | OPENSTREETMAP, IMPORTOSM, OSMIN | Imports an OpenStreetMap .osm extract around the project location: building outlines (optionally extruded to their height), roads, water and areas. | Insert ▸ More |
| `PLOT` | PRINT | Plots the current sheet or view to PDF or a printer. | Insert ▸ More |
| `PLYOUT` | PLYEXPORT, EXPORTPLY | Exports the 3D model as an ASCII PLY mesh (millimetres, Z up, vertex colours from materials). | Insert ▸ More |
| `POINTCLOUDIMPORT` | PCIMPORT, IMPORTCLOUD, XYZIMPORT, PTSIMPORT, POINTCLOUD | Imports a point cloud (XYZ, PTS or PLY ASCII/binary) as point entities with colours, decimated to a point budget and/or a voxel grid. | Insert ▸ More |
| `POINTSEXPORT` | PTEXPORT, EXPORTPOINTS | Writes point entities (selection or all) to CSV: name,x,y,z,code,layer. | Insert ▸ Export |
| `POINTSIMPORT` | CSVPOINTS, PTIMPORT, IMPORTPOINTS | Imports survey points from CSV/TSV/TXT (X,Y[,Z][,name] with or without header, or P,N,E,Z,D). | Insert ▸ Import |
| `PRESENTOUT` | PRESENTATION, SLIDESHOW, PRESENTEXPORT | Writes the sheets and saved views as a self-contained HTML slide show (full screen with F, arrow keys, speaker notes from the sheet field 'notes'). | Tools ▸ Studies, Signatures & Publishing |
| `QUIT` | EXIT | Quits the application. | Insert ▸ More |
| `RECOVER` | RECOVERFILE, OPENRECOVER | Opens a damaged .archi drawing, repairing it: truncated files are closed after the last complete object, undecodable objects and settings are dropped, and the model is audited. | Collaborate ▸ Versions & Issues |
| `RECOVERYFILES` | JOURNALRECOVERY, RECOVERJOURNAL | Lists the autosave copies and change journals left by a crash or forced quit, and opens one (Open n) or deletes them (Clear). | Collaborate ▸ Versions & Issues |
| `RHINOIN` | 3DMIN, 3DMIMPORT, IMPORT3DM, RHINOIMPORT | Imports a Rhino .3dm file (versions 2–8): meshes, B-reps (render meshes or tessellated trimmed faces), extrusions, surfaces, curves, points and blocks, with layers, colours, materials and units. | Tools ▸ Exchange More |
| `RHINOOUT` | 3DMOUT, 3DMEXPORT, EXPORT3DM, RHINOEXPORT | Exports a Rhino .3dm (version 4) file in the drawing units: the 3D model as meshes coloured by material, drafting curves as exact lines, arcs, polylines and NURBS, with layers. | Tools ▸ Exchange More |
| `SAVE` | QSAVE | Saves the drawing. | Insert ▸ More |
| `SAVEAS` | SA | Saves the drawing under a new name. | Insert ▸ More |
| `SAVEASTEMPLATE` | SAVETEMPLATE, TEMPLATESAVE | Saves the drawing's settings, layers, styles and content as a template in the templates folder. | Tools ▸ Start & Templates |
| `SAVECHECK` | ROUNDTRIPCHECK, CHECKSAVE | Verifies that saving and reopening the drawing gives an identical document (lists any section that would change). | Tools ▸ File Tools & Exchange |
| `SAVECOPY` | SAVEACOPY, COPYSAVE | Saves a copy of the drawing under another name or format (.archi, .architemplate, .dxf, .ifc, …); the open drawing keeps its name and unsaved state. | Tools ▸ File Tools & Exchange |
| `SCRIPT` | SCR | Runs a script file of command lines. | Insert ▸ More |
| `SCRIPTTEXT` | RUNSCRIPT | Runs command lines given as text (lines separated by newlines, \n or /). | Insert ▸ More |
| `SHPIMPORT` | SHAPEFILEIMPORT, IMPORTSHP, SHPIN | Imports an ESRI shapefile (.shp with .dbf attributes and .prj CRS: WGS84, UTM, Web Mercator) as points/polylines; elevation attributes become contour elevations. | Insert ▸ More |
| `STARTSCREEN` | START, WELCOME | Shows the start screen: templates, samples and recent drawings. | Tools ▸ Start & Templates |
| `STEPIN` | STEPIMPORT, STPIN, IMPORTSTEP | Imports polyhedral geometry from a STEP (AP203/AP214/AP242) file as mesh solids (planar faces; curved B-rep surfaces are skipped). | Insert ▸ More |
| `STEPOUT` | STEPEXPORT, STPOUT, EXPORTSTEP | Exports the 3D model as STEP AP214 faceted B-reps (one solid per element, millimetres, with colours). | Insert ▸ More |
| `SVGIMPORT` | SVGIN, -SVGIMPORT | Imports SVG paths, lines, polylines, polygons, circles, ellipses, rectangles and text as drawing entities. | Insert ▸ Import |
| `SVGLAYERSOUT` | SVGOUTLAYERS, SVGEXPORTLAYERS, LAYEREDSVG | Exports the current level's plan as SVG with one group (Inkscape/Illustrator layer) per drawing layer. | Insert ▸ Images & Geo |
| `TEMPLATEIN` | LOADTEMPLATE, STARTFROMTEMPLATE | Replaces the drawing with a new untitled drawing started from a template file (undoable). | Tools ▸ File Tools & Exchange |
| `TEMPLATEOUT` | EXPORTTEMPLATE, WRITETEMPLATE | Writes the drawing as a template file (.architemplate) with a name and description; everything in the drawing is kept. | Tools ▸ File Tools & Exchange |
| `UPGRADEFILE` | FILEUPGRADE, MIGRATEFILE | Upgrades older .archi / .architemplate files (a file or every file in a folder) to the current format, keeping the originals as .vN.archi.bak. | Tools ▸ File Tools & Exchange |
| `USDEXPORT` | USDZEXPORT, USDAEXPORT, USDZOUT, USDOUT | Exports the 3D model as USD: .usda text or .usdz package (UsdPreviewSurface materials). | Insert ▸ Export |
| `XLSXIN` | XLSXIMPORT, IMPORTXLSX, EXCELIN | Places the sheets of an .xlsx workbook as table entities. | Insert ▸ More |
| `XLSXOUT` | XLSXEXPORT, SCHEDULEXLSX, EXPORTXLSX | Writes the schedules (walls, doors, windows, rooms, slabs, takeoff, areas by level) to an Excel .xlsx workbook. | Insert ▸ More |

## Help

| Command | Aliases | Summary | Where |
|---|---|---|---|
| `ABOUT` |  | About Oanarina Archi Tool: version, license and credits. | Manage ▸ More |
| `APPSELFTEST` | SELFTEST | Runs the app's built-in regression checks (node graph, sheet set, presets, clipboard, ribbon). | Manage ▸ More |
| `COMMANDS` | CMDLIST | Lists every command with its aliases and summary. | Manage ▸ More |
| `COMMANDSEARCH` | CMDSEARCH, SEARCHCOMMANDS | Opens the command search palette (Ctrl+K). | Manage ▸ More |
| `DOCSITE` | DOCUMENTATIONSITE, HELPSITE, MANUALHTML | Writes the documentation (user guide, scripting, agent API, command reference) as an offline HTML site with search. | Tools ▸ Studies, Signatures & Publishing |
| `EXPORTCOMMANDS` | COMMANDREFEXPORT, CMDEXPORT | Exports the command reference (every registered command: name, aliases, category, summary, where it is in the UI) as Markdown or CSV. | Manage ▸ More |
| `HELP` | ?, F1 | Lists commands by category, or describes one command. | Manage ▸ More |
| `HELPWINDOW` | DOCS, HELPBROWSER, MANUAL | Opens the offline help browser (command pages, tutorials, shortcuts); F1 opens the running command's page. | Tools ▸ Navigation & Sheets |
| `KEYBOARDNAV` | KEYCURSOR, KEYBOARDHELP | Keyboard-only drawing: arrow keys move the crosshair at prompts (Shift ×10, Alt ÷10; Alt+arrows when idle), Enter picks, Tab selects under the crosshair; sets the step. | Tools ▸ Files, Clipboard & Access |
| `SAMPLEHOUSE` | SAMPLE, OPENSAMPLE | Opens the bundled sample house project in a new window. | Tools ▸ Navigation & Sheets |
| `SPEAKDRAWING` | DESCRIBEDRAWING, VOICEOVERSUMMARY, A11YSUMMARY | Describes the drawing, the selection and the current prompt (spoken by Narrator / Windows speech, printed on the command line). | Tools ▸ Files, Clipboard & Access |
| `TUTORIALS` | TUTORIAL, LEARN | Opens the step-by-step tutorials and the sample project in the help browser. | Tools ▸ Navigation & Sheets |
| `WHATSNEW` | RELEASENOTES | Shows what is new in this version (also shown once after an update). | Tools ▸ Families, Views & Panels |

## Inquiry

| Command | Aliases | Summary | Where |
|---|---|---|---|
| `ANGLEBETWEEN` | ANGBETWEEN, LINEANGLE | Angle between two lines (or vertex + two points). | Analyze ▸ Measure |
| `AREA` | AA | Calculates area and perimeter of points or objects (with Add/Subtract). | Analyze |
| `CAL` | QUICKCALC, QC | Evaluates an arithmetic expression (+ - * / ^, sqrt, sin, cos, pi…). | Analyze ▸ Building Physics |
| `COUNT` |  | Counts objects by type, block and element type (selection or whole drawing). | Analyze |
| `DIST` | DI | Measures the distance and angle between two points. | Analyze |
| `DISTTOOBJECT` | DISTOBJ, DISTTOENTITY | Shortest distance from a point to an object. | Analyze ▸ Measure |
| `ID` |  | Displays the coordinates of a location. | Analyze |
| `INSPECT` | OBJECTINFO, LISTPANEL | Opens the Inspector panel: every stored value of the selected objects, with ID and GUID. | Tools ▸ Navigation & Sheets |
| `LIST` | LI, LS | Lists the properties of selected objects. | Analyze |
| `MASSPROP` |  | Reports area, perimeter, centroid, bounding box and volume of objects. | Analyze |
| `MEASURE3D` | 3DMEASURE, DIST3D | Measures in the 3D view: click two points on the model for distance and ΔX/ΔY/ΔZ. | Analyze ▸ 3D Measure |
| `MEASUREGEOM` | MEA | Measures distance, radius, angle, area or volume. | Analyze ▸ Building Physics |
| `NOTIFICATIONS` | WARNINGS, NOTIFYCENTER | Notifications centre: model warnings (overlaps, unhosted openings, family errors, missing blocks) — click one to zoom to it. | Tools ▸ Families, Views & Panels |
| `POINTINSIDE` | INSIDECHECK, PTINSIDE | Tells whether a point is inside, outside or on a closed contour (polyline, circle, ellipse, hatch, room, slab). | Analyze ▸ Measure |
| `SELECTIONINFO` | SELINFO, SELECTIONPANEL | Selection info panel: count and types of the selected objects, layers, total length/area, keep-only/remove filters. | Tools ▸ Families, Views & Panels |
| `STATUS` |  | Displays drawing statistics, modes and extents. | Analyze ▸ Building Physics |
| `TIME` | EDITTIME, DRAWINGTIME | Shows the drawing's creation and last-update dates, total editing time (idle gaps over 5 minutes excluded) and the user elapsed timer; ON/OFF/Reset control the timer. | Tools ▸ Analysis & Generative |
| `TLEN` | TOTALLENGTH, TOTLEN | Total length of the selected lines, arcs, circles, polylines, splines and ellipses (and wall lengths). | Analyze ▸ Measure |

## Insert

| Command | Aliases | Summary | Where |
|---|---|---|---|
| `ADCENTER` | DESIGNCENTER, ADC | Design Center: browses another drawing's blocks, layers, linetypes, styles and materials and adds them here. | Tools ▸ Navigation & Sheets |
| `DGNIMPORT` | DGNIN, IMPORTDGN | Imports a MicroStation V7 .dgn file (lines, line strings, shapes, curves, circles, ellipses, arcs, text; levels become layers). | Tools ▸ Import, Export & Collaboration |
| `DROPIMPORT` | IMPORTDROPPED, PASTEFILE | Imports files as if dropped on the canvas: images and PDFs are attached, vector/3D exchange formats merged, side by side from a point. | Tools ▸ File Tools & Exchange |
| `DWFIMPORT` | DWFXIMPORT, IMPORTDWF | Imports the sheets of a DWFx file (XPS paths, colours, line weights and text; one sheet after the other) as drawing objects. | Tools ▸ Import, Export & Collaboration |
| `IMAGEIMPORT` | IMPORTIMAGE, RASTERIMPORT, GEOIMAGE | Inserts a PNG/JPEG/GIF/BMP/TIFF/WebP image at its pixel aspect ratio; with a world file (.pgw/.jgw/.tfw/.wld) it is georeferenced (world units WORLDUNITMM, local origin GEOORIGIN). | Insert ▸ Images & Geo |
| `PCPLANE` | POINTCLOUDSNAP, SCANPLANE, PCSNAP | Snaps to the scan point nearest a picked location and fits the plane through its neighbours: reports the point, normal, slope and fit error; a vertical plane is drawn as a line along its trace in plan. | Tools ▸ Import, Export & Collaboration |
| `PDFATTACH` | ATTACHPDF, PDFUNDERLAY | Attaches a PDF page as an underlay (by reference, faded and locked, with object snaps on its geometry) at a drawing scale and insertion point. | Tools ▸ File Tools & Exchange |
| `PDFIMPORT` | IMPORTPDF, PDFIN | Imports the vectors and text of a PDF page as drawing objects: paths with their colours and line widths, fills as solid hatches, text (ToUnicode aware), PDF layers (optional content) as layers; at a drawing scale and insertion point. | Tools ▸ Import, Export & Collaboration |
| `PDFUNDERLAYS` | PDFRELOAD, PDFDETACH, PDFADJUST | Manages PDF underlays: List, Reload (re-read changed PDFs), Detach, Fade (0–90 %). | Tools ▸ File Tools & Exchange |
| `POINTCLOUDVIEW` | PCVIEW, POINTCLOUDCLIP, PCCLIP | Point cloud display: Clip to a section box (min/max corners with Z range), Density (octree level of detail: keep at most N points shown, evenly over the cloud), Reset (show all). Hidden points move to layer POINTCLOUD-HIDDEN. | Tools ▸ Import, Export & Collaboration |
| `SURVEYLINES` | FIELDTOFINISH, SURVEYLINEWORK | Survey field-to-finish: joins survey points into polylines by their codes (EP1 B … EP1 E, C to close) and moves points to the feature layers of the description keys (variable SURVEYCODES: EP=V-ROAD-EDGE:line; TREE=V-TREE:point). | Tools ▸ Studies, Signatures & Publishing |

## Layers

| Command | Aliases | Summary | Where |
|---|---|---|---|
| `LAYDESC` | LAYERDESCRIPTION, LAYERDESC | Sets or lists layer descriptions. | Tools ▸ Annotation & Data |
| `LAYERFILTER` | LFILTER | Filters the Layers panel (A-*, ~*TEXT*, #on #used); Save/Delete/List named filters kept in the drawing. | Home ▸ More |
| `LAYERNOTIFY` | LAYEREVAL | Notifies when unreconciled new layers appear (On/Off) or lists them. | Tools ▸ Block & Reference Editing |
| `LAYERSTATE` | LAS, LMAN, -LAYERSTATE | Layer states: Dialog, or ?/Save/Restore/Delete/Import/Export/Rename on the command line (saved in the drawing). | Home ▸ Layers |
| `LAYRECONCILE` | RECONCILELAYERS | Marks unreconciled layers as reconciled (all, or the named ones). | Tools ▸ Block & Reference Editing |

## Layout

| Command | Aliases | Summary | Where |
|---|---|---|---|
| `VIEWTITLE` | VIEWTITLES, VPTITLE | Adds or refreshes view titles (number bubble, name, scale) under every viewport of a sheet. | Output ▸ Sheets |

## MEP

| Command | Aliases | Summary | Where |
|---|---|---|---|
| `CABLETRAY` | TRAYRUN | Draws cable trays (open U-channel with rungs in plan) along points. | Architecture ▸ More |
| `CIRCUIT` | CIRCUITS, ELCIRCUIT | Electrical circuits: Create (devices on a panel circuit with description and breaker), Remove devices, Show wiring home runs, List circuits. | Tools ▸ BIM Graphics & Systems |
| `CONDUIT` | CONDUITRUN | Draws electrical conduit along points with elbows. | Architecture ▸ More |
| `DUCT` | DUCTRUN, DUCTWORK | Draws rectangular ducts along points with flanged bends. | Architecture ▸ More |
| `LIGHTDATA` | PHOTOMETRY, LUMINAIRE, LIGHTFIXTURE | Sets photometric data of light fixtures (lumens, watts, colour temperature, beam angle) used by schedules and rendering. | Architecture ▸ More |
| `LIGHTSCHEDULE` | FIXTURESCHEDULE, LIGHTINGSCHEDULE, LUX | Lighting fixture schedule (mark, type, level, room, position, rotation, lm, W, K) and average illuminance per room. | Analyze ▸ Checks |
| `MEPCONNECTORS` | CONNECTORS, FIXTURECONNECTORS | Lists plumbing/electrical connection points of fixtures and shows or hides them in plan. | Architecture ▸ More |
| `MEPPIPE` | PIPERUN, PIPING | Draws pipes along points with elbow fittings at bends; can start at a plumbing fixture connector, slope and rise. | Architecture ▸ More |
| `MEPSYSTEM` | SYSTEMS, MEPSYSTEMS, SYSTEMBROWSER | Connector-based systems: list connected networks, assign a system to a whole network, show only some systems, or check open ends. | Architecture ▸ More |
| `PANELSCHEDULE` | PANELSCHED | Panel schedule of an electrical panel (circuits, loads, breakers, phase balance): List, Place as a table or Export CSV. | Tools ▸ BIM Graphics & Systems |

## Manage

| Command | Aliases | Summary | Where |
|---|---|---|---|
| `BSDD` | BSDDLOOKUP, DATADICTIONARY | buildingSMART Data Dictionary: Search classes online (or Load a saved bSDD JSON), Assign a class and its properties to elements, add a view Filter on a class, List assigned classes. | Tools ▸ Adaptive, Corners & Roofs |
| `CLASSIFY` | CLASSIFICATION, CLASSCODE | Classification codes: Auto-classify by element kind (Uniformat II, NL-SfB), Set a code in any system (Uniclass 2015, OmniClass…), List, Clear. | Tools ▸ BIM Grids, Zones & Data |
| `DESIGNOPTION` | DESIGNOPTIONS, DOPT | Design options: new set/option, add selection to an option, edit (new elements join it), view, primary, accept primary, list. | Architecture ▸ More |
| `EXPRESSION` | EXPR, PROPEXPR, SETEXPR | Binds a property of selected objects to an expression over their own properties, other objects (id12.height, Name.length) and global parameters; Clear removes it; List shows them. | Tools ▸ BIM Types & Parameters |
| `FAMILYLOCK` | FAMLOCK, FAMILYEQ, PARAMLOCK | Family constraints: Lock a reference plane to a parameter (dimension label), EQ planes equally spaced, Plane (add a reference plane). | Tools ▸ BIM Types & Parameters |
| `GEOLOCATION` | GEOLOC, LOCATION, SITELOCATION | Project geolocation: City preset, or Set latitude, longitude, site elevation, time zone and true north (used by sun studies, energy and exports); List shows it. | Tools ▸ BIM Grids, Zones & Data |
| `GLOBALPARAM` | GLOBALPARAMS, GLOBALPARAMETERS, PROJECTPARAM | Global parameters: New/Set a value or =formula, Bind element dimensions (wall height, thickness, opening width…) to an expression, Unbind, List, Delete; bound elements and family formulas update when a value changes. | Tools ▸ BIM Grids, Zones & Data |
| `OBJECTSTYLES` | OBJSTYLES, OBJECTSTYLE, CATEGORYSTYLES | Object styles: project-wide projection/cut line weights, line colour, cut fill and cut pattern per BIM category (wall, door, window, slab, column…); every plan and section follows. List, Reset, or set e.g. "cut:0.7;proj:0.35;color:red;fill:0.3,0.3,0.3;pattern:ANSI31". | Tools ▸ Styles, Patterns & Occlusion |
| `OBJECTSTYLESDIALOG` | OBJECTSTYLESDLG, OSTYLESDIALOG | Object Styles dialog: projection/cut line weights, line colour, cut fill and cut pattern per BIM category for every plan and section. | Tools ▸ Styles, Patterns & Occlusion |
| `PARAMCELL` | PARAMLINK, SPREADSHEETPARAM, BINDCELL | Drives a global parameter from a spreadsheet cell (a table in the drawing, e.g. Params!B3 or #12!B3); None removes the link. | Tools ▸ BIM Types & Parameters |
| `PLUGINS` | PLUGINMANAGER, APPLOAD | Plugin manager: List plugins (folders with plugin.json + JavaScript), Reload and register their commands, Enable/Disable, Info, New (scaffold a plugin, optionally from a recorded script), Folder. | Script ▸ Automation |
| `PSET` | PSETS, PROPERTYSET, PROPERTYSETS | Property sets (IFC Psets): Set Pset.Property values (typed by templates), Apply a template's defaults, List an element's sets, Remove, Check values, and custom Templates (New/Add/Delete/List). | Tools ▸ BIM Grids, Zones & Data |
| `REPORTPARAM` | REPORTINGPARAM, REPORTINGPARAMETER | Makes a family parameter a reporting parameter measured from the model (host.thickness, host.height, host.length, level.elevation, level.height, self.rotation…). | Tools ▸ BIM Types & Parameters |
| `SCRIPT2JS` | SCRTOJS, RECORDTOJS | Converts a command script (.scr, or the running SCRIPTRECORD recording) into JavaScript calling archi.run() per command. | Script ▸ Automation |
| `TRANSFERSTANDARDS` | TRANSFERPROJECTSTANDARDS, COPYSTANDARDS, TPS | Copies types, styles and settings (wall/slab/opening/stair/railing types, materials, layers, linetypes, text and dimension styles, view templates, families, parameters, schedules, keynotes) from another .archi file. | Tools ▸ BIM Types & Parameters |
| `TYPEIMAGE` | SCHEDULEIMAGE, TYPEPICTURE | Assigns an image file to a type (wall/opening/family type); schedules with an Image field show it in placed tables. | Tools ▸ BIM Types & Parameters |
| `WORKSET` | WORKSETS | Worksets (named element sets): list, new, current, assign selection, hide/show, select members. | Architecture ▸ More |

## Modify

| Command | Aliases | Summary | Where |
|---|---|---|---|
| `ALIGN` | AL | Aligns objects with other objects using source/destination point pairs. | Home ▸ More |
| `ALIGNREF` | ALIGNTO, ROTATETOREF | Rotates objects about a base point so a reference direction (line or two points) aligns with a target line or angle. | Home ▸ More |
| `ARRAY` | AR | Creates copies of objects in a rectangular, polar or path pattern. | Modify |
| `ARRAYCLASSIC` | -ARRAYCLASSIC, ARRAYNONASSOC | Creates a non-associative (separate copies) rectangular, polar or path array. | Tools ▸ Arrays, Macros & Monitor |
| `ARRAYEDIT` | ARRAYED | Edits an associative array: rows, columns, spacing, items, fill angle, rotation, alignment. | Tools ▸ Arrays, Macros & Monitor |
| `ARRAYPATH` |  | Array of objects evenly spaced along a path. | Home ▸ More |
| `ARRAYPOLAR` |  | Polar array of objects around a center point. | Home ▸ More |
| `ARRAYRECT` |  | Rectangular array of objects in rows and columns. | Modify |
| `BREAK` | BR | Breaks an object between two points. | Modify |
| `BREAKALL` | BREAKATINTERSECTIONS, DIVIDEATINTERSECTIONS | Breaks the selected objects at every intersection with each other. | Home ▸ More |
| `BREAKATPOINT` | BRP | Breaks an object into two at a single point. | Home ▸ More |
| `CHAMFER` | CHA | Bevels the corner between two lines (distance or length/angle method). | Modify |
| `CHPROP` | CHANGE, CH, -CH | Changes color, layer, linetype, lineweight or material of objects. | Home ▸ More |
| `CHSPACE` | CHANGESPACE | Moves objects between model space and a layout's paper space through a viewport, keeping their size on the sheet. | Home ▸ More |
| `CLIPPOLY` | CLIPWITHPOLYGON, CLIPBOUNDARY | Clips the selected curves with a closed boundary, keeping the parts Inside or Outside. | Home ▸ More |
| `CONVERTTOPLINE` | TOPLINE, SPLINETOPLINE, CONVTOPL | Converts lines, arcs, circles, ellipses and splines to polylines (curves sampled within a tolerance). | Home ▸ More |
| `COPY` | CO, CP | Copies objects (multiple copies, or a linear array). | Modify |
| `CUTBYLINE` | SLICELINE, DIVIDEBYLINE | Divides the selected objects where a cutting line crosses them. | Home ▸ More |
| `DIVIDE` | DIV | Places points or blocks at equal intervals along an object. | Home ▸ More |
| `DRAWORDER` | DR | Changes the draw order of objects (front, back, above, under). | Home ▸ More |
| `ERASE` | E, DELETE | Removes objects from the drawing. | Modify |
| `EXPLODE` | X | Breaks compound objects (polylines, blocks, hatches, dimensions) into their parts. | Modify |
| `EXTEND` | EX | Extends objects to meet boundary edges (all objects by default). | Modify |
| `EXTENDBY` | TRIMBY, LENGTHENBY | Extends (positive) or trims (negative) curves by an amount at the picked end: lines, arcs, polylines, ellipses, splines. | Home ▸ More |
| `FILLET` | F | Rounds the corner between two objects (radius 0 = sharp corner). | Modify |
| `FLATTEN` |  | Converts objects to flat 2D geometry at elevation 0 (3D solids become their plan outlines). | Home ▸ More |
| `HATCHEDIT` | HE, -HATCHEDIT | Edits hatches: Properties (pattern, scale, angle), Color/background, Associate, DIsassociate, ADd/Remove boundaries, recreate Boundary, separate Hatches. | Home ▸ More |
| `HATCHGENERATEBOUNDARY` | HGB | Creates closed polylines around selected hatches and makes the hatches associative to them. | Home ▸ More |
| `HATCHSETORIGIN` | HATCHORIGIN | Sets the pattern origin of hatches: a point, a corner or the centre of the hatch extents, or the default (0,0). | Home ▸ More |
| `HATCHTOBACK` |  | Sends all hatches behind other objects. | Home ▸ More |
| `IMAGESCALE` | SCALEIMAGE, IMAGECALIBRATE, CALIBRATE | Calibrates an image: pick two points on it and enter their real distance; the image is scaled about the first point. | Insert ▸ Images & Geo |
| `JOIN` | J | Joins lines, arcs and polylines at their end points. | Modify |
| `LENGTHEN` | LEN | Changes the length of lines, arcs and open polylines (Delta/Percent/Total). | Home ▸ More |
| `LINEGAP` | GAPS, CROSSINGGAP | Cuts gaps in the selected objects where other objects cross them (crossing display). | Home ▸ More |
| `MATCHPROP` | MA, PAINTER | Applies the properties of a source object to other objects. | Home ▸ Selection |
| `MEASURE` | ME | Places points or blocks at measured intervals along an object. | Home ▸ More |
| `MIRROR` | MI | Creates a mirrored copy of objects. | Modify |
| `MOVE` | M | Moves objects a specified distance in a specified direction. | Modify |
| `MOVEROTATE` | MOVROT, MR | Moves objects from a base point to a destination, then rotates them about it. | Home ▸ More |
| `NUDGE` |  | Moves the selection by small steps: Left/Right/Up/Down (× count), or a vector dx,dy (arrow-key nudging). | Home ▸ More |
| `OFFSET` | O | Creates parallel copies of lines, arcs, circles and polylines. | Modify |
| `OFFSETMULTI` | EQUIDISTANT, OFFSETM | Creates several equidistant offset copies of an object on one side. | Home ▸ More |
| `OOPS` |  | Restores the objects removed by the last ERASE. | Home ▸ More |
| `OVERKILL` | -OVERKILL | Removes duplicate objects and merges overlapping collinear lines. | Home ▸ More |
| `PEDIT` | PE | Edits polylines: close/open, join, width, spline, decurve, reverse. | Home ▸ More |
| `PLINETOSPLINE` | TOSPLINE, CONVTOSPLINE | Converts polylines (and lines) to splines fitted through their vertices. | Home ▸ More |
| `REGIONINTERSECT` | INTERSECT2D, PINTERSECT | Keeps the common area of closed 2D regions (as closed polylines). | Home ▸ More |
| `REGIONSUBTRACT` | SUBTRACT2D, PSUBTRACT | Subtracts closed 2D regions from others (result as closed polylines; holes become separate polylines). | Home ▸ More |
| `REGIONUNION` | UNION2D, PUNION | Unites closed 2D regions (closed polylines, circles, ellipses, hatches) into closed polylines. | Home ▸ More |
| `REVERSE` |  | Reverses the vertex order of lines, polylines, splines and arcs. | Home ▸ More |
| `ROTATE` | RO | Rotates objects around a base point. | Modify |
| `ROTATE2` | ROTATETWICE, RO2 | Rotates objects about a first centre, then about a second centre. | Home ▸ More |
| `ROTATE90` | R90, ROT90 | Rotates the selection 90° counter-clockwise (or [Clockwise]) about its centre or a base point. | Home ▸ More |
| `SCALE` | SC | Enlarges or reduces objects around a base point. | Modify |
| `SELECT` |  | Selects objects and keeps them as the current selection. | Home ▸ More |
| `SELECTALL` | AI_SELALL | Selects all selectable objects on unlocked layers (current level). | Home ▸ More |
| `SETBYLAYER` | SBL | Sets color, linetype and lineweight of objects (and block contents) to ByLayer. | Home ▸ More |
| `SPLINEDIT` | SPE | Edits splines: Close/Open, Fit data (Add/Delete/Move), control vertices, Convert to CV form or Polyline, Reverse, Undo. | Home ▸ More |
| `STRETCH` | S | Stretches objects crossed by a window; objects fully inside are moved. | Modify |
| `TEXTTOFRONT` |  | Brings text, dimensions and/or leaders in front of other objects (options: Text/Dimensions/Leaders/All). | Home ▸ More |
| `TRIM` | TR | Trims objects at cutting edges (all objects are cutting edges by default). | Modify |
| `TXTEXP` | TEXTEXPLODE, EXPLODETEXT | Explodes text into line geometry drawn with the built-in stroke font (or [Letters]: single-letter text objects). | Home ▸ More |
| `WELD` | MERGECURVES | Merges curves touching end to end (lines, arcs, polylines, splines, ellipse arcs) into polylines. | Home ▸ More |

## Output

| Command | Aliases | Summary | Where |
|---|---|---|---|
| `BATCHPUBLISH` | PUBLISHSET, BATCHPLOTPDF | Publishes chosen sheets to one PDF with bookmarks (sheet number and name) and optional sheet index. | Output ▸ More |
| `EXPORTPDF` | PDFEXPORT, PDFOUT, LAYEREDPDF | Vector PDF with one PDF layer (OCG) per drawing layer, searchable text and hyperlinks: current sheet, model or all sheets, at true scale. | Tools ▸ Navigate, Light & Publish |
| `PAGESETUP` | PSETUP, PAGESETUPMANAGER | Page setup of the active sheet or model: paper, plot style, lineweights, plot stamp, scale. | Output ▸ Plot |
| `PLOTAREA` | PLOTWINDOW | Model-space plot area (Extents/Display/Limits/Window) and fit (Standard scale or Exact) for PLOT, PREVIEW and PDF export. | Tools ▸ Navigation & Sheets |
| `PLOTLOG` | PLOTHISTORY | Shows the plot log (every plot, PDF export and publish with date, sheets and plot style) [List/Open/Clear]. | Output ▸ More |
| `PLOTSTYLE` | CTB, PLOTSTYLES, STYLESMANAGER | Plot style tables (colour → pen colour, lineweight, screening): Edit, Set for the sheet/model, List. | Output ▸ More |
| `PLOTSTYLENAME` | NAMEDPLOTSTYLE, STB | Named plot styles (STB): assign a style to a Layer or to Objects, choose the Table used by the current sheet (or model), or List styles. | Tools ▸ Navigation & Sheets |
| `PREVIEW` | PRE, PRINTPREVIEW, PLOTPREVIEW, PLOTDIALOG | Plot dialog with a live preview: prints or saves exactly what is shown. | Output ▸ Plot |
| `PRINTSETUP` | PRINTOPTIONS, QUICKPRINT | Prints with printer, paper, tray (input slot), media, scaling (fit, 1:1, percent) and copies. | Output ▸ Plot |
| `PSETUPIN` |  | Imports a page setup (plot style, colour mode, lineweights, stamp, paper) from another drawing into the current sheet or all sheets. | Tools ▸ Navigation & Sheets |
| `PUBLISH` | BATCHPLOT, EXPORTSHEETS, PUBLISHPDF | Publishes all sheets to one multi-page PDF (PUBLISH path.pdf, or Enter for a dialog). | Output ▸ Plot |
| `RENDERSAVE` | RENDERPNG, RSAVE | Renders offscreen to a PNG without the render window: RENDERSAVE <preset> <camera/Current> <width> <height> <path> (4× MSAA + supersampling, vertical correction for eye-level cameras). | Tools ▸ Photographic Render |
| `REVCLOUDPANEL` | SHEETCLOUDS | Sheet revision clouds: add a cloud with a revision triangle around a viewport or an area of a sheet, list, open, delete. | Collaborate ▸ Sheets |
| `SHADEPLOT` | VPSHADEPLOT, VIEWPORTSHADE | Shade plot of a 3D (axonometric / perspective) sheet viewport: As Displayed, Wireframe, Hidden or Rendered, and the saved 3D view it shows. | Tools ▸ Navigate, Light & Publish |
| `SHEETFIELD` | PROJECTFIELD, CUSTOMFIELD | Custom title block fields: Project fields appear on every sheet, Sheet fields override them on one sheet. | Tools ▸ Navigation & Sheets |
| `SHEETGRID` | LAYOUTGRID, GUIDEGRID | Guide grid on the current sheet (spacing in paper mm, 0 = off); viewports snap to it when moved. | Tools ▸ Navigation & Sheets |
| `SHEETIMAGE` | LAYOUTIMAGE, SHEETPNG | Exports a sheet (layout) or the Model view of the current level as a PNG, JPEG or TIFF image at a chosen resolution (dpi). | Tools ▸ Families, Views & Panels |
| `SHEETINDEX` | SHEETLIST, DRAWINGLIST | Places or refreshes the sheet list table (number, title, paper, revision) on the active sheet. | Output ▸ Sheets |
| `SHEETPLACEHOLDER` | PLACEHOLDERSHEET | Adds a placeholder sheet (listed in the sheet set and index, never plotted) or toggles the current one. | Tools ▸ Navigation & Sheets |
| `SHEETRENUMBER` | RENUMBERSHEETS | Numbers all sheets in order with a prefix and start number (e.g. A- 101). | Output ▸ More |
| `SHEETREVISION` | REVISION, REVTABLE, ADDREVISION | Adds a revision (next code, date, description, by) to the active sheet's revision table. | Output ▸ More |
| `SHEETSET` | SSM, SHEETSETMANAGER, SHEETS | Sheet set manager: numbering, order, duplicate, revisions, sheet index. | Output ▸ More |
| `SHEETSVG` | LAYOUTSVG, EXPORTSHEETSVG | Exports the current sheet (or All sheets) as true-size vector SVG with one layer per drawing layer. | Tools ▸ Navigation & Sheets |
| `SHEETVIEWTITLES` | VPTITLES, EDITABLEVIEWTITLES | Editable view titles (number bubble, title, scale) under every viewport of the active sheet; keeps edited titles. | Output ▸ More |
| `TITLEBLOCK` | TBEDIT, TITLEBLOCKEDIT | Edits the active sheet's title block and the project information shown on all sheets. | Output ▸ Sheets |
| `TITLEBLOCKDESIGN` | TBDESIGN, CUSTOMTITLEBLOCK, TITLEBLOCKBLOCK | Custom title blocks: Create a starter block (edit it with BEDIT: lines, logo images, {field} texts or attributes), Use a block on all or the current sheet, or go back to the Builtin one. | Tools ▸ Navigate, Light & Publish |
| `VPLOCK` | VPORTLOCK, LOCKVIEWPORT | Locks or unlocks sheet viewports so their scale and position cannot change. | Output ▸ More |
| `WEBVIEWEREXPORT` | WEBEXPORT, EXPORTWEB, WEBVIEWER | Exports the 3D model as one standalone HTML file with a WebGL viewer (orbit, pan, zoom, views) that opens in any browser. | Tools ▸ Navigate, Light & Publish |

## Parametric

| Command | Aliases | Summary | Where |
|---|---|---|---|
| `AUTOCONSTRAIN` | AUTOC | Infers and applies constraints (coincident, tangent, horizontal, vertical, parallel, perpendicular) to the selected objects within tolerances. | Annotate ▸ Parametric |
| `CONSTRAINTBAR` | CBAR, CONSTRAINTGLYPHS, SHOWCONSTRAINTS | Shows or hides constraint glyphs next to constrained objects in the plan [Show/Hide/Toggle] (CONSTRAINTBAR variable). | Annotate ▸ Parametric |
| `CONSTRAINTLIST` | LISTCONSTRAINTS | Lists the constraints (of the selected objects, or all) with their values and the remaining degrees of freedom. | Annotate ▸ Parametric |
| `DCALIGNED` |  | Applies the aligned dimensional constraint. | Annotate ▸ Parametric |
| `DCANGULAR` |  | Applies the angular dimensional constraint. | Annotate ▸ Parametric |
| `DCCONVERT` |  | Converts dimensions into dimensional constraints. | Annotate ▸ Parametric |
| `DCDIAMETER` |  | Applies the diameter dimensional constraint. | Annotate ▸ Parametric |
| `DCDIFFERENCE` |  | Applies the difference dimensional constraint. | Annotate ▸ Parametric |
| `DCHORIZONTAL` |  | Applies the horizontal dimensional constraint. | Annotate ▸ Parametric |
| `DCLINEAR` |  | Applies the linear dimensional constraint. | Annotate ▸ Parametric |
| `DCRADIUS` |  | Applies the radius dimensional constraint. | Annotate ▸ Parametric |
| `DCRATIO` |  | Applies the ratio dimensional constraint. | Annotate ▸ Parametric |
| `DCVERTICAL` |  | Applies the vertical dimensional constraint. | Annotate ▸ Parametric |
| `DELCONSTRAINT` | DELCON | Removes all geometric and dimensional constraints from the selected objects (or All). | Annotate ▸ Parametric |
| `DIMCONSTRAINT` | DCON | Applies a dimensional (driving) constraint: LInear/Horizontal/Vertical/Aligned distance, ANgular, Radius, Diameter, or Convert dimensions; values may be expressions of parameters. | Annotate ▸ Parametric |
| `GCCOINCIDENT` |  | Applies the coincident geometric constraint. | Annotate ▸ Parametric |
| `GCCOLLINEAR` |  | Applies the collinear geometric constraint. | Annotate ▸ Parametric |
| `GCCONCENTRIC` |  | Applies the concentric geometric constraint. | Annotate ▸ Parametric |
| `GCEQUAL` |  | Applies the equal geometric constraint. | Annotate ▸ Parametric |
| `GCFIX` |  | Applies the fixed geometric constraint. | Annotate ▸ Parametric |
| `GCHORIZONTAL` |  | Applies the horizontal geometric constraint. | Annotate ▸ Parametric |
| `GCMIDPOINT` |  | Applies the midpoint geometric constraint. | Annotate ▸ Parametric |
| `GCPARALLEL` | GCPAR | Applies the parallel geometric constraint. | Annotate ▸ Parametric |
| `GCPERPENDICULAR` | GCPERP | Applies the perpendicular geometric constraint. | Annotate ▸ Parametric |
| `GCPOINTONCURVE` | GCONCURVE | Applies the pointOnCurve geometric constraint. | Annotate ▸ Parametric |
| `GCSYMMETRIC` |  | Applies the symmetric geometric constraint. | Annotate ▸ Parametric |
| `GCTANGENT` |  | Applies the tangent geometric constraint. | Annotate ▸ Parametric |
| `GCVERTICAL` |  | Applies the vertical geometric constraint. | Annotate ▸ Parametric |
| `GEOMCONSTRAINT` | GCON, GC | Applies a geometric constraint: Horizontal, Vertical, Perpendicular, PArallel, Tangent, COincident, CONcentric, COLlinear, Symmetric, Equal, Fix, Midpoint, OnCurve. | Annotate ▸ Parametric |
| `MECHANISM` | LINKAGE, ANIMATEDIM, DRIVEDIM | Mechanism simulation: steps a named driving dimension (angles in degrees) through a range, re-solving the constraints each step; draws the path of a traced point, optional ghost poses, reports lock-up and the range of other dimensions. | Tools ▸ Adaptive, Corners & Roofs |
| `MECHANISMPLAY` | ANIMATEMECHANISM, PLAYMECHANISM, MECHANISMANIMATE | Animates a mechanism on the plan: steps a named driving dimension through a range (re-solving the constraints) and plays the poses Once, in a Loop or Bounce; Stop ends it. The drawing is not changed. | Tools ▸ Files, Clipboard & Access |
| `PARAMETERS` | PARAM, PARAMETERSMANAGER, PARAMS | Parameters manager: New/Edit/Delete/List user parameters and dimensional constraint expressions; geometry updates. | Annotate ▸ Parametric |
| `SKETCHPLANE` | SKETCHER, NEWSKETCH, SKETCHON, SKETCH3D | Sketch environment: New sketch on a work plane (XY at an elevation, a solid Face, or vertical through a Line), Add objects drawn in sketch coordinates, Status (degrees of freedom — constrain with the geometric/dimensional constraints), List, Delete. | Tools ▸ Adaptive, Corners & Roofs |

## Properties

| Command | Aliases | Summary | Where |
|---|---|---|---|
| `COLORBOOK` | COLOURBOOK, COLORBOOKS | Colour books (open palettes): list books and colours, apply a colour to objects or set it current (Book$Colour). | Tools ▸ Annotation & Data |

## Scripting

| Command | Aliases | Summary | Where |
|---|---|---|---|
| `AGENTSETTINGS` | AGENTS, AGENTSERVER | Agent server settings: port, start/stop, token, auto-start. | Manage ▸ More |
| `ASK` | NLCOMMAND, SAY, NATURAL | Natural-language request, e.g. "draw a 4 m wall north of grid A", "add a door 900 wide in the middle of the last wall", "move the selection 2 m east": shows what was understood and asks before applying (one undo step). | Tools ▸ Analysis & Design Assist |
| `ASSISTANT` | AI, AICHAT, CHAT, ASKAI | AI assistant panel: Claude or a local model (Ollama) edits the drawing with commands; bulk changes ask for confirmation; everything is undoable. | Tools ▸ Navigate, Light & Publish |
| `CONNECTCLAUDE` | MCPHELP, CLAUDE | Explains how to connect Claude (archi-engine --mcp or the local agent server). | Manage ▸ More |
| `GRAPHPLAYER` | PLAYER, RUNGRAPH, PLAYGRAPH | Graph player: runs a saved node graph with its exposed Number inputs (clamped to their ranges) and bakes the result; Window opens the player panel. | Tools ▸ Navigate, Light & Publish |
| `LISP` | LISPEVAL, EVALLISP | Evaluates an AutoLISP expression, e.g. LISP "(command \"CIRCLE\" '(0 0) 500)"; the result is printed. | Tools ▸ Analysis & Design Assist |
| `LISPLOAD` | LOADLISP, LSPLOAD | Loads an AutoLISP (.lsp) file: its (defun c:NAME …) functions become commands; runs after this command, each (command …) its own undo step. | Tools ▸ Analysis & Design Assist |
| `NODEEDITOR` | NODES, VISUALSCRIPT, GRAPH | Visual node editor (number, point, line, circle, extrude, array…) with live preview; bakes geometry into the drawing. | Model |
| `SCRIPTCONSOLE` | JS, JSCONSOLE, CONSOLE | Shows or hides the JavaScript console (Ctrl+Alt+J). | Manage ▸ More |
| `SCRIPTLIBRARY` | SCRIPTS | Opens the script library folder (startup.js runs in every new window). | Manage ▸ More |

## Select

| Command | Aliases | Summary | Where |
|---|---|---|---|
| `DESELECT` | SELECTNONE, DESELECTALL | Clears the selection (keeps it as the previous selection). | Home ▸ More |
| `FILTER` | FI, SELECTFILTER | Selects objects matching a filter expression (type=circle & radius>50 / layer=A-*); filters can be saved by name. | Home ▸ Selection |
| `HIDEOBJECTS` | HIDEOBJ | Temporarily hides the selected objects (kept with the drawing until UNISOLATEOBJECTS). | Home ▸ Groups |
| `ISOLATEOBJECTS` | ISOLATEOBJ, ISOLATE | Temporarily hides every object except the selected ones (on the current level for building elements). | Home ▸ Groups |
| `QSELECT` | QSEL | Quick select: objects of a type whose property matches a value (e.g. QSELECT Circle radius > 50). | Home ▸ Selection |
| `QSELECTDIALOG` | QSD, QUICKSELECT | Quick Select dialog: type, property, operator and value with a live match count. | Home ▸ Selection |
| `SELECTCHAIN` | SELCHAIN, SELECTCONTOUR | Selects the chain (contour) of curves connected end-to-end with the picked one. | Home ▸ Selection |
| `SELECTINSTANCES` | SELINST, SELECTALLINSTANCES | Selects every instance of the same block, opening type, wall type or element type as the picked object. | Home ▸ More |
| `SELECTINTERSECTING` | SELINT | Selects every object that intersects the picked one. | Home ▸ Selection |
| `SELECTINVERT` | INVSEL, SELINV | Inverts the selection (selects every other selectable object). | Home ▸ Selection |
| `SELECTLAYER` | SELLAYER, LAYSEL | Selects every object on the given layer(s) (wildcards allowed) or on the layer of a picked object. | Home ▸ Selection |
| `SELECTPREVIOUS` | SELPREV, PSELECT | Selects the previous selection set again (only objects still selectable). | Home ▸ More |
| `SELECTSIMILAR` | SELSIM | Selects all objects similar to the selected ones (type, plus the properties in SELECTSIMILARMODE). | Home ▸ Selection |
| `SELECTTYPE` | SELTYPE | Selects objects by type or category (Line, Circle, Text, Annotation, Curve, Wall, Door, Element…); several types separated by commas. | Home ▸ Selection |
| `SELECTWALLCHAIN` | WALLCHAIN | Selects the chain of walls joined to a picked wall (Tab over a wall does the same). | Tools ▸ Navigation & Sheets |
| `SELSET` | NAMEDSELECTION | Saves, restores, lists and deletes named selection sets (stored in the drawing). | Home ▸ Selection |
| `UNISOLATEOBJECTS` | UNISOLATE, UNHIDE, ENDISOLATION | Shows all objects hidden by HIDEOBJECTS or ISOLATEOBJECTS. | Home ▸ Groups |

## Settings

| Command | Aliases | Summary | Where |
|---|---|---|---|
| `3DOSNAP` | -3DOSNAP, 3DOSMODE | Sets 3D object snap modes on solids: ZVertex, ZMidpoint, ZCenter (face), ZKnot, ZPerpendicular, ZNearest, ALL, NONE. | Tools ▸ Feature Modelling |
| `AUDIT` |  | Checks the drawing for errors (duplicate IDs, dangling openings, missing layers/blocks) and fixes them. | Manage ▸ Cleanup |
| `AUTOCONSTRAINANGLE` |  | System variable AUTOCONSTRAINANGLE. | Manage ▸ More |
| `AUTOCONSTRAINDIST` |  | System variable AUTOCONSTRAINDIST. | Manage ▸ More |
| `AUTOSNAP` |  | System variable AUTOSNAP. | Manage ▸ More |
| `AXISLOCK` | LOCKAXIS | Locks point input to the UCS X or Y axis, an angle, or turns the lock Off (arrow keys while drawing). | Tools ▸ Views & Coordinates |
| `CANNOSCALE` |  | System variable CANNOSCALE. | Manage ▸ More |
| `CECOLOR` |  | System variable CECOLOR. | Manage ▸ More |
| `CELTYPE` |  | System variable CELTYPE. | Manage ▸ More |
| `CELWEIGHT` |  | System variable CELWEIGHT. | Manage ▸ More |
| `CENTEREXE` |  | System variable CENTEREXE. | Manage ▸ More |
| `CETRANSPARENCY` |  | System variable CETRANSPARENCY. | Manage ▸ More |
| `CHAMFERA` |  | System variable CHAMFERA. | Manage ▸ More |
| `CHAMFERB` |  | System variable CHAMFERB. | Manage ▸ More |
| `CLAYER` |  | System variable CLAYER. | Manage ▸ More |
| `CLEVEL` |  | System variable CLEVEL. | Manage ▸ More |
| `CMDLINEOPTIONS` | CLISETTINGS, COMMANDLINEOPTIONS, CLIFLOAT | Command line appearance: text Size, history Lines shown, background Opacity; Float it over the canvas or Dock it at the bottom. | Tools ▸ Render, Materials & Environment |
| `COLOR` | COL, COLOUR | Sets the color for new objects (CECOLOR). | Home ▸ More |
| `CONSTRAINTINFER` |  | System variable CONSTRAINTINFER. | Manage ▸ More |
| `CRASHREPORTS` | CRASHREPORT, CRASHLOG | Opt-in crash reports: On, Off, Status, Show the saved reports (reviewed and sent only by you), Clear. | Tools ▸ Styles, Patterns & Occlusion |
| `CUI` | CUSTOMIZE, RIBBONCUSTOMIZE, -CUI | Customizes the ribbon: Dialog, Add a panel of commands to a tab, Remove, Hide/Show a built-in panel, List, Export/Import a customisation file, Reset. | Tools ▸ Render, Materials & Environment |
| `CURSORSIZE` |  | Sets the crosshair size as a percentage of the view (1–100). | Manage ▸ More |
| `DBLCLKEDIT` |  | Turns double-click editing of objects on or off; with an object, runs its double-click editor. | Tools ▸ Views & Coordinates |
| `DELOBJ` |  | System variable DELOBJ. | Manage ▸ More |
| `DIMDLI` |  | System variable DIMDLI. | Manage ▸ More |
| `DIMLAYER` |  | System variable DIMLAYER. | Manage ▸ More |
| `DIMSCALE` |  | System variable DIMSCALE. | Manage ▸ More |
| `DSETTINGS` | DS, SE, DDRMODES | Opens the drafting settings (snap, grid, polar, object snap). | Manage ▸ Settings |
| `DUCS` | UCSDETECT, DYNUCS | Turns the dynamic UCS on or off: points picked over a 3D solid land on the face under the cursor. | Tools ▸ Feature Modelling |
| `DYNMODE` |  | System variable DYNMODE. | Manage ▸ More |
| `EXPORTSETTINGS` | SETTINGSOUT | Exports all preferences (theme, shortcuts, toolbar, workspaces, snippets…) to a settings file for another computer. | Tools ▸ Navigation & Sheets |
| `FILLETRAD` |  | System variable FILLETRAD. | Manage ▸ More |
| `GFILTERS` | GRAPHICFILTERS, DRAFTFILTERS | Rule-based graphic overrides for drafting objects: Add/Remove/Enable/Disable/List (field layer/type/color/linetype/lineweight/property). | Tools ▸ BIM Graphics & Systems |
| `GRAPHICSTYLES` | STYLESMANAGER, GSTYLES | Graphic styles manager: line styles and their layers, lineweights by view scale, pen sets and graphic override filters in one dialog. | Tools ▸ Render, Materials & Environment |
| `GRIDDISPLAY` | DGRID, F7 | Shows/hides the drawing grid or sets its spacing. | Manage ▸ More |
| `GRIDMODE` |  | System variable GRIDMODE. | Manage ▸ More |
| `GRIDUNIT` |  | System variable GRIDUNIT. | Manage ▸ More |
| `HPANG` |  | System variable HPANG. | Manage ▸ More |
| `HPNAME` |  | System variable HPNAME. | Manage ▸ More |
| `HPSCALE` |  | System variable HPSCALE. | Manage ▸ More |
| `IMPORTSETTINGS` | SETTINGSIN | Imports preferences exported by EXPORTSETTINGS (restart to apply everything). | Tools ▸ Navigation & Sheets |
| `INSBASE` |  | System variable INSBASE. | Manage ▸ More |
| `INSUNITS` |  | System variable INSUNITS. | Manage ▸ More |
| `ISODRAFT` |  | Isometric drafting: Orthographic (off), isoLeft, isoTop, isoRight — ortho and grid snap follow the isometric axes. | Manage ▸ More |
| `ISOPLANE` |  | Sets the current isometric plane: Left, Top, Right or Toggle to the next. | Manage ▸ More |
| `LANGUAGE` | UILANGUAGE, LIMBA, SPRACHE, LANGUE, IDIOMA, LINGUA | Interface language of the ribbon: Auto (Windows), English, Română, Deutsch, Français, Español, Italiano. Commands stay English. | Tools ▸ Files, Clipboard & Access |
| `LAYCUR` |  | Changes the layer of selected objects to the current layer. | Home ▸ More |
| `LAYDEL` |  | Deletes a layer and all objects on it. | Home ▸ More |
| `LAYER` | LA, -LAYER, -LA | Manages layers: make, set, new, rename, on/off, freeze/thaw, lock/unlock, color, linetype, lineweight, delete. | Home ▸ More |
| `LAYERP` | LAYP | Undoes the last change to layer settings (on/off, freeze, lock, color, current layer…) without undoing drawing edits. | Home ▸ More |
| `LAYFILTER` | -LAYFILTER | Named layer filters: New property filter (name=A-* on=yes color=1 used=no…), Group filter, Invert, Delete, List, Select, Current. | Home ▸ More |
| `LAYFRZ` |  | Freezes the layer of each selected object. | Home ▸ More |
| `LAYISO` |  | Isolates the layers of selected objects (turns the other layers off or locks them). | Home ▸ More |
| `LAYLCK` | LAYLOCK | Locks the layer of each selected object. | Home ▸ More |
| `LAYMCUR` |  | Makes the layer of a selected object current. | Home ▸ More |
| `LAYMRG` | -LAYMRG, LAYMERGE | Merges layers into a target layer (objects move, the source layers are deleted). | Home ▸ More |
| `LAYOFF` |  | Turns off the layer of each selected object. | Home ▸ More |
| `LAYON` |  | Turns on all layers. | Home ▸ More |
| `LAYTHW` |  | Thaws all layers. | Home ▸ More |
| `LAYTRANS` | -LAYTRANS | Layer translator: maps layers to standard layers (mappings FROM=TO with wildcards, or a mapping file; standards from a drawing). | Home ▸ More |
| `LAYULK` | LAYUNLOCK | Unlocks the layer of a selected object. | Home ▸ More |
| `LAYUNISO` |  | Restores the layers hidden or locked by LAYISO. | Home ▸ More |
| `LAYWALK` |  | Walks through layers showing only the chosen ones (name, pattern, Next/Previous, Filter), then restores them. | Home ▸ More |
| `LIMITS` |  | Sets the drawing limits (LIMMIN/LIMMAX). | Manage ▸ More |
| `LINESTYLES` | LSTYLES, -LINESTYLES | Named line styles (weight, colour, pattern): New/Edit/Delete/List, Apply to objects, set a Layer's line style. | Tools ▸ BIM Graphics & Systems |
| `LINETYPE` | LT, -LINETYPE, LTYPE | Lists, loads, creates and sets the current linetype. | Home ▸ More |
| `LTSCALE` | LTS | Sets the global linetype scale factor. | Home ▸ More |
| `LUPREC` |  | System variable LUPREC. | Manage ▸ More |
| `LWDISPLAY` |  | System variable LWDISPLAY. | Manage ▸ More |
| `LWDISPLAYSCALE` | LWSCALE | Screen display scale of lineweights (0.1–5, default 1); plotted widths are never changed. | Tools ▸ Navigation & Sheets |
| `LWEIGHT` | LW, LINEWEIGHT | Sets the current lineweight and lineweight display. | Home ▸ More |
| `LWTABLE` | LWSCALETABLE | Lineweight table by view scale: lineweights are multiplied by the factor of the current annotation scale (Set/Clear/List). | Tools ▸ BIM Graphics & Systems |
| `MIRRTEXT` |  | System variable MIRRTEXT. | Manage ▸ More |
| `OFFSETDIST` |  | System variable OFFSETDIST. | Manage ▸ More |
| `OPTIONS` | OP, PREFERENCES, SETTINGS, CONFIG | Opens Settings: units, grid and snaps, autosave, colors, shortcuts, toolbar, agents. | Manage ▸ Settings |
| `ORTHO` |  | Constrains cursor movement to horizontal/vertical (F8). | Manage ▸ More |
| `ORTHOMODE` |  | System variable ORTHOMODE. | Manage ▸ More |
| `OSMODE` |  | System variable OSMODE. | Manage ▸ More |
| `OSNAP` | OS, -OSNAP, DDOSNAP | Sets running object snap modes (END,MID,CEN,NOD,QUA,INT,EXT,INS,PER,TAN,NEA,PAR,APP,GCEN, ON/OFF). | Manage ▸ More |
| `OTRACK` |  | System variable OTRACK. | Manage ▸ More |
| `PDMODE` |  | System variable PDMODE. | Manage ▸ More |
| `PDSIZE` |  | System variable PDSIZE. | Manage ▸ More |
| `PENSETS` | PENSET, PENTABLE | Pen sets mapping pen numbers (colour indexes) to plotted weights and colours: New/Pen/Current/Display/Delete/List. | Tools ▸ BIM Graphics & Systems |
| `PICKSTYLE` |  | System variable PICKSTYLE. | Manage ▸ More |
| `PLINEWID` |  | System variable PLINEWID. | Manage ▸ More |
| `PLOTTRANSPARENCY` |  | System variable PLOTTRANSPARENCY. | Manage ▸ More |
| `POLARANG` |  | System variable POLARANG. | Manage ▸ More |
| `POLARMODE` |  | System variable POLARMODE. | Manage ▸ More |
| `PROJECTBASEPOINT` | PBP, SHAREDCOORDINATES | Project base point: its location, shared coordinates (easting/northing) and elevation; List or Reset. | Tools ▸ Views & Coordinates |
| `PURGE` | PU, -PURGE | Removes unused blocks, layers, linetypes, text styles and dimension styles. | Manage ▸ Cleanup |
| `RENAME` | REN, -RENAME | Renames blocks, layers, linetypes, text styles, dimension styles, levels, views and wall types. | Home ▸ More |
| `RP` | REFPLANE, REFERENCEPLANE | Draws a named reference plane (work plane) or lists, renames, deletes one or makes it the current UCS. | Tools ▸ Views & Coordinates |
| `SAVETIME` | AUTOSAVE | Sets the autosave interval in minutes (0 turns autosave off). | Manage ▸ More |
| `SELECTSIMILARMODE` |  | System variable SELECTSIMILARMODE. | Manage ▸ More |
| `SETVAR` | SET | Lists or changes system variables. | Manage ▸ More |
| `SNAP` | SN | Turns grid snap on/off or sets the snap spacing (F9). | Manage ▸ More |
| `SNAPMODE` |  | System variable SNAPMODE. | Manage ▸ More |
| `SNAPUNIT` |  | System variable SNAPUNIT. | Manage ▸ More |
| `SURVEYPOINT` | SURVEY | Places the survey point: a location and its shared coordinates (the base point's shared coordinates follow). | Tools ▸ Views & Coordinates |
| `TEXTLAYER` |  | System variable TEXTLAYER. | Manage ▸ More |
| `TEXTSIZE` |  | System variable TEXTSIZE. | Manage ▸ More |
| `THEME` | COLORTHEME, APPEARANCE | Switches the interface theme [Dark/Light]. | Tools ▸ Start & Templates |
| `TRANSPARENCYDISPLAY` |  | System variable TRANSPARENCYDISPLAY. | Manage ▸ More |
| `TRIMMODE` |  | System variable TRIMMODE. | Manage ▸ More |
| `TRUENORTH` | NORTHROTATION, ROTATETRUENORTH | Sets true north relative to project north (angle counter-clockwise from up, or Align to a picked direction). | Tools ▸ Views & Coordinates |
| `UCS` |  | Sets the user coordinate system: World, Origin, Z rotation, 3point, Object, Previous, Named save/restore. | Manage ▸ More |
| `UCSICON` |  | Controls the UCS icon: ON, OFF, Noorigin (lower-left corner) or ORigin (at the UCS origin when visible). | Tools ▸ Views & Coordinates |
| `UCSMAN` | UC, DDUCS | Named UCS manager: lists the saved user coordinate systems and restores, saves, renames or deletes them (World and Previous too). | Manage ▸ More |
| `UNITS` | UN, -UNITS | Sets drawing units (mm, cm, m, in, ft) and optionally scales the drawing. | Manage ▸ Settings |
| `VPLAYER` | VPFREEZE | Freezes/thaws layers in individual sheet viewports: Freeze, Thaw, Reset, List (layout and viewport numbers or All). | Home ▸ More |
| `WALLHEIGHT` |  | System variable WALLHEIGHT. | Manage ▸ More |
| `WALLTHICKNESS` |  | System variable WALLTHICKNESS. | Manage ▸ More |

## Site

| Command | Aliases | Summary | Where |
|---|---|---|---|
| `BUILDINGPAD` | SITEPAD | Levels a toposurface inside a boundary to a pad elevation (cut and fill). | Model |
| `CONTOURS` | CONTOUR | Sets the contour interval and major-line spacing of toposurfaces (0 = hide contours). | Model |
| `DEMIMPORT` | ASCIIGRID, GRIDTERRAIN, ELEVATIONIMPORT, ASCIMPORT | Creates a toposurface from an ESRI ASCII elevation grid (.asc, metres), subsampled to a point budget. | Architecture ▸ More |
| `GRADEDREGION` | GRADE, GRADING, CUTFILL | Graded region: copies a toposurface, levels a pad to an elevation with daylighting side slopes, and reports cut and fill volumes (the existing surface is kept on a hidden layer). | Tools ▸ BIM Graphics & Systems |
| `PARKINGLOT` | PARKINGROW, CARPARK | Lays out a row (or double row with aisle) of parking bays at 90°, 60° or 45° with paving. | Architecture ▸ More |
| `PROPERTYLINE` | PROPLINE, BOUNDARYLINE | Draws property lines by points or bearings and distances; labels bearings, distances and the enclosed area. | Architecture ▸ More |
| `RETAININGWALL` | RETWALL | Draws a cantilever retaining wall (battered stem on a footing) along points; retained side on the right of travel. | Architecture ▸ More |
| `SANDBOX` | SMOOVE, STAMP, DRAPE, TERRAINGRID, SANDBOXTOOLS | Sandbox terrain tools: Grid (terrain from scratch), Smoove (raise/lower with falloff), Stamp (flat pad with side slopes), Drape (project curves onto the terrain), ToBIM (toposurface → BIM topography element). | Tools ▸ Components & Surfaces |
| `SITEPATH` | FOOTPATH, WALKWAY | Draws a path of a given width along points as a site sub-region (draped on the toposurface). | Architecture ▸ More |
| `SUBREGION` | SITEREGION, LAWN | Creates a site sub-region (lawn, gravel, paving) from points or a closed object, draped on the toposurface. | Architecture ▸ More |
| `TOPO` | TOPOSURFACE, TERRAIN | Creates a toposurface from points (with elevations), contour polylines (picked, or every object on contour Layers of an imported DXF), an XYZ/CSV file or typed x,y,z values. | Model |

## Structure

| Command | Aliases | Summary | Where |
|---|---|---|---|
| `ANALYTICALMODEL` | STRUCTMODEL, ANALYTICAL, ANALYTICALOUT | Builds the structural analytical model (nodes, members, wall/slab panels, supports, loads) from columns, beams, walls and slabs and writes it as JSON, OpenSees Tcl, SAF (.xlsx) or an IFC4 structural analysis view (.ifc). | Architecture ▸ More |
| `BEAMSYSTEM` | BEAMSYS, JOISTS | Fills a boundary with parallel beams at a spacing (direction, size or profile, top elevation). | Architecture ▸ More |
| `BRACE` | BRACING, DIAGONALBRACE | Places a diagonal brace between two plan points at a bottom and a top elevation (profile, default CHS). | Architecture ▸ More |
| `FOUNDATION` | FOOTING, FNDN | Creates strip footings under walls, isolated footings under columns, or pads from points. | Architecture ▸ More Building Tools |
| `FRAMEANALYSIS` | FRAMESOLVE, STRUCTANALYSIS | Linear static analysis of the column/beam frame (self weight + slab loads lumped to columns): displacements and support reactions. | Architecture ▸ More |
| `REBAR` | REINFORCEMENT, RB, REBARSET | Reinforcement in a concrete beam (Bottom/Top bars, Links), column (Vertical bars, Links) or slab (X/Y mesh): cover, bar diameter, count or spacing, BS 8666 shape codes; List prints the bar schedule. | Tools ▸ Images, Links & Structure |
| `STEELCONNECTION` | CONNECTION, BASEPLATE, ENDPLATE, STEELCONN | Steel connections sized from the member section: Base plate with anchor bolts or Cap plate on a column, End plate with bolts on a beam end; they follow the member. | Tools ▸ Images, Links & Structure |
| `STEELPROFILE` | STRUCTPROFILE, SECTIONPROFILE | Applies structural profiles (IPE, HEA, HEB, UPN, I/H/C/L/T, RHS/SHS/CHS, rectangular, round) to beams and columns, or lists them. | Architecture ▸ More |
| `STRUCTCOLUMN` | STRUCTURALCOLUMN, SCOLUMN, STEELCOLUMN | Places structural columns with a profile (HEA/IPE/RHS/CHS… or RECT / ROUND concrete), from the level to the next level (or a height), at points or at every grid intersection. | Tools ▸ BIM Types & Parameters |
| `STRUCTLOAD` | LOADADD, STRUCTURALLOAD | Adds a structural load on layer S-LOADS for the analytical model: Point (kN at a node or on a beam), Line (kN/m along beams) or Area (kN/m² over an outline); vertical downward by default, optional horizontal components and load case. | Tools ▸ Analysis & Design Assist |
| `STRUCTSUPPORT` | SUPPORTADD, BOUNDARYCONDITION | Adds a support (boundary condition) for the analytical model at a node: Fixed, Pinned, Roller or a custom ux uy uz rx ry rz code (e.g. 111000). | Tools ▸ Analysis & Design Assist |
| `STRUCTURAL` | STRUCTURALUSAGE, LOADBEARING | Structural usage of walls, slabs, columns and beams: Bearing, Shear, Combined or Non-bearing (drives the analytical model and schedules). | Tools ▸ BIM Types & Parameters |
| `TRUSS` | TRUSSES | Places a Pratt, Howe, Warren or Fink truss between two bearing points (height, member width, bearing elevation). | Architecture ▸ More |

## Tools

| Command | Aliases | Summary | Where |
|---|---|---|---|
| `ACTMANAGER` | ACTLIST, ACTIONMANAGER | Lists, shows, deletes, renames, exports (.scr) or imports action macros. | Manage ▸ More |
| `ACTPLAY` | ACTIONPLAY | Plays back a recorded action macro. | Manage ▸ More |
| `ACTRECORD` | ACTIONRECORD | Starts recording an action macro (typed commands and picks); ACTSTOP saves it in the drawing. | Manage ▸ More |
| `ACTSTOP` | ACTIONSTOP | Stops recording and saves the action macro under a name (stored in the drawing). | Manage ▸ More |
| `ALIAS` | ALIASEDIT | Defines command aliases and macros (Define/Delete/List/Global/Load/Save); ";" in a macro is Enter. | Manage ▸ More |
| `BATCH` | BATCHJOBS, SCRIPTPRO, RUNBATCH | Runs a JSON batch job file over many drawings: open/import, command lines or a script, outputs in any export format, analysis reports and save (the open drawing is not changed). | Collaborate ▸ Share |
| `DELAY` |  | Pauses a script for the given number of milliseconds (up to 32767). | Script ▸ Automation |
| `HISTORY` | CMDHISTORY, HIST | Command history: List (last N), Recent input values, Save/Load a history file, Clear, or run a previous line (!n). | Manage ▸ More |
| `MACRO` | RUNMACRO | Runs a menu macro: spaces or ; = Enter, \ = pause for your input, ^C^C = cancel first (e.g. ^C^CLINE \ @1000,0 ;). | Script ▸ Automation |
| `MACROBUTTON` | MBUTTON, -CUI, CUIBUTTON | Creates, edits, lists, runs and deletes custom macro buttons (saved in the drawing or in your profile). | Tools ▸ Arrays, Macros & Monitor |
| `MEMORYREPORT` | MEMUSAGE, MEMSTATS, MEMINFO | Memory estimate of the drawing by kind, the app's memory footprint and the budget (MEMORYBUDGET MB) with advice; POINTLIMIT follows the budget. | Tools ▸ Studies, Signatures & Publishing |
| `NODEPACKAGE` | NODEPACKAGES, NODEPKG | Custom node packages (.archinodes): Create one from the drawing's node graph (a snippet per group), Install a file, Insert a snippet into the graph, List, Remove. | Tools ▸ Render, Materials & Environment |
| `RELZERO` | RELATIVEZERO, SETRELZERO | Sets the relative zero (the point @ input is measured from), or locks / unlocks it. | Tools ▸ BIM Grids, Zones & Data |
| `RESUME` |  | Continues a script that was interrupted with Escape. | Script ▸ Automation |
| `SCRIPTRECORD` | RECSCRIPT | Records typed commands and picks as a script (Start/Stop); saved to a .scr file. | Manage ▸ More |
| `SYSVARMONITOR` | SYSMON, -SYSVARMONITOR | Watch list of system variables: you are notified when a command changes one of them. | Tools ▸ Arrays, Macros & Monitor |
| `TUTORIALRECORD` | RECORDTUTORIALS, TUTORIALVIDEOS, TUTREC | Tutorial videos: List the scripted tutorials, Check them, or Record (the videos are recorded by the Mac app; on Windows Record opens the tutorial videos on the website). | Tools ▸ Tutorial Videos |

## View

| Command | Aliases | Summary | Where |
|---|---|---|---|
| `AMBIENTOCCLUSION` | AOCCLUSION, AOBAKE, AOSETTINGS | Ambient occlusion baked on the model: Intensity (0 = off … 2), Radius and Samples; shaded elevations, sections, axonometrics and perspectives (and their PDF/SVG exports) darken corners and overhangs; Report prints the average occlusion. | Tools ▸ Styles, Patterns & Occlusion |
| `ANIMATE` | OBJANIMATE, OBJECTANIMATION, DOORANIMATE | Object animation saved in the drawing: Door swings, Rotate about a pivot, Move by a vector (start time, duration, there and back); Play/Stop in 3D, List, Delete, Clear, Render a frame. | Tools ▸ Render, Materials & Environment |
| `AODIALOG` | AMBIENTOCCLUSIONDIALOG, AOPANEL | Ambient Occlusion dialog: intensity, radius and rays per point for the 3D viewport, renders and shaded views. | Tools ▸ Styles, Patterns & Occlusion |
| `ARQUICKLOOK` | ARVIEW, USDZPREVIEW, ARPREVIEW | AR view: exports the model as a real-scale glTF (GLB) and Previews it in the Windows 3D viewer (mixed reality) or Shares it to a phone or tablet. | Tools ▸ Render, Materials & Environment |
| `AXONVIEW` | AXONVIEWSAVE, SAVE3DVIEW, AXONOMETRIC | Saves a 3D axonometric view (SW / SE / NE / NW isometric, Top, or Custom azimuth/elevation) that refits to the model after every change. | Tools ▸ Views & Coordinates |
| `BACKVIEW` | BACK | Sets the 3D view to back. | View ▸ Views |
| `BILLBOARD` | CUTOUT, IMAGECUTOUT, ENTOURAGE | Places a 2D cutout that always faces the camera in 3D and renders: Person, Tree, Shrub or an image file (PNG with transparency). | Tools ▸ Navigate, Light & Publish |
| `BOTTOMVIEW` | BOTTOM | Sets the 3D view to bottom. | View ▸ More |
| `CALLOUT` | DETAILCALLOUT, CALL | Draws a callout (boundary, leader and numbered bubble) in plan and places the enlarged detail view it refers to. | Architecture ▸ Documentation |
| `CAMERA` | CAM, RESTORECAMERA | Restores a saved 3D camera (or lists them). | View ▸ More |
| `CAMERAPATHEDIT` | ANIMPATH, CAMPATHS | Camera path editor: keys from the 3D view or saved cameras at times, timeline scrubbing and playback, video export. | View ▸ Presentation |
| `CAMERAVIEW` | PLACECAMERA, CAMERAOBJ, PERSPECTIVEVIEW | Places a camera object (eye, target, heights, lens) saved as a perspective 3D view; cameras show in plan with their field of view. | Tools ▸ Views & Coordinates |
| `CLEANSCREENOFF` |  | Restores the ribbon and panels after CLEANSCREENON. | View ▸ More |
| `CLEANSCREENON` | CLEANSCREEN | Clean screen: hides the ribbon and panels (Ctrl+0 toggles). | View ▸ More |
| `CLIPPLANES` | CLIPPLANE, CLIPPINGPLANE | Clipping plane panel in the 3D view: horizontal or vertical cut, live offset slider, flip, remove. | Tools ▸ 3D, Render & Print |
| `DATUMS3D` | SHOWDATUMS, LEVELS3D, GRIDS3D | Shows or hides levels and grids (with heads) in the 3D view. | Architecture ▸ Documentation |
| `DRAFTINGVIEW` | DRAFTING, DRAFTVIEW, DETAILVIEW2D | Drafting views (2D only, not tied to the model): new, edit in isolation, close (store), place in the drawing, list. | View ▸ More |
| `DVIEW` | DV, PLANTWIST | Rotates (twists) the 2D plan display; model coordinates are unchanged. DVIEW TWist 30, DVIEW Off. | Tools ▸ Navigation & Sheets |
| `FILETAB` |  | Shows the file tab bar with one tab per open drawing. | Tools ▸ Navigation & Sheets |
| `FILETABCLOSE` |  | Hides the file tab bar. | Tools ▸ Navigation & Sheets |
| `FLOATPANEL` | UNDOCKPANEL, PANELFLOAT | Floats a panel (Properties, Layers, Levels, Browser, Materials, Tools, Sheets, History) in its own window. | View ▸ More |
| `FLY` | FLYMODE, 3DFLYMODE | Free flight in 3D: W A S D along the view direction, Q/E down/up, drag to look (no gravity or collisions). | Tools ▸ Navigate, Light & Publish |
| `FOG` | ATMOSPHERE, HAZE, RENDERENVIRONMENT | Fog / atmospheric haze in the 3D view and renders: On/Off, start and end distance, colour and falloff (saved in the drawing). | Tools ▸ Navigate, Light & Publish |
| `FOV` | FIELDOFVIEW, LENS | Sets the 3D camera field of view in degrees (15–120), or a Lens length in mm (35 mm equivalent). | Tools ▸ Families, Views & Panels |
| `FRONTVIEW` | FRONT | Sets the 3D view to front. | View ▸ Views |
| `FULLSCREEN` | FS | Enters or leaves full screen for this drawing window. | Tools ▸ Navigation & Sheets |
| `GRAPHICDISPLAY` | GDO, DISPLAYOPTIONS | Graphic display options of the current view: Sketchy lines (0–10), Silhouettes (line weight, 0 = off) and cast Shadows in plan; saved with the view. | Tools ▸ Feature Modelling |
| `HISTORYPANEL` | UNDOHISTORY, HISTORY | Shows the undo history and command history panel. | View ▸ More |
| `INTERIORELEV` | INTERIORELEVATION, IELEV, ROOMELEVATIONS | Places a 4-way interior elevation marker in a room and draws its four interior elevations (A–D). | Architecture ▸ Documentation |
| `ISOVIEW` | ISO, SWISO | Sets the 3D view to swiso. | View ▸ Views |
| `LAYOUT` | LO, -LAYOUT, SHEET | Creates, sets, renames and deletes sheets (layouts); sets paper size and title block. | View ▸ More |
| `LAYOUTTABS` | LAYOUTTAB, MODELTAB | Shows or hides the Model / layout tabs under the drawing area. | Tools ▸ Navigation & Sheets |
| `LEFTVIEW` | LEFT | Sets the 3D view to left. | View ▸ Views |
| `LEGEND` | LEGENDS, LEGENDVIEW, BUILDUPLEGEND | Places a legend view: wall types, door/window types, floor/roof build-ups, components or materials (VIEWUPDATE refreshes it). | View ▸ More |
| `LEVELVIEW3D` | ISOLATELEVEL3D, EXPLODELEVELS | 3D view by level: show All levels, Isolate one level, or Explode levels apart by a gap. | Tools ▸ Families, Views & Panels |
| `LIGHT` | LIGHTS, POINTLIGHT, SPOTLIGHT, ARTIFICIALLIGHT | Places point, spot, area, line or IES lights (lumens, colour temperature, beam) that light the 3D view and renders; List, On/Off. | Tools ▸ Navigate, Light & Publish |
| `LIGHTMIX` | LIGHTGROUPS, RENDERLIGHTMIX | Light mix of path-traced renders: weights of the Sun, Sky and Artificial light groups, changeable after rendering (saved in the drawing). | Tools ▸ Render, Materials & Environment |
| `LINEWORK` | LINEWORKOVERRIDE, LWO | Overrides the line style of individual element edges in the current project view (Invisible, Hidden, Thin, Wide, Medium, Color, or Reset). | Tools ▸ Views & Coordinates |
| `LOOKAROUND` | LOOK, LOOKAROUNDTOOL | Looks around from the current eye point (drag or arrow keys turn the head; the camera does not move). | Tools ▸ Navigate, Light & Publish |
| `MATASSET` | MATERIALASSETS, MATIDENTITY, MATPHYSICAL | Material assets kept apart from the render appearance: Identity (description, manufacturer, mark, cost), Graphics (shading colour, surface pattern) and Physical/thermal (density, conductivity, specific heat); List. | Tools ▸ Render, Materials & Environment |
| `MATBROWSER` | MATLIB, MATERIALLIBRARY | Material library browser with rendered thumbnails: add to the drawing or assign to the selection. | Insert ▸ Content |
| `MATCHLINE` | MATCHLINES | Matchlines between dependent views: On / Off / List. | Tools ▸ Views & Coordinates |
| `MATEMISSIVE` | EMISSIVE, SELFILLUM, MATEMIT | Makes a material self-illuminated (luminance factor 0–20; 0 turns it off): screens, lamps, signs glow in 3D and renders. | Tools ▸ Navigate, Light & Publish |
| `MATERIALS` | MAT, RMAT, MATEDITOR, MATBROWSEROPEN | Opens the material editor panel (color, roughness, metalness, transparency, texture). | View ▸ More |
| `MATFROMIMAGE` | MATPHOTO, PHOTOMATERIAL, IMAGETOMATERIAL | Creates a seamless PBR material from a photo: de-lit albedo, normal, roughness and AO maps derived from the image, at a real-world tile size. | Tools ▸ Render, Materials & Environment |
| `MATMAPPING` | TEXTUREMAPPING, UVMAPPING, MATERIALMAPPING, POSITIONTEXTURE | Texture mapping of a material: Box, Planar, Cylindrical, Spherical or UV, and texture positioning (offset, rotation, scale) on its faces; Reset. | Tools ▸ Navigate, Light & Publish |
| `MATMAPS` | PBRMAPS, MATERIALMAPS | PBR texture maps of a material: Normal, Roughness, Metallic, AO and Displacement images, normal strength and displacement height; List/Clear. | Tools ▸ Render, Materials & Environment |
| `MVIEW` | MV, VIEWPORT | Places a viewport on the current sheet (corners in paper mm, scale 1:n, view kind, level). | View ▸ More |
| `MVIEWPOLY` | MVPOLY, POLYVIEWPORT | Creates a polygonal sheet viewport from paper points (x,y in mm) showing the current level. | Tools ▸ Navigation & Sheets |
| `MVSETUP` |  | Aligns sheet viewports: pans one viewport so a model point lines up horizontally or vertically with a point in another. | Tools ▸ Navigation & Sheets |
| `NAVIGATOR` | OVERVIEW, MINIMAP | Navigator: overview map of the whole drawing with the visible area; drag the rectangle to pan. | Tools ▸ Families, Views & Panels |
| `NAVSWHEEL` | STEERINGWHEEL, WHEEL, SWHEEL | Steering wheel in 3D: Zoom, Orbit, Pan, Rewind (outer ring), Center, Walk, Up/Down, Look (inner ring). | Tools ▸ Navigate, Light & Publish |
| `NAVVCUBE` | VIEWCUBE | Shows or hides the view cube in 3D. | View ▸ 3D Tools |
| `NEISO` |  | Sets the 3D view to neiso. | View ▸ More |
| `NWISO` |  | Sets the 3D view to nwiso. | View ▸ More |
| `ORBITSELECTION` | ORBITSEL, 3DORBITSEL, ZOOMSELECTED3D | Orbits around (and zooms to) the selected elements in 3D. | View ▸ 3D Tools |
| `PAN` | P, -PAN | Moves the view by a displacement. | View ▸ More |
| `PANORAMA` | 360, PANO, RENDER360 | Renders a 360° equirectangular panorama (PNG/JPEG) from the 3D camera position or a picked plan point. | View ▸ Presentation |
| `PATHTRACE` | PTRENDER, RENDERPT, PATHTRACER, RAYTRACE | Progressive path-traced render of the 3D view (GGX materials, glass refraction, PBR maps, sun, sky, lights): Window, or File with size, samples and denoising. | Tools ▸ Render, Materials & Environment |
| `PERSPECTIVE` | PROJECTION | 3D projection: 1 = perspective, 0 = parallel (orthographic). | Tools ▸ Navigation & Sheets |
| `PHASEANIMATION` | PHASEVIDEO, 4DVIDEO, 4DANIMATION | Construction sequence (4D) video from the phases (new elements appear bottom-up, demolished ones disappear) or from the work schedule (day by day), captioned (MP4). | Tools ▸ Navigate, Light & Publish |
| `PLAN` |  | Shows the plan view of the current UCS, a named UCS or the world (rotates the 2D display so the UCS X axis is horizontal). | Tools ▸ Views & Coordinates |
| `PLANORIENT` | ORIENTATION | Orients the plan to Project north (up) or True north (display rotation only). | Tools ▸ Views & Coordinates |
| `POSITIONCAMERA` | POSCAM, EYEPOINT | Places the camera at a plan point at eye height looking towards a second point, then looks around (SketchUp style). | Tools ▸ Navigate, Light & Publish |
| `PROCMATERIAL` | PROCEDURALMATERIAL, PROCTEXTURE, MATPROCEDURAL | Procedural seamless material (Wood, Brick, Tile, Marble, Stone, Concrete, Terrazzo) with albedo, normal and roughness maps from colours, courses, joint width and a seed. | Tools ▸ Render, Materials & Environment |
| `PROJECTVIEW` | PVIEW, VIEWS, VIEWBROWSER | Project views: New (plan / ceiling / 3D), Open, Close, Duplicate (plain, with detailing, as dependent), Split into dependent views, Rename, Delete, List. | Tools ▸ Views & Coordinates |
| `QUICKPROPS` | QP, QUICKPROPERTIES | Quick Properties: a compact editor of the selection's key properties over the drawing. | Tools ▸ Navigation & Sheets |
| `RADIALMENU` | MARKINGMENU, PIEMENU | Right-drag marking menu with the 8 most used commands for the context (On/Off/List). | Tools ▸ Navigate, Light & Publish |
| `RCP` | REFLECTEDCEILING, CEILINGPLAN | Reflected ceiling plan on/off (ceilings with grids and heights, ceiling fixtures), and ceiling grid settings. | Architecture ▸ More |
| `REGEN` | RE, REGENALL, REA, REDRAW, R | Regenerates the display. | View ▸ More |
| `RENDER` | RR | Renders the 3D model. | View ▸ Presentation |
| `RENDERPRESET` | LIGHTINGPRESET, BEAUTYPRESET, PHOTOLOOK | Photographic lighting preset of the Realistic view and renders: Daylight, Golden hour, Overcast or Night (glowing windows); Off returns to the default look. | Tools ▸ Photographic Render |
| `RENDERPROMPT` | AIRENDER, RENDERSTYLE, PROMPTRENDER | Styles the render from a description (e.g. “golden hour, soft shadows, warm, 4K”): saves it as the “Prompt” render preset and opens the render window. | Tools ▸ Navigate, Light & Publish |
| `RENDERQUEUE` | BATCHRENDER, RENDERHISTORY | Render queue: add the current view or saved cameras, render them in turn to PNG files; render history with thumbnails. | View ▸ Presentation |
| `RENDERTOFILE` | RENDERFILE, RENDEROUT, RENDERPASS | Renders to an image file: any size up to 7680×4320 (tiled), a pass (Beauty, Alpha, Depth, Normal, Material ID), a style (Photographic, Sketch, Watercolour) and an optional region of the frame. | Tools ▸ Navigate, Light & Publish |
| `REVEALHIDDEN` | REVEAL, SHOWHIDDEN | Reveal hidden elements: On draws temporarily hidden objects in magenta, Off stops, Unhide restores objects by id (#12,#15) or All. | Tools ▸ Temporary Visibility |
| `RIGHTVIEW` | RIGHT, SIDE | Sets the 3D view to right. | View ▸ Views |
| `SAVECAMERA` | CAMSAVE, NEWCAMERA | Saves the current 3D camera by name (restored with CAMERA). | View ▸ 3D Tools |
| `SCOPEBOX` | SCOPEBOXES | Scope boxes: New (two corners, rotation), Grids (assign grids — they are trimmed to the box), View (crop a project view by the box), Delete, List. | Tools ▸ Views & Coordinates |
| `SEASON` | SEASONS | Season of the vegetation in the 3D view and renders: Spring, Summer, Autumn or Winter colours for grass, trees and plants. | Tools ▸ Render, Materials & Environment |
| `SECTION` | SECTIONLINE, SECTIONMARK | Places a section line (A–A…) in plan; section views and sheets use the current section. | Architecture ▸ Documentation |
| `SECTIONBOX` | SBOX, 3DSECTIONBOX | Section box in 3D: On/Off/Selection/Level/Reset; the box is saved with the drawing. | View ▸ 3D Tools |
| `SECTIONPLANE` | SPLANE, CUTPLANE, LIVESECTION | Live section plane in 3D with cap faces: Horizontal at a height, Vertical through two plan points, Flip, Off. | View ▸ Presentation |
| `SEISO` |  | Sets the 3D view to seiso. | View ▸ More |
| `SHOW2D` | 2D | Shows the 2D plan view. | View ▸ More |
| `SHOW3D` | 3D, 3DVIEW, MODEL3D | Shows the 3D model view. | View ▸ More |
| `SPACEMOUSE` | 3DMOUSE, NDOF, 3DCONNEXION | 3Dconnexion SpaceMouse: On/Off, Object (orbit) or Fly mode, Sensitivity, Status. Axes move the 3D camera; button 1 fits the view. | Tools ▸ Render, Materials & Environment |
| `SPLIT` | SPLITVIEW, VPORTS | Shows the plan and 3D views side by side. | View ▸ More |
| `STEREOPANORAMA` | STEREO360, ODSPANORAMA, VRPANORAMA | Stereo 360° panorama for VR viewers: left and right eye equirectangular images over-under (omni-directional stereo), from the 3D camera or a plan point. | Tools ▸ Navigate, Light & Publish |
| `SUNSTUDY` | SUN, SUNPROPERTIES | Sun study panel in the 3D view: date and time sliders with a day animation. | View ▸ 3D Tools |
| `SUNSTUDYVIDEO` | SUNVIDEO, SHADOWSTUDY | Exports an MP4 sun-study time-lapse (shadows through the day) from the current 3D camera. | View ▸ Presentation |
| `SYSWINDOWS` | ARRANGEWINDOWS, TILEWINDOWS, WINDOWS | Arranges the open drawing windows: Vertical (side by side), Horizontal, Cascade, Tabs or Separate windows. | Tools ▸ Navigate, Light & Publish |
| `TEMPHIDE` | HH, HIDECATEGORY, HC | Temporarily hides the selected elements, or a whole Category (wall, door, component…) on the current level; UNISOLATEOBJECTS or REVEALHIDDEN Unhide restores them. | Tools ▸ Temporary Visibility |
| `TEMPISOLATE` | HI, ISOLATECATEGORY, IC | Temporarily isolates element categories on the current level: every other category is hidden until UNISOLATEOBJECTS. | Tools ▸ Temporary Visibility |
| `TILEDVIEWS` | VPTILE, TILEVIEWS | Tiled model views: 2, 3 or 4 views (plan, 3D, section, elevations), each with its own zoom and pan. | Tools ▸ Navigation & Sheets |
| `TOOLPALETTES` | TP, TOOLPALETTE | Shows the tool palettes panel (grouped tools and My Tools). | View ▸ More |
| `TOOLPALETTESCLOSE` |  | Hides the tool palettes panel. | View ▸ More |
| `TOPVIEW` | TOP, PLANVIEW | Sets the 3D view to top. | View ▸ Views |
| `TWOPOINT` | TWOPOINTPERSPECTIVE, 2PT, VERTICALS | Two-point perspective: levels the 3D camera so vertical lines stay vertical, shifting the lens to keep the framing (On/Off). | Tools ▸ Navigate, Light & Publish |
| `UNDERLAY` | UNDERLAYLEVEL, HALFTONELEVEL | Shows another level halftone under the current plan (None to turn off). | Tools ▸ BIM Grids, Zones & Data |
| `VIEW` | V, -VIEW | Saves, restores, lists and deletes named views. | View ▸ More |
| `VIEWCROP` | CROPREGION, CROPVIEW, ANNOTATIONCROP | Crop region of the current project view: Window, Polygon, On, Off, Annotation crop offset, Show / Hide the crop boundary. | Tools ▸ Views & Coordinates |
| `VIEWDRAW` | DRAWINGVIEW, SECTIONVIEW, ELEVATIONVIEW | Places an elevation or section of the model as a 2D drawing (with level heads and grid bubbles) in model space. | Architecture ▸ Documentation |
| `VIEWGRAPHICS` | SECTIONGRAPHICS, ELEVGRAPHICS, DEPTHCUE, HIDDENLINES, VG, VISGRAPHICS | View graphics: Categories (visibility/graphics overrides per category), Filters (rule-based view filters), Detail level, and Section/elevation graphics (line weights by depth, hidden lines, depth cueing, far clip, dimensions). | View ▸ More |
| `VIEWIMAGE` | VIEWPORTIMAGE, SAVEIMG3D | Saves the 3D view as a PNG, JPEG or TIFF at a chosen size, optionally with a transparent background. | Tools ▸ Families, Views & Panels |
| `VIEWRANGE` | VR, PLANRANGE | Plan view range relative to the level: Top, Cut plane, Bottom and View depth; elements above the top are left out and those below the bottom (down to the view depth, also from lower levels) are drawn as beyond. Off restores the default. | Tools ▸ BIM Grids, Zones & Data |
| `VIEWSECTIONBOX` | SECTIONBOXVIEW, CROP3D | Section box of the current 3D view: Fit (selection, level or model), Box (two corners and heights), On, Off. | Tools ▸ Views & Coordinates |
| `VIEWTEMPLATE` | VIEWTEMPLATES, VT | View templates: list, apply to the current view, capture the current settings as a template, set a template value, apply to a placed drawing view, or delete. | View ▸ More |
| `VIEWUPDATE` | UPDATEVIEWS | Regenerates all placed elevation/section drawing views from the current model. | Architecture ▸ Documentation |
| `VISUALSTYLES` | VSM, VISUALSTYLEMANAGER | Visual styles manager: New/Edit a custom style from a base (edges, edge colour, face opacity, shadows, background), Delete, List, Current. | Tools ▸ Navigation & Sheets |
| `VPCLIP` |  | Clips a sheet viewport to a polygon of paper points (x,y in mm), or Deletes the clip. | Tools ▸ Navigation & Sheets |
| `VPMAX` | VPMAXIMIZE | Maximises a sheet viewport: edits the model through it at full window size (VPMIN returns). | Tools ▸ Navigation & Sheets |
| `VPMIN` | VPMINIMIZE | Returns from a maximised viewport to its sheet, keeping the new view centre (unless the viewport is locked). | Tools ▸ Navigation & Sheets |
| `VRVIEW` | WEBXR, VREXPORT, HEADSETVIEW | VR headset viewing: writes the model as a WebXR page (life-size, floor on the room floor, pinch/trigger steps forward) for Apple Vision Pro, Meta Quest or OpenXR browsers; Open, Reveal (AirDrop) or just Save. | Tools ▸ Styles, Patterns & Occlusion |
| `VSCURRENT` | VS, SHADEMODE | Sets the visual style of the 3D view. | View ▸ More |
| `WALK` | 3DWALK, WALKTHROUGH, 3DFLY | Starts a first-person walkthrough of the 3D model. | View ▸ Presentation |
| `WALKTHROUGHVIDEO` | WALKVIDEO, ANIPATH, CAMERAPATH | Exports an MP4 walkthrough along a smooth path through the saved cameras (in order). | View ▸ Presentation |
| `WEATHER` | RAIN, SNOW, WEATHERFX | Weather in the 3D view and renders: Clear, Rain, Snow or Fog with an intensity, snow cover on up-facing faces and wet surfaces. | Tools ▸ Render, Materials & Environment |
| `WINDOWTABS` | DOCTABS | Window tabs: Merge all drawing windows into tabs, or open new drawings in Tabs / Windows. | Tools ▸ Navigation & Sheets |
| `WSCURRENT` | WS, WORKSPACE | Switches workspace (panels, views and ribbon tab), e.g. WSCURRENT 3D Modeling. | View ▸ More |
| `WSSAVE` |  | Saves the current window arrangement as a named workspace. | View ▸ More |
| `ZOOM` | Z | Zooms: All/Extents, Window, Previous, Center, Object, or a scale (2, 0.5x). | View ▸ More |
| `ZOOMXP` | ZXP, ZOOMPAPER, ZOOMSCALEXP | ZOOM nXP: in a sheet sets the selected viewport to 1:n (1/100XP); on the plan shows the drawing at that paper scale at true size on the screen. | Tools ▸ Files, Clipboard & Access |
