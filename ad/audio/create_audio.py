from pathlib import Path
import asyncio, json, subprocess, wave, os
import numpy as np
import scipy.signal as signal
import imageio_ffmpeg

ROOT=Path(__file__).parent
FFMPEG=imageio_ffmpeg.get_ffmpeg_exe()
SR=48000
DURATION=60.0
CUES=[
(0.8,'Every meeting starts with a voice.'),
(5.0,'But life has a way of getting in.'),
(10.4,'Meet Hearly. Your voice, brought into focus.'),
(17.0,'Hearly learns the sound of your voice, right on your device.'),
(24.0,'Then it separates you from the noise around you.'),
(30.3,'The keyboard. The café. The conversation across the room.'),
(37.3,'So when you speak, only your voice goes into the meeting.'),
(44.5,'One clear connection. From your microphone, through Hearly, to your call.'),
(52.5,'Hearly. Your voice. Nothing else.'),
]

def decode(path):
    raw=subprocess.check_output([FFMPEG,'-v','error','-i',str(path),'-f','f32le','-ac','1','-ar',str(SR),'-'])
    return np.frombuffer(raw,dtype=np.float32).copy()

def save(path,x):
    x=np.atleast_2d(x.T).T if x.ndim==1 else x
    with wave.open(str(path),'wb') as f:
        f.setnchannels(x.shape[1]); f.setsampwidth(3); f.setframerate(SR)
        y=np.clip(x,-1,1)*8388607
        y=y.astype(np.int32).reshape(-1)
        packed=np.empty((y.size,3),np.uint8)
        packed[:,0]=y&255; packed[:,1]=(y>>8)&255; packed[:,2]=(y>>16)&255
        f.writeframes(packed.tobytes())

async def synthesize():
    import edge_tts
    for i,(_,text) in enumerate(CUES):
        p=ROOT/f'voice_{i+1:02d}.mp3'
        if not p.exists():
            spoken=text.replace('Hearly','Hear lee')
            comm=edge_tts.Communicate(spoken,'en-US-JennyNeural',rate='-8%',pitch='-2Hz')
            await comm.save(str(p))
        print('synthesized',p.name,flush=True)

def music(cues):
    n=int(SR*DURATION); t=np.arange(n)/SR
    track=np.zeros((n,2),np.float64)
    # Original A-major/relative-minor suspended harmony, warm and unhurried.
    chords=[(0,[45,52,59,64]),(8,[42,49,57,61]),(16,[38,45,52,57]),(24,[40,47,54,59]),(32,[45,52,59,64]),(40,[42,49,57,61]),(48,[38,45,52,57]),(54,[45,52,59,64])]
    for ci,(start,notes) in enumerate(chords):
        end=chords[ci+1][0]+2.5 if ci+1<len(chords) else 60
        a=int(max(0,start-.9)*SR); b=int(min(60,end)*SR)
        tt=t[a:b]-start
        env=np.clip((tt+.9)/2.8,0,1)*np.clip((end-(t[a:b]))/2.5,0,1)
        env=np.sin(env*np.pi/2)**2
        for k,m in enumerate(notes):
            f=440*2**((m-69)/12)
            sig=(np.sin(2*np.pi*f*tt+0.10*np.sin(2*np.pi*.14*tt))+.20*np.sin(2*np.pi*f*2*tt)+.04*np.sin(2*np.pi*f*3*tt))*.018
            sig*=env
            pan=(k-1.5)*.22
            track[a:b,0]+=sig*np.sqrt((1-pan)/2)
            track[a:b,1]+=sig*np.sqrt((1+pan)/2)
    # Sparse rounded felt-synth notes; spacious ping reflections.
    pattern=[(2,76),(6,71),(11,73),(14,80),(19,76),(22,73),(27,71),(31,78),(35,76),(39,73),(43,69),(47,76),(51,73)]
    for k,(start,m) in enumerate(pattern):
        f=440*2**((m-69)/12); dur=4.4
        tt=np.arange(int(SR*dur))/SR
        env=(1-np.exp(-tt/.022))*np.exp(-tt/1.4)
        sig=(np.sin(2*np.pi*f*tt)+.13*np.sin(2*np.pi*2*f*tt))*env*.032
        pan=.38*(-1 if k%2 else 1)
        for delay,gain in [(0,1),(.33,.20),(.66,.11)]:
            a=int((start+delay)*SR); b=min(n,a+len(sig));
            if b>a:
                track[a:b,0]+=sig[:b-a]*gain*np.sqrt((1-pan)/2)
                track[a:b,1]+=sig[:b-a]*gain*np.sqrt((1+pan)/2)
    # Very soft pulse gives the graphic animation forward motion.
    for start in np.arange(10.4,53,1.5):
        tt=np.arange(int(SR*.4))/SR
        pulse=np.sin(2*np.pi*(68*tt-18*tt**2))*np.exp(-tt*15)*(1-np.exp(-tt*90))*.015
        a=int(start*SR); track[a:a+len(pulse)]+=pulse[:,None]
    # Three original logo tones after the final spoken line.
    for start,m in [(57.35,69),(57.65,76),(58.0,81)]:
        tt=np.arange(int(SR*3.0))/SR; f=440*2**((m-69)/12)
        sig=(np.sin(2*np.pi*f*tt)+.13*np.sin(2*np.pi*2*f*tt))*(1-np.exp(-tt/.015))*np.exp(-tt/1.25)*.09
        a=int(start*SR); b=min(n,a+len(sig)); track[a:b]+=sig[:b-a,None]/np.sqrt(2)
    # Smooth ducking around narration; modest recovery during pauses.
    duck=np.ones(n)
    for c in cues:
        a=int(max(0,c['start']-.30)*SR); b=int(min(60,c['end']+.45)*SR)
        u=t[a:b]
        left=np.clip((u-(c['start']-.30))/.30,0,1)
        right=np.clip((c['end']+.45-u)/.45,0,1)
        weight=np.minimum(left,right)
        duck[a:b]=np.minimum(duck[a:b],1-.32*(.5-.5*np.cos(np.pi*weight)))
    fade=np.minimum(np.clip(t/2.2,0,1),np.clip((60-t)/2.2,0,1))
    track*=duck[:,None]*np.sin(fade*np.pi/2)[:,None]**2
    return track

def mix():
    n=int(SR*DURATION); voice=np.zeros(n); cues=[]
    for i,(start,text) in enumerate(CUES):
        path=ROOT/f'voice_{i+1:02d}.mp3'
        x=decode(path)
        active=np.flatnonzero(np.abs(x)>.003)
        if len(active):
            x=x[max(0,active[0]-int(SR*.035)):min(len(x),active[-1]+int(SR*.12))]
        # Gentle peak normalization maintains stable, intelligible narration.
        x*=.67/max(.001,np.max(np.abs(x)))
        x*=np.minimum(1,np.arange(len(x))/(SR*.008))
        end=start+len(x)/SR
        next_start=CUES[i+1][0] if i+1<len(CUES) else 57.4
        if end>next_start-.22: raise RuntimeError(f'Cue {i+1} too long: {end:.3f} against {next_start}')
        a=round(start*SR); voice[a:a+len(x)]+=x
        cues.append({'id':i+1,'start':start,'end':round(end,3),'text':text,'audio_file':f'voice_{i+1:02d}.wav'})
        save(ROOT/f'voice_{i+1:02d}.wav',x)
    mus=music(cues)
    v=np.column_stack([voice,voice])
    full=v+mus
    # Master headroom with gentle soft saturation only at extreme transients.
    peak=float(np.max(np.abs(full)))
    if peak>.89: full*=.89/peak
    save(ROOT/'voice_stem.wav',v)
    save(ROOT/'music_stem.wav',mus)
    save(ROOT/'hearly_ad_mix.wav',full)
    (ROOT/'cues.json').write_text(json.dumps(cues,indent=2)+'\n')
    report={'duration_seconds':len(full)/SR,'sample_rate':SR,'channels':2,'bit_depth':24,'peak_dbfs':round(20*np.log10(np.max(np.abs(full))),2),'rms_dbfs':round(20*np.log10(np.sqrt(np.mean(full**2))),2),'ffmpeg':FFMPEG,'cues':cues}
    (ROOT/'validation.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2),flush=True)

if __name__=='__main__':
    import sys
    if len(sys.argv)>1 and sys.argv[1]=='mix': mix()
    else: asyncio.run(synthesize()); mix()
