shader_type spatial;
uniform float wetness = 0.0;
uniform float city_sheen = 0.0;
uniform bool course_coordinates = false;
uniform float detail_strength = 1.0;
uniform int quality = 1;
uniform sampler2D surface_map : filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 road_position;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }

float noise2d(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
    road_position = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
    if (course_coordinates) { road_position.xz = UV2; }
}
void fragment() {
    vec2 p = road_position.xz;
    vec3 surface = texture(surface_map,p*.20).rgb;
    // Four parallel driving lanes: gentle paired tire wear, never visual geometry bumps.
    float lane = mod(p.x+8.0,4.0)-2.0;
    float wear = exp(-pow((abs(lane)-.70)*3.8,2.0));
    vec2 patch_cell = floor(p/vec2(3.0,19.0));
    vec2 uv = fract(p/vec2(3.0,19.0));
    float patch = step(.89,hash(patch_cell))*smoothstep(.10,.15,uv.x)*(1.0-smoothstep(.78,.83,uv.x))*smoothstep(.2,.23,uv.y)*(1.0-smoothstep(.55,.58,uv.y));
    vec3 base_albedo = vec3(.077,.087,.102)+(surface.r-.5)*.060*detail_strength-wear*.011-patch*.015;

    float pool = 0.0;
    float ripples = 0.0;
    if (wetness > 0.01) {
        // Natural puddle pooling: gathering irregularly along worn tyre ruts and road depressions
        vec2 p_puddle = p * vec2(0.16, 0.07);
        float p_noise = noise2d(p_puddle) * 0.70 + noise2d(p_puddle * 2.4 + vec2(3.8, 1.9)) * 0.30;
        float rut_bias = wear * 0.26;
        float puddle_mask = smoothstep(0.58 - rut_bias, 0.74 - rut_bias, p_noise);
        float road_bounds = 1.0 - smoothstep(6.2, 8.1, abs(p.x));
        pool = puddle_mask * road_bounds * wetness;

        if (pool > 0.005) {
            // Surface raindrop ripples inside puddles
            vec2 puddle_center = floor(p / vec2(3.5, 7.0)) * vec2(3.5, 7.0);
            vec2 local_p = p - puddle_center;
            float dist = length(local_p);
            float r1 = sin(dist * 20.0 - TIME * 7.5);
            float r2 = sin((p.x * 0.8 + p.y * 1.2) * 14.0 - TIME * 6.0);
            ripples = (r1 * 0.65 + r2 * 0.35) * 0.026 * pool;
        }
    }

    // Wet road optical response:
    // 1. Water fills micro-cavities causing noticeable darkening of wet porous asphalt
    float wet_darkening = 1.0 - wetness * 0.38 - pool * 0.24;
    ALBEDO = base_albedo * wet_darkening;
    // Subtle cool water tint in deeper puddles
    ALBEDO = mix(ALBEDO, ALBEDO * vec3(0.90, 0.95, 1.04), pool * 0.5);

    // 2. Roughness:
    // Dry asphalt: 0.58 - 0.94 (diffuse stone)
    // Damp/Wet asphalt: 0.24 (thin water sheen)
    // Standing puddles: 0.04 (smooth water surface)
    float dry_roughness = clamp(surface.g - wear * 0.11 + patch * 0.05, 0.58, 0.94);
    float wet_roughness = mix(dry_roughness, 0.24, wetness);
    ROUGHNESS = mix(wet_roughness, 0.04, pool);

    // 3. Specular response:
    // Glancing reflections and water sheen
    ROUGHNESS = mix(ROUGHNESS, max(0.27,ROUGHNESS*0.55),city_sheen);
    SPECULAR = mix(0.5, 0.65, max(wetness,city_sheen));
    SPECULAR = mix(SPECULAR, 0.94, pool);

    METALLIC = 0.0;

    // 4. Normal map:
    // Micro-grain is smoothed out by standing water in puddles, with ripples overlaying it
    if (detail_strength > 0.05 || abs(ripples) > 0.001) {
        float grain = (surface.r - 0.5) * 0.055 * detail_strength * (1.0 - pool * 0.85);
        vec2 norm_xy = vec2(grain * (1.0 - pool) + ripples, -grain * (1.0 - pool) + ripples);
        NORMAL_MAP = normalize(vec3(norm_xy, 1.0)) * 0.5 + 0.5;
        NORMAL_MAP_DEPTH = mix(0.18, 0.36, pool);
    }
}
