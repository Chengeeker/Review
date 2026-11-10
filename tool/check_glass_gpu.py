from ctypes import *
import os
import sys
import json
from pathlib import Path
import struct
import zlib

sdk=Path(os.environ['LOCALAPPDATA'])/'Android/Sdk/emulator/lib64/gles_swiftshader'
dll=os.add_dll_directory(str(sdk))
egl=WinDLL(str(sdk/'libEGL.dll'))
gles=WinDLL(str(sdk/'libGLESv2.dll'))
I,U,F,P=c_int,c_uint,c_float,c_void_p
def api(d,n,r,*a):
 f=getattr(d,n); f.restype=r; f.argtypes=a
 globals()[n]=f
def e(n,r,*a): api(egl,'egl'+n,r,*a)
def g(n,r,*a): api(gles,'gl'+n,r,*a)
e('GetDisplay',P,P); e('Initialize',I,P,P,P); e('BindAPI',I,U)
e('ChooseConfig',I,P,P,P,I,P); e('CreatePbufferSurface',P,P,P,P)
e('CreateContext',P,P,P,P,P);e('MakeCurrent',I,P,P,P,P)
g('GetString',c_char_p,U);g('GetError',U)
g('CreateShader',U,U);g('ShaderSource',None,U,I,P,P);g('CompileShader',None,U)
g('GetShaderiv',None,U,U,P);g('GetShaderInfoLog',None,U,I,P,P)
g('CreateProgram',U);g('AttachShader',None,U,U);g('LinkProgram',None,U)
g('GetProgramiv',None,U,U,P);g('GetProgramInfoLog',None,U,I,P,P);g('UseProgram',None,U)
g('GenBuffers',None,I,P);g('BindBuffer',None,U,U);g('BufferData',None,U,c_size_t,P,U)
g('EnableVertexAttribArray',None,U);g('VertexAttribPointer',None,U,I,U,c_ubyte,I,P)
g('GenTextures',None,I,P);g('ActiveTexture',None,U);g('BindTexture',None,U,U)
g('TexParameteri',None,U,U,I);g('TexImage2D',None,U,I,I,I,I,I,U,U,P)
g('GenFramebuffers',None,I,P);g('BindFramebuffer',None,U,U)
g('FramebufferTexture2D',None,U,U,U,U,I);g('CheckFramebufferStatus',U,U)
g('GetUniformLocation',I,U,c_char_p);g('Uniform1i',None,I,I);g('Uniform1f',None,I,F)
for k in range(1,5):g(f'Uniform{k}fv',None,I,I,P)
g('Viewport',None,I,I,I,I);g('DrawArrays',None,U,I,I)
g('ClearColor',None,F,F,F,F);g('Clear',None,U);g('Enable',None,U);g('Disable',None,U)
g('BlendFunc',None,U,U);g('ReadPixels',None,I,I,I,I,U,U,P)
d=eglGetDisplay(None)
assert d and eglInitialize(d,None,None) and eglBindAPI(0x30a0)
attrs=(I*15)(0x3033,1,0x3040,0x40,0x3024,8,0x3023,8,0x3022,8,0x3021,8,0x3038)
conf=P();count=I()
assert eglChooseConfig(d,attrs,byref(conf),1,byref(count)) and count.value
mode = sys.argv[1] if len(sys.argv) > 1 else "nav"
W,H=(412,172) if mode=="top" else (256,86)
surface=eglCreatePbufferSurface(d,conf,(I*5)(0x3057,W,0x3056,H,0x3038))
ctx=eglCreateContext(d,conf,None,(I*3)(0x3098,3,0x3038))
assert surface and ctx and eglMakeCurrent(d,surface,surface,ctx)
print('Renderer:',glGetString(0x1f01).decode())
root=Path(__file__).resolve().parent.parent
base=root/'app/src/main/assets/glass'
src=(root/'app/src/main/java/com/review/compose/GlassView.kt').read_text(encoding='utf-8')
vs=src.split('"""#version',1)[1].split('"""',1)[0]
vs=('#version'+vs).encode()
def program(name):
 p=glCreateProgram()
 for kind,source in ((0x8b31,vs),(0x8b30,(base/f'{name}.frag').read_bytes())):
  sh=glCreateShader(kind); strings=(c_char_p*1)(source)
  glShaderSource(sh,1,strings,None);glCompileShader(sh);glAttachShader(p,sh)
  ok=I();glGetShaderiv(sh,0x8b81,byref(ok))
  if not ok.value:
   log=create_string_buffer(8192);glGetShaderInfoLog(sh,len(log),None,log);raise RuntimeError(log.value)
 glLinkProgram(p);ok=I();glGetProgramiv(p,0x8b82,byref(ok))
 if not ok.value:
  log=create_string_buffer(8192);glGetProgramInfoLog(p,len(log),None,log);raise RuntimeError(log.value)
 return p
geometry,render,compose=[program(n) for n in ('liquid_glass_geometry_blended','liquid_glass_render','compose')]
program('gallery_button')  # GlassView compiles this shared compatibility program during initialization.
vbo=U();glGenBuffers(1,byref(vbo));glBindBuffer(0x8892,vbo)
glBufferData(0x8892,32,(F*8)(-1,-1,1,-1,-1,1,1,1),0x88e4)
glEnableVertexAttribArray(0);glVertexAttribPointer(0,2,0x1406,0,0,None)
glViewport(0,0,W,H)
tex=(U*7)();fbo=(U*4)();glGenTextures(7,tex);glGenFramebuffers(4,fbo)
def upload(i,data=None):
 glActiveTexture(0x84c0);glBindTexture(0xde1,tex[i])
 glTexImage2D(0xde1,0,0x1908,W,H,0,0x1908,0x1401,data)
for i in range(7):
 upload(i)
 for key,value in [(0x2801,0x2601),(0x2800,0x2601),(0x2802,0x812f),(0x2803,0x812f)]:
  glTexParameteri(0xde1,key,value)
for i in range(4):
 glBindFramebuffer(0x8d40,fbo[i]);glFramebufferTexture2D(0x8d40,0x8ce0,0xde1,tex[i+2],0)
 assert glCheckFramebufferStatus(0x8d40)==0x8cd5
def uniform(p,n,*v):
 loc=glGetUniformLocation(p,n.encode())
 if len(v)==1:glUniform1f(loc,v[0])
 elif len(v)<=4:globals()[f'glUniform{len(v)}fv'](loc,1,(F*len(v))(*v))
 else:glUniform1fv(loc,len(v),(F*len(v))(*v))
def sampler(p,n,unit,index):
 glActiveTexture(0x84c0+unit);glBindTexture(0xde1,tex[index])
 glUniform1i(glGetUniformLocation(p,n.encode()),unit)
def use(p,target):
 glBindFramebuffer(0x8d40,target);glUseProgram(p);uniform(p,'size',W,H)
def draw():glDrawArrays(5,0,4)
def blend(on):
 (glEnable if on else glDisable)(0xbe2)
 if on:glBlendFunc(1,0x303)
def comp(dst,source,flip=0,blur=0,vertical=False,indicator=0,labels=0,inner=0):
 use(compose,dst);sampler(compose,'source',0,source)
 for n,v in dict(flip=(flip,),blur=(blur,),denseBlur=(int(mode=="top"),),blurDirection=(0,1) if vertical else (1,0),
                 indicator=(indicator,),dark=(dark,),pill=pill,labelPass=(labels,),pillBlur=(inner,)).items():uniform(compose,n,*v)
 if labels:sampler(compose,'selectedLabels',2,6)
 if inner:sampler(compose,'pillBackdrop',3,5)
 draw()
def glass(lens, gallery=False, layer_fade=0):
 use(geometry,fbo[0]);blend(False)
 cx,cy,w,h=pill if lens else (128,43,48,48) if gallery else (128,43,216,56)
 ri,ca,t=(1.18,.025,20/3) if lens else (1.24,.025,32/3) if gallery else (1.16,.008,10/3)
 for n,v in dict(uSize=(W,H),uOpticalProps=(ri,ca,t,0),uShapeSettings=(1,1),
                 uNativeEdge=(float(lens and not dark),),uShapeData=(3,cx,cy,w,h,9999,9999)+(0,)*105).items():uniform(geometry,n,*v)
 draw()
 use(render,0 if lens else fbo[2]);blend(True)
 rgb=0 if gallery else dark if lens else 1-dark
 alpha=.4 if gallery else (38 if dark else 24)/255 if lens else (.4 if dark else 240/255)
 for n,v in dict(uSize=(W,H),uGeometryOffset=(cx-w/2,cy-h/2),uGeometrySize=(w,h),uGlassColor=(rgb,rgb,rgb,alpha),
                 uOpticalProps=(ri,ca,t,1),uLightConfig=(2 if lens else .25,0,1.5 if lens or gallery else 1),
                 uLightDirection=(-.7071068,.7071068),uWhiten=(0,),uWhitenGated=(1,),
                 uPinchStrength=(.7 if lens else 0,),uBackgroundFallback=(0,0,0,0),uCaptureOffset=(0,0),
                 uEdgeConfig=(0,1,1/3,0),uPlatformViewMode=(0,),uBodyMode=(1,),uTouchPosition=(cx,cy),
                 uTouchIntensity=(.125 if lens else 0,),uRimConfig=(.12 if lens and not dark else 0,.35 if lens and not dark else 0 if gallery else .12 if dark and not lens else 1 if not lens else 0,.2),
                 uLensModel=(0,),uFrost=(0,0,0,1),uBodyShade=(0,),uBackgroundFlip=(0,),uLayerFade=(layer_fade,)).items():uniform(render,n,*v)
 sampler(render,'uBackgroundTexture',0,0);sampler(render,'uGeometryTexture',1,2)
 draw()
def read():
 data=create_string_buffer(W*H*4);glReadPixels(0,0,W,H,0x1908,0x1401,data)
 return data.raw
def px(data,x,y):
 i=((H-y-1)*W+x)*4
 return tuple(data[i:i+4])
def png(path,data):
 def chunk(tag,b):return struct.pack('>I',len(b))+tag+b+struct.pack('>I',zlib.crc32(tag+b))
 raw=b''.join(b'\0'+data[(H-1-y)*W*4:(H-y)*W*4] for y in range(H))
 path.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',W,H,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(raw))+chunk(b'IEND',b''))

# The input is identical to GlassGpuTest.renderOriginalOpticsComparisonFrames.
scene=bytes(c for y in range(H) for x in range(W) for c in (x,y*3,220 if (x//16+y//16)%2==0 else 40,255))
upload(0,scene)
results=[]
for dark in (0,1):
 for lens in (0,1):
  pill=(128,43,97,67)
  glBindFramebuffer(0x8d40,0 if lens else fbo[2]);glClearColor(0,0,0,0);glClear(0x4000)
  glass(lens)
  assert glGetError()==0
  frame=read()
  actual=(root/f'app/build/parity/agsl-{str(bool(dark)).lower()}-{str(bool(lens)).lower()}.rgba').read_bytes()
  differences=[]
  alpha_error=0
  for y in range(H):
   for x in range(W):
    ref=px(frame,x,y)
    a=actual[(y*W+x)*4:(y*W+x+1)*4]
    alpha_error=max(alpha_error,abs(ref[3]-a[3]))
    if ref[3]==255 and a[3]==255:
     differences.extend(abs(ref[c]-a[c]) for c in range(3))
  ordered=sorted(differences)
  result=dict(dark=bool(dark),lens=bool(lens),mean=sum(ordered)/len(ordered),p99=ordered[int(len(ordered)*.99)],max=max(ordered),alphaMax=alpha_error)
  print(result)
  assert result['mean'] < .05 and result['p99'] <= 1 and result['max'] <= 16 and alpha_error <= 1, result
  results.append(result)
  png(root/f'build/original-optics-{dark}-{lens}.png',frame)
(root/'build/glass-optics-comparison.json').write_text(json.dumps(results,indent=2))


# A lens over transparent pixels must approach zero in premultiplied color and alpha.
def release_sample(fade):
 glBindFramebuffer(0x8d40,0);glClearColor(0,0,0,0);glClear(0x4000)
 glass(True, layer_fade=fade)
 assert glGetError()==0
 return px(read(),128,43)
active=release_sample(0)
half=release_sample(.5)
lifted=release_sample(1)
assert active[3] > 240 and lifted == (0,0,0,0)
assert all(abs(h-a*.5) <= 1 for h,a in zip(half,active)), (active,half)
print('Release opacity:', active, half, lifted)
