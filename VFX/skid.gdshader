shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
varying vec4 deposit;
void vertex() { deposit = COLOR; }
void fragment() {
    float edge = smoothstep(0.0,0.18,UV.x)*(1.0-smoothstep(0.82,1.0,UV.x));
    float rubber = 0.82+0.18*sin(UV.x*82.0+sin(UV.y*17.0)*0.7);
    ALBEDO = deposit.rgb;
    ALPHA = deposit.a*edge*rubber;
}
