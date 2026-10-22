"""Six original authored parameter sets; writes only expansion assets, never original cars."""
import copy,json,math,wave,struct
import generate_sports_models as g
R=g.R
specs=[('tempest_gt','Tempest GT','Grand Tourer',4.95,2.03,1.39,2.93,.81,-1.02,-.18,.75,1.48,0,350000),('nebula_r','Nebula R','Electric Hypercar',4.72,2.15,1.13,2.92,.59,-1.61,-.83,.35,1.28,4,650000),('razor_x','Razor X','Track Supercar',4.28,2.12,1.12,2.60,.62,-.97,-.50,.18,.78,3,520000),('solaris_v','Solaris V','Hybrid Supercar',4.83,2.01,1.32,2.84,.76,-1.26,-.53,.65,1.43,1,750000),('cyclone_rs','Cyclone RS','Performance Coupe',4.54,2.22,1.23,2.70,.75,-.86,-.24,.27,.95,2,900000),('aether_one','Aether One','Flagship Hypercar',5.16,2.20,1.09,3.08,.59,-1.58,-.86,.54,1.71,5,1400000)]
cat=json.loads((R/'Data/VehicleCatalog.json').read_text());cat['cars']=cat['cars'][:6];metrics=[]
for n,(id,name,cls,L,W,H,wb,hood,wf,rf,rr,rg,style,price) in enumerate(specs):
 p=copy.deepcopy(cat['cars'][style]);p.update(id=id,name=name,**{'class':cls},price=price,length=L,width=W,height=H,wheelbase=wb,hood_y=hood,windshield_z=wf,roof_front_z=rf,roof_rear_z=rr,rear_glass_z=rg,top_speed_kmh=265+n*12,turbo_speed=325+n*12,acceleration=14+n*.8,weight_kg=1450-n*35)
 p['engine_sound_id']=cat['cars'][style]['id'];p['interior']['style']=style;p['interior']['steering_style']=(style+2)%6;p['interior']['cluster_style']=(style+1)%6;p['interior']['accent']=['d6a86c','78efff','f5dd76','a6e4d7','cf8ff5','e7eefb'][n];p['interior']['horn_path']='res://Assets/Audio/horn_'+id+'.wav'
 for tier in g.TIERS:
  body=g.vehicle(p,style,tier)
  # Individually authored LED paths: arc, full-width bridge, chevrons,
  # broken ribbons, vertical hooks, and nested orbital signatures.
  for side in [-1,1]:
   front=-L/2-.10;rear=L/2+.11
   if n==0:points=[(side*(.45+j*.055),hood-.08+.07*math.sin(j/9*math.pi),front) for j in range(10)]
   elif n==1:points=[(side*j*W*.045,hood-.06+.04*math.cos(j/10*math.pi),front) for j in range(11)]
   elif n==2:points=[(side*.92,hood-.03,front),(side*.60,hood-.12,front),(side*.90,hood-.19,front)]
   elif n==3:points=[(side*(.45+j*.045),hood-.04+.05*math.sin(j*.4),front) for j in range(10)]
   elif n==4:points=[(side*.88,hood-.25,front),(side*.88,hood-.02,front),(side*.55,hood-.02,front)]
   else:points=[(side*(.71+.19*math.cos(j/16*math.tau)),hood-.08+.055*math.sin(j/16*math.tau),front) for j in range(17)]
   pass # LED detail stays inside the authored fascia housing.
   pass # No detached overlay at the bumper end plane.
  wheels=g.wheel(p['wheel_radius'],tier,style)
  # Distinct hub accent and spoke counts from each base wheel language.
  for side in [-1,1]:
   wheels.tube([(side*.16,.065*math.cos(j/12*math.tau),.065*math.sin(j/12*math.tau)) for j in range(13)],.009,10,6)
  metrics.append(g.write_glb(p,body,wheels,tier));print(id,tier['name'],flush=True)
 p['visual_scene_path']=f'res://Assets/Player/{id}.glb';p['visual_lod_paths']=[f'res://Assets/Player/{id}_low.glb',f'res://Assets/Player/{id}_medium.glb',p['visual_scene_path']]
 p['camera_anchors']=[[0,3.3,7.4],[0,5.4,12],[0,hood+.32,wf-.18],[0,.54,-L/2-.26],[-.30,H-.13,rf+.10]]
 p['attachment_markers']={k:v for k,v in zip(['camera_chase_anchor','camera_far_anchor','camera_hood_anchor','camera_bumper_anchor','camera_cockpit_anchor'],p['camera_anchors'])};p['attachment_markers'].update(headlight_L=[-W*.32,hood-.04,-L/2-.03],headlight_R=[W*.32,hood-.04,-L/2-.03]);p['rear_light_points']=[[-W*.3,hood-.07,L/2],[W*.3,hood-.07,L/2]];p['exhaust_points']=[[-W*.30,.4,L/2+.06],[W*.30,.4,L/2+.06]]
 with wave.open(str(R/f'Assets/Audio/horn_{id}.wav'),'wb') as f:
  f.setparams((1,2,16000,0,'NONE','not compressed'));samples=[]
  for i in range(7200):
   t=i/16000;env=min(1,t/.025)*min(1,(.45-t)/.07);v=env*.3*(math.sin(math.tau*(310+n*23)*t)+.6*math.sin(math.tau*(415+n*17)*t));samples.append(struct.pack('<h',int(v*24000)))
  f.writeframes(b''.join(samples))
 # Lighting anchors follow this car's curved fascia, not the donor configuration.
 tip,waist,muscle=[(.88,.055,.11),(.81,.035,.12),(.90,.09,.14),(.77,.105,.10),(.72,.12,.08),(.79,.12,.15)][style]
 p['light_anchors']={}
 for rear in [False,True]:
  sign=1 if rear else -1;z=sign*L/2;w=W/2*(tip-waist*math.exp(-(z/.7)**2)+.018*math.exp(-((z-wb/2)/.4)**2));top=hood-.17+muscle*max(math.exp(-((z-wb/2)/.36)**2),math.exp(-((z+wb/2)/.36)**2))
  for side,label in [(-1,'left'),(1,'right')]:
   p['light_anchors'][('rear' if rear else 'front')+'_'+label+'_light_anchor']=[side*w*.65,top-.025,z+sign*(.123-.28*.65**2)]
   if rear:p['light_anchors']['reverse_'+label+'_anchor']=[side*w*.5,top-.055,z+.123-.28*.5**2]
  if rear:p['light_anchors']['high_brake_anchor']=[0,top-.015,z+.102]
 cat['cars'].append(p)
(R/'Data/VehicleCatalog.json').write_text(json.dumps(cat,indent=2)+'\n');(R/'Docs/expansion-lods.json').write_text(json.dumps(metrics,indent=2)+'\n')
