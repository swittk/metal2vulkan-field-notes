#!/usr/bin/env python3
from pathlib import Path
import csv,json,subprocess as sp,collections,sys,time,os
import numpy as np
N=Path(os.environ.get('REIMS_EVIDENCE_ROOT','.')).resolve()
D=N/(sys.argv[1] if len(sys.argv)>1 else 'native-stream-off2-20261118')
rows=list(csv.DictReader((D/'frames.csv').open()))
for r in rows:
 for k in r:r[k]=int(r[k])
assert all(r['ordinal']==i and r['written']==r['full_length'] for i,r in enumerate(rows))
assert rows[-1]['offset']+rows[-1]['written']==(D/'received.bin').stat().st_size
filter='[0:v]format=rgb24,split=4[a][b][c][d];[a]crop=1920:1:0:500:exact=1[a1];[b]crop=1920:1:0:600:exact=1[b1];[c]crop=1920:1:0:700:exact=1[c1];[d]crop=1920:1:0:800:exact=1[d1];[a1][b1][c1][d1]vstack=inputs=4[out]'
log=(D/'decode.log').open('w');cmd=['ffmpeg','-hide_banner','-loglevel','warning','-threads','4','-f','hevc','-i',str(D/'received.bin'),'-filter_complex_threads','1','-filter_complex',filter,'-map','[out]','-vsync','0','-f','rawvideo','-pix_fmt','rgb24','pipe:1']
proc=sp.Popen(cmd,stdout=sp.PIPE,stderr=log);size=1920*4*3;frames=[]
while True:
 data=bytearray()
 while len(data)<size:
  chunk=proc.stdout.read(size-len(data))
  if not chunk:break
  data.extend(chunk)
 if not data:break
 assert len(data)==size,'Incomplete decoded frame'
 arr=np.frombuffer(data,np.uint8).reshape(4,1920,3);out={}
 for n,y in enumerate([500,600,700,800]):
  px=arr[n].astype(np.int16);mask=(px[:,0]>190)&(px[:,1]<90)&(px[:,2]>190)
  edges=np.diff(np.r_[False,mask,False].astype(np.int8));starts=np.where(edges==1)[0];ends=np.where(edges==-1)[0]
  runs=[(int(a),int(b-a)) for a,b in zip(starts,ends) if 400<=a<1000 and 7<=b-a<=18]
  out['x'+str(y)]=runs[0][0] if len(runs)==1 else (-1 if not runs else -2)
  out['matches'+str(y)]=len(runs)
 out['meanRgb']=float(arr.mean());out['ordinal']=len(frames);frames.append(out)
code=proc.wait(timeout=20);log.close();assert code==0,(D/'decode.log').read_text()
assert len(frames)==len(rows),(len(frames),len(rows))
for frame,row in zip(frames,rows):frame.update(row)
with (D/'decoded-positions.csv').open('w') as f:
 writer=csv.DictWriter(f,fieldnames=frames[0].keys());writer.writeheader();writer.writerows(frames)
marked=[f for f in frames if f['matches700']==1];lo=marked[0]['mono_ns']/1e9+1;hi=marked[-1]['mono_ns']/1e9-1;active=[f for f in frames if lo<=f['mono_ns']/1e9<=hi]
def q(v):
 v=sorted(v)
 if not v:return {}
 return {'count':len(v),'p50':round(v[len(v)//2],4),'p99':round(v[min(len(v)-1,int(len(v)*.99))],4),'max':round(v[-1],4),'over60':sum(x>60 for x in v),'over100':sum(x>100 for x in v)}
assert all(f['matches700']==1 for f in active), 'Ambiguous marker detections: do not interpret as frame holds or jumps'
holds=[];changes=[];start=active[0]
for a,b in zip(active,active[1:]):
 if a['x700']!=b['x700']:
  holds.append({'x':start['x700'],'start':start['mono_ns']/1e9,'ms':(b['mono_ns']-start['mono_ns'])/1e6})
  changes.append({'t':b['mono_ns']/1e9,'x':b['x700'],'dx':b['x700']-a['x700']});start=b
flips=[b for a,b in zip(changes,changes[1:]) if a['dx']*b['dx']<0 and 525<b['x']<840]
tears=[f['ordinal'] for f in active if all(f['matches'+str(y)]==1 for y in [500,600,700,800]) and max(f['x'+str(y)] for y in [500,600,700,800])-min(f['x'+str(y)] for y in [500,600,700,800])>1]
profile=json.loads((N/(sys.argv[2] if len(sys.argv)>2 else 'native-pipeline-stream1-20261118')/'result.json').read_text());groups=collections.defaultdict(list)
for event in profile['events']:
 if lo<=event['t']<=hi and not event['type'].endswith('ret'):groups[event['type']].append(event['t'])
stages={k:{'count':len(v),'hz':round((len(v)-1)/(v[-1]-v[0]),3),'gapMs':q([(b-a)*1000 for a,b in zip(v,v[1:])])} for k,v in groups.items() if len(v)>1}
summary={'markerDetector':'7..18px unique magenta stripe; rejects24px decorative bars; all active positions required valid','decodedFrames':len(frames),'encodedUnits':len(rows),'decodeExit':code,'decodeMessages':(D/'decode.log').read_text(),'activeWindowMonotonic':[lo,hi],'activeSeconds':hi-lo,'activeFrames':len(active),'configuredFps':60,'receivedFps':(len(active)-1)/((active[-1]['mono_ns']-active[0]['mono_ns'])/1e9),'receiveGapMs':q([(b['mono_ns']-a['mono_ns'])/1e6 for a,b in zip(active,active[1:])]),'capturePresentationGapMs':q([(b['presentation_us']-a['presentation_us'])/1e3 for a,b in zip(active,active[1:])]),'hostProcessingLatencyMs':q([f['host_latency_tenth_ms']/10 for f in active if f['host_latency_tenth_ms']]),'positionHoldMs':q([h['ms'] for h in holds]),'longestHolds':sorted(holds,key=lambda x:x['ms'],reverse=True)[:12],'unexpectedDirectionReversals':flips,'crossScanlineMismatches':tears,'missingMarkersInActiveWindow':[f['ordinal'] for f in active if f['matches700']!=1],'nonconsecutiveFrameNumbers':sum(b['frame_number']!=a['frame_number']+1 for a,b in zip(active,active[1:])),'stages':stages,'remainingProbes':profile['remainingProbes'],'limitations':['Local paired receiver records real encoded frames. It does not measure the user device/network/physical display.','Sunshine image and capture settings match original; temporary authentication identity differs.']}
(D/'analysis.json').write_text(json.dumps(summary,indent=2)+'\n');print(json.dumps(summary,indent=2),flush=True)
