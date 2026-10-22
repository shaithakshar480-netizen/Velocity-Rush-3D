shader_type spatial;
render_mode unshaded, cull_back;
varying vec3 world;
void vertex(){ world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment(){
 vec2 p=vec2(world.z*.18,world.y*.085);
 float band=0.5+0.5*sin(p.y*5.0+p.x*3.0);
 vec3 color=mix(vec3(.04,.67,.85),vec3(.83,.055,.43),smoothstep(.3,.7,band));
 float scan=.75+.25*step(.18,fract(world.y*3.0));
 float emblem=1.0-smoothstep(.035,.075,abs(length(fract(p)-.5)-.28));
 ALBEDO=color*(.28+.72*emblem)*scan;
}
