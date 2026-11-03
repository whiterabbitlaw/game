import numpy as np
from PIL import Image, ImageFilter, ImageDraw
W,H=720,1280
rng=np.random.default_rng(7)
def lerp(a,b,t): return a+(b-a)*t
def noise1d(n,scale,seed):
    r=np.random.default_rng(seed); k=int(n/scale)+3
    pts=r.random(k); x=np.linspace(0,k-3,n)
    i=x.astype(int); f=x-i; f=f*f*(3-2*f)
    return pts[i]*(1-f)+pts[i+1]*f
PAL={
 "dawn": dict(top=(255,236,214),mid=(236,226,240),bot=(190,222,232),sun=(255,214,170),ink=(120,150,180),mist=(255,248,240)),
 "dusk": dict(top=(255,196,170),mid=(240,190,200),bot=(170,170,214),sun=(255,168,130),ink=(118,104,160),mist=(255,225,215)),
 "night":dict(top=(40,46,96),mid=(70,72,130),bot=(110,110,170),sun=(240,240,255),ink=(36,40,84),mist=(150,150,210)),
 "rain": dict(top=(196,208,218),mid=(190,206,214),bot=(160,186,196),sun=(235,240,240),ink=(90,116,130),mist=(226,236,238)),
 "starry":dict(top=(22,26,70),mid=(54,52,120),bot=(100,92,160),sun=(255,244,214),ink=(28,28,72),mist=(140,130,200)),
}
def make(name,p):
    y=np.linspace(0,1,H)[:,None,None]
    top=np.array(p["top"])[None,None,:];mid=np.array(p["mid"])[None,None,:];bot=np.array(p["bot"])[None,None,:]
    g=np.where(y<0.5,lerp(top,mid,y/0.5),lerp(mid,bot,(y-0.5)/0.5))
    img=np.broadcast_to(g,(H,W,3)).copy()
    im=Image.fromarray(img.astype(np.uint8)).convert("RGBA")
    # sun / moon halo
    halo=Image.new("RGBA",(W,H),(0,0,0,0)); d=ImageDraw.Draw(halo)
    cx,cy=500,300
    for r,a in [(200,40),(150,60),(110,90),(78,255)]:
        d.ellipse((cx-r,cy-r,cx+r,cy+r),fill=p["sun"]+(a,))
    halo=halo.filter(ImageFilter.GaussianBlur(10)); im=Image.alpha_composite(im,halo)
    # stars for night
    if name in("night","starry"):
        s=Image.new("RGBA",(W,H),(0,0,0,0)); d=ImageDraw.Draw(s)
        for _ in range(110):
            x=rng.integers(0,W);yy=rng.integers(0,int(H*0.55));r=rng.choice([1,1,2]);d.ellipse((x-r,yy-r,x+r,yy+r),fill=(255,255,235,int(rng.integers(120,255))))
        im=Image.alpha_composite(im,s)
    # mountains layers
    layers=[(560,120,0.35,0),(680,150,0.55,1),(820,170,0.75,2),(980,120,0.95,3)]
    for base,amp,dens,i in layers:
        n=noise1d(W,90,i+3)*0.7+noise1d(W,30,i+13)*0.3
        top_y=base-n*amp*1.6
        m=Image.new("RGBA",(W,H),(0,0,0,0)); a=np.zeros((H,W),np.uint8)
        yy=np.arange(H)[:,None]
        a=(yy>=top_y[None,:]).astype(np.float32)
        a=np.clip(a,0,1)
        # vertical fade into mist
        fade=np.clip(1-(yy-top_y[None,:])/ (320),0.0,1)
        col=np.array(p["ink"],np.float32)*(1-0.55*(1-dens))+np.array(p["mist"],np.float32)*0.55*(1-dens)
        arr=np.zeros((H,W,4),np.float32); arr[...,:3]=col; arr[...,3]=a*(0.30+0.5*dens)*255*(0.55+0.45*fade)
        mi=Image.fromarray(arr.astype(np.uint8),"RGBA").filter(ImageFilter.GaussianBlur(1.6))
        im=Image.alpha_composite(im,mi)
        # mist band
        mb=Image.new("RGBA",(W,H),(0,0,0,0)); d=ImageDraw.Draw(mb)
        for k in range(14):
            x=rng.integers(-100,W);yv=int(base+rng.integers(-40,60));w=rng.integers(260,520)
            d.ellipse((x,yv-26,x+w,yv+30),fill=p["mist"]+(int(60+25*dens),))
        mb=mb.filter(ImageFilter.GaussianBlur(22)); im=Image.alpha_composite(im,mb)
    # foreground ground fade at bottom
    fg=np.zeros((H,W,4),np.float32); yy=np.linspace(0,1,H)[:,None]
    t=np.clip((yy-0.78)/0.22,0,1)
    fg[...,:3]=np.array(p["ink"])*0.55+np.array(p["mist"])*0.45; fg[...,3]=np.broadcast_to(t*150,(H,W))
    im=Image.alpha_composite(im,Image.fromarray(fg.astype(np.uint8),"RGBA"))
    im.convert("RGB").save(f"xianxia-game/assets/bg/{name}.jpg",quality=88)
for n,p in PAL.items(): make(n,p)
# cloud sprite
cl=Image.new("RGBA",(512,200),(0,0,0,0)); d=ImageDraw.Draw(cl)
for x,y,r in [(110,120,60),(190,90,80),(290,95,85),(380,120,62),(250,130,70)]:
    d.ellipse((x-r,y-r*0.6,x+r,y+r*0.6),fill=(255,255,255,200))
cl=cl.filter(ImageFilter.GaussianBlur(14)); cl.save("xianxia-game/assets/fx/cloud.png")
# soft glow circle & particle dot
g=np.zeros((128,128,4),np.uint8); yy,xx=np.mgrid[:128,:128]; r=np.hypot(xx-63.5,yy-63.5)/64
a=np.clip(1-r,0,1)**2; g[...,:3]=255; g[...,3]=(a*255).astype(np.uint8); Image.fromarray(g).save("xianxia-game/assets/fx/glow.png")
# ring
rg=np.zeros((256,256,4),np.uint8); yy,xx=np.mgrid[:256,:256]; r=np.hypot(xx-127.5,yy-127.5)/128
a=np.exp(-((r-0.86)/0.06)**2); rg[...,:3]=255; rg[...,3]=(a*255).astype(np.uint8); Image.fromarray(rg).save("xianxia-game/assets/fx/ring.png")
# heart & star small sprites
def star(path,pts,col):
    im=Image.new("RGBA",(64,64),(0,0,0,0)); d=ImageDraw.Draw(im); d.polygon(pts,fill=col); im=im.filter(ImageFilter.GaussianBlur(1)); im.save(path)
import math
pts=[]
for i in range(8):
    r=30 if i%2==0 else 8; a=i*math.pi/4-math.pi/2; pts.append((32+r*math.cos(a),32+r*math.sin(a)))
star("xianxia-game/assets/fx/spark.png",pts,(255,255,255,255))
