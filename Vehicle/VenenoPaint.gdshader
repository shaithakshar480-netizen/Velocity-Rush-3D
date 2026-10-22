shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// Only Material__24.001 of the supplied Veneno atlas uses this shader.
// UV gates exclude the badge/lamp islands and the entire upper-right decal bank.
uniform sampler2D body_atlas : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 paint_color : source_color = vec4(1.0);
uniform float paint_roughness : hint_range(0.05, 1.0) = 0.28;

float box_mask(vec2 uv, vec2 low, vec2 high) {
    vec2 inside = step(low, uv) * step(uv, high);
    return inside.x * inside.y;
}

void fragment() {
    vec3 original = texture(body_atlas, UV).rgb;
    float panels = box_mask(UV, vec2(0.0, 0.0), vec2(0.55, 1.0));
    panels = max(panels, box_mask(UV, vec2(0.55, 0.44), vec2(0.80, 0.76)));
    panels = max(panels, box_mask(UV, vec2(0.53, 0.76), vec2(0.61, 1.0)));
    // Central lamps, emblem, fuel cap, carbon/fastener strip and lower lamp.
    panels *= 1.0 - box_mask(UV, vec2(0.18, 0.19), vec2(0.39, 0.385));
    panels *= 1.0 - box_mask(UV, vec2(0.0, 0.57), vec2(0.12, 0.76));
    panels *= 1.0 - box_mask(UV, vec2(0.40, 0.83), vec2(0.47, 0.90));
    float brightest = max(original.r, max(original.g, original.b));
    float darkest = min(original.r, min(original.g, original.b));
    // Dark carbon and coloured markings remain original. Preserve baked shading.
    float neutral = 1.0 - smoothstep(0.025, 0.09, brightest - darkest);
    float painted = panels * neutral * smoothstep(0.09, 0.23, darkest);
    ALBEDO = mix(original, original * paint_color.rgb, painted);
    METALLIC = 0.4 * painted;
    ROUGHNESS = mix(0.7885257, paint_roughness, painted);
    CLEARCOAT = 1.0;
    CLEARCOAT_ROUGHNESS = 0.04;
}
