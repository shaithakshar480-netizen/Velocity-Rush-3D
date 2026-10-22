from pathlib import Path
import numpy as np,runpy
# Reuse the documented HDR writer only, without rerunning old assets.
ROOT=Path(__file__).resolve().parents[1];p=ROOT/'Tools/generate_premium_surfaces.py';source=p.read_text();a=source.index('def hdr(');b=source.index('y,x=np.mgrid',a);scope={'np':np};exec(source[a:b],scope)
D=ROOT/'Assets/Environment';W=1024;H=512;y,x=np.mgrid[0:H,0:W];alt=(.5-y/(H-1))*np.pi;up=np.clip(np.sin(alt),0,1)[:,:,None]
for name,top,horizon in [('morning',[.13,.32,.61],[.95,.80,.65]),('evening',[.08,.19,.37],[.88,.51,.27]),('dusk',[.05,.065,.20],[.5,.21,.17]),('night',[.009,.019,.055],[.075,.095,.16])]:
 sky=np.array(horizon)*(1-up)**3+np.array(top)*(1-(1-up)**3)
 ground=np.array(horizon)*(.16 if name=='night' else .23)
 sky=np.where((alt<0)[:,:,None],ground,sky)
 cloud=(.5+.5*np.sin(x*.019+np.sin(y*.045)*2))*(.5+.5*np.sin(x*.047-y*.013))
 cloud=np.maximum(cloud-.5,0)*np.exp(-((alt-.25)/.19)**2)*(alt>0)
 sky+=cloud[:,:,None]*np.array([.24,.23,.25])*(.2 if name=='night' else 1)
 if name=='night':
  rng=np.random.default_rng(71);mask=(rng.random((H,W))>.9992)&(alt>.12);sky[mask]+=.55
 sky[:,0]=sky[:,-1]=(sky[:,0]+sky[:,-1])*.5
 scope['hdr'](D/(name+'.hdr'),sky)
print('Four original 1K time-of-day HDR variants')
