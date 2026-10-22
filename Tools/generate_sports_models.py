"""Original sculpted sports-car surfaces and three authored tessellation/detail tiers.
No downloaded mesh or texture inputs. Smooth loft normals, real wheel-arch openings,
curved integrated glazing, recessed fascia, split spokes and brake rotors.
"""
from pathlib import Path
import json, math, struct
import numpy as np
R=Path(__file__).resolve().parents[1]; OUT=R/'Assets/Player'; OUT.mkdir(exist_ok=True)
TAU=math.tau
ROLES=['Paint','Glass','Trim','Rubber','Alloy','Headlight','Taillight','Carbon','Housing','BrakeDisc','BrakeCaliper','Lens','LightInternals']
COLORS=[(.14,.5,.57),(.08,.19,.25),(.035,.045,.055),(.025,.028,.033),(.66,.71,.76),(.69,.87,.95),(.65,.025,.04),(.04,.048,.056),(.085,.095,.11),(.33,.35,.37),(.56,.13,.08),(.32,.47,.57),(.58,.65,.71)]
TIERS=[dict(name='low',nz=58,nc=9,ring=24,tire=4,detail=0),dict(name='medium',nz=88,nc=18,ring=36,tire=6,detail=1),dict(name='high',nz=140,nc=27,ring=60,tire=10,detail=2)]
def normalize(v):
 v=np.asarray(v,dtype=float);return v/max(np.linalg.norm(v),1e-12)
def smooth(t): t=max(0,min(1,t));return t*t*(3-2*t)
def interp(points,t):
 for (a,x),(b,y) in zip(points,points[1:]):
  if t<=b:return x+(y-x)*smooth((t-a)/(b-a))
 return points[-1][1]
class Mesh:
 def __init__(self):self.groups={i:[] for i in range(len(ROLES))}
 def tri(self,a,b,c,role,normal=None,normals=None):
  a,b,c=[np.asarray(v,float) for v in [a,b,c]];n=np.cross(b-a,c-a)
  if np.linalg.norm(n)<1e-9:return
  if normal is not None and np.dot(n,normal)<0:
   b,c=c,b;n=-n
   if normals is not None:normals=[normals[0],normals[2],normals[1]]
  n=normalize(n);self.groups[role].append(([a,b,c], [n,n,n] if normals is None else [normalize(v) if np.linalg.norm(v)>1e-8 else n for v in normals]))
 def quad(self,a,b,c,d,role,normal=None):self.tri(a,b,c,role,normal);self.tri(a,c,d,role,normal)
 def surface(self,fn,nu,nv,role=0,flip=False):
  vertices=[[np.array(fn(i/nu,j/nv),float) for j in range(nv+1)] for i in range(nu+1)]
  normals=[]
  for i in range(nu+1):
   row=[]
   for j in range(nv+1):
    du=vertices[min(i+1,nu)][j]-vertices[max(i-1,0)][j]
    dv=vertices[i][min(j+1,nv)]-vertices[i][max(j-1,0)]
    row.append(normalize(np.cross(du,dv))*(-1 if flip else 1))
   normals.append(row)
  for i in range(nu):
   for j in range(nv):
    ids=[(i,j),(i+1,j),(i+1,j+1),(i,j+1)]
    if flip:ids=ids[::-1]
    mat=role((i+.5)/nu,(j+.5)/nv) if callable(role) else role
    for tri in [(0,1,2),(0,2,3)]:
     self.tri(*(vertices[ids[k][0]][ids[k][1]] for k in tri),mat,normals=[normals[ids[k][0]][ids[k][1]] for k in tri])
 def tube(self,points,radius,role,segments=8):
  points=[np.array(p,float) for p in points];rings=[]
  for i,p in enumerate(points):
   tangent=normalize(points[min(i+1,len(points)-1)]-points[max(i-1,0)])
   n=normalize(np.cross(tangent,(0,1,0) if abs(tangent[1])<.9 else (1,0,0)));b=np.cross(tangent,n)
   rings.append([p+radius*(n*math.cos(TAU*k/segments)+b*math.sin(TAU*k/segments)) for k in range(segments)])
  for a,b in zip(rings,rings[1:]):
   for k in range(segments):self.quad(a[k],b[k],b[(k+1)%segments],a[(k+1)%segments],role)
 def pocket(self,points,inward,role=8):
  # Beveled rim and recessed dark interior; no transparent overlapping layers.
  pts=[np.array(p,float) for p in points];center=sum(pts)/len(pts);inside=[center+(p-center)*.80+np.array(inward) for p in pts]
  for i in range(len(pts)):
   j=(i+1)%len(pts);self.quad(pts[i],pts[j],inside[j],inside[i],role)
   self.tri(sum(inside)/len(inside),inside[i],inside[j],2)

def vehicle(p,index,tier):
 m=Mesh();L=p['length'];W=p['width'];h=p['height'];r=p['wheel_radius'];wb=p['wheelbase'];half=L/2
 # Distinct design language: taper, muscular wheel shoulders, waist, canopy and hood channels.
 design=[(.88,.055,.11,.015),(.81,.035,.12,.025),(.90,.09,.14,.018),(.77,.105,.10,.038),(.72,.12,.08,.052),(.79,.12,.15,.045)][index]
 tip,waist,muscle,channel=design
 wf=p['windshield_z'];rf=p['roof_front_z'];rr=p['roof_rear_z'];rg=p['rear_glass_z']
 def width(z):
  u=z/half
  return W/2*(1-(1-tip)*abs(u)**5-waist*math.exp(-(z/.7)**2)+.018*math.exp(-((z-wb/2)/.4)**2))
 def deck(z):
  return p['hood_y']-.17*(abs(z)/half)**5+muscle*max(math.exp(-((z-wb/2)/.36)**2),math.exp(-((z+wb/2)/.36)**2))
 def lift(z):
  if z<=wf or z>=rg:return 0
  return (h-p['hood_y']-.025)*interp([(wf,0),(rf,1),(rr,.97),(rg,0)],z)
 def low(z):
  y=.23 if index<3 else .19
  for c in [-wb/2,wb/2]:
   d=z-c;rad=r+.048
   if abs(d)<rad:y=max(y,r+math.sqrt(rad*rad-d*d))
  return y
 def pos(side,z,t):
  w=width(z);base=deck(z);raise_y=lift(z)
  if index==1:raise_y*=.91
  if index==2:raise_y*=.95
  if index==3:raise_y*=.86
  if index==4:raise_y*=.90
  if index==5:raise_y*=.84
  x=interp([(0,0),(.42,.67),(.65,.965),(.84,1),(1,.94)],t)*w
  y=interp([(0,base+raise_y+.022),(.42,base+raise_y*.94),(.65,base-.015),(.84,base-.19),(1,low(z))],t)
  if t>.65:y=max(y,low(z)+.012*(1-t))
  # Two sculpted hood channels and raised outer fender crown.
  if z<wf and t<.65:y-=channel*math.exp(-((t-.3)/.065)**2)*math.sin(math.pi*(z+half)/(wf+half))**2
  edge=(x/max(w,.01))**2
  zz=z+(-.10+.28*edge)*math.exp(-(z+half)/.16)+(.06-.14*edge)*math.exp(-(half-z)/.16)
  return (side*x,y,zz)
 def material(u,t):
  z=-half+L*u
  if lift(z)>.04:
   if index==4 and t<.43 and z>rf and z<rr:return 1
   if index==5 and t<.10 and z>rf and z<rr:return 7
   if t<.43 and ((z<rf-.045 and z>wf+.075) or (z>rr+.045 and z<rg-.075)):return 1
   if .44<t<.64 and z>wf+.14 and z<rg-.16:
    if index==1 and abs(z-.10)<.035:return 2
    return 1
  return 0
 for side in [-1,1]:
  m.surface(lambda u,t:pos(side,-half+L*u,t),tier['nz'],tier['nc'],material,flip=side<0)
  # Wrapped cutout lip: the mesh ends above each tire, with smooth three-dimensional return.
  for wz in [-wb/2,wb/2]:
   n=tier['ring']//2
   m.surface(lambda u,v:(side*(width(wz+(r+.048+v*.025)*math.cos(math.pi*u))+.004-v*.027),r+(r+.048+v*.025)*math.sin(math.pi*u),wz+(r+.048+v*.025)*math.cos(math.pi*u)),n,2,0,flip=side>0)
  # Door cut line follows the actual sculpted side contour.
  line=[]
  path=[(wf+.12,.67),(wf+.17,.79),(wf+.23,.98),(.65,.98),(.78,.80),(.78,.67)]
  for (za,ta),(zb,tb) in zip(path,path[1:]):
   for blend in np.linspace(0,1,9):
    q=np.array(pos(side,za+(zb-za)*blend,ta+(tb-ta)*blend));q[0]+=side*.012;line.append(q)
  m.tube(line,.0035,2,4)
  # Flush handle, integrated side intake and skirt blade.
  z=.38 if index<3 else .55;w=width(z)
  m.tube([(side*(w+.008),deck(z)-.1,z-.09),(side*(w+.009),deck(z)-.1,z+.07)],.009,4,6)
  if index>=2:
   za=.36;zb=wb/2-.42
   def side_intake(u,v):
    z=za+(zb-za)*u;t=.74+.21*v
    q=np.array(pos(side,z,t));q[0]+=side*.024
    return q
   m.surface(side_intake,10,5,lambda u,v:8 if u<.10+.3*v or u>.9 or v<.15 or v>.85 else 2,flip=side<0)
  m.surface(lambda u,v:(side*(width(-wb/2+.43+(wb-.86)*u)+.045*math.sin(math.pi*v)),.21+.05*math.sin(math.pi*v),-wb/2+.43+(wb-.86)*u),12 if tier['detail'] else 6,3,7)
  # Streamlined mirror shell (ellipsoidal, not a cube).
  mx=side*(W/2+.09);mz=wf+.15;my=p['hood_y']+.15
  m.surface(lambda u,v:(mx+.15*math.sin(math.pi*u)*math.cos(TAU*v),my+.053*math.cos(math.pi*u),mz+.105*math.sin(math.pi*u)*math.sin(TAU*v)),6+tier['detail']*3,12+tier['detail']*4,0)
  m.tube([(side*W*.40,my-.03,mz+.035),(mx,my-.035,mz+.045)],.019,2,6)
 # Curved front/rear fascia with three recessed intakes and deliberately different light signatures.
 for rear in [False,True]:
  z=half if rear else -half;sign=1 if rear else -1;w=width(z);top=deck(z)
  def fascia_role(u,v):
   x=abs(u*2-1);y=.22+v*(top-.22)
   central=x<(.29+.09*v)
   outside=.49+.05*v<x<.94-.08*v
   if index==1:central=x<.70-.18*v;outside=.82<x<.93
   if index in [3,4]:central=.13+.02*v<x<.78-.16*v;outside=False
   if .28<y<.45 and (central or outside):return 2
   if .265<y<.465 and (central or outside):return 8
   return 0
  def fascia(u,v):
   x=(u*2-1)*w;y=.22+v*(top-.22)
   recess=.028 if fascia_role(u,v)==2 else 0
   return (x,y,z+sign*(.10-.28*abs(u*2-1)**2-recess))
  m.surface(fascia,20+tier['detail']*12,6+tier['detail']*3,fascia_role,flip=rear)
  # Wide integrated carbon splitter/diffuser with swept edge.
  m.surface(lambda u,v:((u*2-1)*w*(.94+.07*math.sin(math.pi*v)),.20+.025*math.sin(math.pi*v),z+sign*(-.17+.30*v+.055*math.cos((u-.5)*math.pi))),20,3,7,flip=not rear)
  for side in [-1,1]:
   a=side*w*.42;b=side*w*.90

   # Enclosed lens sits ahead of the fascia, never intersects the hood mesh.
   def lens_at(f):return z+sign*(.10-.28*f*f+.023)
   lens_z=lens_at(.7)
   pts=[(side*w*.43,top-.065,lens_at(.43)),(side*w*.92,top-.038,lens_at(.92)),(side*w*.88,top+.008,lens_at(.88)),(side*w*.47,top-.002,lens_at(.47))]
   m.pocket(pts,(0,0,-sign*.003),11)
   # Individual optical projector barrels behind the DRL: no alpha layers.
   for k in range(2 if index<3 else 3):
    f=.52+k*.105;cx=side*w*f;cy=top-.024;cz=lens_at(f)+sign*.004
    m.surface(lambda u,v:(cx+(.018+.006*v)*math.cos(TAU*u),cy+(.018+.006*v)*math.sin(TAU*u),cz+sign*.002*v),8+tier['detail']*4,1,12,flip=rear)
   length=14+tier['detail']*8
   m.surface(lambda u,v:(side*w*(.48+.38*u),top-.040+.021*u+v*.014,lens_at(.48+.38*u)+sign*.009),length,2,6 if rear else 5,flip=rear)
   if index in [1,3,4,5]:
    m.tube([(side*w*.88,top-.026,lens_at(.88)+sign*.010),(side*w*.89,top-.10-index*.004,lens_at(.89)+sign*.010)],.008,6 if rear else 5,6)
  # Grille slats and rear diffuser vanes kept at all tiers with bounded detail.
  for k in range(4+tier['detail']*4):
   x=-w*.30+k*w*.60/(3+tier['detail']*4)
   m.tube([(x,.30,z+sign*(.075-.28*(x/w)**2)),(x,.415,z+sign*(.075-.28*(x/w)**2))],.004 if tier['detail'] else .006,2,4)
  if rear:
   for x in [-.56,-.28,0,.28,.56]:m.quad((x,.17,z-.23),(x,.28,z-.16),(x,.27,z+.09),(x,.17,z+.10),7)
 # Hood feature ribs and supercar engine cooling louvers follow the body crown.
 if tier['detail']:
  for side in [-1,1]:
   points=[(side*width(z)*.54,deck(z)+.024,z) for z in np.linspace(-half+.34,wf-.06,12)]
   m.tube(points,.004,0,4)
  for k in range((4 if index<3 else 9)+tier['detail']*2):
   z=rg+.045+k*.038
   if z>half-.22:break
   y=deck(z)+.027
   m.tube([(-width(z)*.32,y,z),(width(z)*.32,y,z)],.008,2,4)
 # Tier-specific aero: lip, short pedestal, split flying wing, long hypercar wing.
 wing_y=deck(half-.20)+(.035 if index<3 else .25+(index-3)*.05)
 wing_z=half-.19
 span=W*(.78 if index<3 else .98)
 m.surface(lambda u,v:((u-.5)*span,wing_y+.06*math.sin(math.pi*v)+.02*math.cos(TAU*u),wing_z+(v-.5)*(.16 if index<3 else .34)),24+tier['detail']*12,4+tier['detail']*2,0 if index<3 else 7)
 if index>=3:
  for side in [-1,1]:
   m.tube([(side*.55,deck(wing_z)+.01,wing_z+.06),(side*.57,wing_y,wing_z)],.027,7,6)
   m.quad((side*span/2,wing_y-.015,wing_z-.19),(side*span/2,wing_y+.11,wing_z-.13),(side*span/2,wing_y+.11,wing_z+.18),(side*span/2,wing_y-.015,wing_z+.18),7)
 for x,y,z in p['exhaust_points']:
  m.surface(lambda u,v:(x+(.083-v*.025)*math.cos(TAU*u),y+(.083-v*.025)*math.sin(TAU*u),z+.014*math.sin(math.pi*v)),tier['ring']//2,3,4)
  m.surface(lambda u,v:(x+.057*math.cos(TAU*u),y+.057*math.sin(TAU*u),z-.07*v),tier['ring']//2,1,2)
 # Stationary brake calipers sit behind the rim; unlike rotors they never spin.
 for wz in [-wb/2,wb/2]:
  for side in [-1,1]:
   cx=side*(W/2-.055+.086);cy=r;cz=wz+r*.47
   m.surface(lambda u,v:(cx+.034*math.sin(math.pi*u)*math.cos(TAU*v),cy+.12*math.cos(math.pi*u),cz+.046*math.sin(math.pi*u)*math.sin(TAU*v)),6+tier['detail']*2,8,10)
 # Track aero: fender gills and flying buttresses follow each vehicle's own profile.
 if index>=2:
  for side in [-1,1]:
   for j in range(3 if index<5 else 5):
    zz=-wb/2+.02+j*.056
    m.tube([(side*width(zz)*.74,deck(zz)+.025,zz),(side*width(zz)*.90,deck(zz)-.012,zz+.016)],.010,2,4)
 if index>=3:
  for side in [-1,1]:
   for j in range(3):
    zz=rg-.16+j*.075
    m.tube([(side*width(zz)*.52,deck(zz)+lift(zz)*.6+.02,zz),(side*width(zz)*.88,deck(zz)+.025,zz+.18)],.014 if index<5 else .022,7,6)
 if index==4:
  # Segmented rear light bridge, distinct from the other five signatures.
  for j in range(9):
   x=(j-4)*W*.065
   m.tube([(x-.035,deck(half)-.035,half+.095),(x+.035,deck(half)-.035,half+.095)],.008,6,6)
 return m

def wheel(radius,tier,index):
 m=Mesh();n=tier['ring'];depth=.125
 # Rounded tire shoulder and molded sidewall with true circular contact radius.
 m.surface(lambda u,v:(-depth+2*depth*v,radius*(.79+.21*math.sin(math.pi*v)**.35)*math.cos(TAU*u),radius*(.79+.21*math.sin(math.pi*v)**.35)*math.sin(TAU*u)),n,tier['tire'],3)
 for side in [-1,1]:
  x=side*.127
  for inn,out,mat,xx in [(.67,.79,4,x),(.12,.65,9,x-side*.025),(.09,.20,4,x+side*.025)]:
   m.surface(lambda u,v:(xx,(inn+(out-inn)*v)*radius*math.cos(TAU*u),(inn+(out-inn)*v)*radius*math.sin(TAU*u)),n,1,mat,flip=side<0)
  # Split forged spokes with concavity and real gaps revealing the brake rotor.
  spokes=[5,6,5,7,5,8][index]
  for j in range(spokes):
   for branch in [-1,1]:
    a=TAU*j/spokes
    def spoke(u,v):
     rr=radius*(.17+.56*u);ang=a+branch*(.04+.08*u)+(.015+.025*u)*(2*v-1)
     return (side*(.132+.025*math.sin(math.pi*u)),rr*math.cos(ang),rr*math.sin(ang))
    m.surface(spoke,1+tier['detail']*2,1 if tier['detail']==0 else 2,4,flip=side<0)
  # Hub disk, five lug sockets, rotor perforation detail on higher tiers.
  m.surface(lambda u,v:(x+side*.03,radius*.105*v*math.cos(TAU*u),radius*.105*v*math.sin(TAU*u)),n//2,1,4,flip=side<0)
  if tier['detail']:
   for j in range(5):
    a=TAU*j/5;cy=radius*.14*math.cos(a);cz=radius*.14*math.sin(a)
    m.surface(lambda u,v:(x+side*.029,cy+.010*v*math.cos(TAU*u),cz+.010*v*math.sin(TAU*u)),6,1,8,flip=side<0)
   for j in range(12 if tier['detail']==1 else 24):
    a=TAU*j/(12 if tier['detail']==1 else 24);cy=radius*.55*math.cos(a);cz=radius*.55*math.sin(a)
    m.surface(lambda u,v:(x-side*.023,cy+.006*v*math.cos(TAU*u),cz+.006*v*math.sin(TAU*u)),5,1,8,flip=side<0)
 return m

def write_glb(p,body,wheels,tier):
 binary=bytearray();views=[];accessors=[];meshes=[]
 def accessor(rows):
  arr=np.asarray(rows,dtype='<f4');off=len(binary);binary.extend(arr.tobytes());vi=len(views)
  views.append(dict(buffer=0,byteOffset=off,byteLength=arr.nbytes,target=34962));accessors.append(dict(bufferView=vi,componentType=5126,count=len(arr),type='VEC3',min=arr.min(axis=0).tolist(),max=arr.max(axis=0).tolist()));return len(accessors)-1
 for name,mesh in [('Body',body),('Wheel',wheels)]:
  primitives=[]
  for role,tris in mesh.groups.items():
   if not tris:continue
   ps=[p for tri,ns in tris for p in tri];ns=[n for tri,ns in tris for n in ns]
   primitives.append(dict(attributes=dict(POSITION=accessor(ps),NORMAL=accessor(ns)),material=role,mode=4))
  meshes.append(dict(name=name,primitives=primitives))
 nodes=[dict(name=p['id'],children=[1,2,3,4,5]),dict(name='Body',mesh=0)]
 for j,(x,z) in enumerate([(side*(p['width']/2-.055),z) for z in [-p['wheelbase']/2,p['wheelbase']/2] for side in [-1,1]]):nodes.append(dict(name='Wheel_'+str(j),mesh=1,translation=[x,p['wheel_radius'],z]))
 colors=COLORS.copy();hexv=CAT['paints'][p['default_paint']]['hex'];colors[0]=tuple(int(hexv[i:i+2],16)/255 for i in [0,2,4])
 materials=[]
 for name,col in zip(ROLES,colors):
  mat=dict(name=name,pbrMetallicRoughness=dict(baseColorFactor=[*col,1],metallicFactor=.75 if name in ['Paint','Alloy','BrakeDisc'] else (.35 if name=='Glass' else .05),roughnessFactor=.20 if name in ['Paint','Glass','Alloy'] else .75 if name=='Rubber' else .4),doubleSided=True)
  if name in ['Headlight','Taillight']:mat['emissiveFactor']=[v*.16 for v in col]
  materials.append(mat)
 doc=dict(asset=dict(version='2.0',generator='Velocity Rush original sports surfaces v1'),scene=0,scenes=[dict(nodes=[0])],nodes=nodes,meshes=meshes,materials=materials,buffers=[dict(byteLength=len(binary))],bufferViews=views,accessors=accessors)
 raw=json.dumps(doc,separators=(',',':')).encode();raw+=b' '*((-len(raw))%4)
 glb=struct.pack('<III',0x46546C67,2,28+len(raw)+len(binary))+struct.pack('<II',len(raw),0x4E4F534A)+raw+struct.pack('<II',len(binary),0x004E4942)+binary
 name=p['id']+('_'+tier['name'] if tier['name']!='high' else '')+'.glb';(OUT/name).write_bytes(glb)
 tris=sum(map(len,body.groups.values()))+4*sum(map(len,wheels.groups.values()))
 return dict(id=p['id'],lod=tier['name'],triangles=tris,bytes=len(glb),path='res://Assets/Player/'+name,wheel_contact_y=0.0,material_roles=ROLES)

CAT=json.loads((R/'Data/VehicleCatalog.json').read_text())
def main():
 metrics=[]
 for i,p in enumerate(CAT['cars']):
  if i==1:
   p.update(roof_front_z=-.38,roof_rear_z=.40,rear_glass_z=1.23)
  for tier in TIERS:
   b=vehicle(p,i,tier);w=wheel(p['wheel_radius'],tier,i);row=write_glb(p,b,w,tier);metrics.append(row);print(p['name'],tier['name'],row['triangles'],flush=True)
  p['visual_scene_path']='res://Assets/Player/'+p['id']+'.glb'
  p['visual_lod_paths']=['res://Assets/Player/'+p['id']+'_low.glb','res://Assets/Player/'+p['id']+'_medium.glb',p['visual_scene_path']]
  p['camera_anchors']=[[0,3.2,7.1+(p['length']-4.18)*.45],[0,5.4,11.8],[0,p['hood_y']+.32,p['windshield_z']-.18],[0,.54,-p['length']/2-.26],[-.30,p['height']-.13,p['roof_front_z']+.10]]
  p['attachment_markers']={k:v for k,v in zip(['camera_chase_anchor','camera_far_anchor','camera_hood_anchor','camera_bumper_anchor','camera_cockpit_anchor'],p['camera_anchors'])}
  p['attachment_markers'].update(headlight_L=[-p['width']*.32,p['hood_y']-.04,-p['length']/2-.03],headlight_R=[p['width']*.32,p['hood_y']-.04,-p['length']/2-.03])
  p['rear_light_points']=[[-p['width']*.3,p['hood_y']-.07,p['length']/2],[p['width']*.3,p['hood_y']-.07,p['length']/2]]
 (R/'Data/VehicleCatalog.json').write_text(json.dumps(CAT,indent=2)+'\n')
 (R/'Docs/sports-lod-metrics.json').write_text(json.dumps(metrics,indent=2)+'\n')
if __name__=='__main__':main()
