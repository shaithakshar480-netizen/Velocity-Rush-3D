shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform bool fire = false;
uniform vec4 tint : source_color = vec4(.34,.37,.40,.55);
varying float seed;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
 vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void vertex() {
 seed = dot(MODEL_MATRIX[3].xyz,vec3(.31,.19,.47));
 MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0]*length(MODEL_MATRIX[0].xyz),INV_VIEW_MATRIX[1]*length(MODEL_MATRIX[1].xyz),INV_VIEW_MATRIX[2]*length(MODEL_MATRIX[2].xyz),MODEL_MATRIX[3]);
}
void fragment() {
 vec2 uv = UV;
 float n = noise(uv*5.0+vec2(seed,TIME*(fire?2.7:.22)));
 n = n*.7+noise(uv*11.0+seed+vec2(0,TIME*(fire?4.0:.35)))*.3;
 float edge = 1.0-smoothstep(.18,.50,length(uv-.5)+(n-.5)*.14);
 if(fire) {
  float taper=mix(.12,.44,uv.y);
  float tongue=1.0-smoothstep(taper*.35,taper,abs(uv.x-.5+(n-.5)*.16));
  edge*=tongue;
  float heat=clamp(uv.y*.7+n*.6,0.0,1.0);
  vec3 color=mix(vec3(.95,.08,.008),vec3(1.0,.94,.65),heat);
  ALBEDO=color; EMISSION=color*1.4;
  ALPHA=edge*smoothstep(.22,.65,n)*tint.a*COLOR.a;
 } else {
  ALBEDO=tint.rgb*(.5+n*.85); ALPHA=edge*smoothstep(.12,.72,n)*tint.a*COLOR.a;
 }
}
