// Oanarina Archi Tool — GPL-3.0-or-later
// Wind / CFD basics (ANL-028): writes a ready-to-run OpenFOAM case (external solver, simpleFoam k-epsilon with an
// atmospheric boundary layer inlet) for the building: the model as an STL in metres, rotated so the wind blows along
// +X, a blockMesh domain sized from the building height (5H upstream and sideways, 15H downstream, 6H high),
// snappyHexMesh refinement around the building and a pedestrian-level (1.5 m) velocity sample. The sampled result
// (raw "x y z Ux Uy Uz" files) is read back as wind arrows coloured by speed and pedestrian-comfort classes.
import Foundation

public enum WindStudy {
    public struct Options {
        /// Reference wind speed (m/s) at `referenceHeight` (m).
        public var speed = 5.0
        public var referenceHeight = 10.0
        /// Meteorological direction the wind comes FROM (degrees clockwise from north): 270 = westerly wind.
        public var direction = 270.0
        /// Aerodynamic roughness length z0 (m): 0.03 open country, 0.3 suburbs, 1 city centre.
        public var roughness = 0.3
        /// Background cell size (m) and surface refinement level of snappyHexMesh.
        public var cellSize = 0.0
        public var refinement = 2
        public var iterations = 500
        public var sampleHeight = 1.5
        public init() {}
        public static func from(_ doc: ArchiDocument) -> Options {
            var o = Options()
            func v(_ k: String) -> Double? { Double(doc.variable(k) ?? "") }
            o.speed = v("WINDSPEED") ?? o.speed
            o.direction = v("WINDDIRECTION") ?? o.direction
            o.roughness = v("WINDROUGHNESS") ?? o.roughness
            o.cellSize = v("WINDCELL") ?? o.cellSize
            o.iterations = Int(v("WINDITERATIONS") ?? Double(o.iterations))
            return o
        }
    }

    public struct Domain: Hashable {
        public var min: Vec3, max: Vec3
        public var cells: (Int, Int, Int)
        public var buildingHeight: Double
        public static func == (a: Domain, b: Domain) -> Bool { a.min == b.min && a.max == b.max && a.cells == b.cells }
        public func hash(into h: inout Hasher) { h.combine(min); h.combine(max) }
    }

    /// Angle (radians, CCW from +X in the drawing) of the direction the wind blows TOWARDS.
    public static func flowAngle(_ o: Options, northAngle: Double) -> Double {
        // "From" direction clockwise from north → blowing towards (from + 180). North is up (+Y) rotated by northAngle.
        let towards = (o.direction + 180) * .pi / 180
        return .pi / 2 - towards + northAngle * .pi / 180
    }

    /// Building triangles in metres, rotated so the wind blows along +X, standing on z = 0.
    public static func buildingTriangles(_ doc: ArchiDocument, options o: Options) -> [(Vec3, Vec3, Vec3)] {
        let k = doc.units.mm / 1000
        let a = -flowAngle(o, northAngle: doc.info.northAngle)
        let ca = cos(a), sa = sin(a)
        var out: [(Vec3, Vec3, Vec3)] = []
        var zmin = Double.infinity
        for g in MeshBuilder.build(doc: doc) {
            let m = g.mesh
            let t = MeshExport.triangles(m)
            var i = 0
            while i + 2 < t.count {
                let p = [t[i], t[i + 1], t[i + 2]].map { idx -> Vec3 in
                    let q = m.positions[Int(idx)] * k
                    return Vec3(q.x * ca - q.y * sa, q.x * sa + q.y * ca, q.z)
                }
                zmin = min(zmin, p[0].z, p[1].z, p[2].z)
                out.append((p[0], p[1], p[2]))
                i += 3
            }
        }
        guard zmin.isFinite else { return [] }
        return out.map { ($0.0 - Vec3(0, 0, zmin), $0.1 - Vec3(0, 0, zmin), $0.2 - Vec3(0, 0, zmin)) }
    }

    public static func domain(for tris: [(Vec3, Vec3, Vec3)], options o: Options) -> Domain? {
        guard !tris.isEmpty else { return nil }
        var lo = Vec3(.infinity, .infinity, .infinity), hi = Vec3(-.infinity, -.infinity, -.infinity)
        for t in tris { for p in [t.0, t.1, t.2] { lo = Vec3(min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z)); hi = Vec3(max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z)) } }
        let h = max(hi.z, 1)
        let mn = Vec3(lo.x - 5 * h, lo.y - 5 * h, 0), mx = Vec3(hi.x + 15 * h, hi.y + 5 * h, 6 * h)
        let cell = o.cellSize > 0 ? o.cellSize : max(0.5, h / 4)
        func n(_ l: Double) -> Int { max(4, Int((l / cell).rounded(.up))) }
        return Domain(min: mn, max: mx, cells: (n(mx.x - mn.x), n(mx.y - mn.y), n(mx.z - mn.z)), buildingHeight: h)
    }

    static func header(_ cls: String, _ obj: String, location: String? = nil) -> String {
        """
        /*--------------------------------*- C++ -*----------------------------------*\\
          Written by Oanarina Archi Tool (OpenFOAM case, simpleFoam)
        \\*---------------------------------------------------------------------------*/
        FoamFile
        {
            version     2.0;
            format      ascii;
            class       \(cls);
        \(location.map { "    location    \"\($0)\";\n" } ?? "")    object      \(obj);
        }

        """
    }

    /// Files of the case, keyed by relative path.
    public static func caseFiles(_ doc: ArchiDocument, options o: Options) throws -> [String: String] {
        let tris = buildingTriangles(doc, options: o)
        guard let d = domain(for: tris, options: o) else { throw AgentTools.ToolError(message: "The model has no 3D geometry for a wind study.") }
        func f(_ v: Double) -> String { String(format: "%.6g", v) }
        var stl = "solid building\n"
        for t in tris {
            let n = (t.1 - t.0).cross(t.2 - t.0).normalized
            stl += "facet normal \(f(n.x)) \(f(n.y)) \(f(n.z))\n outer loop\n"
            for p in [t.0, t.1, t.2] { stl += "  vertex \(f(p.x)) \(f(p.y)) \(f(p.z))\n" }
            stl += " endloop\nendfacet\n"
        }
        stl += "endsolid building\n"
        let (a, b) = (d.min, d.max)
        let blockMesh = header("dictionary", "blockMeshDict") + """
        convertToMeters 1;
        vertices
        (
            (\(f(a.x)) \(f(a.y)) \(f(a.z))) (\(f(b.x)) \(f(a.y)) \(f(a.z))) (\(f(b.x)) \(f(b.y)) \(f(a.z))) (\(f(a.x)) \(f(b.y)) \(f(a.z)))
            (\(f(a.x)) \(f(a.y)) \(f(b.z))) (\(f(b.x)) \(f(a.y)) \(f(b.z))) (\(f(b.x)) \(f(b.y)) \(f(b.z))) (\(f(a.x)) \(f(b.y)) \(f(b.z)))
        );
        blocks ( hex (0 1 2 3 4 5 6 7) (\(d.cells.0) \(d.cells.1) \(d.cells.2)) simpleGrading (1 1 1) );
        boundary
        (
            inlet  { type patch; faces ((0 4 7 3)); }
            outlet { type patch; faces ((1 2 6 5)); }
            ground { type wall;  faces ((0 3 2 1)); }
            top    { type symmetryPlane; faces ((4 5 6 7)); }
            sides  { type symmetryPlane; faces ((0 1 5 4) (3 7 6 2)); }
        );

        """
        let inside = Vec3(a.x + 1, a.y + 1, d.buildingHeight * 3)
        let snappy = header("dictionary", "snappyHexMeshDict") + """
        castellatedMesh true;
        snap            true;
        addLayers       false;
        geometry { building { type triSurfaceMesh; file "building.stl"; } refinementBox { type searchableBox; min (\(f(a.x + 4 * d.buildingHeight)) \(f(a.y + 3 * d.buildingHeight)) 0); max (\(f(b.x - 10 * d.buildingHeight)) \(f(b.y - 3 * d.buildingHeight)) \(f(2 * d.buildingHeight))); } }
        castellatedMeshControls
        {
            maxLocalCells 2000000; maxGlobalCells 8000000; minRefinementCells 10; nCellsBetweenLevels 3; maxLoadUnbalance 0.1;
            features ();
            refinementSurfaces { building { level (\(o.refinement) \(o.refinement)); } }
            resolveFeatureAngle 30;
            refinementRegions { refinementBox { mode inside; levels ((1E15 1)); } }
            locationInMesh (\(f(inside.x)) \(f(inside.y)) \(f(inside.z)));
            allowFreeStandingZoneFaces true;
        }
        snapControls { nSmoothPatch 3; tolerance 2.0; nSolveIter 30; nRelaxIter 5; }
        addLayersControls { relativeSizes true; layers {} expansionRatio 1.0; finalLayerThickness 0.3; minThickness 0.1; nGrow 0; featureAngle 60; nRelaxIter 3; nSmoothSurfaceNormals 1; nSmoothNormals 3; nSmoothThickness 10; maxFaceThicknessRatio 0.5; maxThicknessToMedialRatio 0.3; minMedialAxisAngle 90; nBufferCellsNoExtrude 0; nLayerIter 50; }
        meshQualityControls { maxNonOrtho 65; maxBoundarySkewness 20; maxInternalSkewness 4; maxConcave 80; minVol 1e-13; minTetQuality 1e-15; minArea -1; minTwist 0.02; minDeterminant 0.001; minFaceWeight 0.05; minVolRatio 0.01; minTriangleTwist -1; nSmoothScale 4; errorReduction 0.75; }
        mergeTolerance 1e-6;

        """
        // Atmospheric boundary layer: u* = kappa U / ln((z + z0)/z0).
        let kappa = 0.41, cmu = 0.09
        let ustar = kappa * o.speed / log((o.referenceHeight + o.roughness) / o.roughness)
        let kIn = ustar * ustar / sqrt(cmu)
        let epsIn = pow(ustar, 3) / (kappa * (o.referenceHeight + o.roughness))
        let abl = """
                flowDir         (1 0 0);
                zDir            (0 0 1);
                Uref            \(f(o.speed));
                Zref            \(f(o.referenceHeight));
                z0              uniform \(f(o.roughness));
                zGround         uniform 0;
                d               uniform 0;
                kappa           \(kappa);
                Cmu             \(cmu);
        """
        func field(_ cls: String, _ name: String, dims: String, initial: String, inlet: String, wall: String) -> String {
            header(cls, name, location: "0") + """
            dimensions      \(dims);
            internalField   uniform \(initial);
            boundaryField
            {
                inlet    { \(inlet) }
                outlet   { type inletOutlet; inletValue uniform \(initial); value uniform \(initial); }
                ground   { \(wall) }
                building { \(wall) }
                top      { type symmetryPlane; }
                sides    { type symmetryPlane; }
            }

            """
        }
        let U = field("volVectorField", "U", dims: "[0 1 -1 0 0 0 0]", initial: "(\(f(o.speed)) 0 0)",
                      inlet: "type atmBoundaryLayerInletVelocity;\n" + abl + "\n        value uniform (\(f(o.speed)) 0 0);", wall: "type noSlip;")
            .replacingOccurrences(of: "outlet   { type inletOutlet; inletValue uniform (\(f(o.speed)) 0 0); value uniform (\(f(o.speed)) 0 0); }", with: "outlet   { type inletOutlet; inletValue uniform (0 0 0); value uniform (\(f(o.speed)) 0 0); }")
        let p = field("volScalarField", "p", dims: "[0 2 -2 0 0 0 0]", initial: "0", inlet: "type zeroGradient;", wall: "type zeroGradient;")
            .replacingOccurrences(of: "outlet   { type inletOutlet; inletValue uniform 0; value uniform 0; }", with: "outlet   { type fixedValue; value uniform 0; }")
        let kF = field("volScalarField", "k", dims: "[0 2 -2 0 0 0 0]", initial: f(kIn), inlet: "type atmBoundaryLayerInletK;\n" + abl + "\n        value uniform \(f(kIn));", wall: "type kqRWallFunction; value uniform \(f(kIn));")
        let eF = field("volScalarField", "epsilon", dims: "[0 2 -3 0 0 0 0]", initial: f(epsIn), inlet: "type atmBoundaryLayerInletEpsilon;\n" + abl + "\n        value uniform \(f(epsIn));",
                       wall: "type epsilonWallFunction; value uniform \(f(epsIn));")
            .replacingOccurrences(of: "ground   { type epsilonWallFunction; value uniform \(f(epsIn)); }", with: "ground   { type atmEpsilonWallFunction; z0 uniform \(f(o.roughness)); value uniform \(f(epsIn)); }")
        let nut = field("volScalarField", "nut", dims: "[0 2 -1 0 0 0 0]", initial: "0", inlet: "type calculated; value uniform 0;", wall: "type nutkWallFunction; value uniform 0;")
            .replacingOccurrences(of: "ground   { type nutkWallFunction; value uniform 0; }", with: "ground   { type nutkAtmRoughWallFunction; z0 uniform \(f(o.roughness)); value uniform 0; }")
        let control = header("dictionary", "controlDict") + """
        application     simpleFoam;
        startFrom       latestTime;
        startTime       0;
        stopAt          endTime;
        endTime         \(o.iterations);
        deltaT          1;
        writeControl    timeStep;
        writeInterval   \(max(1, o.iterations / 5));
        purgeWrite      2;
        writeFormat     ascii;
        writePrecision  8;
        runTimeModifiable true;
        functions
        {
            pedestrianLevel
            {
                type            surfaces;
                libs            (sampling);
                writeControl    onEnd;
                surfaceFormat   raw;
                fields          (U);
                interpolationScheme cellPoint;
                surfaces
                {
                    zPedestrian { type cuttingPlane; planeType pointAndNormal; point (0 0 \(f(o.sampleHeight))); normal (0 0 1); interpolate true; }
                }
            }
        }

        """
        let schemes = header("dictionary", "fvSchemes") + """
        ddtSchemes { default steadyState; }
        gradSchemes { default cellLimited Gauss linear 1; }
        divSchemes { default none; div(phi,U) bounded Gauss linearUpwind grad(U); div(phi,k) bounded Gauss upwind; div(phi,epsilon) bounded Gauss upwind; div((nuEff*dev2(T(grad(U))))) Gauss linear; }
        laplacianSchemes { default Gauss linear limited corrected 0.33; }
        interpolationSchemes { default linear; }
        snGradSchemes { default limited corrected 0.33; }
        wallDist { method meshWave; }

        """
        let solution = header("dictionary", "fvSolution") + """
        solvers
        {
            p { solver GAMG; tolerance 1e-6; relTol 0.1; smoother GaussSeidel; }
            "(U|k|epsilon)" { solver smoothSolver; smoother symGaussSeidel; tolerance 1e-6; relTol 0.1; }
        }
        SIMPLE { nNonOrthogonalCorrectors 0; consistent yes; residualControl { p 1e-4; U 1e-4; "(k|epsilon)" 1e-4; } }
        relaxationFactors { equations { U 0.9; ".*" 0.9; } }

        """
        let transport = header("dictionary", "transportProperties", location: "constant") + "transportModel  Newtonian;\nnu              1.5e-05;\n"
        let turbulence = header("dictionary", "turbulenceProperties", location: "constant") + "simulationType RAS;\nRAS { RASModel kEpsilon; turbulence on; printCoeffs on; }\n"
        let decompose = header("dictionary", "decomposeParDict") + "numberOfSubdomains 4;\nmethod scotch;\n"
        let allrun = """
        #!/bin/sh
        # Oanarina Archi Tool wind study: run inside an OpenFOAM environment (v2012+ or 9+).
        cd "${0%/*}" || exit 1
        blockMesh > log.blockMesh 2>&1 || exit 1
        snappyHexMesh -overwrite > log.snappyHexMesh 2>&1 || exit 1
        simpleFoam > log.simpleFoam 2>&1 || exit 1
        echo "Done: postProcessing/pedestrianLevel/*/zPedestrian/ holds the pedestrian-level velocities (WINDRESULTS imports them)."

        """
        let readme = """
        Wind study case written by Oanarina Archi Tool.
        Wind \(f(o.speed)) m/s at \(f(o.referenceHeight)) m from \(f(o.direction))° (z0 = \(f(o.roughness)) m); the model is rotated so the wind blows along +X.
        Rotation applied to the model (radians, about Z): \(f(-flowAngle(o, northAngle: doc.info.northAngle)))
        Domain \(f(b.x - a.x)) × \(f(b.y - a.y)) × \(f(b.z - a.z)) m, \(d.cells.0)×\(d.cells.1)×\(d.cells.2) background cells, building height \(f(d.buildingHeight)) m.
        Run ./Allrun, then import the result with WINDRESULTS.

        """
        return ["constant/triSurface/building.stl": stl, "system/blockMeshDict": blockMesh, "system/snappyHexMeshDict": snappy,
                "system/controlDict": control, "system/fvSchemes": schemes, "system/fvSolution": solution, "system/decomposeParDict": decompose,
                "constant/transportProperties": transport, "constant/turbulenceProperties": turbulence,
                "0/U": U, "0/p": p, "0/k": kF, "0/epsilon": eF, "0/nut": nut, "Allrun": allrun, "README.txt": readme]
    }

    /// Writes the case folder (created if needed). Returns the written relative paths.
    @discardableResult
    public static func writeCase(_ doc: ArchiDocument, to dir: URL, options: Options) throws -> [String] {
        let files = try caseFiles(doc, options: options)
        let fm = FileManager.default
        for (rel, text) in files {
            let u = dir.appendingPathComponent(rel)
            try fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: u, atomically: true, encoding: .utf8)
        }
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.appendingPathComponent("Allrun").path)
        return files.keys.sorted()
    }

    // MARK: Results

    public struct Sample: Hashable { public var p: Vec3; public var u: Vec3; public var speed: Double { u.length } }

    /// Parses a raw surface sample ("x y z Ux Uy Uz" rows, '#' comments).
    public static func parseSamples(_ text: String) -> [Sample] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, !t.hasPrefix("#") else { return nil }
            let v = t.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "," }).compactMap { Double($0) }
            guard v.count >= 6 else { return nil }
            return Sample(p: Vec3(v[0], v[1], v[2]), u: Vec3(v[3], v[4], v[5]))
        }
    }

    /// Lawson-style pedestrian comfort class of a mean speed (m/s).
    public static func comfortClass(_ speed: Double) -> String {
        switch speed { case ..<2.5: return "Sitting"; case ..<4: return "Standing"; case ..<6: return "Strolling"; case ..<8: return "Business walking"; default: return "Uncomfortable" }
    }

    /// Wind arrows on layer WIND in drawing coordinates (the case rotation is undone), thinned to a grid of `spacing` m.
    public static func arrows(_ samples: [Sample], doc: ArchiDocument, options o: Options, spacing: Double = 2) -> [Entity] {
        let k = 1000 / doc.units.mm
        let a = flowAngle(o, northAngle: doc.info.northAngle)
        let ca = cos(a), sa = sin(a)
        var seen = Set<String>()
        var out: [Entity] = []
        let vmax = max(samples.map(\.speed).max() ?? 1, 1e-9)
        for s in samples {
            let key = "\(Int((s.p.x / spacing).rounded())),\(Int((s.p.y / spacing).rounded()))"
            guard seen.insert(key).inserted else { continue }
            let p = Vec2(s.p.x * ca - s.p.y * sa, s.p.x * sa + s.p.y * ca) * k
            let d = Vec2(s.u.x * ca - s.u.y * sa, s.u.x * sa + s.u.y * ca)
            guard d.length > 1e-9 else { continue }
            let len = spacing * 0.8 * k * s.speed / vmax
            let e = p + d.normalized * len
            let t = s.speed / vmax
            let color = ColorRef.rgb(UInt8(255 * t), UInt8(255 * (1 - abs(t - 0.5) * 2)), UInt8(255 * (1 - t)))
            let head = d.normalized * (len * 0.25)
            let l1 = e - head.rotated(by: 0.4), l2 = e - head.rotated(by: -0.4)
            out.append(Entity(layer: "WIND", color: color, geometry: .polyline(PolylineGeom(points: [p, e])), props: ["speed": fmt(s.speed, 2), "comfort": comfortClass(s.speed)]))
            out.append(Entity(layer: "WIND", color: color, geometry: .polyline(PolylineGeom(points: [l1, e, l2])), props: ["speed": fmt(s.speed, 2)]))
        }
        return out
    }
}
