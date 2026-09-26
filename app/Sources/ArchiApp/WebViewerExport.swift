// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation
import ArchiCore

/// Standalone HTML/WebGL 2 viewer of the 3D model (VIS-087): one file, no external scripts; meshes merged per
/// material (metres, Y up), orbit with drag, pan with Shift-drag or right-drag, zoom with the wheel, and view buttons.
enum WebViewerExport {
    struct Batch: Codable { var name: String; var color: [Double]; var opacity: Double; var p: [Double]; var n: [Double]; var i: [UInt32] }
    struct Scene: Codable { var title: String; var batches: [Batch]; var center: [Double]; var radius: Double; var triangles: Int }

    static func scene(doc: ArchiDocument) -> Scene {
        var byMat: [String: Batch] = [:]
        var order: [String] = []
        var b = BBox3.empty
        func r(_ v: Double) -> Double { (v * 1000).rounded() / 1000 }
        for g in MeshBuilder.build(doc: doc) where !g.mesh.positions.isEmpty {
            let key = g.material
            if byMat[key] == nil {
                let m = doc.material(key)
                let c = m?.color ?? RGBA(0.8, 0.8, 0.8)
                byMat[key] = Batch(name: key, color: [c.r, c.g, c.b], opacity: 1 - min(max(m?.transparency ?? 0, 0), 0.9), p: [], n: [], i: [])
                order.append(key)
            }
            var batch = byMat[key]!
            let base = UInt32(batch.p.count / 3)
            let hasN = g.mesh.normals.count == g.mesh.positions.count
            for (k, p) in g.mesh.positions.enumerated() {
                b.add(p)
                batch.p += [r(p.x * 0.001), r(p.z * 0.001), r(-p.y * 0.001)]
                let nn = hasN ? g.mesh.normals[k] : Vec3(0, 0, 1)
                batch.n += [r(nn.x), r(nn.z), r(-nn.y)]
            }
            batch.i += g.mesh.indices.map { $0 + base }
            byMat[key] = batch
        }
        let batches = order.compactMap { byMat[$0] }
        let c = b.isEmpty ? Vec3.zero : b.center
        return Scene(title: doc.info.name, batches: batches, center: [c.x * 0.001, c.z * 0.001, -c.y * 0.001],
                     radius: b.isEmpty ? 10 : max(b.size.length * 0.0005, 1), triangles: batches.reduce(0) { $0 + $1.i.count / 3 })
    }

    static func html(doc: ArchiDocument) -> String {
        let s = scene(doc: doc)
        let json = (try? String(data: JSONEncoder().encode(s), encoding: .utf8)) ?? "{}"
        let title = s.title.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        return """
        <!DOCTYPE html>
        <html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>\(title) — 3D viewer</title>
        <meta name="generator" content="Oanarina Archi Tool">
        <style>html,body{margin:0;height:100%;background:#1e1f22;color:#e6e6e6;font:13px -apple-system,Helvetica,sans-serif;overflow:hidden}
        canvas{width:100%;height:100%;display:block;touch-action:none}#bar{position:fixed;left:12px;top:12px;display:flex;gap:6px;align-items:center}
        #bar button{background:#2f3035;color:#e6e6e6;border:1px solid #444;border-radius:6px;padding:4px 10px;cursor:pointer}#bar button:hover{border-color:#F5C518}
        #t{font-weight:600;margin-right:8px}#help{position:fixed;left:12px;bottom:10px;opacity:.6;font-size:12px}</style></head>
        <body><canvas id="c"></canvas>
        <div id="bar"><span id="t">\(title)</span><button data-v="iso">Iso</button><button data-v="top">Top</button><button data-v="front">Front</button><button data-v="right">Right</button></div>
        <div id="help">Drag to orbit · Shift-drag or right-drag to pan · wheel to zoom · \(s.triangles) triangles · Oanarina Archi Tool</div>
        <script id="model" type="application/json">\(json)</script>
        <script>
        (function(){
        const S=JSON.parse(document.getElementById('model').textContent);
        const cv=document.getElementById('c');const gl=cv.getContext('webgl2',{antialias:true});
        if(!gl){document.body.innerHTML='<p style="padding:20px">WebGL 2 is not available in this browser.</p>';return;}
        const vs=`#version 300 es
        in vec3 p;in vec3 n;uniform mat4 mvp;out vec3 vn;void main(){vn=n;gl_Position=mvp*vec4(p,1.0);}`;
        const fs=`#version 300 es
        precision mediump float;in vec3 vn;uniform vec3 col;uniform float op;out vec4 o;
        void main(){vec3 l=normalize(vec3(-0.45,0.75,0.5));float d=abs(dot(normalize(vn),l));o=vec4(col*(0.35+0.65*d),op);}`;
        function sh(t,s){const x=gl.createShader(t);gl.shaderSource(x,s);gl.compileShader(x);return x;}
        const pr=gl.createProgram();gl.attachShader(pr,sh(gl.VERTEX_SHADER,vs));gl.attachShader(pr,sh(gl.FRAGMENT_SHADER,fs));gl.linkProgram(pr);gl.useProgram(pr);
        const L={p:gl.getAttribLocation(pr,'p'),n:gl.getAttribLocation(pr,'n'),mvp:gl.getUniformLocation(pr,'mvp'),col:gl.getUniformLocation(pr,'col'),op:gl.getUniformLocation(pr,'op')};
        const B=S.batches.map(b=>{const va=gl.createVertexArray();gl.bindVertexArray(va);
          const pb=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,pb);gl.bufferData(gl.ARRAY_BUFFER,new Float32Array(b.p),gl.STATIC_DRAW);gl.enableVertexAttribArray(L.p);gl.vertexAttribPointer(L.p,3,gl.FLOAT,false,0,0);
          const nb=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,nb);gl.bufferData(gl.ARRAY_BUFFER,new Float32Array(b.n),gl.STATIC_DRAW);gl.enableVertexAttribArray(L.n);gl.vertexAttribPointer(L.n,3,gl.FLOAT,false,0,0);
          const ib=gl.createBuffer();gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER,ib);gl.bufferData(gl.ELEMENT_ARRAY_BUFFER,new Uint32Array(b.i),gl.STATIC_DRAW);
          return {va:va,count:b.i.length,col:b.color,op:b.opacity};});
        let tgt=S.center.slice(),dist=S.radius*2.6,yaw=-0.785,pitch=0.52;
        function view(v){if(v==='top'){yaw=0;pitch=1.5699;}else if(v==='front'){yaw=0;pitch=0;}else if(v==='right'){yaw=1.5708;pitch=0;}else{yaw=-0.785;pitch=0.52;}tgt=S.center.slice();dist=S.radius*2.6;draw();}
        document.querySelectorAll('#bar button').forEach(b=>b.onclick=()=>view(b.dataset.v));
        function persp(f,a,n,fa){const t=1/Math.tan(f/2);return[t/a,0,0,0,0,t,0,0,0,0,(fa+n)/(n-fa),-1,0,0,2*fa*n/(n-fa),0];}
        function mul(a,b){const o=new Array(16).fill(0);for(let c=0;c<4;c++)for(let r=0;r<4;r++)for(let k=0;k<4;k++)o[c*4+r]+=a[k*4+r]*b[c*4+k];return o;}
        function look(e,c){const f=norm([c[0]-e[0],c[1]-e[1],c[2]-e[2]]);const s=norm(cross(f,[0,1,0]));const u=cross(s,f);
          return[s[0],u[0],-f[0],0,s[1],u[1],-f[1],0,s[2],u[2],-f[2],0,-dot(s,e),-dot(u,e),dot(f,e),1];}
        function cross(a,b){return[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]];}
        function dot(a,b){return a[0]*b[0]+a[1]*b[1]+a[2]*b[2];}
        function norm(a){const l=Math.hypot(a[0],a[1],a[2])||1;return[a[0]/l,a[1]/l,a[2]/l];}
        function eye(){return[tgt[0]+dist*Math.cos(pitch)*Math.sin(yaw),tgt[1]+dist*Math.sin(pitch),tgt[2]+dist*Math.cos(pitch)*Math.cos(yaw)];}
        function draw(){const w=cv.clientWidth*devicePixelRatio,h=cv.clientHeight*devicePixelRatio;if(cv.width!==w||cv.height!==h){cv.width=w;cv.height=h;}
          gl.viewport(0,0,w,h);gl.clearColor(0.118,0.122,0.133,1);gl.clear(gl.COLOR_BUFFER_BIT|gl.DEPTH_BUFFER_BIT);gl.enable(gl.DEPTH_TEST);
          gl.enable(gl.BLEND);gl.blendFunc(gl.SRC_ALPHA,gl.ONE_MINUS_SRC_ALPHA);
          const m=mul(persp(0.8,w/Math.max(h,1),Math.max(dist/500,0.01),dist*20+S.radius*4),look(eye(),tgt));gl.uniformMatrix4fv(L.mvp,false,new Float32Array(m));
          const sorted=B.slice().sort((a,b)=>b.op-a.op);
          for(const b of sorted){gl.depthMask(b.op>0.99);gl.uniform3fv(L.col,b.col);gl.uniform1f(L.op,b.op);gl.bindVertexArray(b.va);gl.drawElements(gl.TRIANGLES,b.count,gl.UNSIGNED_INT,0);}
          gl.depthMask(true);}
        let drag=null;cv.oncontextmenu=e=>e.preventDefault();
        cv.onpointerdown=e=>{drag={x:e.clientX,y:e.clientY,pan:e.shiftKey||e.button===2};cv.setPointerCapture(e.pointerId);};
        cv.onpointerup=()=>drag=null;
        cv.onpointermove=e=>{if(!drag)return;const dx=e.clientX-drag.x,dy=e.clientY-drag.y;drag.x=e.clientX;drag.y=e.clientY;
          if(drag.pan){const k=dist*0.0015;const s=[Math.cos(yaw),0,-Math.sin(yaw)];tgt[0]-=s[0]*dx*k;tgt[2]-=s[2]*dx*k;tgt[1]+=dy*k;}
          else{yaw-=dx*0.006;pitch=Math.max(-1.5699,Math.min(1.5699,pitch+dy*0.006));}draw();};
        cv.onwheel=e=>{e.preventDefault();dist*=Math.exp(e.deltaY*0.0015);dist=Math.max(0.2,dist);draw();};
        addEventListener('resize',draw);draw();
        })();
        </script></body></html>
        """
    }
}
