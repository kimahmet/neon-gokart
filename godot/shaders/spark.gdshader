shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;
// Camera-facing additive sparks drawn from one MultiMesh.
void vertex() {
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
}
void fragment() { ALBEDO = COLOR.rgb * 2.5; ALPHA = COLOR.a; }
