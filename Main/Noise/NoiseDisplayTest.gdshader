shader_type spatial;
render_mode unshaded, fog_disabled;
uniform sampler3D sampler;
uniform float scale;
void fragment() {
vec3 worldPosition = ((INV_VIEW_MATRIX * vec4(VERTEX,1)).xyz);
	worldPosition*=scale;
	ALBEDO = texture(sampler,worldPosition ).xyz;


}