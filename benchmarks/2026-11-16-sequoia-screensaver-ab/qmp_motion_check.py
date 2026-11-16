#!/usr/bin/env python3
"""Inside the disposable REIMS VM container: sample actual QEMU images, no synthetic frames."""
from pathlib import Path
import hashlib,json,socket,time,sys,statistics,datetime
label=sys.argv[1]
assert label.isascii() and label.replace("-","").isalnum() and len(label)<80
root=Path(__import__("os").environ["REIMS_QMP_SCREENDUMP_DIR"])
shot=root/("benchmark-motion-"+label+".ppm")
assert not shot.exists()
sock=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM)
sock.settimeout(25)
sock.connect(__import__("os").environ["REIMS_QMP_SOCKET"])
f=sock.makefile("rwb",buffering=0)
assert "QMP" in json.loads(f.readline())
def call(name,argument=None):
    msg={"execute":name,"id":name}
    if argument:msg["arguments"]=argument
    f.write((json.dumps(msg)+"\n").encode())
    for i in range(100):
        response=json.loads(f.readline())
        if response.get("id")==name:
            if "error" in response:raise RuntimeError(response["error"])
            return response.get("return")
    raise RuntimeError("No QMP response")
call("qmp_capabilities")
hashes=[];frame_seconds=[];sample=[];start=time.monotonic()
try:
    for i in range(32):
        due=start+i*0.135
        time.sleep(max(0,due-time.monotonic()))
        call("screendump",{"filename":str(shot)})
        raw=shot.read_bytes()
        assert raw[:17]==b"P6\n1920 1080\n255\n",(i,raw[:40])
        payload=raw[17:]
        assert len(payload)==1920*1080*3
        hashes.append(hashlib.sha256(payload).hexdigest())
        frame_seconds.append(time.monotonic()-start)
        # Brightness and nonuniformity control: inspect a central 200px x 50px region
        if i in (0,15,31):
            coords=[((y*1920+x)*3) for y in range(510,560,4) for x in range(790,990,4)]
            v=[sum(payload[j:j+3])//3 for j in coords]
            sample.append({"frame":i,"luma_min":min(v),"luma_max":max(v),
                           "luma_mean":round(statistics.mean(v),2)})
finally:
    shot.unlink(missing_ok=True)
    f.close();sock.close()
report={"label":label,"utc":datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "method":"QEMU 1920x1080 P6 screendump, 32 scheduled samples at 135ms intervals, SHA-256 of full RGB bytes",
        "samples":32,"unique":len(set(hashes)),"hashes":hashes,
        "interval_ms":[round((frame_seconds[i]-frame_seconds[i-1])*1000,3) for i in range(1,32)],
        "sampled_luminance":sample,
        "duration_seconds":round(frame_seconds[-1],3)}
print(json.dumps(report))
if report["unique"]<30:
    raise SystemExit("Motion correctness rejected: not 30 distinct sampled frames")
