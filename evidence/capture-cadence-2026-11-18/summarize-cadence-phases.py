#!/usr/bin/env python3
from pathlib import Path
import csv,json,collections,sys,os
N=Path(os.environ.get('REIMS_EVIDENCE_ROOT','.')).resolve()
D=N/(sys.argv[1] if len(sys.argv)>1 else 'native-stream-cadence-aba1-20261118')
run=json.loads((D/'run.json').read_text())
data=list(csv.DictReader((D/'decoded-positions.csv').open()))
for row in data:
 for k in row:row[k]=float(row[k]) if k=='meanRgb' else int(row[k])
profile=json.loads((N/(sys.argv[2] if len(sys.argv)>2 else 'native-pipeline-cadenceaba-20261118')/'result.json').read_text())
marker=run['nativeMarker']['monotonic'];phases=run['phases']
def q(v):
 v=sorted(v)
 return {'count':len(v),'p50':v[len(v)//2],'p99':v[min(len(v)-1,int(len(v)*.99))],'max':v[-1],'over60':sum(x>60 for x in v),'over100':sum(x>100 for x in v)} if v else {}
out={'run':{k:run[k] for k in ['startUtc','endUtc','sunshineImage','originalConfigSha256','phases','nativeMarker','originalReady']},'method':'Same process, same encoded stream, same native motion; only D-Bus capture polling interval switched. A30 analysis begins 14 s after native launch, after a one-time startup screenshot; switching transients are excluded.','phases':[],'remainingProbes':profile['remainingProbes']}
ranges=[('A30',30,marker+14,phases[1]['monotonic']-1),('B16',16,phases[1]['monotonic']+2,phases[2]['monotonic']-1),('A30_repeat',30,phases[2]['monotonic']+2,marker+73)]
for name,interval,lo,hi in ranges:
 a=[r for r in data if lo<=r['mono_ns']/1e9<=hi]
 assert len(a)>100 and all(r['matches700']==1 for r in a)
 groups=collections.defaultdict(list)
 for e in profile['events']:
  if lo<=e['t']<=hi and not e['type'].endswith('ret'):groups[e['type']].append(e['t'])
 stages={k:{'count':len(v),'hz':(len(v)-1)/(v[-1]-v[0]),'gapMs':q([(b-a)*1000 for a,b in zip(v,v[1:])])} for k,v in groups.items() if len(v)>1}
 changes=[];holds=[];start=a[0]
 for x,y in zip(a,a[1:]):
  if x['x700']!=y['x700']:
   holds.append((y['mono_ns']-start['mono_ns'])/1e6);start=y
   changes.append({'x':y['x700'],'dx':y['x700']-x['x700'],'ordinal':y['ordinal']})
 flips=[y for x,y in zip(changes,changes[1:]) if x['dx']*y['dx']<0 and 525<y['x']<840]
 tears=[r['ordinal'] for r in a if all(r['matches'+str(y)]==1 for y in [500,600,700,800]) and max(r['x'+str(y)] for y in [500,600,700,800])-min(r['x'+str(y)] for y in [500,600,700,800])>1]
 result={'label':name,'captureIntervalMs':interval,'windowMonotonic':[lo,hi],'seconds':hi-lo,'frames':len(a),'receivedFps':(len(a)-1)/((a[-1]['mono_ns']-a[0]['mono_ns'])/1e9),'receiveGapMs':q([(y['mono_ns']-x['mono_ns'])/1e6 for x,y in zip(a,a[1:])]),'capturePresentationGapMs':q([(y['presentation_us']-x['presentation_us'])/1e3 for x,y in zip(a,a[1:])]),'hostProcessingLatencyMs':q([r['host_latency_tenth_ms']/10 for r in a if r['host_latency_tenth_ms']]),'positionHoldMs':q(holds),'unexpectedDirectionReversals':flips,'crossScanlineMismatches':tears,'nonconsecutiveFrameNumbers':sum(y['frame_number']!=x['frame_number']+1 for x,y in zip(a,a[1:])),'stages':stages}
 out['phases'].append(result)
(D/'phase-analysis.json').write_text(json.dumps(out,indent=2)+'\n')
for r in out['phases']:
 print(json.dumps({k:v for k,v in r.items() if k!='stages'},indent=2))
 print('STAGE_RATES',json.dumps({k:round(v['hz'],3) for k,v in r['stages'].items()}))
print('REMAINING_PROBES',out['remainingProbes'])
