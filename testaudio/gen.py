# Synthetic "beats" with known key and BPM: diatonic chord progression + bass + drums.
import numpy as np, wave, json, subprocess
SR=44100
ROOTS=['C','C#','D','D#','E','F','F#','G','G#','A','A#','B']
MAJ=[0,2,4,5,7,9,11]; MIN=[0,2,3,5,7,8,10]
rng=np.random.default_rng(7)
def note(f,dur,amp,kind='keys'):
    t=np.arange(int(dur*SR))/SR
    if kind=='keys':
        w=np.sin(2*np.pi*f*t)+0.4*np.sin(4*np.pi*f*t)+0.2*np.sin(6*np.pi*f*t)
        env=np.minimum(1,t/0.01)*np.exp(-t*1.2)
    else: # bass / 808
        w=np.sin(2*np.pi*f*t)+0.15*np.sin(4*np.pi*f*t)
        env=np.minimum(1,t/0.005)*np.exp(-t*2.0)
    return amp*w*env
def kick(): 
    t=np.arange(int(0.25*SR))/SR; f=50+90*np.exp(-t*30)
    return 0.9*np.sin(2*np.pi*np.cumsum(f)/SR)*np.exp(-t*12)
def snare():
    t=np.arange(int(0.18*SR))/SR
    return 0.5*(rng.uniform(-1,1,len(t))*np.exp(-t*25)+0.4*np.sin(2*np.pi*190*t)*np.exp(-t*30))
def hat():
    t=np.arange(int(0.05*SR))/SR
    x=rng.uniform(-1,1,len(t)); x=np.diff(np.concatenate([[0],x]))
    return 0.18*x*np.exp(-t*80)
def mix(buf,x,start):
    s=int(start*SR); e=min(len(buf),s+len(x)); 
    if s<len(buf): buf[s:e]+=x[:e-s]
def make(name,root,mode,bpm,bars=8,prog=None,halftime=False,swing=0.0):
    pc=ROOTS.index(root); sc=MAJ if mode=='major' else MIN
    prog=prog or ([0,4,5,3] if mode=='major' else [0,5,2,6])  # I V vi IV / i VI III VII
    beat=60/bpm; bar=4*beat; n=int(bars*bar*SR)+SR; buf=np.zeros(n)
    tonic=48+pc  # C3 area
    for b in range(bars):
        deg=prog[b%len(prog)]; t0=b*bar
        chord=[sc[(deg+i)%7]+12*((deg+i)//7) for i in (0,2,4)]
        for i,iv in enumerate(chord):
            f=440*2**((tonic+12+iv-69)/12); mix(buf,note(f,bar,0.12),t0)
        fb=440*2**((tonic-12+sc[deg]-69)/12)
        for k in (0,2.5) if not halftime else (0,):
            mix(buf,note(fb,beat*1.5,0.35,'bass'),t0+k*beat)
        # drums
        kicks=[0,2] if not halftime else [0,2.75]
        snares=[1,3] if not halftime else [2]
        for k in kicks: mix(buf,kick(),t0+k*beat)
        for s in snares: mix(buf,snare(),t0+s*beat)
        for h in range(8): 
            off=(swing*beat/2) if h%2 else 0
            mix(buf,hat(),t0+h*beat/2+off)
    buf=buf/np.max(np.abs(buf))*0.89
    st=np.stack([buf,buf*0.97],1)
    pcm=(st*32767).astype('<i2')
    with wave.open(name+'.wav','wb') as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())
CASES=[
 ('beat01','A','minor',140.0,False,0.0,'mp3'),
 ('beat02','C','major',90.0,False,0.0,'wav'),
 ('beat03','F#','minor',72.5,False,0.0,'flac'),
 ('beat04','D#','major',128.0,False,0.0,'m4a'),
 ('beat05','G','minor',95.0,False,0.12,'mp3'),
 ('beat06','E','minor',150.0,True,0.0,'wav'),
 ('beat07','A#','major',102.75,False,0.0,'flac'),
 ('beat08','B','minor',87.0,False,0.0,'mp3'),
 ('beat09','F','major',120.0,False,0.0,'aiff'),
 ('beat10','C#','minor',160.0,True,0.0,'m4a'),
]
meta=[]
for name,root,mode,bpm,ht,sw,fmt in CASES:
    make(name,root,mode,bpm,halftime=ht,swing=sw)
    out=f'{name}.{fmt}'
    if fmt!='wav':
        args={'mp3':['-c:a','libmp3lame','-b:a','192k'],'flac':['-c:a','flac'],'m4a':['-c:a','aac','-b:a','192k'],'aiff':['-c:a','pcm_s16be']}[fmt]
        subprocess.run(['ffmpeg','-y','-loglevel','error','-i',name+'.wav',*args,out],check=True)
        import os; os.remove(name+'.wav')
    meta.append(dict(file=out,key=f'{root} {mode}',bpm=bpm,halftime=ht,swing=sw))
json.dump(meta,open('truth.json','w'),indent=1)
print(json.dumps(meta))
