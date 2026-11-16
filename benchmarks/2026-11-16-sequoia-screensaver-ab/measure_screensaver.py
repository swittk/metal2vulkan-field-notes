#!/usr/bin/env python3
"""Record a real, moving 1080p macOS screensaver at the pinned GPU.

QEMU frame identity check occurs outside the measured GPU/CPU sampling window.
Never changes guest disk, renderer, screen resolution, display mode or video content.
"""
from pathlib import Path
import json,datetime,subprocess,time,re,sys,os,statistics
root=Path(__file__).resolve().parent
label=sys.argv[1];seconds=int(sys.argv[2]) if len(sys.argv)>2 else 45
assert re.fullmatch("[a-z0-9-]{1,60}",label) and 30<=seconds<=180
out=root/"results";out.mkdir(exist_ok=True)
target=out/(label+".json")
assert not target.exists(),target
GPU_UUID=os.environ["REIMS_BENCH_GPU_UUID"]
GPU_INDEX=os.environ["REIMS_BENCH_GPU_INDEX"]
VM_CONTAINER=os.environ["REIMS_BENCH_CONTAINER"]
GPU_BUS_ID=os.environ["REIMS_BENCH_GPU_BUS_ID"]
def command(cmd,timeout=25,**kwargs):
    p=subprocess.run(cmd,capture_output=True,text=True,timeout=timeout,**kwargs)
    if p.returncode!=0:raise RuntimeError(f"{cmd[:5]} failed: {p.stderr[-700:]} {p.stdout[-100:]}")
    return p.stdout
def utc():return datetime.datetime.now(datetime.timezone.utc).isoformat()
def vm():
    d=json.loads(command(["docker","inspect",VM_CONTAINER]))[0]
    assert d["State"]["Running"] and d["State"]["Health"]["Status"]=="healthy",d["State"]
    # The QMP capture checker validates the actual 1920x1080 framebuffer.
    return {"image":d["Config"]["Image"],"digest":d["Image"],"boot":d["State"]["StartedAt"],"id":d["Id"]}
before=vm()
def sensor():
    line=command(["nvidia-smi","-i",GPU_INDEX,
      "--query-gpu=index,uuid,pci.bus_id,utilization.gpu,utilization.memory,utilization.encoder,utilization.decoder,power.draw,clocks.gr,memory.used,temperature.gpu",
      "--format=csv,noheader,nounits"],timeout=10).strip()
    parts=[v.strip() for v in line.split(",")]
    assert len(parts)==11,line
    assert parts[0]==GPU_INDEX and parts[1]==GPU_UUID and parts[2].upper()==GPU_BUS_ID.upper(),parts[:3]
    try:
        values=[float(x) for x in parts[3:]]
    except ValueError:raise RuntimeError("Missing numeric sensor counters: "+repr(parts))
    return dict(zip(["gpu_pct","memory_pct","encoder_pct","decoder_pct","power_w",
           "graphics_clock_mhz","gpu_memory_mib","temp_c"],values))
def qemu_process():
    text=command(["docker","top",VM_CONTAINER,"-eo","pid,comm"],timeout=12)
    matches=[]
    for line in text.splitlines()[1:]:
        fields=line.split()
        if len(fields)>=2 and fields[1]=="macos":matches.append(int(fields[0]))
    assert len(matches)==1,matches
    return matches[0]
def cpu_ticks(pid):
    stat=Path(f"/proc/{pid}/stat").read_text()
    rest=stat[stat.rfind(") ")+2:].split()
    return int(rest[11])+int(rest[12])
def motion(phase):
    p=subprocess.run(["docker","exec","-i",
           "-e",f"REIMS_QMP_SOCKET={os.environ['REIMS_QMP_SOCKET']}",
           "-e",f"REIMS_QMP_SCREENDUMP_DIR={os.environ['REIMS_QMP_SCREENDUMP_DIR']}",
           VM_CONTAINER,"python3","-",
           label+"-"+phase],input=(root/"qmp_motion_check.py").read_text(),
           capture_output=True,text=True,timeout=65)
    if p.returncode:raise RuntimeError(f"Guest motion validation failed {phase}: {p.stderr[-1000:]} {p.stdout[-500:]}")
    report=json.loads(p.stdout.splitlines()[-1])
    assert report["unique"]>=30
    return report
def frame_stats(start,end):
    command_line=["docker","logs","--timestamps","--since",start,"--until",end,VM_CONTAINER]
    process=subprocess.run(command_line,capture_output=True,text=True,timeout=25)
    if process.returncode!=0:raise RuntimeError(process.stderr[-800:])
    lines=process.stdout+"\n"+process.stderr
    points=[]
    for line in lines.splitlines():
        match=re.search(r"reims-vgpu stats: port 0: guest ([0-9.]+)/s, max gap ([0-9.]+) ms",line)
        if match:points.append({"guest_hz":float(match[1]),"max_gap_ms":float(match[2])})
    return points
print("PRECHECK",label,before,flush=True)
pre=motion("before")
p=qemu_process()
sampling_start=utc()
read0=cpu_ticks(p);t0=time.monotonic()
records=[]
for i in range(seconds):
    target_mono=t0+i
    time.sleep(max(0,target_mono-time.monotonic()))
    now=time.monotonic()
    record=sensor()
    record["seconds_since_start"]=round(now-t0,3)
    records.append(record)
read1=cpu_ticks(p);end=time.monotonic();sampling_end=utc()
post=motion("after")
after=vm()
assert before==after,("VM changed during sample",before,after)
stats=frame_stats(sampling_start,sampling_end)
mean_hz=statistics.mean(v["guest_hz"] for v in stats) if stats else 0
duration=end-t0
report={"label":label,"utc_start":sampling_start,"utc_end":sampling_end,
        "variant_image":before,"seconds":round(duration,3),"samples":seconds,
        "sensor_rows":records,"guest_presentations":stats,
        "summary":{name:round(statistics.mean(v[name] for v in records),4)
           for name in ["gpu_pct","memory_pct","encoder_pct","decoder_pct","power_w",
                        "graphics_clock_mhz","gpu_memory_mib","temp_c"]},
        "mean_guest_hz":round(mean_hz,4),
        "max_guest_gap_ms":max((v["max_gap_ms"] for v in stats),default=None),
        "qemu_cpu_one_core_pct":round((read1-read0)/os.sysconf("SC_CLK_TCK")/duration*100,3),
        "motion_before":pre,"motion_after":post,
        "quality":"PENDING: classification follows; retain all raw measurements even if rejected"}
checks={
  "sample_count":len(records)==seconds,
  "presentation_sample_count":len(stats)>=seconds-5,
  "presentation_rate":29.5<=mean_hz<=30.5,
  "no_active_encoder":not any(v["encoder_pct"]>0 for v in records),
  "hardware_decoder_active":all(v["decoder_pct"]>1 for v in records),
  "before_motion":pre["unique"]>=30,
  "after_motion":post["unique"]>=30,
  "same_vm":before==after,
}
report["checks"]=checks
report["quality"]="PASS" if all(checks.values()) else "INVALID"
report["per_second_presentation_rates"]=[x["guest_hz"] for x in stats]
target.write_text(json.dumps(report,indent=2)+"\n")
print("QUALITY",report["quality"],"CHECKS",checks,flush=True)
print("MEASURED",json.dumps({"label":label,"image":before["image"],"seconds":duration,
        "mean_gpu_pct":report["summary"]["gpu_pct"],"board_power_w":report["summary"]["power_w"],
        "qemu_cpu_one_core_pct":report["qemu_cpu_one_core_pct"],"guest_hz":mean_hz,
        "max_gap_ms":report["max_guest_gap_ms"],"before_unique":pre["unique"],"after_unique":post["unique"]}),flush=True)
