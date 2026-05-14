"""Shader Craft — Godot 4 .gdshader and Unity ShaderLab/HLSL generators.

Templates for 5 common game shaders, with sensible defaults that work
out of the box. Each emits the shader file plus a JSON usage cheatsheet
(how to apply in the editor — which node, which uniforms to expose,
which RenderingServer flags if any).

Subcommands
-----------
water         Animated water surface. 2D canvas_item or 3D spatial.
fog           Distance + height fog (3D spatial only).
dissolve      Edge-burning dissolve transition. 2D or 3D.
outline       Sprite/mesh outline. 2D dilation or 3D depth-edge.
pixel-dither  Ordered Bayer dither for pixel-art transparency fades.
list          List available shaders and their target modes.

Pure text — no ComfyUI / Tripo3D / etc.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


# ---------------------------------------------------------------------------
# Godot 4 .gdshader templates
# ---------------------------------------------------------------------------

GD_WATER_CANVAS = '''shader_type canvas_item;
// Animated 2D water surface. Apply to a CanvasItem (Sprite2D, ColorRect)
// or wrap a Subviewport. Scroll speed, color depth, and ripple amplitude
// are exposed as uniforms.

uniform vec4 color_shallow : source_color = vec4(0.35, 0.75, 0.95, 0.85);
uniform vec4 color_deep    : source_color = vec4(0.05, 0.20, 0.45, 1.00);
uniform float scroll_speed = 0.15;
uniform float ripple_amplitude = 0.012;
uniform float ripple_frequency = 24.0;
uniform float depth_mask = 0.7; // 0 = all shallow, 1 = all deep at bottom

void fragment() {
    vec2 uv = UV;
    // Two scrolling layers at different speeds for depth.
    vec2 uv_a = uv + vec2(TIME * scroll_speed, TIME * scroll_speed * 0.4);
    vec2 uv_b = uv - vec2(TIME * scroll_speed * 0.6, 0.0);
    float ripple = sin(uv_a.x * ripple_frequency + TIME) * cos(uv_b.y * ripple_frequency * 0.7);
    vec2 sample_uv = uv + vec2(ripple * ripple_amplitude, ripple * ripple_amplitude);
    vec4 base = texture(TEXTURE, sample_uv);
    // Blend shallow→deep down the y axis.
    float depth_t = clamp(uv.y * depth_mask, 0.0, 1.0);
    vec4 water_tint = mix(color_shallow, color_deep, depth_t);
    COLOR = vec4(mix(base.rgb, water_tint.rgb, water_tint.a), base.a * water_tint.a);
}
'''

GD_WATER_SPATIAL = '''shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;
// Animated 3D water surface for MeshInstance3D plane meshes. Uses world-
// space UV scrolling so tiled meshes stay seamless.

uniform vec4 color_shallow : source_color = vec4(0.35, 0.75, 0.95, 0.85);
uniform vec4 color_deep    : source_color = vec4(0.05, 0.20, 0.45, 1.00);
uniform float scroll_speed = 0.05;
uniform float wave_height = 0.05;
uniform float wave_frequency = 4.0;
uniform float fresnel_power = 4.0;

varying vec3 world_pos;

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    float wave = sin(world_pos.x * wave_frequency + TIME) * cos(world_pos.z * wave_frequency * 0.7 + TIME * 0.6);
    VERTEX.y += wave * wave_height;
}

void fragment() {
    vec2 uv = world_pos.xz * 0.1 + vec2(TIME * scroll_speed, 0.0);
    float band = clamp(world_pos.y / max(wave_height * 2.0, 0.001) + 0.5, 0.0, 1.0);
    vec3 base = mix(color_deep.rgb, color_shallow.rgb, band);
    float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), fresnel_power);
    ALBEDO = mix(base, vec3(1.0), fresnel * 0.4);
    ALPHA = mix(color_deep.a, color_shallow.a, band);
    ROUGHNESS = 0.05;
    METALLIC = 0.1;
}
'''

GD_FOG_SPATIAL = '''shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
// Volumetric-ish fog applied as a full-screen pass via WorldEnvironment
// or attached to a large box mesh that surrounds the play area. For real
// volumetrics use Godot 4's built-in FogMaterial; this is a cheaper
// stylized alternative for pixel-art / low-end 3D.

uniform vec4 fog_color : source_color = vec4(0.7, 0.75, 0.85, 1.0);
uniform float fog_density = 0.04;
uniform float fog_height = 5.0;
uniform float fog_height_falloff = 0.5;
uniform float noise_scale = 0.1;
uniform float noise_strength = 0.15;
uniform float scroll_speed = 0.02;

float hash(vec3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.zyx + 31.32);
    return fract((p.x + p.y) * p.z);
}
float noise3(vec3 p) {
    vec3 i = floor(p); vec3 f = fract(p);
    f = f*f*(3.0-2.0*f);
    float n000 = hash(i + vec3(0,0,0));
    float n100 = hash(i + vec3(1,0,0));
    float n010 = hash(i + vec3(0,1,0));
    float n110 = hash(i + vec3(1,1,0));
    float n001 = hash(i + vec3(0,0,1));
    float n101 = hash(i + vec3(1,0,1));
    float n011 = hash(i + vec3(0,1,1));
    float n111 = hash(i + vec3(1,1,1));
    return mix(
        mix(mix(n000,n100,f.x), mix(n010,n110,f.x), f.y),
        mix(mix(n001,n101,f.x), mix(n011,n111,f.x), f.y),
        f.z);
}

void fragment() {
    vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
    float dist = length(world_pos - (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz);
    float depth_fog = 1.0 - exp(-dist * fog_density);
    float height_fog = clamp(exp(-(world_pos.y - fog_height) * fog_height_falloff), 0.0, 1.0);
    float noise = noise3(world_pos * noise_scale + vec3(TIME * scroll_speed, 0.0, TIME * scroll_speed * 0.7));
    float fog_amount = clamp(max(depth_fog, height_fog) + (noise - 0.5) * noise_strength, 0.0, 1.0);
    ALBEDO = fog_color.rgb;
    ALPHA = fog_color.a * fog_amount;
}
'''

GD_DISSOLVE_CANVAS = '''shader_type canvas_item;
// Edge-burning dissolve transition. Drive `dissolve_amount` from 0
// (fully visible) to 1 (fully dissolved) via AnimationPlayer or tween.

uniform sampler2D noise_texture : repeat_enable, filter_linear;
uniform float dissolve_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 edge_color : source_color = vec4(1.0, 0.5, 0.1, 1.0);
uniform float edge_width : hint_range(0.0, 0.2) = 0.05;
uniform float noise_scale = 1.0;

void fragment() {
    vec4 base = texture(TEXTURE, UV);
    float noise = texture(noise_texture, UV * noise_scale).r;
    float threshold = dissolve_amount * 1.2 - 0.1;
    if (noise < threshold) {
        discard;
    } else if (noise < threshold + edge_width) {
        // Edge band — burning glow.
        COLOR = vec4(edge_color.rgb, base.a * edge_color.a);
    } else {
        COLOR = base;
    }
}
'''

GD_DISSOLVE_SPATIAL = '''shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque, diffuse_lambert;
// 3D mesh dissolve effect. Same idea as the 2D version but with the
// shaded material under the edge band.

uniform sampler2D base_albedo : source_color, filter_linear;
uniform sampler2D noise_texture : repeat_enable, filter_linear;
uniform float dissolve_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 edge_color : source_color = vec4(1.0, 0.5, 0.1, 1.0);
uniform float edge_width : hint_range(0.0, 0.2) = 0.05;
uniform float noise_scale = 2.0;
uniform float edge_emission_strength = 4.0;

void fragment() {
    vec3 base = texture(base_albedo, UV).rgb;
    float noise = texture(noise_texture, UV * noise_scale).r;
    float threshold = dissolve_amount * 1.2 - 0.1;
    if (noise < threshold) {
        discard;
    }
    ALBEDO = base;
    if (noise < threshold + edge_width) {
        EMISSION = edge_color.rgb * edge_emission_strength;
    }
}
'''

GD_OUTLINE_CANVAS = '''shader_type canvas_item;
// Pixel-art sprite outline via 1-px dilation. Samples 4 neighbors; emits
// outline_color where the sprite's alpha goes from transparent to opaque
// across the sample. Cheap, pixel-perfect at 1× scale.

uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float outline_width : hint_range(1.0, 8.0) = 1.0;

void fragment() {
    vec2 size = vec2(textureSize(TEXTURE, 0));
    vec2 px = outline_width / size;
    vec4 c = texture(TEXTURE, UV);
    if (c.a > 0.5) {
        COLOR = c;
        return;
    }
    // Check 4 cardinal neighbors. If any is opaque, paint outline.
    float a =
        texture(TEXTURE, UV + vec2( px.x, 0.0)).a +
        texture(TEXTURE, UV + vec2(-px.x, 0.0)).a +
        texture(TEXTURE, UV + vec2(0.0,  px.y)).a +
        texture(TEXTURE, UV + vec2(0.0, -px.y)).a;
    if (a > 0.5) {
        COLOR = outline_color;
    } else {
        COLOR = vec4(0.0);
    }
}
'''

GD_OUTLINE_SPATIAL = '''shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque;
// Inverted-hull outline for 3D meshes. Apply as a SECOND material slot
// on the MeshInstance3D (after the regular surface material). Vertex
// shader pushes vertices outward along normals; cull_front means only
// the back faces draw, giving a 1-px (or N-px) silhouette.

uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float outline_thickness : hint_range(0.001, 0.1) = 0.01;

void vertex() {
    VERTEX += NORMAL * outline_thickness;
}

void fragment() {
    ALBEDO = outline_color.rgb;
    ALPHA = outline_color.a;
}
'''

GD_PIXEL_DITHER = '''shader_type canvas_item;
// Ordered Bayer dither for transparency. Use when you need fade-in /
// fade-out on a pixel-art sprite without smooth alpha blending (which
// looks wrong at 1× scale). Drive `alpha` from 0 (fully invisible)
// to 1 (fully visible).

uniform float alpha : hint_range(0.0, 1.0) = 1.0;
uniform int bayer_size : hint_range(2, 8) = 4;

// 4x4 Bayer matrix flattened — values in [0..15] / 16
const float BAYER_4[16] = float[16](
    0.0/16.0,  8.0/16.0,  2.0/16.0, 10.0/16.0,
   12.0/16.0,  4.0/16.0, 14.0/16.0,  6.0/16.0,
    3.0/16.0, 11.0/16.0,  1.0/16.0,  9.0/16.0,
   15.0/16.0,  7.0/16.0, 13.0/16.0,  5.0/16.0
);

void fragment() {
    vec4 base = texture(TEXTURE, UV);
    if (base.a < 0.01) { discard; }
    // Pick a Bayer cell from screen-space pixel coords.
    ivec2 px = ivec2(FRAGCOORD.xy);
    int size = bayer_size;
    int idx = (px.x % size) * size + (px.y % size);
    float threshold = BAYER_4[idx % 16];
    if (alpha < threshold) {
        discard;
    }
    COLOR = vec4(base.rgb, 1.0);
}
'''


# ---------------------------------------------------------------------------
# Unity HLSL (ShaderLab + HLSL) templates — URP-compatible
# ---------------------------------------------------------------------------

UNITY_WATER = '''Shader "Custom/SceneArt_Water" {
    Properties {
        _MainTex ("Texture", 2D) = "white" {}
        _ColorShallow ("Shallow Color", Color) = (0.35, 0.75, 0.95, 0.85)
        _ColorDeep    ("Deep Color",    Color) = (0.05, 0.20, 0.45, 1.0)
        _ScrollSpeed ("Scroll Speed", Float) = 0.15
        _RippleAmplitude ("Ripple Amplitude", Float) = 0.012
        _RippleFrequency ("Ripple Frequency", Float) = 24
    }
    SubShader {
        Tags { "RenderType"="Transparent" "Queue"="Transparent" }
        Blend SrcAlpha OneMinusSrcAlpha
        Pass {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"
            sampler2D _MainTex;
            float4 _MainTex_ST;
            fixed4 _ColorShallow;
            fixed4 _ColorDeep;
            float _ScrollSpeed;
            float _RippleAmplitude;
            float _RippleFrequency;
            struct appdata { float4 v : POSITION; float2 uv : TEXCOORD0; };
            struct v2f    { float4 p : SV_POSITION; float2 uv : TEXCOORD0; };
            v2f vert(appdata i) {
                v2f o;
                o.p = UnityObjectToClipPos(i.v);
                o.uv = TRANSFORM_TEX(i.uv, _MainTex);
                return o;
            }
            fixed4 frag(v2f i) : SV_Target {
                float2 uvA = i.uv + float2(_Time.y * _ScrollSpeed, _Time.y * _ScrollSpeed * 0.4);
                float2 uvB = i.uv - float2(_Time.y * _ScrollSpeed * 0.6, 0.0);
                float ripple = sin(uvA.x * _RippleFrequency + _Time.y) * cos(uvB.y * _RippleFrequency * 0.7);
                float2 s = i.uv + float2(ripple, ripple) * _RippleAmplitude;
                fixed4 base = tex2D(_MainTex, s);
                fixed4 tint = lerp(_ColorShallow, _ColorDeep, saturate(i.uv.y * 0.7));
                return fixed4(lerp(base.rgb, tint.rgb, tint.a), base.a * tint.a);
            }
            ENDHLSL
        }
    }
}
'''

UNITY_DISSOLVE = '''Shader "Custom/SceneArt_Dissolve" {
    Properties {
        _MainTex ("Texture", 2D) = "white" {}
        _NoiseTex ("Noise", 2D) = "white" {}
        _DissolveAmount ("Dissolve", Range(0,1)) = 0
        _EdgeColor ("Edge Color", Color) = (1.0, 0.5, 0.1, 1.0)
        _EdgeWidth ("Edge Width", Range(0.0, 0.2)) = 0.05
        _NoiseScale ("Noise Scale", Float) = 1
    }
    SubShader {
        Tags { "RenderType"="Transparent" "Queue"="Transparent" }
        Blend SrcAlpha OneMinusSrcAlpha
        Pass {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"
            sampler2D _MainTex; sampler2D _NoiseTex;
            float4 _MainTex_ST;
            float _DissolveAmount;
            fixed4 _EdgeColor;
            float _EdgeWidth;
            float _NoiseScale;
            struct appdata { float4 v : POSITION; float2 uv : TEXCOORD0; };
            struct v2f    { float4 p : SV_POSITION; float2 uv : TEXCOORD0; };
            v2f vert(appdata i) {
                v2f o; o.p = UnityObjectToClipPos(i.v);
                o.uv = TRANSFORM_TEX(i.uv, _MainTex); return o;
            }
            fixed4 frag(v2f i) : SV_Target {
                fixed4 base = tex2D(_MainTex, i.uv);
                float n = tex2D(_NoiseTex, i.uv * _NoiseScale).r;
                float threshold = _DissolveAmount * 1.2 - 0.1;
                clip(n - threshold);
                if (n < threshold + _EdgeWidth) {
                    return fixed4(_EdgeColor.rgb, base.a * _EdgeColor.a);
                }
                return base;
            }
            ENDHLSL
        }
    }
}
'''

UNITY_OUTLINE_CANVAS = '''Shader "Custom/SceneArt_Outline2D" {
    Properties {
        _MainTex ("Texture", 2D) = "white" {}
        _OutlineColor ("Outline Color", Color) = (0,0,0,1)
        _OutlineWidth ("Outline Width", Range(1, 8)) = 1
    }
    SubShader {
        Tags { "RenderType"="Transparent" "Queue"="Transparent" }
        Blend SrcAlpha OneMinusSrcAlpha
        Pass {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"
            sampler2D _MainTex;
            float4 _MainTex_TexelSize;
            float4 _MainTex_ST;
            fixed4 _OutlineColor;
            float _OutlineWidth;
            struct appdata { float4 v : POSITION; float2 uv : TEXCOORD0; };
            struct v2f    { float4 p : SV_POSITION; float2 uv : TEXCOORD0; };
            v2f vert(appdata i) {
                v2f o; o.p = UnityObjectToClipPos(i.v);
                o.uv = TRANSFORM_TEX(i.uv, _MainTex); return o;
            }
            fixed4 frag(v2f i) : SV_Target {
                fixed4 c = tex2D(_MainTex, i.uv);
                if (c.a > 0.5) return c;
                float2 px = _MainTex_TexelSize.xy * _OutlineWidth;
                float a =
                    tex2D(_MainTex, i.uv + float2( px.x, 0)).a +
                    tex2D(_MainTex, i.uv + float2(-px.x, 0)).a +
                    tex2D(_MainTex, i.uv + float2(0,  px.y)).a +
                    tex2D(_MainTex, i.uv + float2(0, -px.y)).a;
                if (a > 0.5) return _OutlineColor;
                return fixed4(0,0,0,0);
            }
            ENDHLSL
        }
    }
}
'''

UNITY_FOG = '''Shader "Custom/SceneArt_FogVolume" {
    // Apply to a large skybox-style box surrounding the play area, OR use
    // as a post-process URP Renderer Feature input. URP integration is
    // editor-specific; this is the legacy SubShader path for quick wiring.
    Properties {
        _FogColor ("Fog Color", Color) = (0.7, 0.75, 0.85, 1.0)
        _FogDensity ("Density", Float) = 0.04
        _FogHeight ("Height", Float) = 5.0
        _NoiseScale ("Noise Scale", Float) = 0.1
        _ScrollSpeed ("Scroll Speed", Float) = 0.02
    }
    SubShader {
        Tags { "RenderType"="Transparent" "Queue"="Transparent" }
        Blend SrcAlpha OneMinusSrcAlpha
        ZWrite Off
        Pass {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"
            fixed4 _FogColor;
            float _FogDensity, _FogHeight, _NoiseScale, _ScrollSpeed;
            struct appdata { float4 v : POSITION; };
            struct v2f    { float4 p : SV_POSITION; float3 wp : TEXCOORD0; };
            v2f vert(appdata i) {
                v2f o; o.p = UnityObjectToClipPos(i.v);
                o.wp = mul(unity_ObjectToWorld, i.v).xyz; return o;
            }
            float hash3(float3 p) {
                p = frac(p * 0.1031);
                p += dot(p, p.zyx + 31.32);
                return frac((p.x + p.y) * p.z);
            }
            fixed4 frag(v2f i) : SV_Target {
                float dist = length(i.wp - _WorldSpaceCameraPos);
                float depth_fog = 1.0 - exp(-dist * _FogDensity);
                float h = saturate(exp(-(i.wp.y - _FogHeight) * 0.5));
                float n = hash3(i.wp * _NoiseScale + float3(_Time.y * _ScrollSpeed, 0, _Time.y * _ScrollSpeed * 0.7));
                float amount = saturate(max(depth_fog, h) + (n - 0.5) * 0.15);
                return fixed4(_FogColor.rgb, _FogColor.a * amount);
            }
            ENDHLSL
        }
    }
}
'''

UNITY_PIXEL_DITHER = '''Shader "Custom/SceneArt_PixelDither" {
    Properties {
        _MainTex ("Texture", 2D) = "white" {}
        _Alpha ("Alpha", Range(0,1)) = 1
    }
    SubShader {
        Tags { "RenderType"="Transparent" "Queue"="Transparent" }
        Blend SrcAlpha OneMinusSrcAlpha
        Pass {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"
            sampler2D _MainTex;
            float4 _MainTex_ST;
            float _Alpha;
            struct appdata { float4 v : POSITION; float2 uv : TEXCOORD0; };
            struct v2f    { float4 p : SV_POSITION; float2 uv : TEXCOORD0; float4 sp : TEXCOORD1; };
            v2f vert(appdata i) {
                v2f o; o.p = UnityObjectToClipPos(i.v);
                o.uv = TRANSFORM_TEX(i.uv, _MainTex);
                o.sp = ComputeScreenPos(o.p);
                return o;
            }
            static const float BAYER_4[16] = {
                 0.0/16,  8.0/16,  2.0/16, 10.0/16,
                12.0/16,  4.0/16, 14.0/16,  6.0/16,
                 3.0/16, 11.0/16,  1.0/16,  9.0/16,
                15.0/16,  7.0/16, 13.0/16,  5.0/16
            };
            fixed4 frag(v2f i) : SV_Target {
                fixed4 base = tex2D(_MainTex, i.uv);
                clip(base.a - 0.01);
                int2 sp = int2(i.sp.xy / i.sp.w * _ScreenParams.xy);
                int idx = (sp.x % 4) * 4 + (sp.y % 4);
                float th = BAYER_4[idx % 16];
                clip(_Alpha - th);
                return fixed4(base.rgb, 1);
            }
            ENDHLSL
        }
    }
}
'''


# ---------------------------------------------------------------------------
# Shader catalog — maps (name, target, engine) → template + usage cheatsheet
# ---------------------------------------------------------------------------

CATALOG = {
    "water": {
        "godot": {
            "canvas_item": (GD_WATER_CANVAS, ".gdshader",
                            "Attach to a Sprite2D or ColorRect via ShaderMaterial. "
                            "Uniforms scroll_speed / ripple_amplitude on the material."),
            "spatial":     (GD_WATER_SPATIAL, ".gdshader",
                            "Apply to a MeshInstance3D plane via ShaderMaterial. "
                            "Vertex displacement requires sufficient mesh subdivision (PlaneMesh subdivide=64+)."),
        },
        "unity": {
            "canvas_item": (UNITY_WATER, ".shader",
                            "Create Material with this shader, assign _MainTex. URP-compatible."),
            "spatial":     (UNITY_WATER, ".shader",
                            "Same shader works for both 2D Sprite and 3D Quad with this template; "
                            "for true 3D water with vertex displacement, port the Godot spatial version."),
        },
    },
    "fog": {
        "godot": {
            "spatial": (GD_FOG_SPATIAL, ".gdshader",
                        "Apply to a large BoxMesh around the play area, OR use as the "
                        "material on a WorldEnvironment fog volume. Stylized alternative "
                        "to Godot 4's built-in FogMaterial."),
        },
        "unity": {
            "spatial": (UNITY_FOG, ".shader",
                        "Apply to a large box surrounding the play area, set Renderer Queue "
                        "to Transparent+1. For real post-process fog, integrate via URP Renderer Feature."),
        },
    },
    "dissolve": {
        "godot": {
            "canvas_item": (GD_DISSOLVE_CANVAS, ".gdshader",
                            "Sprite dissolve. Assign noise_texture (any grayscale noise PNG). "
                            "Tween dissolve_amount 0→1 to dissolve, 1→0 to materialize."),
            "spatial":     (GD_DISSOLVE_SPATIAL, ".gdshader",
                            "Mesh dissolve. Assign base_albedo (the mesh's normal texture) and "
                            "noise_texture. Edge band emits at edge_emission_strength * edge_color."),
        },
        "unity": {
            "canvas_item": (UNITY_DISSOLVE, ".shader",
                            "Sprite dissolve. Same usage as Godot canvas_item variant."),
            "spatial":     (UNITY_DISSOLVE, ".shader",
                            "Same shader for mesh dissolve; URP-compatible. Assign _NoiseTex on material."),
        },
    },
    "outline": {
        "godot": {
            "canvas_item": (GD_OUTLINE_CANVAS, ".gdshader",
                            "Sprite outline via 1-px dilation. Best at outline_width=1 for "
                            "pixel-art; 2-3 for crisp HD sprites."),
            "spatial":     (GD_OUTLINE_SPATIAL, ".gdshader",
                            "Inverted-hull mesh outline. Apply as a SECOND surface_material_override "
                            "on MeshInstance3D (after the regular material). cull_front + vertex "
                            "push gives silhouette."),
        },
        "unity": {
            "canvas_item": (UNITY_OUTLINE_CANVAS, ".shader",
                            "Sprite outline. Material on a SpriteRenderer; works with URP 2D."),
            "spatial":     (UNITY_OUTLINE_CANVAS, ".shader",
                            "For 3D inverted-hull outline, see the Godot spatial version and "
                            "port the cull_front + vertex push pattern manually (URP needs an "
                            "extra Renderer Feature pass)."),
        },
    },
    "pixel-dither": {
        "godot": {
            "canvas_item": (GD_PIXEL_DITHER, ".gdshader",
                            "Drive `alpha` (0..1) for pixel-art-friendly fade. Use bayer_size=4 "
                            "for medium pattern; 2 for chunky; 8 for fine."),
        },
        "unity": {
            "canvas_item": (UNITY_PIXEL_DITHER, ".shader",
                            "Drive _Alpha (0..1) on the material. URP-compatible."),
        },
    },
}


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def cmd_emit(name: str, args) -> None:
    """Resolve (name, target, engine) -> template, write file, emit JSON."""
    target = getattr(args, "target", "")
    engine = args.engine

    by_engine = CATALOG[name].get(engine)
    if by_engine is None:
        raise SystemExit(f"shader '{name}' has no template for engine '{engine}'.")
    # Pick target. If only one target is available, default to it.
    targets = list(by_engine.keys())
    if not target:
        if len(targets) == 1:
            target = targets[0]
        else:
            raise SystemExit(f"shader '{name}' requires --target (choices: {targets}).")
    if target not in by_engine:
        raise SystemExit(f"shader '{name}' for {engine} only supports targets {targets}, got {target!r}")

    src, ext, cheatsheet = by_engine[target]
    output = Path(args.output)
    if output.suffix == "":
        output = output.with_suffix(ext)
    elif output.suffix != ext:
        # Don't fight the user; honor their explicit extension.
        pass
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(src, encoding="utf-8")

    print(json.dumps({
        "ok": True, "shader": name, "engine": engine, "target": target,
        "path": str(output), "extension": output.suffix,
        "cheatsheet": cheatsheet,
    }, indent=2))


def cmd_list(args) -> None:
    rows: list[str] = ["Available shaders:"]
    for name, engines in CATALOG.items():
        for engine, targets in engines.items():
            rows.append(f"  {name:14s} engine={engine:6s} targets={list(targets.keys())}")
    print("\n".join(rows))


def main():
    parser = argparse.ArgumentParser(description="shader-craft: Godot/Unity shader generators")
    sub = parser.add_subparsers(required=True, dest="cmd")

    def _add_emit_parser(name, allow_targets):
        p = sub.add_parser(name, help=f"Emit {name} shader template")
        p.add_argument("--engine", default="godot", choices=["godot", "unity"])
        if len(allow_targets) > 1:
            p.add_argument("--target", required=True, choices=allow_targets)
        else:
            p.add_argument("--target", default=allow_targets[0], choices=allow_targets)
        p.add_argument("-o", "--output", required=True, help="Output shader file path")
        p.set_defaults(func=lambda a, _n=name: cmd_emit(_n, a))

    _add_emit_parser("water",        ["canvas_item", "spatial"])
    _add_emit_parser("fog",          ["spatial"])
    _add_emit_parser("dissolve",     ["canvas_item", "spatial"])
    _add_emit_parser("outline",      ["canvas_item", "spatial"])
    _add_emit_parser("pixel-dither", ["canvas_item"])

    p = sub.add_parser("list", help="List available shaders")
    p.set_defaults(func=cmd_list)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
