"""Original lightweight glTF 2.0 traffic meshes, generated offline from TrafficProfiles.
No third-party model/texture inputs. Standard-library generator; Pillow preview is optional.
"""
import json, math, struct
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'Assets/Traffic'
BODY_STEPS=80
WHEEL_SEGMENTS=24
PROFILES=json.loads((ROOT/'Data/TrafficProfiles.json').read_text())
DARK=(.035,.055,.075); GLASS=(.055,.14,.19); RUBBER=(.025,.031,.04); ALLOY=(.58,.64,.68)

def sub(a,b): return tuple(x-y for x,y in zip(a,b))
def cross(a,b): return (a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])
def dot(a,b): return sum(x*y for x,y in zip(a,b))

class Shape:
    def __init__(self): self.groups={i:[] for i in range(7)}
    def tri(self,a,b,c,color,normal=None,group=0):
        n=cross(sub(b,a),sub(c,a)); mag=math.sqrt(dot(n,n))
        if mag<1e-9:return
        if normal and dot(n,normal)<0:b,c=c,b;n=tuple(-x for x in n)
        n=tuple(x/mag for x in n)
        if group==1: role=5 if color[0]<.9 else 6
        elif color==GLASS: role=1
        elif color==DARK: role=2
        elif color==RUBBER: role=3
        elif color==ALLOY: role=4
        else: role=0
        self.groups[role].append((a,b,c,n,color))
    def quad(self,a,b,c,d,color,normal=None,group=0):
        self.tri(a,b,c,color,normal,group);self.tri(a,c,d,color,normal,group)
    def box(self,at,size,color,group=0):
        x,y,z=at;w,h,l=[v/2 for v in size]
        pts=[(x+dx*w,y+dy*h,z+dz*l) for dx,dy,dz in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]]
        for ids,n in [([0,1,2,3],(0,0,-1)),([4,5,6,7],(0,0,1)),([0,3,7,4],(-1,0,0)),([1,2,6,5],(1,0,0)),([3,2,6,7],(0,1,0)),([0,1,5,4],(0,-1,0))]:
            self.quad(*(pts[i] for i in ids),color,n,group)

def body(p):
    s=Shape();l=p['length']/2;w=p['width']/2;h=p['height'];r=p['wheel_radius'];wb=p['wheelbase']/2
    paint=tuple(p['color']);hood=p['hood_y'];sill=.25 if h<1.5 else .31
    def width(z):return w*(.9+.1*min(1,(l-abs(z))/.4))
    def deck(z):return hood-.14*max(0,(abs(z)-(l-.42))/.42)
    # Lower side boundary follows an actual wheel-arch cutout, not a box hiding the tire.
    zs=sorted(set([-l,l]+[-l+i*p['length']/BODY_STEPS for i in range(BODY_STEPS+1)]+[c+d for c in [-wb,wb] for d in [-r-.075,r+.075]]))
    def low(z):
        result=sill
        for center in [-wb,wb]:
            d=z-center;ar=r+.06
            if abs(d)<ar:result=max(result,r+math.sqrt(ar*ar-d*d))
        return min(result,deck(z)-.018)
    for za,zb in zip(zs,zs[1:]):
        wa,wbx=width(za),width(zb);ya,yb=deck(za),deck(zb)
        if not (p['style']=='utility pickup' and za>p['rear_glass_z']+.06):
            s.quad((-wa+.065,ya,za),(wa-.065,ya,za),(wbx-.065,yb,zb),(-wbx+.065,yb,zb),paint,(0,1,0))
        for side in [-1,1]:
            s.quad((side*wa,low(za),za),(side*wa,ya-.07,za),(side*wbx,yb-.07,zb),(side*wbx,low(zb),zb),paint,(side,0,0))
            s.quad((side*wa,ya-.07,za),(side*(wa-.065),ya,za),(side*(wbx-.065),yb,zb),(side*wbx,yb-.07,zb),paint,(side,1,0))
    for z,n in [(-l,(0,0,-1)),(l,(0,0,1))]:
        s.quad((-width(z),sill,z),(width(z),sill,z),(width(z)-.065,deck(z),z),(-width(z)+.065,deck(z),z),paint,n)
    s.box((0,sill,-.05),(p['width']*.67,.1,p['length']-.2),DARK)
    # Sloped glazing, a separate roof plane, and explicitly split side windows/pillars.
    wf=p['windshield_z'];rf=p['roof_front_z'];rr=p['roof_rear_z'];rg=p['rear_glass_z'];rw=w*.72;bw=w*.84
    s.quad((-bw,hood+.015,wf),(bw,hood+.015,wf),(rw,h-.045,rf),(-rw,h-.045,rf),GLASS,(0,1,-1))
    s.quad((-rw,h-.025,rf),(rw,h-.025,rf),(rw,h-.025,rr),(-rw,h-.025,rr),paint,(0,1,0))
    s.quad((-rw,h-.045,rr),(rw,h-.045,rr),(bw,hood+.015,rg),(-bw,hood+.015,rg),GLASS,(0,1,1))
    mid=(rf+rr)/2
    for side in [-1,1]:
        # Window strips leave visible A/B/C pillars and a beltline.
        s.quad((side*bw,hood+.04,wf+.09),(side*rw,h-.075,rf+.07),(side*rw,h-.075,mid-.04),(side*bw,hood+.04,mid-.04),GLASS,(side,0,0))
        s.quad((side*bw,hood+.04,mid+.055),(side*rw,h-.075,mid+.055),(side*rw,h-.075,rr-.06),(side*bw,hood+.04,rg-.1),GLASS,(side,0,0))
        for lo,hi in [(wf,rf),(rg,rr)]:
            s.quad((side*(bw+.035),hood,lo),(side*(rw+.035),h,hi),(side*(rw-.025),h,hi+.05),(side*(bw-.025),hood,lo+.065),paint,(side,0,0))
        s.quad((side*bw,hood,mid-.04),(side*rw,h,mid-.04),(side*rw,h,mid+.055),(side*bw,hood,mid+.055),DARK,(side,0,0))
        s.box((side*(w+.055),hood+.09,wf+.13),(.17,.095,.22),paint)
        s.box((side*(w+.008),hood-.14,mid+.2),(.025,.03,.2),ALLOY)
        s.box((side*(w-.02),sill+.05,0),(.09,.105,p['wheelbase']-.9),DARK)
        for wz in [-p['wheelbase']/2,p['wheelbase']/2]:
            # Trim ring sits outside the cutout, leaving the wheel uncovered.
            for i in range(18):
                a=i*math.pi/18;b=(i+1)*math.pi/18
                def point(theta,rad):return (side*(w+.008),r+math.sin(theta)*rad,wz+math.cos(theta)*rad)
                s.quad(point(a,r+.045),point(a,r+.082),point(b,r+.082),point(b,r+.045),DARK,(side,0,0))
    # Intentional bumpers, grille, slim LED signatures and a rear lightbar.
    s.box((0,.34,-l-.025),(p['width']*.89,.16,.14),DARK)
    s.box((0,.47,-l-.071),(p['width']*.46,.13,.022),DARK)
    s.box((0,.32,l+.015),(p['width']*.9,.16,.12),DARK)
    for side in [-1,1]:
        s.box((side*w*.69,deck(-l)-.045,-l-.043),(.4,.048,.028),(.7,.92,1),1)
        s.box((side*w*.88,deck(-l)-.095,-l-.044),(.045,.14,.028),(.7,.92,1),1)
        s.box((side*w*.63,deck(l)-.065,l+.035),(.48,.055,.025),(1,.09,.1),1)
        s.box((side*w*.68,.41,-l-.073),(.28,.11,.025),DARK)
    if p['style']=='sporty fastback':
        s.box((0,hood+.055,l-.12),(p['width']*.86,.04,.19),DARK)
    if p['style']=='SUV crossover':
        for side in [-1,1]:s.box((side*rw,h+.008,(rf+rr)/2),(.045,.045,rr-rf+.2),DARK)
    if p['style']=='utility pickup':
        # Open load bed, rails and tailgate distinguish this from the passenger cabins.
        bed_start=rg+.06;bed_end=l-.09
        s.box((0,hood-.12,(bed_start+bed_end)/2),(p['width']*.8,.06,bed_end-bed_start),DARK)
        for side in [-1,1]:s.box((side*w*.91,hood+.045,(bed_start+bed_end)/2),(.14,.25,bed_end-bed_start),paint)
        s.box((0,hood+.02,l-.035),(p['width']*.9,.26,.085),paint)
    return s

def wheel(radius):
    s=Shape();segments=WHEEL_SEGMENTS
    rings=[(-.125,.78*radius),(-.11,.96*radius),(-.07,radius),(.07,radius),(.11,.96*radius),(.125,.78*radius)]
    for (x0,r0),(x1,r1) in zip(rings,rings[1:]):
        for i in range(segments):
            a=2*math.pi*i/segments;b=2*math.pi*(i+1)/segments
            pt=lambda x,r,t:(x,math.cos(t)*r,math.sin(t)*r)
            s.quad(pt(x0,r0,a),pt(x1,r1,a),pt(x1,r1,b),pt(x0,r0,b),RUBBER,(0,math.cos((a+b)/2),math.sin((a+b)/2)))
    for side in [-1,1]:
        x=side*.127
        for i in range(segments):
            a=2*math.pi*i/segments;b=2*math.pi*(i+1)/segments
            s.tri((x,0,0),(x,math.cos(a)*radius*.79,math.sin(a)*radius*.79),(x,math.cos(b)*radius*.79,math.sin(b)*radius*.79),DARK,(side,0,0))
            def rim(t,r):return (x+side*.004,math.cos(t)*r,math.sin(t)*r)
            s.quad(rim(a,radius*.7),rim(a,radius*.79),rim(b,radius*.79),rim(b,radius*.7),ALLOY,(side,0,0))
        for i in range(5):
            a=2*math.pi*i/5;z=side*.134
            def spoke(t,r):return (z,math.cos(t)*r,math.sin(t)*r)
            s.quad(spoke(a-.10,.055),spoke(a-.055,radius*.72),spoke(a+.055,radius*.72),spoke(a+.10,.055),ALLOY,(side,0,0))
        s.box((side*.137,0,0),(.012,.09,.09),ALLOY)
    return s

def write_glb(p,shapes):
    binary=bytearray();views=[];accessors=[];meshes=[]
    def accessor(values,components,kind):
        while len(binary)%4:binary.append(0)
        off=len(binary);flat=[v for row in values for v in row]
        binary.extend(struct.pack('<'+'f'*len(flat),*flat));idx=len(views)
        views.append({'buffer':0,'byteOffset':off,'byteLength':len(binary)-off,'target':34962})
        a={'bufferView':idx,'componentType':5126,'count':len(values),'type':kind}
        if kind=='VEC3':a.update(min=[min(v[i] for v in values) for i in range(components)],max=[max(v[i] for v in values) for i in range(components)])
        accessors.append(a);return len(accessors)-1
    for name,shape in shapes:
        primitives=[]
        for mat,triangles in shape.groups.items():
            if not triangles:continue
            pos=[];normal=[];colors=[]
            for a,b,c,n,color in triangles:
                pos.extend([a,b,c]);normal.extend([n]*3);colors.extend([(*color,1)]*3)
            primitives.append({'attributes':{'POSITION':accessor(pos,3,'VEC3'),'NORMAL':accessor(normal,3,'VEC3')},'material':mat,'mode':4})
        meshes.append({'name':name,'primitives':primitives})
    nodes=[{'name':p['id'],'children':[1,2,3,4,5]},{'name':'Body','mesh':0}]
    for i,(x,z) in enumerate([(side*(p['width']/2-.055),z) for z in [-p['wheelbase']/2,p['wheelbase']/2] for side in [-1,1]]):
        nodes.append({'name':'Wheel_'+str(i),'mesh':1,'translation':[x,p['wheel_radius'],z]})
    doc={'asset':{'version':'2.0','generator':'Velocity Rush original procedural traffic v2.1'},'scene':0,'scenes':[{'nodes':[0]}],'nodes':nodes,'meshes':meshes, 'materials':[
        {'name':name,'pbrMetallicRoughness':{'baseColorFactor':[*color,1],'metallicFactor':metal,'roughnessFactor':rough},'doubleSided':True,**({'emissiveFactor':[v*.16 for v in color]} if name in ['Headlight','Taillight'] else {})}
        for name,color,metal,rough in [('Paint',p['color'],.62,.27),('Glass',GLASS,.28,.16),('Trim',DARK,.15,.6),('Rubber',RUBBER,0,.92),('Alloy',ALLOY,.8,.25),('Headlight',(.7,.92,1),.15,.22),('Taillight',(.65,.035,.045),.1,.3)]],
        'buffers':[{'byteLength':len(binary)}],'bufferViews':views,'accessors':accessors}
    payload=json.dumps(doc,separators=(',',':')).encode();payload+=b' '*((-len(payload))%4);binary+=b'\0'*((-len(binary))%4)
    glb=struct.pack('<III',0x46546C67,2,12+8+len(payload)+8+len(binary))+struct.pack('<II',len(payload),0x4E4F534A)+payload+struct.pack('<II',len(binary),0x004E4942)+binary
    (OUT/(p['id']+'.glb')).write_bytes(glb)
    return {'id':p['id'],'triangles':sum(len(t) for t in shapes[0][1].groups.values())+4*sum(len(t) for t in shapes[1][1].groups.values()),'bytes':len(glb),'wheel_contact_y':0.0}

def preview(models):
    try:from PIL import Image,ImageDraw,ImageFont
    except ImportError:return
    im=Image.new('RGB',(1500,1210),(9,19,29));draw=ImageDraw.Draw(im)
    font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',22)
    small=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',15)
    yaw=.65;pitch=.32
    def project(v):
        x,y,z=v;xx=x*math.cos(yaw)+z*math.sin(yaw);zz=-x*math.sin(yaw)+z*math.cos(yaw)
        return xx,-y*math.cos(pitch)-zz*math.sin(pitch),-y*math.sin(pitch)+zz*math.cos(pitch)
    for i,(p,body_mesh,wheel_mesh) in enumerate(models):
        col=i%2;row=i//2;cx=375+col*750;cy=220+row*340;scale=103
        tris=[]
        pieces=[(body_mesh,(0,0,0))]+[(wheel_mesh,(side*(p['width']/2-.055),p['wheel_radius'],z)) for z in [-p['wheelbase']/2,p['wheelbase']/2] for side in [-1,1]]
        draw.ellipse((cx-245,cy-20,cx+245,cy+87),fill=(5,12,18))
        for mesh,offset in pieces:
            for group in mesh.groups.values():
                for a,b,c,n,color in group:
                    pts=[project(tuple(v[j]+offset[j] for j in range(3))) for v in [a,b,c]]
                    light=.55+.45*max(0,dot(n,(-.3,.8,-.5)))
                    rgb=tuple(int(min(255,255*(max(0,v*light)**.7))) for v in color)
                    tris.append((sum(t[2] for t in pts)/3,[(cx+t[0]*scale,cy+t[1]*scale) for t in pts],rgb))
        for _,points,color in sorted(tris,reverse=True):draw.polygon(points,fill=color)
        draw.text((cx-310,cy+103),p['name']+' / '+p['style'].upper(),font=font,fill=(213,237,240))
        draw.text((cx-310,cy+134),f"{p['length']:.2f} m long | {p['height']:.2f} m high | original mesh",font=small,fill=(117,157,171))
    draw.text((60,1115),'GEOMETRY PREVIEW',font=font,fill=(70,225,211))
    draw.text((60,1150),'Offline projection of the delivered meshes.',font=small,fill=(162,184,199))
    draw.text((730,1150),'Not a Godot screenshot or performance test.',font=small,fill=(162,184,199))
    im.save(ROOT/'Docs/traffic-geometry-preview.png')

def main():
    OUT.mkdir(exist_ok=True);report=[];models=[]
    for p in PROFILES:
        b=body(p);w=wheel(p['wheel_radius']);models.append((p,b,w));report.append(write_glb(p,[('Body',b),('Wheel',w)]))
    (ROOT/'Docs/traffic-mesh-metrics.json').write_text(json.dumps(report,indent=2)+'\n');preview(models)
    print(json.dumps(report))
if __name__=='__main__':main()
