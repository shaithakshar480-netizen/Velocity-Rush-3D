shader_type spatial;
render_mode cull_back;
uniform vec4 facade_color : source_color = vec4(0.20,0.25,0.31,1.0);
uniform float night = 0.0;
varying vec3 building_position;
varying vec3 building_normal;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
void vertex() {
 building_position = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
 building_normal = normalize(mat3(MODEL_MATRIX)*NORMAL);
}
void fragment() {
 vec2 p = vec2(abs(building_normal.x)>.5 ? building_position.z : building_position.x,building_position.y);
 vec2 cell = floor(p/vec2(1.45,2.6));
 vec2 grid = fract(p/vec2(1.45,2.6));
 float glass = step(.12,grid.x)*step(grid.x,.88)*step(.18,grid.y)*step(grid.y,.85)*(1.0-step(.8,abs(building_normal.y)));
 float occupied = step(.34,hash(cell));
 ALBEDO = mix(facade_color.rgb,vec3(.065,.12,.18),glass);
 ROUGHNESS = mix(.72,.24,glass);
 METALLIC = glass*.38;
 EMISSION = mix(vec3(.10,.24,.34),vec3(.60,.70,.96),hash(cell+7.0))*glass*occupied*night*1.35;
}
