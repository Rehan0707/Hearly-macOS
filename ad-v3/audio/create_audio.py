from pathlib import Path
import sys, asyncio, json, subprocess
import numpy as np
import scipy.signal as sig
import edge_tts
import imageio_ffmpeg
ROOT=Path(__file__).parent
FFMPEG=imageio_ffmpeg.get_ffmpeg_exe(); SR=48000; N=60*SR
CUES=[
(.4,5.6,"Meet Hearly. The AI between your microphone and your meeting."),
(7.3,2.5,"You're ready to speak."),
(10.3,5.0,"The keyboard. The café. The conversation nearby. They join in, too."),
(16.3,3.6,"Your ideas deserve a clearer connection."),
(21.3,3.5,"Train your voice on your Mac."),
(25.4,4.5,"Hearly learns to recognize you, right on your device."),
(30.6,5.4,"Turn Hearly on, and select Hearly Microphone in your meeting."),
(37.1,6.0,"It filters background noise before your audio reaches the call."),
(44.0,4.5,"Less distraction. More of what you have to say."),
(50.4,5.3,"Join the Hearly waitlist at hearly dot live."),
(56.5,2.7,"Hearly. Be heard.")]
async def generate():
 for i,(start,dur,text) in enumerate(CUES):
  p=ROOT/f'raw_{i+1:02d}.mp3'
  if not p.exists():
   await edge_tts.Communicate(text.replace('Hearly','Hear lee'),'en-US-AvaMultilingualNeural',rate='-12%',pitch='+0Hz').save(str(p))
  print('Voice',i+1,flush=True)
def decode(p):
 return np.frombuffer(subprocess.check_output([FFMPEG,'-v','error','-i',str(p),'-f','f32le','-ac','1','-ar',str(SR),'-']),np.float32).copy()
def save(p,a):
 a=np.asarray(a,np.float32)
 if a.ndim==1:a=np.column_stack([a,a])
 subprocess.run([FFMPEG,'-y','-v','error','-f','f32le','-ar',str(SR),'-ac','2','-i','pipe:0','-c:a','pcm_s24le',str(p)],input=a.tobytes(),check=True)
def mix():
 voice=np.zeros((N,2)); cues=[]
 for i,(start,target,text) in enumerate(CUES):
  raw=decode(ROOT/f'raw_{i+1:02d}.mp3'); inds=np.flatnonzero(abs(raw)>.0025)
  raw=raw[max(0,inds[0]-1000):min(len(raw),inds[-1]+5000)]
  speed=np.clip(len(raw)/(target*SR),.72,1.18)
  processed=subprocess.check_output([FFMPEG,'-v','error','-f','f32le','-ar',str(SR),'-ac','1','-i','pipe:0','-af',f'atempo={speed:.6f}', '-f','f32le','-'],input=raw.tobytes())
  a=np.frombuffer(processed,np.float32).copy();a*=.63/max(.001,np.max(abs(a)))
  a*=np.minimum(1,np.arange(len(a))/500)
  end=start+len(a)/SR
  assert end<(CUES[i+1][0]-.05 if i+1<len(CUES) else 59.8),(i,end)
  at=round(start*SR);voice[at:at+len(a)]+=a[:,None]
  save(ROOT/f'voice_{i+1:02d}.wav',a)
  cues.append(dict(start=start,end=round(end,3),text=text))
 # Original piano-like felt notes over broad, warm suspended harmony.
 t=np.arange(N)/SR;music=np.zeros((N,2));rng=np.random.default_rng(52)
 chords=[(0,[45,52,59,64]),(7.5,[42,49,57,61]),(15,[38,45,52,57]),(22.5,[40,47,54,59]),(30,[45,52,59,64]),(37.5,[42,49,57,61]),(45,[38,45,52,57]),(52.5,[45,52,59,64])]
 for j,(start,notes) in enumerate(chords):
  end=min(60,start+10); ix=np.arange(max(0,int((start-1)*SR)),int(end*SR)); tt=ix/SR-start
  env=np.sin(np.minimum(np.clip((tt+1)/2,0,1),np.clip((end-ix/SR)/2,0,1))*np.pi/2)**2
  for k,m in enumerate(notes):
   f=440*2**((m-69)/12);a=(np.sin(2*np.pi*f*tt+.2*np.sin(tt*.8))+.16*np.sin(4*np.pi*f*tt))*.014*env
   pan=(k-1.5)*.3;music[ix,0]+=a*np.sqrt((1-pan)/2);music[ix,1]+=a*np.sqrt((1+pan)/2)
 # Repeating motif gains gentle momentum after Hearly appears.
 for start in np.arange(1,57,1.875):
  ci=min(7,int(start/7.5)); notes=chords[ci][1];m=notes[int((start-1)/1.875)%4]+24
  f=440*2**((m-69)/12); tt=np.arange(int(3.6*SR))/SR
  a=(np.sin(2*np.pi*f*tt)+.15*np.sin(4*np.pi*f*tt)+.06*np.sin(6*np.pi*f*tt))*np.exp(-tt/1.05)*(1-np.exp(-tt/.016))*.047
  pan=.35*np.sin(start);at=int(start*SR);end=min(N,at+len(a));music[at:end,0]+=a[:end-at]*np.sqrt((1-pan)/2);music[at:end,1]+=a[:end-at]*np.sqrt((1+pan)/2)
 # Soft heartbeat-like rounded bass after the resolve.
 for start in np.arange(15,52.5,.9375):
  tt=np.arange(int(.25*SR))/SR;a=np.sin(2*np.pi*(60*tt-26*tt*tt))*np.exp(-tt*18)*(1-np.exp(-tt*100))*.025
  at=int(start*SR);music[at:at+len(a)]+=a[:,None]
 fx=np.zeros((N,2))
 # Brief tactile typing / room texture at the noisy scene. These are designed sounds, not a product test.
 for start in np.arange(10.4,15.0,.22):
  tt=np.arange(int(.035*SR))/SR;a=rng.normal(size=len(tt))*np.exp(-tt*150)*.026
  at=int(start*SR);fx[at:at+len(a)]+=a[:,None]
 for start in [6.7,20.7,24.8,30.1,36.5,43.5,49.7]:
  tt=np.arange(int(.6*SR))/SR;noise=rng.normal(size=len(tt));noise=sig.sosfilt(sig.butter(2,[450,2800],fs=SR,btype='band',output='sos'),noise)
  a=noise*np.sin(np.pi*tt/.6)**2*.022;at=int(start*SR);fx[at:at+len(a),0]+=a;fx[at:at+len(a),1]+=np.roll(a,330)
 for start in [23.8,31.8,35.2]:
  tt=np.arange(int(.16*SR))/SR;a=np.sin(2*np.pi*950*tt)*np.exp(-tt*35)*.028;at=int(start*SR);fx[at:at+len(a)]+=a[:,None]
 for start,m in [(59.1,69),(59.3,76),(59.5,81)]:
  tt=np.arange(int(2*SR))/SR;f=440*2**((m-69)/12);a=np.sin(2*np.pi*f*tt)*np.exp(-tt*1.7)*(1-np.exp(-tt*70))*.095;at=int(start*SR);end=min(N,at+len(a));music[at:end]+=a[:end-at,None]
 duck=np.ones(N)
 for cue in cues:
  v=np.minimum(np.clip((t-cue['start']+.18)/.18,0,1),np.clip((cue['end']+.35-t)/.35,0,1));duck=np.minimum(duck,1-.38*v)
 fade=np.sin(np.minimum(np.clip(t/1.1,0,1),np.clip((60-t)/1.5,0,1))*np.pi/2)**2
 music*=duck[:,None]*fade[:,None];fx*=fade[:,None]
 final=voice+music+fx
 peak=max(abs(final).max(),.01)
 if peak>.91:final*=.91/peak
 save(ROOT/'voice_stem.wav',voice);save(ROOT/'music_stem.wav',music);save(ROOT/'sound_design.wav',fx);save(ROOT/'hearly_ad_mix.wav',final)
 (ROOT/'cues.json').write_text(json.dumps(cues,indent=2))
 def ts(s):
  ms=round(s*1000);return f'{ms//3600000:02d}:{ms//60000%60:02d}:{ms//1000%60:02d},{ms%1000:03d}'
 (ROOT/'captions.srt').write_text('\n\n'.join(f"{i+1}\n{ts(q['start'])} --> {ts(q['end'])}\n{q['text']}" for i,q in enumerate(cues))+'\n')
 print(json.dumps(cues,indent=2))
if __name__=='__main__':
 asyncio.run(generate());mix()
