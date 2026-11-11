#!/usr/bin/env python3
"""Does the engine write the right registers to a sound chip? (the chips themselves are not in the emulator)

    python3 tools/chiplog.py LOG.ram gmc|ssc|sid

LOG.ram is a RAM dump of a run of an audio.asm built with -DTESTLOG=1: every byte the engine sends a chip is
logged at $0700-$0DEF (a ring), tick by tick. This puts the log in tick order, finds where in the start
music (assets/audio/synth/snd00.bin) it lies, and counts the voices (of the first 80 ticks) whose period or
frequency, volume and tone-or-noise are what the stream says. Exit 0 if 90% are right.
"""
import sys
import os
HERE=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
d=open(sys.argv[1],'rb').read(); chip=sys.argv[2]
p=(d[0xFD90]<<8)|d[0xFD91]
raw=d[0x700:0xDF0]; 
pos=p-0x700
ordered=raw[pos:]+raw[:pos]
e=[(ordered[a],ordered[a+1]) for a in range(0,len(ordered),2)]
ticks=[];cur=None
for t,b in e:
    if t==0: cur=[];ticks.append(cur)
    elif cur is not None: cur.append((t,b))
s=open(os.path.join(HERE,'assets','audio','synth','snd00.bin'),'rb').read()
def inc(k,v): return s[k*9+v*3]*256+s[k*9+v*3+1]
def vol(k,v): return s[k*9+v*3+2]&15
def wave(k,v): return s[k*9+v*3+2]>>4
if chip=='gmc':
    K=909318
    def dec(tk):
        tone={};att=[15,15,15,15];i=0;bs=[b for t,b in tk]
        while i<len(bs):
            b=bs[i]
            if b&0x80:
                ch=(b>>5)&3
                if b&0x10: att[ch]=b&15
                elif ch<3: tone[ch]=((bs[i+1]&0x3F)<<4)|(b&15); i+=1
            i+=1
        return tone,att
    def check(tk,k):
        tone,att=dec(tk); good=tot=0
        for v in range(3):
            if vol(k,v)==0: continue
            tot+=1
            if wave(k,v)==8: good+= (att[3]==15-vol(k,v)); continue
            ep=K//inc(k,v)
            while ep>1023: ep//=2
            good+= (v in tone and abs(tone[v]-ep)<=max(2,ep*.01) and att[v]==15-vol(k,v))
        return good,tot
elif chip=='ssc':
    K=909318
    def dec(tk):
        bs=[b for t,b in tk]
        regs={}
        i=0
        if bs and bs[0]==0xAF: i=1
        while i+1<len(bs) and bs[i]!=0xFF:
            regs[bs[i]]=bs[i+1]; i+=2
        return regs
    def check(tk,k):
        r=dec(tk); good=tot=0
        for v in range(3):
            if vol(k,v)==0: continue
            tot+=1
            if wave(k,v)==8:
                good+=(r.get(8+v)==vol(k,v) and not (r.get(7,0x3F)&(8<<v)));continue
            ep=K//inc(k,v)
            per=(r.get(2*v+1,0)<<8)|r.get(2*v,0)
            good+=(abs(per-ep)<=max(2,ep*.01) and r.get(8+v)==vol(k,v) and not (r.get(7,0x3F)&(1<<v)))
        return good,tot
else:  # sid
    def dec(tk):
        regs={};i=0;bs=tk
        while i+1<len(bs):
            if bs[i][0]==3 and bs[i+1][0]==4: regs[bs[i][1]]=bs[i+1][1]; i+=2
            else: i+=1
        return regs
    def check(tk,k):
        r=dec(tk); good=tot=0
        for v in range(3):
            if vol(k,v)==0: continue
            tot+=1
            b=7*v; fn=(r.get(b+1,0)<<8)|r.get(b,0); ef=round(inc(k,v)*8062/65536*16.777216)
            good+=(abs(fn-ef)<=max(3,ef*.004) and (r.get(b+6,0)>>4)==vol(k,v) and (r.get(b+4,0)&1)==1)
        return good,tot
best=None
for off in range(0,264):
    g=t=0
    for j,tk in enumerate(ticks[:80]):
        k=j+off
        if k*9+9>len(s): break
        a,b=check(tk,k); g+=a; t+=b
    if t>=30 and (best is None or g/t>best[0]): best=(g/t,off,g,t)
print('%s: %d ticks logged, best fit at tick %s: %s of %s voices right' % (chip, len(ticks), best[1] if best else '?', best[2] if best else 0, best[3] if best else 0))
sys.exit(0 if best and best[0] >= 0.9 else 1)
