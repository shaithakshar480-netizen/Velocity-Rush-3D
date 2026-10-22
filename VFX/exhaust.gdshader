shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform float power : hint_range(0.0, 1.0) = 0.0;
uniform float phase = 0.0;
void fragment() {
    // Quad +Y points backward along the exhaust; UV.y=1 is the nozzle.
    float travel = 1.0-UV.y;
    float turbulence = sin(travel*25.0-phase*31.0)*0.035*travel;
    turbulence += sin(travel*51.0-phase*43.0)*0.018*travel;
    float width = abs(UV.x-0.5-turbulence)*2.0;
    float taper = pow(max(1.0-travel,0.0),0.72);
    float sheath = 1.0-smoothstep(taper*0.25,taper*0.88+0.001,width);
    float core = 1.0-smoothstep(taper*0.06,taper*0.32+0.001,width);
    float tip = 1.0-smoothstep(0.68,1.0,travel);
    float ignition = smoothstep(0.0,0.025,travel);
    float pulse = 0.86+0.08*sin(phase*29.0-travel*17.0)+0.06*sin(phase*47.0+travel*9.0);
    float diamonds = pow(max(sin(travel*36.0-phase*2.0),0.0),6.0);
    vec3 blue = mix(vec3(0.025,0.12,0.95),vec3(0.04,0.48,1.0),core);
    vec3 hot = mix(blue,vec3(0.62,0.92,1.0),core*(0.65+diamonds*0.35)*(1.0-travel*0.55));
    ALBEDO = hot;
    ALPHA = sheath*tip*ignition*power*pulse*0.72;
}
