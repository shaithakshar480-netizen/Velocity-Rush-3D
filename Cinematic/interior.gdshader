shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
float grain(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
void fragment() {
    // Fine original soft-touch grain; no texture residency or extra geometry.
    float g = grain(floor(UV*420.0));
    ALBEDO = vec3(.024,.031,.040)*(0.92+g*.16);
    ROUGHNESS = .76+g*.12;
    METALLIC = .035;
}
