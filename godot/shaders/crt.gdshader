shader_type canvas_item;

// Simple CRT scanline effect for terminal backgrounds
uniform float scanline_opacity : hint_range(0.0, 0.5) = 0.08;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.3;

void fragment() {
	vec2 uv = UV;
	vec4 col = texture(TEXTURE, uv);
	
	// Scanlines
	float scanline = sin(uv.y * SCREEN_PIXEL_SIZE.y * 500.0) * 0.5 + 0.5;
	col.rgb = mix(col.rgb, col.rgb * scanline, scanline_opacity);
	
	// Vignette
	float dist = length(uv - 0.5) * 1.4;
	col.rgb *= 1.0 - dist * vignette_strength;
	
	COLOR = col;
}
