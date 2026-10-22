"""Original pooled scenery: irregular ridges, rock cuts, skyline, roadside props.
All meshes generated offline, no gameplay colliders, no external assets.
"""
from pathlib import Path
import math,struct,json,random
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'Assets/Environment';OUT.mkdir(exist_ok=True)
MATS=[('Earth',(.25,.28,.19),0,.95),('Rock',(.35,.33,.28),0,.9),('Distant',(.26,.34,.42),0,.95),('Leaf',(.19,.29,.18),0,.95),('Structure',(.43,.48,.51),.1,.65),('Glass',(.18,.30,.38),.3,.3),('Metal',(.27,.31,.34),.45,.45)]
class Mesh:
 def __init__(self):self.groups={}
 def tri(self,a,b,c,mat):
  u=[b[i]-a[i] for i in range(3)];v=[c[i]-a[i] for i in range(3)];n=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]];length=math.sqrt(sum(x*x for x in n))
  if length<1e-9:return
  n=[x/length for x in n];self.groups.setdefault(mat,[]).extend([(a,n),(b,n),(c,n)])
 def quad(self,a,b,c,d,mat):self.tri(a,b,c,mat);self.tri(a,c,d,mat)
 def box(self,pos,size,mat):
  x,y,z=pos;w,h,l=[x/2 for x in size];p=[(x+a*w,y+b*h,z+c*l) for a,b,c in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]]
  for ids in [(0,3,2,1),(4,5,6,7),(0,4,7,3),(1,2,6,5),(3,7,6,2),(0,1,5,4)]:self.quad(*(p[i] for i in ids),mat)
 def ring_shape(self,x,z,rad,height,mat,seed):
  rng=random.Random(seed);rings=[];count=9
  for level,scale in [(0,1),(height*.38,.94),(height*.78,.6),(height,.18)]:
   rings.append([(x+math.cos(i*math.tau/count)*rad*scale*(.8+rng.random()*.35),level-.35,z+math.sin(i*math.tau/count)*rad*scale) for i in range(count)])
  for a,b in zip(rings,rings[1:]):
   for j in range(count):self.quad(a[j],a[(j+1)%count],b[(j+1)%count],b[j],mat)
  for j in range(count):self.tri(rings[-1][j],rings[-1][(j+1)%count],(x,height-.1,z),mat)
def write(name,parts):
 binary=bytearray();views=[];accessors=[];meshes=[];nodes=[]
 def acc(rows):
  off=len(binary);flat=[v for r in rows for v in r];binary.extend(struct.pack('<'+'f'*len(flat),*flat));views.append({'buffer':0,'byteOffset':off,'byteLength':len(binary)-off})
  accessors.append({'bufferView':len(views)-1,'componentType':5126,'count':len(rows),'type':'VEC3','min':[min(r[i] for r in rows) for i in range(3)],'max':[max(r[i] for r in rows) for i in range(3)]});return len(accessors)-1
 tris=0
 for part,mesh in parts.items():
  prims=[]
  for mat,vertices in mesh.groups.items():
   prims.append({'attributes':{'POSITION':acc([v[0] for v in vertices]),'NORMAL':acc([v[1] for v in vertices])},'material':mat,'mode':4});tris+=len(vertices)//3
  if prims:
   nodes.append({'name':part,'mesh':len(meshes)});meshes.append({'name':part,'primitives':prims})
 doc={'asset':{'version':'2.0','generator':'Velocity Rush original environment 4'},'scene':0,'scenes':[{'nodes':list(range(len(nodes)))}],'nodes':nodes,'meshes':meshes,'materials':[{'name':n,'doubleSided':True,'pbrMetallicRoughness':{'baseColorFactor':[*c,1],'metallicFactor':m,'roughnessFactor':r}} for n,c,m,r in MATS],'buffers':[{'byteLength':len(binary)}],'bufferViews':views,'accessors':accessors}
 text=json.dumps(doc,separators=(',',':')).encode();text+=b' '*((-len(text))%4)
 raw=struct.pack('<III',0x46546c67,2,28+len(text)+len(binary))+struct.pack('<II',len(text),0x4e4f534a)+text+struct.pack('<II',len(binary),0x004e4942)+binary
 (OUT/(name+'.glb')).write_bytes(raw);return {'id':name,'triangles':tris,'bytes':len(raw),'parts':list(parts)}
reports=[]
for section in range(4):
 parts={name:Mesh() for name in ['Terrain','RidgeNear','RidgeFar','RidgeHorizon','Vegetation','Rocks','Structures','StructuresFar','Details','Overpass']};rng=random.Random(400+section)
 # Sloping berms connect the shoulder to inaccessible terrain; flat road remains empty.
 for side in [-1,1]:
  for j in range(12):
   za=-60+j*10;zb=za+10
   parts['Terrain'].quad((side*10,-.25,za),(side*10,-.25,zb),(side*110,-.65,zb),(side*110,-.65,za),0)
  # Ridge chain: irregular multi-level cross-sections, shared endpoint profile per tile.
  for band in range(3):
   distant=band>0
   mesh=parts[['RidgeNear','RidgeFar','RidgeHorizon'][band]];base=[34 if section==1 else 75,165,290][band];amp=[18 if section==1 else 35,62,85][band]*(1 if section<2 else .65)
   stations=[]
   for j in range(33):
    z=-60+j*3.75;h=amp*(.58+.18*math.sin(z*math.pi/60+section+band*.8)+.14*math.cos(z*math.pi/30+1.2)+.08*math.sin(z*math.pi/15+band)+.04*math.cos(z*math.pi/7.5))
    stations.append([(side*(base-18),-.55,z),(side*(base-5),h*.38,z),(side*(base+9),h,z),(side*(base+28),h*.64,z),(side*(base+50),-.5,z)])
   for a,b in zip(stations,stations[1:]):
    for j in range(4):mesh.quad(a[j],b[j],b[j+1],a[j+1],2 if distant else 1)
  for j in range(8):
   x=side*(19+rng.random()*32);z=-52+j*14
   parts['Rocks'].ring_shape(x,z,1.1+rng.random()*1.6,1.4+rng.random()*2.8,1,section*200+j)
  for j in range(12 if section!=1 else 5):
   x=side*(24+rng.random()*39);z=rng.uniform(-55,55);h=rng.uniform(3,6)
   parts['Vegetation'].box((x,h*.26,z),(.24,h*.6,.24),6)
   parts['Vegetation'].ring_shape(x,z,1.8,h,3,section*2000+j)
  # Merged grass blades and low shrubs: no alpha billboard overdraw or per-blade nodes.
  for j in range(34):
   x=side*rng.uniform(12,38);z=rng.uniform(-59,59)
   for blade in range(5):
    a=rng.random()*math.tau;h=rng.uniform(.18,.58);w=.09
    parts['Vegetation'].tri((x-w,-.1,z),(x+w,-.1,z),(x+math.sin(a)*.18,h,z+math.cos(a)*.14),3)
   if j%7==0:parts['Vegetation'].ring_shape(x,z,.65,.75,3,j+section*80)
  # Culvert mouth, utility cabinet and communications mast outside guardrails.
  parts['Details'].box((side*14,.45,32),(1.7,1.1,2.6),4)
  parts['Details'].box((side*14,.5,33.31),(1.4,.8,.025),6)
  parts['Details'].box((side*28,6,47),(.25,12,.25),6)
  for y in [8,10,12]:parts['Details'].box((side*28,y,47),(2.5,.09,.12),6)
 if section>=2:
  for j in range(8 if section==2 else 12):
   side=-1 if j%2==0 else 1;x=side*(65+(j%4)*12);z=-52+(j//2)*20;h=rng.uniform(16,42)+(8 if section==3 else 0)
   parts['Structures'].box((x,h/2,z),(8,h,10),4)
   parts['StructuresFar'].box((x,h/2,z),(8,h,10),4)
   parts['Structures'].box((x,h+1.5,z),(5,3,7),6)
   # Stepped crowns, rooftop equipment and facade fins break the box skyline.
   parts['Structures'].box((x+1,h+4,z),(2.5,3,4),5)
   for dx in [-3.1,0,3.1]:parts['Structures'].box((x+dx,h*.5,z+5.12),(.13,h*.94,.3),6)
   if j%3==0:
    parts['Structures'].box((x,h+8,z),(.15,10,.15),6)
    parts['Structures'].ring_shape(x+12,z,3.3,9,4,j)

   for y in range(3,int(h)-1,4):
    parts['Structures'].box((x,y,z+5.025),(7.7,2.2,.05),5)
   parts['Structures'].box((x-4.025,h/2,z),(.05,h*.88,8.5),5)
 # Bridge uses angled piers and a shallow spanning deck; no gameplay collision.
 for side in [-1,1]:
  parts['Overpass'].box((side*14,3.5,-4),(1.1,7,2.0),4)
  parts['Overpass'].box((side*22,5.3,-4),(1.3,10.6,2.0),4)
 parts['Overpass'].box((0,8,-4),(66,1.0,7),4)
 for z in [-7.6,-.4]:
  parts['Overpass'].box((0,8.7,z),(66,.8,.15),6)
 reports.append(write(['open_mountain','rock_cut','city_approach','outskirts'][section],parts))
(ROOT/'Docs/environment-mesh-metrics.json').write_text(json.dumps(reports,indent=2)+'\n')
print(json.dumps(reports))
