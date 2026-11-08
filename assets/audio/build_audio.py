#!/usr/bin/env python3
"""PAK FAN: original chiptune compositions and game effects.

Synthesizes all signals from mathematical oscillators, envelopes and the
original note patterns defined below. No external audio/ROM source required.
Produces 44.1 kHz PCM WAV, 6-bit CoCo DAC previews and binary DAC samples.
"""
from __future__ import annotations
import csv
import json
import math
import re
import wave
from pathlib import Path
import numpy as np
from scipy.signal import resample_poly

ROOT=Path(__file__).resolve().parent
MASTER_RATE=44100
DAC_RATE=8200
TWO_PI=2.0*np.pi
OUTPUTS={
    'master':ROOT/'WAV_Master_44100Hz',
    'preview':ROOT/'WAV_CoCo_6bit_8200Hz',
    'raw':ROOT/'6809_PCM_Data',
}
for d in OUTPUTS.values():d.mkdir(parents=True,exist_ok=True)

SOUNDS = [
  ('start_music','Opening theme','4.40-second original D-minor/Dorian game-start melody'),
  ('intermission_music','Intermission groove','Original syncopated A-Dorian chiptune with bass and percussion'),
  ('coin_insert','Credit accepted','Bright dual-register rising credit confirmation'),
  ('extra_life','Bonus life','Six-note sparkling fanfare with downward-resolution ending'),
  ('siren_1','Chase alert, low','Gentle triple-step warning arpeggio'),
  ('siren_2','Chase alert, medium-low','Quicker harmonic rising warning arpeggio'),
  ('siren_3','Chase alert, medium','Urgent alternating warning tones'),
  ('siren_4','Chase alert, high','Faster jagged warning cycle'),
  ('siren_5','Chase alert, maximum','Most urgent pulsing alert with a third accent'),
  ('power_pellet_fright','Power mode','Low pulsing, rhythmic electric growl'),
  ('ghost_eyes_return','Enemy returning','Light ascending and repeating shimmer'),
  ('eat_dot_1','Small pickup A','Quick two-pitch mouth-click and chirp'),
  ('eat_dot_2','Small pickup B','Alternating lower hollow bite click'),
  ('eat_fruit','Bonus pickup','Bright glassy three-pitch prize sparkle'),
  ('eat_ghost','Enemy captured','Grainy descending swoosh and chime'),
  ('death','Life lost','Multi-phrase descending digital dissolve'),
  ('fruit_bounce','Bouncing bonus','Tight springy rubber bounce'),
]

# Individual note names to frequencies, independent of legacy sound tables.
PITCH_INDEX={'C':0,'C#':1,'Db':1,'D':2,'D#':3,'Eb':3,'E':4,
             'F':5,'F#':6,'Gb':6,'G':7,'G#':8,'Ab':8,'A':9,
             'A#':10,'Bb':10,'B':11}
def hz(s):
    m=re.fullmatch(r'([A-G](?:#|b)?)([0-8])',s)
    if not m:raise ValueError(s)
    midi=12*(int(m.group(2))+1)+PITCH_INDEX[m.group(1)]
    return 440.0*2**((midi-69)/12)

def envelope(t,duration,attack=.004,release=.045,decay=0):
    up=np.minimum(1.0,t/max(attack,1e-6))
    down=np.clip((duration-t)/max(release,1e-6),0,1)
    return up*down*(np.exp(-t*decay) if decay else 1)

def oscillator(phase,waveform):
    # Original analytic waveforms, harmonics deliberately modest to survive
    # downsampling to the CoCo's roughly 4 kHz Nyquist limit.
    if waveform=='pulse':
        return (.75*np.sin(phase)+.33*np.sin(2*phase)-.2*np.sin(3*phase)
                +.12*np.sin(4*phase)-.075*np.sin(5*phase))
    if waveform=='triangle':
        return (np.sin(phase)-np.sin(3*phase)/9+np.sin(5*phase)/25)
    if waveform=='softsquare':
        return (.89*np.sin(phase)+.25*np.sin(3*phase)+.1*np.sin(5*phase))
    if waveform=='bell':
        return (.65*np.sin(phase)+.27*np.sin(2.01*phase)+.21*np.sin(3.99*phase))
    if waveform=='saw':
        return (.75*np.sin(phase)+.36*np.sin(2*phase)+.24*np.sin(3*phase)
                +.15*np.sin(4*phase)+.1*np.sin(5*phase))
    return np.sin(phase)

class Composer:
    def __init__(self,duration,seed=0):
        self.duration=duration
        self.mix=np.zeros(round(duration*MASTER_RATE),dtype=np.float64)
        self.rng=np.random.default_rng(seed)
    def note(self,start,dur,pitch,amp=.35,kind='pulse',attack=.003,release=.025,
             wobble=0.0,detune=0.0):
        if isinstance(pitch,str):pitch=hz(pitch)
        a=max(0,round(start*MASTER_RATE))
        b=min(len(self.mix),round((start+dur)*MASTER_RATE))
        if b<=a:return
        t=np.arange(b-a)/MASTER_RATE
        freq=pitch*(1+detune)+wobble*np.sin(TWO_PI*6.4*t)
        phase=np.cumsum(freq)*(TWO_PI/MASTER_RATE)
        self.mix[a:b]+=amp*envelope(t,dur,attack,release)*oscillator(phase,kind)
    def sweep(self,start,dur,fstart,fend,amp=.35,kind='pulse',shape='linear',
              attack=.002,release=.045,twist=0.0,echo=False):
        a=max(0,round(start*MASTER_RATE)); b=min(len(self.mix),round((start+dur)*MASTER_RATE))
        if b<=a:return
        t=np.arange(b-a)/MASTER_RATE
        frac=t/dur
        if shape=='exp':freq=fstart*np.exp(np.log(fend/fstart)*frac)
        else:freq=fstart+(fend-fstart)*frac
        freq=freq*(1+twist*np.sin(TWO_PI*(11.0*frac+7.0*frac**2)))
        phase=np.cumsum(freq)*(TWO_PI/MASTER_RATE)
        sig=amp*envelope(t,dur,attack,release)*oscillator(phase,kind)
        if echo:sig*=.70+.30*np.cos(TWO_PI*12.0*t)
        self.mix[a:b]+=sig
    def hiss(self,start,dur,amp=.18,bright=False):
        a=max(0,round(start*MASTER_RATE)); b=min(len(self.mix),round((start+dur)*MASTER_RATE))
        if b<=a:return
        t=np.arange(b-a)/MASTER_RATE
        white=self.rng.uniform(-1,1,len(t))
        if not bright:
            white=(white+np.roll(white,1)+np.roll(white,2))*0.33
        self.mix[a:b]+=amp*white*envelope(t,dur,attack=.0003,release=.025)*np.exp(-t*20)
    def thump(self,start,amp=.25):
        self.sweep(start,.105,155,51,amp,'triangle',release=.02)
    def signal(self):
        x=self.mix.copy()
        # Soft limit + level matching, preserve 6-bit dynamic range.
        x=np.tanh(x*1.18)
        peak=np.max(np.abs(x))
        if peak>0:x*=.87/peak
        # Sustained alerts should not be dramatically louder than jingles.
        loudness=np.sqrt(np.mean(x*x))
        if loudness>.38:x*=.38/loudness
        # 3-ms fade on non-looping ends (avoid DAC end click).
        fade=min(len(x),round(.006*MASTER_RATE))
        if fade:x[-fade:]*=np.linspace(1,0,fade)
        return x

def opening():
    tempo=168; step=60/tempo/4
    c=Composer(4.40,11)
    tune=[
        (0,2,'D5'),(2,2,'F5'),(4,3,'A5'),(7,1,'G5'),
        (8,2,'E5'),(10,2,'C6'),(12,2,'A5'),(14,2,'F5'),
        (16,2,'Bb4'),(18,1,'D5'),(19,3,'G5'),(22,2,'F5'),
        (24,1,'A5'),(25,3,'C6'),(28,2,'D6'),(30,2,'A5'),
        (32,1,'G5'),(33,2,'E5'),(35,1,'C5'),(36,2,'F5'),(38,2,'A5'),
        (40,1,'C6'),(41,2,'E6'),(43,1,'D6'),(44,2,'A5'),(46,2,'D6')]
    for pos,length,n in tune:
        c.note(pos*step,length*step*.94,n,.46,'pulse',release=.015)
    roots=['D3','C3','Bb2','G2','F2','D3']
    for i,root in enumerate(roots):
        pos=i*8
        c.note(pos*step,3.6*step,root,.34,'triangle',release=.04)
        c.note((pos+4)*step,2.7*step,root,.24,'triangle')
    for pos,pitch in [(0,'A4'),(8,'G4'),(16,'F4'),(24,'Bb4'),(32,'A4'),(40,'F4')]:
        c.note(pos*step,.11,pitch,.15,'bell')
    return c.signal()

def intermission():
    tempo=180;step=60/tempo/4
    c=Composer(10.74,29)
    # Eight original 4/4 measures. Several rests and syncopations intentionally
    # differentiate this from the standard arcade intermission melody.
    bars=[
        [(0,2,'A4'),(3,1,'C5'),(4,2,'D5'),(6,2,'E5'),(8,2,'G5'),(10,1,'E5'),(11,1,'D5'),(12,2,'C5'),(14,2,'A4')],
        [(0,2,'B4'),(2,2,'D5'),(4,2,'F#5'),(6,1,'E5'),(7,1,'D5'),(8,2,'C5'),(10,2,'A4'),(12,1,'G4'),(13,1,'B4'),(14,2,'D5')],
        [(0,1,'E5'),(1,2,'G5'),(4,1,'A5'),(5,2,'C6'),(8,1,'B5'),(9,2,'G5'),(12,2,'F#5'),(14,2,'E5')],
        [(0,2,'D5'),(2,1,'B4'),(4,2,'A4'),(7,1,'C5'),(8,2,'E5'),(10,1,'D5'),(11,1,'C5'),(12,4,'B4')],
        [(0,2,'A4'),(2,1,'E5'),(3,1,'G5'),(4,2,'A5'),(7,1,'E5'),(8,2,'C6'),(10,2,'B5'),(12,2,'G5'),(14,2,'E5')],
        [(0,1,'D5'),(1,2,'F#5'),(4,1,'A5'),(5,1,'F#5'),(6,2,'E5'),(8,2,'D5'),(10,1,'B4'),(11,1,'C5'),(12,2,'D5'),(14,2,'F#5')],
        [(0,1,'G5'),(1,1,'E5'),(2,2,'D5'),(4,1,'C5'),(5,1,'B4'),(6,2,'A4'),(8,2,'C5'),(10,2,'E5'),(12,2,'G5'),(14,2,'A5')],
        [(0,1,'C6'),(1,2,'A5'),(4,2,'G5'),(6,2,'E5'),(8,1,'F#5'),(9,1,'D5'),(10,2,'B4'),(12,4,'A4')],
    ]
    bass_roots=['A2','G2','D3','E3','A2','D3','G2','A2']
    for bar,pattern in enumerate(bars):
        base=bar*16
        for pos,length,n in pattern:
            c.note((base+pos)*step,length*step*.87,n,.36,'pulse',release=.012)
        for i in (0,6,10,14):
            c.note((base+i)*step,1.7*step,bass_roots[bar],.24,'triangle',attack=.002,release=.012)
        for i in (0,8):c.thump((base+i)*step,.18)
        for i in (4,12):c.hiss((base+i)*step,.055,.12)
        for i in (2,6,10,14):c.hiss((base+i)*step,.025,.075,bright=True)
    return c.signal()

def sound(name):
    if name=='start_music':return opening()
    if name=='intermission_music':return intermission()
    if name=='coin_insert':
        c=Composer(.34,2)
        c.sweep(0,.12,930,1280,.33,'bell',release=.04)
        c.note(.08,.20,'E6',.41,'bell',release=.09)
        c.note(.095,.19,'B5',.23,'triangle',release=.08)
    elif name=='extra_life':
        c=Composer(2.12,3)
        fanfare=[(0,'G5',.14),(.18,'C6',.18),(.4,'E6',.20),(.67,'A5',.12),(.83,'D6',.18),(1.05,'G6',.30), (1.47,'E6',.28),(1.72,'C6',.33)]
        for start,n,dur in fanfare:c.note(start,dur,n,.45,'bell',release=.07)
        c.note(1.55,.46,'C5',.21,'triangle')
    elif name.startswith('siren_'):
        stage=int(name[-1]);c=Composer(1.6,stage+5)
        bases=[305,334,372,415,463];base=bases[stage-1]
        periods=[.32,.29,.26,.225,.195];period=periods[stage-1]
        k=0
        while k*period<1.58:
            tm=k*period
            chord=[base,base*1.36,base*.91]
            tone=chord[k%3]
            c.sweep(tm,min(period*.94,1.6-tm),tone*.98,tone*1.10,.30+stage*.025,'softsquare',release=.018,twist=.013)
            if stage>=4 and k%3==0:c.hiss(tm,.08,.06)
            k+=1
    elif name=='power_pellet_fright':
        c=Composer(1.6,21)
        for i in range(9):
            t=i*.178
            c.sweep(t,min(.18,1.6-t),151+((i%3)*19),116+((i%4)*12),.40,'saw','exp',release=.03,twist=.045)
            if i%2==0:c.note(t,.11,'D3',.22,'pulse')
    elif name=='ghost_eyes_return':
        c=Composer(1.6,20)
        for i,n in enumerate(['E5','G5','A5','C6','B5','D6','E6','G6','E6']):
            t=i*.172
            c.note(t,.17,n,.31,'triangle',release=.025)
            if i%2==0:c.note(t+.04,.11,220+(i*55),.16,'bell')
    elif name=='eat_dot_1':
        c=Composer(.155,8)
        c.sweep(0,.082,290,610,.40,'triangle',release=.015)
        c.sweep(.047,.087,420,820,.31,'pulse',release=.026)
        c.hiss(0,.014,.22)
    elif name=='eat_dot_2':
        c=Composer(.155,9)
        c.sweep(0,.084,620,340,.38,'triangle',release=.018)
        c.sweep(.048,.081,470,690,.34,'pulse',release=.021)
        c.hiss(.01,.018,.20)
    elif name=='eat_fruit':
        c=Composer(.52,10)
        for start,n,dur in [(0,'C6',.17),(.1,'G6',.19),(.235,'D7',.24)]:
            c.note(start,dur,n,.38,'bell',release=.055)
        c.hiss(.016,.05,.09)
    elif name=='eat_ghost':
        c=Composer(.64,12)
        c.sweep(0,.40,1120,175,.51,'saw','exp',release=.08,twist=.055)
        c.note(.21,.27,'Eb5',.21,'bell',release=.07)
        c.note(.32,.25,'G4',.20,'triangle',release=.06)
        c.hiss(0,.17,.16)
    elif name=='death':
        c=Composer(2.93,13)
        # Three phrases, staggered pulse positions, falling intervals.
        notes=[('E6',0,.2),('C6',.22,.17),('G5',.43,.19),('F#5',.64,.20),
               ('D5',.9,.18),('Bb4',1.13,.21),('G4',1.38,.19),
               ('Eb4',1.64,.22),('B3',1.91,.2),('A3',2.2,.23)]
        for n,t,d in notes:
            c.note(t,d,n,.38,'softsquare',release=.085,wobble=3.5)
        c.sweep(2.28,.49,233,48,.28,'triangle','exp',release=.20,twist=.08)
        for i in range(8):c.hiss(2.31+i*.067,.037,.05+(i*.008))
    elif name=='fruit_bounce':
        c=Composer(.29,17)
        c.sweep(0,.115,410,790,.38,'triangle',release=.015)
        c.sweep(.085,.155,710,270,.36,'pulse',release=.038)
        c.note(.15,.10,'E5',.13,'bell')
    else:
        raise KeyError(name)
    return c.signal()

def write_wav(path,signal,sr):
    s=np.clip(np.round(signal*32767.0),-32768,32767).astype('<i2')
    with wave.open(str(path),'wb') as wav:
        wav.setnchannels(1);wav.setsampwidth(2);wav.setframerate(sr);wav.writeframes(s.tobytes())

def make_6bit(signal):
    reduced=resample_poly(signal,82,441)
    # 6-bit unsigned level 0..63, high 6 PIA DAC bits, low 2 always zero.
    index=np.clip(np.rint(31.5 + np.clip(reduced,-1,1)*31.1),0,63).astype(np.uint8)
    raw=(index<<2).astype(np.uint8)
    # WAV audit previews intentionally contain only the 64 possible CoCo levels.
    wavsig=(raw.astype(np.float64)-128.0)/128.0
    return raw,wavsig

def make_waveform_library():
    xs=np.linspace(0,2*np.pi,32,endpoint=False)
    waves=[oscillator(xs,n) for n in ['pulse','triangle','softsquare','bell','saw','sin']]
    waves.append(.65*oscillator(xs,'triangle')+.35*oscillator(xs*2,'saw'))
    waves.append(.8*np.sin(xs)+.22*np.cos(xs*3))
    lines=['; PAK FAN: 8 ORIGINAL PROCEDURAL INSTRUMENT WAVETABLES','; 32 entries each, values 0..15. No external ROM or borrowed chip table.','; Optional building blocks for custom realtime DAC synthesizers.','']
    for i,w in enumerate(waves):
        w=w/max(1e-9,np.max(np.abs(w)))
        nums=np.clip(np.rint(7.5+7.3*w),0,15).astype(np.uint8)
        lines.append(f'WAVE{i}  FCB '+','.join(f'${b:02X}' for b in nums))
    (ROOT/'6809_ASM'/'pak_fan_waveforms.asm').write_text('\n'.join(lines)+'\n')

def main():
    catalog=[]
    for name,title,desc in SOUNDS:
        master=sound(name)
        pcm,dac_preview=make_6bit(master)
        write_wav(OUTPUTS['master']/f'{name}.wav',master,MASTER_RATE)
        write_wav(OUTPUTS['preview']/f'{name}_coco6bit.wav',dac_preview,DAC_RATE)
        (OUTPUTS['raw']/f'{name}.raw').write_bytes(pcm.tobytes())
        print(f'{name:25} {len(master)/MASTER_RATE:6.3f}s  {len(pcm):7} samples')
        catalog.append({'name':name,'title':title,'description':desc,
                       'duration_sec':round(len(pcm)/DAC_RATE,4),
                       'master_wav':name+'.wav',
                       'coco_wav':name+'_coco6bit.wav',
                       'raw_dac':name+'.raw','sample_rate':DAC_RATE,
                       'channels':1,'sample_bits':6,'asm_parts':[]})
    # A single continuous audition file with obvious separators.
    sequence=[]
    for name,*_ in SOUNDS:
        sequence.append(sound(name));sequence.append(np.zeros(int(.24*MASTER_RATE)))
    preview=np.concatenate(sequence)
    prevfolder=ROOT/'LISTEN_FIRST';prevfolder.mkdir(exist_ok=True)
    write_wav(prevfolder/'Pak_Fan_All_17_Sounds_Preview.wav',preview,MASTER_RATE)
    (OUTPUTS['raw']/'manifest.json').write_text(json.dumps(catalog,indent=2)+'\n')
    with (OUTPUTS['raw']/'manifest.csv').open('w',newline='') as f:
        w=csv.DictWriter(f,['name','title','description','duration_sec','raw_dac','sample_rate','sample_bits']);w.writeheader()
        for entry in catalog:w.writerow({k:entry[k] for k in w.fieldnames})
    make_waveform_library()
if __name__=='__main__':main()
