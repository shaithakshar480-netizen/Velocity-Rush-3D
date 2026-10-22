"""Original lightweight vector illustrations for Velocity Rush's storefront."""
from pathlib import Path
import json,math
R=Path(__file__).resolve().parents[1];O=R/'Assets/Store';O.mkdir(exist_ok=True)
def svg(name,body):
 defs='''<defs><linearGradient id="gold" x2=".8" y2="1"><stop stop-color="#fff1a5"/><stop offset=".42" stop-color="#edbb4e"/><stop offset="1" stop-color="#936018"/></linearGradient><linearGradient id="blue" x2="1" y2="1"><stop stop-color="#b8f8ff"/><stop offset=".4" stop-color="#4cbcdf"/><stop offset="1" stop-color="#164367"/></linearGradient><linearGradient id="metal" x2="1" y2="1"><stop stop-color="#7e9aad"/><stop offset=".4" stop-color="#2d4357"/><stop offset="1" stop-color="#0f1b2b"/></linearGradient><radialGradient id="halo"><stop stop-color="#48c4ec" stop-opacity=".22"/><stop offset="1" stop-color="#48c4ec" stop-opacity="0"/></radialGradient></defs>'''
 (O/(name+'.svg')).write_text('<svg xmlns="http://www.w3.org/2000/svg" width="360" height="220" viewBox="0 0 360 220">'+defs+'<ellipse cx="180" cy="125" rx="170" ry="100" fill="url(#halo)"/><ellipse cx="180" cy="191" rx="127" ry="14" fill="#020b14" opacity=".6"/>'+body+'</svg>')
def coin(x,y,scale=1):
 return f'<g transform="translate({x} {y}) scale({scale})"><path d="M-28-4v9a28 11 0 0 0 56 0V-4" fill="#a06c23" stroke="#f0bf58"/><ellipse cy="-4" rx="28" ry="12" fill="url(#gold)" stroke="#fff0a7"/><ellipse cy="-4" rx="20" ry="8" fill="none" stroke="#a9792c"/><path d="m-8-8 7 10 9-12" fill="none" stroke="#fff3b7" stroke-width="3"/></g>'
def chest(big=False):
 return '<path d="M70 112 102 71H269l29 41-9 78H79Z" fill="url(#metal)" stroke="#9ab7c9" stroke-width="3"/><path d="M83 105 108 81H261l22 25Z" fill="#061422"/><path d="M81 118H287M110 115v72m145-72v72" stroke="'+('#eac978' if big else '#4ec6e5')+'" stroke-width="8"/><path d="M166 121h29v34h-29Z" fill="url(#gold)"/><path d="m172 132 8 12 10-17" fill="none" stroke="#644515" stroke-width="3"/>'
for tier in range(5):
 body=''
 if tier>=3:body+=chest(tier==4)
 if tier==2:body+='<path d="m139 47 15 32c-72 40-77 109 21 114 93 4 95-68 27-114l15-32-35 11Z" fill="url(#metal)" stroke="#70c4dc" stroke-width="3"/><path d="M145 79h63" stroke="#e3bd69" stroke-width="8"/><path d="m155 124 24 31 25-40" fill="none" stroke="#ffe294" stroke-width="10"/>'
 positions=[(165,174,5),(130,177,6),(221,183,4)] if tier==1 else [(178,170,5)]
 if tier>=2:positions=[(90,181,3),(269,184,4)]
 for x,y,n in positions:
  for i in range(n):body+=coin(x,y-i*9,1.3 if tier==0 else (.9 if tier==1 else .72))
 if tier>=3:
  for i in range(13 if tier==4 else 7):body+=coin(107+(i%6)*28,106-(i//6)*16,.65)
 if tier==4:body+='<path d="m53 81 5 12 13 5-13 5-5 13-5-13-13-5 13-5Zm258-52 4 10 11 4-11 4-4 11-4-11-10-4 10-4Z" fill="#fbe9aa"/>'
 svg(['coin_stack','coin_pile','coin_bag','coin_chest','coin_vault'][tier],body)
svg('turbo','<g transform="rotate(16 180 120)"><rect x="133" y="51" width="94" height="135" rx="25" fill="url(#blue)" stroke="#b8faff" stroke-width="3"/><path d="M148 49V29h64v20" fill="url(#metal)" stroke="#70d2ef" stroke-width="3"/><path d="M157 30V18h46v12M130 79h100m-101 83h102" fill="none" stroke="#14334b" stroke-width="8"/><path d="M186 77c8 25-27 34-17 57 8-1 13-11 13-18 34 34 12 53-8 42-25-15-4-41 2-50-2 12 3 13 3 13-7-19 3-27 7-44Z" fill="#e1fbff"/></g>')
svg('repair','<path d="M145 64V46h72v18" fill="none" stroke="#9bbaca" stroke-width="12"/><rect x="82" y="66" width="198" height="123" rx="18" fill="url(#metal)" stroke="#7dd4e5" stroke-width="3"/><path d="M83 108h196M109 83v16m141-16v16" stroke="#bdeafa" stroke-width="6"/><path d="M171 87a23 23 0 0 0 27 30l35 35-16 17-35-36a23 23 0 0 0-24-31l15 16 13-13Z" fill="url(#blue)"/>')
svg('magnet','<path d="M100 69v67a80 57 0 0 0 160 0V69h-45v67a35 25 0 0 1-70 0V69Z" fill="url(#blue)" stroke="#c5f5ff" stroke-width="3"/><path d="M100 69h45v26h-45zm115 0h45v26h-45Z" fill="url(#metal)"/><path d="M123 56q56-59 115 0m-95 0q35-35 71 0" fill="none" stroke="#6addf0" stroke-width="2" stroke-dasharray="6 7"/>'+coin(180,42,.55))
svg('shield','<path d="m180 25 83 34v60c0 37-83 80-83 80s-83-43-83-80V59Z" fill="url(#metal)" stroke="#6de0f5" stroke-width="6"/><path d="m180 43 66 26v48c0 28-66 62-66 62s-66-34-66-62V69Z" fill="url(#blue)" opacity=".5"/><path d="m145 103 26 28 46-57" fill="none" stroke="#d1fbff" stroke-width="12"/>')
car='<path d="M40 143 82 132 126 105Q171 88 218 106L266 135 318 145 309 171H48Z" fill="url(#metal)" stroke="#9bd9ed" stroke-width="3"/><path d="M132 109 105 130h140l-33-21Q170 97 132 109Z" fill="#52a6c3"/><path d="M65 137h52m129 0h41" stroke="#a3f4ff" stroke-width="6"/><circle cx="104" cy="161" r="21" fill="#08111b" stroke="#b4c7d0" stroke-width="6"/><circle cx="254" cy="161" r="21" fill="#08111b" stroke="#b4c7d0" stroke-width="6"/>'
for plan in ['weekly','monthly']:
 body='<path d="M30 68 138 44H330M18 95l97-15m132-35h78M21 180l55-9m202 7h56" fill="none" stroke="'+('#e1c17b' if plan=='monthly' else '#5cbddb')+'" stroke-width="4"/>'+car
 if plan=='monthly':body+='<path d="m180 18 9 16 18 3-13 13 2 18-16-8-16 8 2-18-13-13 18-3Z" fill="url(#gold)"/>'
 svg('pass_'+plan,body)
# Shared benefit symbols retain a consistent stroke treatment.
paths={'car':'M90 148 113 98h129l32 50Zm18 0v25m145-25v25M127 121h112','paint':'m122 63 94 94-47 34-94-94Zm106 92c26 29 34 44 11 44s-24-16-11-44Z','no_ads':'M96 77h173v101H96Zm-15-15 201 134','bonus':'M180 43v126m-40-39 40 40 40-40M112 81h136','calendar':'M100 69h160v122H100Zm0 35h160m-126-52v35m91-35v35'}
svg('benefit_coins',coin(180,122,2.4))
for k,d in paths.items():svg('benefit_'+k,f'<path d="{d}" fill="none" stroke="#8adceb" stroke-width="10" stroke-linejoin="round"/>')
config={'coins':{},'boosts':{},'memberships':{},'benefit_icons':{k:'res://Assets/Store/benefit_'+k+'.svg' for k in ['coins','car','paint','no_ads','bonus','calendar']}}
for price,art,badge in zip([50,80,150,250,500],['coin_stack','coin_pile','coin_bag','coin_chest','coin_vault'],['','POPULAR','','HIGH VALUE','BEST VALUE']):config['coins']['coins_'+str(price)]={'art':'res://Assets/Store/'+art+'.svg','badge':badge}
for id,title,desc in [('turbo','TURBO BOOSTERS','+2 Turbo Charges'),('repair','REPAIR KIT','Restore vehicle durability'),('magnet','COIN MAGNET','Attract nearby road coins'),('shield','SHIELD','Block one eligible impact')]:config['boosts'][id]={'art':'res://Assets/Store/'+id+'.svg','title':title,'description':desc,'reward_label':'+2 TURBO' if id=='turbo' else '+1 '+title}
for plan,days,price,coins,daily,bonus in [('weekly',7,99,8000,1500,10),('monthly',30,299,25000,2500,20)]:config['memberships'][plan]={'art':'res://Assets/Store/pass_'+plan+'.svg','title':plan.upper()+' RUSH PASS','duration':str(days)+' DAYS','fallback_price_inr':price,'price_period':'WEEK' if plan=='weekly' else 'MONTH','provider_product_id':plan,'badge':'BEST VALUE' if plan=='monthly' else 'WEEKLY ACCESS','initial_coins':coins,'daily_coins':daily,'race_bonus_percent':bonus}
(R/'Data/StorePresentation.json').write_text(json.dumps(config,indent=2)+'\n')
if __name__=='__main__':print('Created original Store SVGs and presentation mapping.')
