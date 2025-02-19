shader_type spatial;
// Prevent the quad from being affected by lighting and fog. This also improves performance.
render_mode unshaded, fog_disabled;
uniform sampler2D depth_texture : source_color, hint_depth_texture;
uniform float cloudRenderDepth = 100;
uniform sampler2D textureToOutput;
uniform float test = 0;
void fragment() {
  float depth = texture(depth_texture, SCREEN_UV).x;
  vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
  vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
  view.xyz /= view.w;
  float linear_depth = -view.z;


	if(linear_depth > cloudRenderDepth){
		vec4 color = texture(textureToOutput, SCREEN_UV);
		ALBEDO = color.xyz;
		ALPHA = color.w;
	}
  else
 	ALPHA = 0.;
}
void vertex() {
  POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}