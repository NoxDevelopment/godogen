shader_type canvas_item;
// res://shaders/sanity_overlay.gdshader
// Sanity vignette: a cold, closing dark ring plus a faint pulse, scaled by
// `intensity` (0 = sane/invisible, 1 = broken). The room script sets
// intensity from Sanity.normalized() every change.

uniform float intensity : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 centered = UV - vec2(0.5);
	float ring = smoothstep(0.28, 0.75, length(centered));
	float pulse = 1.0 + 0.15 * sin(TIME * 3.1) * intensity;
	float alpha = clamp(ring * intensity * 0.9 * pulse, 0.0, 0.92);
	COLOR = vec4(0.03, 0.005, 0.05, alpha);
}
