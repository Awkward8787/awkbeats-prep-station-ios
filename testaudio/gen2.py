import json, subprocess, os, importlib.util
spec=importlib.util.spec_from_file_location('g','gen.py')
src=open('gen.py').read().split('CASES=[')[0]
ns={}; exec(src,ns)
# Set B: common producer progressions (fixed before evaluation)
CASES=[
 ('beat11','D','minor',145.0,[0,5,6,0],True,'mp3'),   # i VI VII i (trap)
 ('beat12','G','major',98.0,[0,3,4,0],False,'wav'),   # I IV V I
 ('beat13','C','minor',130.0,[0,3,4,0],False,'flac'),  # i iv v i
 ('beat14','E','major',85.5,[0,5,3,4],False,'m4a'),    # I vi IV V
 ('beat15','F','minor',76.0,[0,0,5,6],False,'mp3'),    # i i VI VII
 ('beat16','G#','minor',142.0,[0,3,5,4],True,'wav'),   # i iv VI v
 ('beat17','A','major',110.0,[0,4,5,3],False,'aiff'),  # I V vi IV
 ('beat18','D#','minor',68.0,[0,5,3,4],False,'mp3'),   # i VI iv v
 ('beat19','B','major',124.0,[0,3,0,4],False,'flac'),  # I IV I V
 ('beat20','F#','major',93.33,[0,5,3,4],False,'m4a'),  # I vi IV V
]
meta=json.load(open('truth.json'))
meta=[m for m in meta if m['file'][4:6] < '11']
for name,root,mode,bpm,prog,ht,fmt in CASES:
    ns['make'](name,root,mode,bpm,prog=prog,halftime=ht)
    out=f'{name}.{fmt}'
    if fmt!='wav':
        args={'mp3':['-c:a','libmp3lame','-b:a','192k'],'flac':['-c:a','flac'],'m4a':['-c:a','aac','-b:a','192k'],'aiff':['-c:a','pcm_s16be']}[fmt]
        subprocess.run(['ffmpeg','-y','-loglevel','error','-i',name+'.wav',*args,out],check=True); os.remove(name+'.wav')
    meta.append(dict(file=out,key=f'{root} {mode}',bpm=bpm,halftime=ht,set='B'))
for m in meta: m.setdefault('set','A')
json.dump(meta,open('truth.json','w'),indent=1)
