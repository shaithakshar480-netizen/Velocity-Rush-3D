shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
void fragment() {
    float radius = length((UV - vec2(0.5)) * 2.0);
    ALBEDO = vec3(0.015, 0.018, 0.025);
    ALPHA = (1.0 - smoothstep(0.35, 1.0, radius)) * 0.43;
}
