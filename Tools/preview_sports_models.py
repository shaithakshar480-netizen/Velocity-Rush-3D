"""Offline projection of delivered GLB triangles. Not a Godot screenshot."""
from pathlib import Path
import json,struct,math
import numpy as np
from PIL import Image,ImageDraw,ImageFont
R=Path(__file__).resolve().parents[1]
def mesh(path):
 raw=path.read_bytes();n=struct.unpack_from('<I',raw,12)[0];d=json.loads(raw[20:20+n]);binary=raw[28+n:];tris=[];normals=[];colors=[];roles=[]
 def arr(a):
  a=d['accessors'][a];v=d['bufferViews'][a['bufferView']];return np.frombuffer(binary,dtype='<f4',offset=v.get('byteOffset',0),count=a['count']*3).reshape(-1,3)
 for node in d['nodes']:
  if 'mesh' not in node:continue
  for p in d['meshes'][node['mesh']]['primitives']:
   vertices=arr(p['attributes']['POSITION'])+np.array(node.get('translation',[0,0,0]));ns=arr(p['attributes']['NORMAL']);mat=d['materials'][p['material']]
   tris.extend(vertices.reshape(-1,3,3));normals.extend(ns.reshape(-1,3,3).mean(axis=1));colors.extend([mat['pbrMetallicRoughness']['baseColorFactor'][:3]]*(len(vertices)//3));roles.extend([mat['name']]*(len(vertices)//3))
 return np.array(tris),np.array(normals),np.array(colors),roles

def draw_car(canvas,at,size,data,rear=False):
 ps,ns,colors,roles=data;eye=np.array([5,2.8,7 if rear else -7.]);view=eye/np.linalg.norm(eye);right=np.cross([0,1,0],view);right/=np.linalg.norm(right);up=np.cross(view,right)
 projected=np.stack([ps@right,-ps@up,ps@view],axis=-1);scale=min(size[0]/(np.ptp(projected[:,:,0])+1),size[1]/(np.ptp(projected[:,:,1])+.5));center=np.array(at)+np.array(size)/2
 projected[:,:,:2]*=scale;projected[:,:,:2]+=center
 light=np.array([-.3,.82,-.45]);light/=np.linalg.norm(light);half=(light+view);half/=np.linalg.norm(half)
 facing=(ns@view); lambert=np.maximum(ns@light,0);spec=np.maximum(ns@half,0)**70
 rgb=colors*(.40+.50*lambert[:,None]);refl=2*(ns@view)[:,None]*ns-view
 sky=np.clip(.5+refl[:,1]*.5,0,1)
 for i,role in enumerate(roles):
  if role in ['Paint','Glass','Alloy']:
   rgb[i]=rgb[i]*(.82 if role!='Glass' else .45)+np.array([.55,.68,.80])*(.12*sky[i]+.7*spec[i])
   if role=='Glass':rgb[i]+=.13*max(0,1-abs(refl[i,1]-.20)*8)
  if role in ['Headlight','Taillight']:rgb[i]+=colors[i]*.15
 rgb=np.clip(rgb,0,1)**(1/1.65)*255
 draw=ImageDraw.Draw(canvas)
 # Flat road plane ellipse is only presentation, all car geometry is from GLB bytes.
 draw.ellipse((center[0]-size[0]*.32,center[1]-size[1]*.12,center[0]+size[0]*.32,center[1]+size[1]*.12),fill=(8,14,21))
 for i in np.argsort(projected[:,:,2].mean(axis=1)):
  # Double-sided faces retained as in the actual asset; use average smooth normals.
  draw.polygon([tuple(v) for v in projected[i,:,:2]],fill=tuple(rgb[i].astype(int)))

if __name__=='__main__':
 cars=json.loads((R/'Data/VehicleCatalog.json').read_text())['cars']
 image=Image.new('RGB',(1800,1600),(15,24,34));draw=ImageDraw.Draw(image)
 font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',25);small=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',16)
 draw.text((55,30),'VELOCITY RUSH 3D / SPORTS SURFACE REDESIGN',font=font,fill=(99,229,218))
 for i,car in enumerate(cars):
  x=40+(i%2)*890;y=95+(i//2)*480
  draw.rounded_rectangle((x,y,x+860,y+450),radius=20,fill=(21,33,46))
  draw_car(image,(x+15,y+45),(820,350),mesh(R/car['visual_scene_path'].replace('res://','')))
  draw.text((x+24,y+400),car['name'].upper(),font=font,fill=(229,238,245))
 draw.text((55,1550),'OFFLINE GLB GEOMETRY PROJECTION / Original meshes, illustrative lighting. Not a Godot render or FPS test.',font=small,fill=(163,184,203))
 out=R/'Docs/sports-models-preview.png'
 temporary=out.with_suffix('.tmp.png');image.save(temporary);temporary.replace(out)
 with Image.open(out) as verify:verify.load()
 print('Preview verified',out.stat().st_size)
