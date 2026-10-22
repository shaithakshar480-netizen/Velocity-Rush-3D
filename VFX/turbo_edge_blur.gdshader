shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float strength : hint_range(0.0,1.0) = 0.0;
uniform bool rich = false;
void fragment() {
    vec2 ray = SCREEN_UV - vec2(0.5,0.46);
    // Leave car, horizon and lane directly ahead sharp; smear only outer edges.
    float edge = smoothstep(0.25,0.49,max(abs(ray.x),abs(ray.y)*0.78));
    vec2 step_uv = ray * (0.010 * strength * edge);
    vec3 base = texture(screen_texture,SCREEN_UV).rgb;
    vec3 smear = base * 0.4;
    smear += texture(screen_texture,SCREEN_UV-step_uv).rgb * 0.3;
    smear += texture(screen_texture,SCREEN_UV-step_uv*2.0).rgb * 0.3;
    if (rich) {
        smear = smear * 0.7 + texture(screen_texture,SCREEN_UV-step_uv*3.5).rgb * 0.3;
    }
    COLOR = vec4(mix(base,smear,edge*strength),1.0);
}
