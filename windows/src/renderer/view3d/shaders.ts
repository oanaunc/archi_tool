// Oanarina Archi Tool for Windows — GPL-3.0-or-later
// GLSL ES 3.00 shaders of the 3D view. The model is drawn in world metres, Z up (model millimetres × 0.001).
// Lighting follows the Mac's SceneKit set-up (Viewport3DView.swift Scene3DBuilder, BeautyLighting.swift):
// physically based sun + HDR sky (image-based lighting) for Realistic, Blinn / Lambert / constant for the other styles.

const header = `#version 300 es
precision highp float;
precision highp int;
precision highp sampler2D;
`;

/** Leaf-cluster lumps of BeautyLighting.foliageLumps (model millimetres). */
const foliage = `
vec3 foliageLumps(vec3 p, vec3 n) {
  vec3 q = p * 0.0042;
  float k = sin(q.x * 1.7 + sin(q.y * 2.3)) * sin(q.y * 1.9 + sin(q.z * 2.1)) * sin(q.z * 2.2 + sin(q.x * 1.3));
  vec3 r = p * 0.011;
  k += 0.5 * sin(r.x * 1.3 + sin(r.z * 1.7)) * sin(r.y * 1.1 + sin(r.x * 2.3)) * sin(r.z * 1.9 + sin(r.y * 1.5));
  return p + n * k * 140.0;
}
`;

export const meshVS = header + foliage + `
layout(location = 0) in vec3 aPos;
layout(location = 1) in vec3 aNormal;
layout(location = 2) in vec2 aUV;
uniform mat4 uViewProj;
uniform mat4 uModel;          // model-mm transform of the mesh (gizmo preview, exploded levels, animations)
uniform float uFoliage;
uniform float uUVScale;
uniform float uUnit;
out vec3 vWorld;
out vec3 vNormal;
out vec2 vUV;
void main() {
  vec3 p = aPos;
  if (uFoliage > 0.5) p = foliageLumps(p, aNormal);
  p = (uModel * vec4(p, 1.0)).xyz;
  vWorld = p * uUnit;
  vNormal = mat3(uModel) * aNormal;
  vUV = aUV * uUVScale;
  gl_Position = uViewProj * vec4(vWorld, 1.0);
}
`;

export const meshFS = header + `
in vec3 vWorld;
in vec3 vNormal;
in vec2 vUV;
layout(location = 0) out vec4 outColor;
// Indirect light (image-based diffuse + ambient) on its own: SceneKit's SSAO darkens only that part.
layout(location = 1) out vec4 outIndirect;

uniform int uMode;            // 0 physically based, 1 Blinn, 2 Lambert, 3 constant (unlit)
uniform vec3 uColor;          // linear base colour
uniform float uOpacity;
uniform int uHasTex;
uniform sampler2D uAlbedo;
uniform vec3 uMultiply;       // linear tint multiplied into the texture
uniform int uHasNormal;
uniform sampler2D uNormalMap;
uniform float uNormalStrength;
uniform int uHasRough;
uniform sampler2D uRoughMap;
uniform float uRoughness;
uniform float uRoughGamma;
uniform float uMetalness;
uniform float uSpecular;      // Blinn specular level
uniform float uShininess;
uniform vec3 uEmissive;
uniform int uCutout;

uniform vec3 uCamPos;
uniform vec3 uViewDir;        // for orthographic views
uniform int uOrtho;

uniform vec3 uSunDir;         // towards the sun
uniform vec3 uSunColor;       // colour × intensity (1 = SceneKit 1000)
uniform int uShadows;
uniform sampler2D uShadowMap;
uniform mat4 uShadowMat;
uniform float uShadowRadius;  // in shadow-map texels
uniform float uShadowAlpha;
uniform float uLampSunShadow;
uniform float uShadowTexel;
uniform float uShadowBias;
uniform float uShadowRange;   // depth range of the sun's orthographic shadow camera (m)
uniform float uSlopeTexels;   // largest filter radius (texels) the slope bias covers
uniform int uShadowSamples;

uniform vec3 uSH[9];
uniform float uEnvIntensity;
uniform float uEnvDiffuse;
uniform float uEnvSide;       // image-based light on vertical and downward faces relative to up-facing ones (Renderer.ENV_SIDE)
uniform float uEnvSideSpec;   // the same for the image-based specular of opaque dielectrics (Renderer.ENV_SIDE_SPECULAR)
uniform int uHasEnv;
uniform sampler2D uEnv;
uniform float uEnvMaxLod;
uniform vec3 uAmbient;

uniform vec4 uFog;            // start, end, exponent, on
uniform vec3 uFogColor;

uniform int uNumLights;
uniform vec4 uLightPos[16];   // xyz, w = attenuation end distance
uniform vec4 uLightColor[16]; // rgb × intensity, w = 0 point, 1 spot, 2 area (Lambertian emitter), 3 IES (spot + profile)
uniform sampler2D uIES;        // 32 × 16 relative candela by vertical angle 0…180° (row = light), IES lights
uniform vec4 uLightDir[16];   // xyz = direction the spot points, w = cos(outer/2)
uniform float uLightInner[16];// cos(inner/2)
uniform int uNumSpotShadows;   // spot / IES shadow maps, 2 × 2 atlas (tile k: light uSpotShadowLight[k], uSpotShadowMat[k])
uniform int uSpotShadowLight[4];
uniform mat4 uSpotShadowMat[4];
uniform sampler2D uSpotShadowMap;
uniform float uSpotShadowAlpha;
uniform float uSpotShadowRadius; // in shadow-map texels
uniform vec2 uSpotNearFar;       // SCNLight zNear / zFar (m)

uniform vec4 uClipMin;        // section box (w = on)
uniform vec4 uClipMax;
uniform vec4 uPlaneP;         // section plane (w = on)
uniform vec4 uPlaneN;
uniform vec3 uHighlight;      // selection emission
uniform float uSnow;          // snow cover on up-facing faces (WEATHER)
uniform float uWet;           // rain wetness
uniform int uWater;           // animated water waves (WaterSurface)
uniform float uTime;

const float PI = 3.14159265359;

// Equirect lookup with SceneKit's orientation of background / lighting-environment images: the texel made for the
// Panorama direction (y, z, x) is the one seen along model direction (x, y, z) (measured on the Mac renders).
vec2 equirect(vec3 d) {
  return vec2(atan(d.y, -d.x) / (2.0 * PI) + 0.5, 0.5 - asin(clamp(d.z, -1.0, 1.0)) / PI);
}

vec3 shIrradiance(vec3 n) {
  float x = n.x, y = n.y, z = n.z;
  return max(vec3(0.0),
    uSH[0] * 0.282095 + uSH[1] * 0.488603 * y + uSH[2] * 0.488603 * z + uSH[3] * 0.488603 * x +
    uSH[4] * 1.092548 * x * y + uSH[5] * 1.092548 * y * z + uSH[6] * 0.315392 * (3.0 * z * z - 1.0) +
    uSH[7] * 1.092548 * x * z + uSH[8] * 0.546274 * (x * x - y * y));
}

mat3 cotangentFrame(vec3 N, vec3 p, vec2 uv) {
  vec3 dp1 = dFdx(p), dp2 = dFdy(p);
  vec2 duv1 = dFdx(uv), duv2 = dFdy(uv);
  vec3 dp2perp = cross(dp2, N), dp1perp = cross(N, dp1);
  vec3 T = dp2perp * duv1.x + dp1perp * duv2.x;
  vec3 B = dp2perp * duv1.y + dp1perp * duv2.y;
  float m = max(dot(T, T), dot(B, B));
  if (m < 1e-20) return mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), N);
  float inv = inversesqrt(m);
  return mat3(T * inv, B * inv, N);
}

float hash12(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }

float sunShadow(vec3 wp, vec3 n, float cosL) {
  if (uShadows == 0) return 1.0;
  vec4 sp = uShadowMat * vec4(wp + n * uShadowTexel * 1.5, 1.0);
  vec3 s = sp.xyz / sp.w * 0.5 + 0.5;
  if (s.x <= 0.0 || s.x >= 1.0 || s.y <= 0.0 || s.y >= 1.0 || s.z >= 1.0) return 1.0;
  // Slope-scaled bias over the filter footprint: a surface lit at a grazing angle (low sun on the ground) must not
  // shadow itself inside the soft-shadow kernel (the Mac renders show clean pavement at golden hour).
  float tanL = sqrt(max(1.0 - cosL * cosL, 0.0)) / max(cosL, 0.05);
  float footprint = (clamp(uShadowRadius, 0.75, uSlopeTexels) + 1.0) * uShadowTexel;
  float bias = uShadowBias + min(footprint * tanL / max(uShadowRange, 1e-3), 0.02);
  float r = max(uShadowRadius, 0.75) / float(textureSize(uShadowMap, 0).x);
  float a0 = hash12(gl_FragCoord.xy) * 6.2831853;
  float lit = 0.0;
  int n0 = uShadowSamples;
  for (int i = 0; i < 32; i++) {
    if (i >= n0) break;
    float fi = float(i) + 0.5;
    float rr = sqrt(fi / float(n0));
    float a = a0 + fi * 2.39996323;
    vec2 o = vec2(cos(a), sin(a)) * rr * r;
    float d = texture(uShadowMap, s.xy + o).r;
    lit += (s.z - bias <= d) ? 1.0 : 0.0;
  }
  return lit / float(n0);
}

// Shadow of spot light tile k (SceneKit castsShadow, 8 samples): 1 − alpha × the blocked share of the samples.
float spotShadow(int k, vec3 wp) {
  vec4 sp = uSpotShadowMat[k] * vec4(wp, 1.0);
  float z = sp.w;   // distance along the spot's axis (m)
  if (z <= uSpotNearFar.x || z >= uSpotNearFar.y) return 1.0;
  vec2 uv = sp.xy / z * 0.5 + 0.5;
  if (uv.x <= 0.0 || uv.x >= 1.0 || uv.y <= 0.0 || uv.y >= 1.0) return 1.0;
  float texel = 1.0 / float(textureSize(uSpotShadowMap, 0).x);
  vec2 tile = vec2(float(k % 2), float(k / 2)) * 0.5;
  vec2 lo = tile + texel, hi = tile + 0.5 - texel;
  vec2 c = tile + uv * 0.5;
  float bias = 0.01 + z * 0.004;   // grows with the texel footprint of the perspective map
  float a0 = hash12(gl_FragCoord.xy + float(k) * 7.0) * 6.2831853;
  float lit = 0.0;
  for (int i = 0; i < 8; i++) {
    float fi = float(i) + 0.5;
    float a = a0 + fi * 2.39996323;
    vec2 o = vec2(cos(a), sin(a)) * sqrt(fi / 8.0) * uSpotShadowRadius * texel;
    float d = texture(uSpotShadowMap, clamp(c + o, lo, hi)).r;
    float zl = uSpotNearFar.x * uSpotNearFar.y / (uSpotNearFar.y - d * (uSpotNearFar.y - uSpotNearFar.x));
    lit += (z - bias <= zl) ? 1.0 : 0.0;
  }
  return 1.0 - uSpotShadowAlpha * (1.0 - lit / 8.0);
}

float D_GGX(float NdH, float a) { float a2 = a * a; float d = NdH * NdH * (a2 - 1.0) + 1.0; return a2 / (PI * d * d); }
float V_Smith(float NdV, float NdL, float a) {
  float k = a * 0.5;
  return 0.25 / max((NdV * (1.0 - k) + k) * (NdL * (1.0 - k) + k), 1e-4);
}
vec3 F_Schlick(vec3 F0, float c) { return F0 + (1.0 - F0) * pow(1.0 - c, 5.0); }
vec3 envBRDF(vec3 F0, float rough, float NdV) {
  const vec4 c0 = vec4(-1.0, -0.0275, -0.572, 0.022);
  const vec4 c1 = vec4(1.0, 0.0425, 1.04, -0.04);
  vec4 r = rough * c0 + c1;
  float a004 = min(r.x * r.x, exp2(-9.28 * NdV)) * r.x + r.y;
  vec2 AB = vec2(-1.04, 1.04) * a004 + r.zw;
  return F0 * AB.x + AB.y;
}

void main() {
  outIndirect = vec4(0.0);
  if (uClipMax.w > 0.5 && (any(lessThan(vWorld, uClipMin.xyz)) || any(greaterThan(vWorld, uClipMax.xyz)))) discard;
  if (uPlaneN.w > 0.5 && dot(vWorld - uPlaneP.xyz, uPlaneN.xyz) > 0.0) discard;

  vec3 albedo = uColor;
  float alpha = uOpacity;
  if (uHasTex == 1) {
    vec4 t = texture(uAlbedo, vUV);
    albedo = t.rgb * uMultiply;
  }
  // BeautyLighting.foliageCutout reads _surface.diffuse: the texture before SceneKit's multiply tint.
  if (uCutout == 1 && dot(uHasTex == 1 ? texture(uAlbedo, vUV).rgb : albedo, vec3(0.3, 0.59, 0.11)) < 0.075) discard;
  if (uCutout == 2 && uHasTex == 1 && texture(uAlbedo, vUV).a < 0.5) discard;

  if (uMode == 3) {
    vec3 c = albedo + uEmissive + uHighlight;
    outColor = vec4(c, alpha);
    return;
  }

  vec3 N = normalize(vNormal);
  vec3 V = uOrtho == 1 ? -uViewDir : normalize(uCamPos - vWorld);
  if (!gl_FrontFacing) N = -N;
  // Weather (WeatherSettings.shaderModifier): snow on faces whose normal points up, rain darkens and adds gloss.
  float wetRough = 1.0, snowCover = 0.0;
  if (uSnow > 0.0 || uWet > 0.0) {
    snowCover = uSnow * smoothstep(0.45, 0.85, N.z);
    albedo = mix(albedo * (1.0 - 0.3 * uWet), vec3(0.93, 0.94, 0.96), snowCover);
    wetRough = 1.0 - 0.65 * uWet;
  }
  // Water (WaterSurface.shaderModifier): travelling waves on up-facing faces, SceneKit world (x, z = −y) metres.
  if (uWater == 1 && N.z > 0.5) {
    vec3 wp = vec3(vWorld.x, vWorld.z, -vWorld.y);
    float t = uTime;
    float gx = cos(wp.x * 6.98 + wp.z * 2.09 + t * 1.1) * 0.5 + cos(wp.x * 7.2 - wp.z * 7.2 + t * 2.3) * 0.3 + cos(wp.x * 2.3 + wp.z * 10.3 + t * 3.1) * 0.2;
    float gz = cos(-wp.x * 4.1 + wp.z * 10.3 + t * 1.7) * 0.5 + cos(wp.x * 7.2 + wp.z * 7.2 + t * 2.3) * 0.3 + cos(wp.x * 9.9 - wp.z * 2.2 + t * 2.7) * 0.2;
    N = normalize(vec3(-gx * 0.12, gz * 0.12, 1.0));
  }
  if (uHasNormal == 1) {
    vec3 m = texture(uNormalMap, vUV).xyz * 2.0 - 1.0;
    m.y = -m.y;
    m.xy *= uNormalStrength;
    mat3 TBN = cotangentFrame(N, vWorld, vUV);
    N = normalize(TBN * m);
  }
  float NdV = max(dot(N, V), 1e-4);
  vec3 L = normalize(uSunDir);
  float NdL = max(dot(N, L), 0.0);
  // SceneKit deferred shadows: a screen-space pass darkens the whole shaded pixel (sun, sky light, lamps, emission)
  // by the shadow colour's alpha where the sun is blocked; surfaces turned away from the sun count as shadowed.
  vec3 Ng = normalize(vNormal) * (gl_FrontFacing ? 1.0 : -1.0);
  float NgL = dot(Ng, L);
  float vis = 1.0;
  if (uShadows == 1) vis = NgL > 0.0 ? sunShadow(vWorld, Ng, NgL) * smoothstep(0.0, 0.08, NgL) : 0.0;
  float shadowK = 1.0 - uShadowAlpha * (1.0 - vis);
  const float lightK = 1.0;
  vec3 color;
  vec3 lamps = vec3(0.0);   // placed lights: darkened by uLampSunShadow of the sun's deferred shadow
  vec3 indirect = vec3(0.0);

  if (uMode == 0) {
    float rough = uRoughness;
    if (uHasRough == 1) rough = pow(texture(uRoughMap, vUV).g, uRoughGamma);
    rough = mix(rough * wetRough, 0.75, snowCover);
    rough = clamp(rough, 0.03, 1.0);
    float a = rough * rough;
    float metal = clamp(uMetalness, 0.0, 1.0);
    vec3 F0 = mix(vec3(0.04), albedo, metal);
    vec3 diff = albedo * (1.0 - metal);
    vec3 Lo = vec3(0.0);
    vec3 Lamp = vec3(0.0);
    if (NdL > 0.0) {
      vec3 H = normalize(L + V);
      float NdH = max(dot(N, H), 0.0), VdH = max(dot(V, H), 0.0);
      vec3 F = F_Schlick(F0, VdH);
      vec3 spec = D_GGX(NdH, a) * V_Smith(NdV, NdL, a) * F;
      Lo += (diff * (1.0 - F) + PI * spec) * uSunColor * NdL * lightK;
    }
    for (int i = 0; i < 16; i++) {
      if (i >= uNumLights) break;
      vec3 d = uLightPos[i].xyz - vWorld;
      float dist = length(d);
      vec3 l = d / max(dist, 1e-4);
      // SceneKit attenuation: full at the light, falling to zero at the end distance with exponent 2.
      float att = pow(clamp(1.0 - dist / uLightPos[i].w, 0.0, 1.0), 2.0);
      float kind = uLightColor[i].w;
      float c = dot(-l, normalize(uLightDir[i].xyz));
      if (kind > 0.5 && kind < 1.5) att *= smoothstep(uLightDir[i].w, uLightInner[i], c);
      else if (kind > 1.5 && kind < 2.5) att *= max(c, 0.0);
      else if (kind > 2.5) {
        // IES: the photometric web's relative intensity at the vertical angle from the aiming direction.
        float a = acos(clamp(c, -1.0, 1.0)) / PI;
        att *= texture(uIES, vec2((a * 31.0 + 0.5) / 32.0, (float(i) + 0.5) / 16.0)).r;
      }
      float nl = max(dot(N, l), 0.0);
      if (att <= 0.0 || nl <= 0.0) continue;
      for (int k = 0; k < 4; k++) if (k < uNumSpotShadows && uSpotShadowLight[k] == i) att *= spotShadow(k, vWorld);
      vec3 H = normalize(l + V);
      float NdH = max(dot(N, H), 0.0), VdH = max(dot(V, H), 0.0);
      vec3 F = F_Schlick(F0, VdH);
      vec3 spec = D_GGX(NdH, a) * V_Smith(NdV, nl, a) * F;
      Lamp += (diff * (1.0 - F) + PI * spec) * uLightColor[i].rgb * nl * att;
    }
    // SceneKit's diffuse image-based light, relative to lights of intensity / 1000 (measured on the Mac renders).
    // SceneKit's image-based light on faces turned away from the zenith is weaker than the cosine-weighted irradiance
    // and the split-sum specular give (measured on the Mac renders: walls and cedar under the overcast sky).
    float up = clamp(N.z, 0.0, 1.0);
    vec3 amb = diff * (shIrradiance(N) * uEnvIntensity * uEnvDiffuse * mix(uEnvSide, 1.0, up) + uAmbient);
    vec3 specEnv = vec3(0.0);
    if (uHasEnv == 1) {
      vec3 R = reflect(-V, N);
      vec3 env = textureLod(uEnv, equirect(normalize(R)), rough * uEnvMaxLod).rgb;
      specEnv = env * envBRDF(F0, rough, NdV) * uEnvIntensity * (alpha < 1.0 || metal > 0.5 ? 1.0 : mix(uEnvSideSpec, 1.0, up));
    }
    color = Lo + amb + specEnv;
    indirect = amb;
    lamps = Lamp;
    // Transparent dielectrics keep their reflection when their base colour fades.
    if (alpha < 1.0) {
      float f = pow(1.0 - NdV, 5.0);
      alpha = clamp(alpha + (1.0 - alpha) * f * 0.6, 0.0, 1.0);
    }
  } else {
    vec3 amb = albedo * uAmbient;
    vec3 dif = albedo * uSunColor * NdL * lightK;
    vec3 spc = vec3(0.0);
    if (uMode == 1 && NdL > 0.0) {
      vec3 H = normalize(L + V);
      spc = vec3(uSpecular) * pow(max(dot(N, H), 0.0), uShininess) * uSunColor * lightK;
    }
    color = amb + dif + spc;
    indirect = amb;
  }
  color += uEmissive;
  color = color * shadowK + lamps * mix(1.0, shadowK, uLampSunShadow) + uHighlight;
  indirect *= shadowK;

  if (uFog.w > 0.5) {
    float d = length(vWorld - uCamPos);
    float f = pow(clamp((d - uFog.x) / max(uFog.y - uFog.x, 1e-3), 0.0, 1.0), uFog.z);
    color = mix(color, uFogColor, f);
    indirect *= 1.0 - f;
  }
  outColor = vec4(color, alpha);
  outIndirect = vec4(indirect, alpha);
}
`;

export const shadowVS = header + foliage + `
layout(location = 0) in vec3 aPos;
layout(location = 1) in vec3 aNormal;
layout(location = 2) in vec2 aUV;
uniform mat4 uViewProj;
uniform mat4 uModel;
uniform float uFoliage;
uniform float uUVScale;
uniform float uUnit;
out vec2 vUV;
void main() {
  vec3 p = aPos;
  if (uFoliage > 0.5) p = foliageLumps(p, aNormal);
  p = (uModel * vec4(p, 1.0)).xyz;
  vUV = aUV * uUVScale;
  gl_Position = uViewProj * vec4(p * uUnit, 1.0);
}
`;

export const shadowFS = header + `
in vec2 vUV;
uniform int uCutout;
uniform sampler2D uAlbedo;
uniform vec3 uMultiply;
out vec4 o;
void main() {
  if (uCutout == 1 && dot(texture(uAlbedo, vUV).rgb, vec3(0.3, 0.59, 0.11)) < 0.075) discard;
  if (uCutout == 2 && texture(uAlbedo, vUV).a < 0.5) discard;
  o = vec4(1.0);
}
`;

export const lineVS = header + `
layout(location = 0) in vec3 aPos;
uniform mat4 uViewProj;
uniform mat4 uModel;
uniform float uUnit;
uniform float uPointSize;
out vec3 vWorld;
void main() { vWorld = (uModel * vec4(aPos, 1.0)).xyz * uUnit; gl_Position = uViewProj * vec4(vWorld, 1.0); gl_PointSize = uPointSize; }
`;

export const lineFS = header + `
in vec3 vWorld;
uniform vec4 uColor;
uniform vec4 uClipMin;
uniform vec4 uClipMax;
uniform vec4 uPlaneP;
uniform vec4 uPlaneN;
uniform int uRound;           // 1 = round point sprites (snow)
out vec4 o;
void main() {
  if (uClipMax.w > 0.5 && (any(lessThan(vWorld, uClipMin.xyz)) || any(greaterThan(vWorld, uClipMax.xyz)))) discard;
  if (uPlaneN.w > 0.5 && dot(vWorld - uPlaneP.xyz, uPlaneN.xyz) > 0.0) discard;
  float a = 1.0;
  if (uRound == 1) { vec2 q = gl_PointCoord * 2.0 - 1.0; float r = dot(q, q); if (r > 1.0) discard; a = 1.0 - r * r; }
  o = vec4(uColor.rgb, uColor.a * a);
}
`;

/** Full-screen triangle. */
export const quadVS = header + `
out vec2 vUV;
void main() {
  vec2 p = vec2(float((gl_VertexID << 1) & 2), float(gl_VertexID & 2));
  vUV = p;
  gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
}
`;

/** Sky background (equirect) or the flat gradient of the non-realistic styles. */
export const skyFS = header + `
in vec2 vUV;
uniform mat4 uInvViewProj;
uniform int uUseEnv;
uniform sampler2D uEnv;
uniform vec3 uTop;
uniform vec3 uBottom;
out vec4 o;
const float PI = 3.14159265359;
void main() {
  if (uUseEnv == 1) {
    vec4 a = uInvViewProj * vec4(vUV * 2.0 - 1.0, -1.0, 1.0);
    vec4 b = uInvViewProj * vec4(vUV * 2.0 - 1.0, 1.0, 1.0);
    vec3 d = normalize(b.xyz / b.w - a.xyz / a.w);
    vec2 uv = vec2(atan(d.y, -d.x) / (2.0 * PI) + 0.5, 0.5 - asin(clamp(d.z, -1.0, 1.0)) / PI);
    o = vec4(textureLod(uEnv, uv, 0.0).rgb, 1.0);
  } else {
    o = vec4(mix(uBottom, uTop, vUV.y), 1.0);
  }
}
`;

/** Scalable ambient obscurance from the depth buffer (SceneKit screenSpaceAmbientOcclusion*). */
export const ssaoFS = header + `
in vec2 vUV;
uniform sampler2D uDepth;
uniform mat4 uInvProj;
uniform mat4 uProj;
uniform float uRadius;
uniform vec2 uTexel;
out vec4 o;
vec3 viewPos(vec2 uv) {
  float z = texture(uDepth, uv).r;
  vec4 p = uInvProj * vec4(uv * 2.0 - 1.0, z * 2.0 - 1.0, 1.0);
  return p.xyz / p.w;
}
float hash12(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
void main() {
  float z = texture(uDepth, vUV).r;
  if (z >= 1.0) { o = vec4(1.0); return; }
  vec3 P = viewPos(vUV);
  vec3 Px = viewPos(vUV + vec2(uTexel.x, 0.0)), Py = viewPos(vUV + vec2(0.0, uTexel.y));
  vec3 N = normalize(cross(Px - P, Py - P));
  if (N.z < 0.0) N = -N;
  float occ = 0.0;
  float a0 = hash12(gl_FragCoord.xy) * 6.2831853;
  const int S = 12;
  for (int i = 0; i < S; i++) {
    float fi = float(i) + 0.5;
    float r = uRadius * sqrt(fi / float(S));
    float a = a0 + fi * 2.39996323;
    // Sample on a disc around P in the plane facing the camera, lifted along N.
    vec3 t = normalize(abs(N.x) < 0.9 ? cross(N, vec3(1.0, 0.0, 0.0)) : cross(N, vec3(0.0, 1.0, 0.0)));
    vec3 bt = cross(N, t);
    vec3 S3 = P + (t * cos(a) + bt * sin(a)) * r + N * r * 0.35;
    vec4 c = uProj * vec4(S3, 1.0);
    vec2 suv = c.xy / c.w * 0.5 + 0.5;
    if (suv.x < 0.0 || suv.x > 1.0 || suv.y < 0.0 || suv.y > 1.0) continue;
    vec3 Q = viewPos(suv);
    vec3 v = Q - P;
    float dv = length(v);
    float h = max(dot(N, v / max(dv, 1e-4)) - 0.03, 0.0);
    float fall = 1.0 - smoothstep(uRadius * 0.6, uRadius * 1.6, dv);
    occ += h * fall;
  }
  float ao = clamp(1.0 - occ / float(S) * 1.6, 0.0, 1.0);
  o = vec4(ao, ao, ao, 1.0);
}
`;

/** Separable blur (bloom and AO). */
export const blurFS = header + `
in vec2 vUV;
uniform sampler2D uTex;
uniform vec2 uDir;      // texel step × direction
uniform float uSigma;   // in steps
out vec4 o;
void main() {
  vec4 acc = texture(uTex, vUV);
  float wsum = 1.0;
  int n = int(ceil(uSigma * 2.5));
  for (int i = 1; i < 40; i++) {
    if (i > n) break;
    float w = exp(-0.5 * float(i * i) / (uSigma * uSigma));
    acc += (texture(uTex, vUV + uDir * float(i)) + texture(uTex, vUV - uDir * float(i))) * w;
    wsum += 2.0 * w;
  }
  o = acc / wsum;
}
`;

/** Bright pass of the bloom (after exposure). */
export const brightFS = header + `
in vec2 vUV;
uniform sampler2D uTex;
uniform float uExposure;
uniform float uSceneScale;
uniform float uThreshold;
out vec4 o;
void main() {
  vec3 c = texture(uTex, vUV).rgb * exp2(uExposure) * uSceneScale;
  float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
  o = vec4(l > uThreshold ? c * ((l - uThreshold) / l) : vec3(0.0), 1.0);
}
`;

/** Camera response: exposure, AO, bloom, tone mapping (white point), saturation, contrast, vignette, sRGB. */
export const compositeFS = header + `
in vec2 vUV;
uniform sampler2D uHDR;
uniform sampler2D uDepth;
uniform sampler2D uAO;
uniform sampler2D uBloom;
uniform float uAOIntensity;
uniform float uExposure;
uniform float uSceneScale;
uniform float uBloomIntensity;
uniform int uToneMap;
uniform float uWhite;
uniform float uSaturation;
uniform float uContrast;
uniform float uContrastPivot;
uniform float uVignette;
uniform float uVignettePower;
uniform int uHasBloom;
uniform int uHasAO;
uniform int uAOIndirect;       // 1: the AO darkens the indirect light only (uIndirect), 0: the whole pixel
uniform sampler2D uIndirect;
out vec4 o;
vec3 toSRGB(vec3 c) {
  c = clamp(c, 0.0, 1.0);
  return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}
void main() {
  vec3 c = texture(uHDR, vUV).rgb;
  if (uHasAO == 1 && texture(uDepth, vUV).r < 1.0) {
    float ao = texture(uAO, vUV).r;
    float k = clamp(uAOIntensity * (1.0 - ao), 0.0, 1.0);
    if (uAOIndirect == 1) c = max(c - texture(uIndirect, vUV).rgb * k, 0.0);
    else c *= 1.0 - k;
  }
  c *= exp2(uExposure) * uSceneScale;
  if (uHasBloom == 1) c += texture(uBloom, vUV).rgb * uBloomIntensity;
  if (uToneMap == 1) {
    // SceneKit's HDR camera is close to linear up to the highlights, then rolls off towards white.
    const float k = 0.72;
    vec3 over = max(c - k, 0.0);
    c = min(c, vec3(k)) + (1.0 - k) * (1.0 - exp(-over / (1.0 - k)));
  }
  float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
  c = max(mix(vec3(l), c, uSaturation), 0.0);
  vec3 s = toSRGB(c);
  s = clamp((s - uContrastPivot) * (1.0 + uContrast) + uContrastPivot, 0.0, 1.0);
  if (uVignette > 0.0) {
    vec2 d = vUV - 0.5;
    float r = length(d) * 1.41421356;
    s *= 1.0 - uVignette * pow(clamp(r, 0.0, 1.0), 1.0 / max(uVignettePower, 0.05)) ;
  }
  o = vec4(s, 1.0);
}
`;

/** Box downsample of a supersampled frame (final renders). */
export const downsampleFS = header + `
in vec2 vUV;
uniform sampler2D uTex;
uniform int uK;
uniform vec2 uSrcTexel;
out vec4 o;
void main() {
  vec2 base = floor(gl_FragCoord.xy) * float(uK);
  vec4 acc = vec4(0.0);
  for (int y = 0; y < 4; y++) for (int x = 0; x < 4; x++) {
    if (x >= uK || y >= uK) continue;
    acc += texture(uTex, (base + vec2(float(x), float(y)) + 0.5) * uSrcTexel);
  }
  o = acc / float(uK * uK);
}
`;

export const copyFS = header + `
in vec2 vUV;
uniform sampler2D uTex;
out vec4 o;
void main() { o = texture(uTex, vUV); }
`;

/** Depth of field (SCNCamera wantsDepthOfField, focusDistance, fStop, sensor 24 mm): a disc gather over the HDR frame
 *  with the circle of confusion of each sample, so sharp surfaces in front do not bleed into the blur. */
export const dofFS = header + `
in vec2 vUV;
uniform sampler2D uTex;
uniform sampler2D uDepth;
uniform vec2 uNearFar;      // metres
uniform float uFocus;       // metres
uniform float uFocal;       // metres (lens focal length)
uniform float uAperture;    // metres (focal / f-stop)
uniform float uPixelsPerM;  // frame height in pixels / sensor height (0.024 m)
uniform float uMaxCoC;      // pixels
uniform vec2 uTexel;
uniform int uOrtho;
out vec4 o;
float linearZ(float d) {
  float n = uNearFar.x, f = uNearFar.y;
  if (uOrtho == 1) return n + d * (f - n);
  float z = d * 2.0 - 1.0;
  return 2.0 * n * f / (f + n - z * (f - n));
}
float coc(vec2 uv) {
  float z = linearZ(texture(uDepth, uv).r);
  float c = uAperture * uFocal * abs(z - uFocus) / max(z * (uFocus - uFocal), 1e-6);
  return min(c * uPixelsPerM, uMaxCoC);
}
void main() {
  float c0 = coc(vUV);
  vec3 sum = texture(uTex, vUV).rgb;
  float wsum = 1.0;
  const int N = 48;
  for (int i = 1; i < N; i++) {
    float fi = float(i);
    float r = sqrt(fi / float(N)) * uMaxCoC;
    float a = fi * 2.39996323;
    vec2 uv = vUV + vec2(cos(a), sin(a)) * r * uTexel;
    float cs = coc(uv);
    // A sample contributes when its own blur disc reaches this pixel (and not from sharp surfaces behind).
    float w = smoothstep(r - 1.0, r + 1.0, min(cs, c0 + 2.0) );
    sum += texture(uTex, uv).rgb * w;
    wsum += w;
  }
  o = vec4(sum / wsum, 1.0);
}
`;
