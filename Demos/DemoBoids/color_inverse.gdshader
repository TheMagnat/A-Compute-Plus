shader_type canvas_item;

uniform sampler2D screen: hint_screen_texture;

void fragment() {
	COLOR.rgb = vec3(1.0) - texture(screen, SCREEN_UV).rgb;
}
