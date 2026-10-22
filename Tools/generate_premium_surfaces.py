"""Original authored HDR skies and tileable asphalt maps; no image downloads."""
from pathlib import Path
import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter,zoom
R=Path(__file__).resolve().parents[1];D=R/'Assets/Environment';W=2048;H=1024
rng=np.random.default_rng(7419)
def hdr(path,a):
 a=np.maximum(a,0);v=a.max(2);mant,e=np.frexp(v);scale=mant*256/np.maximum(v,1e-30);rgb=np.clip(a*scale[:,:,None],0,255).astype('uint8');rgbe=np.concatenate([rgb,np.clip(e+128,0,255).astype('uint8')[:,:,None]],2)
 with open(path,'wb') as f:
  f.write(f'#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y {a.shape[0]} +X {a.shape[1]}\n'.encode())
  for row in rgbe:
   f.write(bytes([2,2,a.shape[1]>>8,a.shape[1]&255]))
   for c in range(4):
    for i in range(0,len(row),128):
     chunk=row[i:i+128,c];f.write(bytes([len(chunk)]));f.write(chunk.tobytes())
y,x=np.mgrid[0:H,0:W];elev=(.5-y/(H-1))*np.pi;az=x/W*np.pi*2
up=np.clip(np.sin(elev),0,1)[:,:,None];sky=np.array([.73,.51,.32])*(1-up)**3+np.array([.085,.19,.37])*(1-(1-up)**3)
sky=np.where((elev<0)[:,:,None],np.array([.095,.105,.12]),sky)
noise=np.zeros((H,W))
for res,amp in [(16,.55),(32,.25),(64,.12),(128,.08)]:
 layer=zoom(rng.random((res//2,res)),(H/(res//2),W/res),order=1,mode='wrap');noise+=layer[:H,:W]*amp
cloud=np.clip((noise-.47)*5,0,.62)*np.exp(-((elev-.24)/.28)**2)
sky=sky*(1-cloud[:,:,None])+np.array([.92,.78,.61])*cloud[:,:,None]
# Broad warm atmospheric glow and compact sun matched to the key's approximate direction.
d=(np.cos(elev)*np.cos(az-2.23)*np.cos(.45)+np.sin(elev)*np.sin(.45));halo=np.exp((d-1)*65);sun=np.exp((d-1)*14000)
sky+=halo[:,:,None]*np.array([.85,.44,.18])+sun[:,:,None]*np.array([10,7,3.6])
sky[:,0]=sky[:,-1]=(sky[:,0]+sky[:,-1])*.5
hdr(D/'golden_hour.hdr',sky)
Image.fromarray((np.clip(sky/(1+sky),0,1)**(1/2.2)*255).astype('uint8')).resize((1024,512)).save(R/'Docs/sky-preview.png')
# Studio light cards baked into reflection panorama: zero runtime reflection probes.
studio=np.broadcast_to(np.array([.035,.05,.075]),(512,1024,3)).copy();yy,xx=np.mgrid[0:512,0:1024]
for cx,cy,sx,sy,col in [(180,170,34,55,[3.4,3.8,4.4]),(600,190,85,22,[4.6,3.8,2.8]),(880,110,38,60,[1.3,1.8,2.4])]:
 light=np.exp(-((xx-cx)/sx)**8-((yy-cy)/sy)**8);studio+=light[:,:,None]*np.array(col)
hdr(D/'studio_reflections.hdr',studio)
# Shared 1K packed roughness/albedo texture. World coordinates keep road seams continuous.
a=rng.random((1024,1024));a=gaussian_filter(a,.65,mode='wrap');coarse=gaussian_filter(rng.random((1024,1024)),18,mode='wrap');a=.5+(a-.5)*.6+(coarse-.5)*5
packed=np.stack([np.clip(a,0,1),np.clip(.83+(a-.5)*.18,0,1),np.clip(.5+(a-.5)*.3,0,1)],2)
Image.fromarray((packed*255).astype('uint8')).save(D/'asphalt_surface.png')
print('Created 2K golden-hour HDR, 1K studio HDR and 1K packed asphalt texture')
