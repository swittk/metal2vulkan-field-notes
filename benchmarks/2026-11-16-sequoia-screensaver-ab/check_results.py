#!/usr/bin/env python3
"""Check the archived full-guest macOS screensaver A/B without a GPU."""
import json
import statistics
from pathlib import Path
p=Path(__file__).resolve().with_name("observations.json")
d=json.loads(p.read_text())
assert d["m2v_master_commit"]=="d9236a8a11d3b90a1aa27b54e2d74d3891c4d2e5"
assert d["master_qemu_sha256"]=="1eeed39c2f87b155d76144f1cf7d633d0b9f2571fdee066b8b8c3e891a95540a"
assert len(d["results"])==7
assert len([v for v in d["results"] if v["supplemental"]])==1
matched=[v for v in d["results"] if not v["supplemental"]]
assert len(matched)==6
assert len([v for v in matched if v["variant"]=="accepted"])==3
assert len([v for v in matched if v["variant"]=="m2v-master"])==3
assert d["matched_run_order"]==[x["run"] for x in matched]
for item in d["results"]:
    assert item["quality"]=="PASS"
    assert item["duration_requested_seconds"] in (45,60)
    assert 42<=item["duration_recorded_seconds"]<=62
    assert len(item["gpu_sensor_samples"])==item["duration_requested_seconds"]
    assert len(item["per_second_guest_presentation"])>=item["duration_requested_seconds"]-5
    assert 29.5<=item["mean_guest_presents_per_second"]<=30.5
    assert item["mean_hw_encoder_util_pct"]==0.0
    assert item["mean_hw_decoder_util_pct"]>1.0
    assert item["mean_gpu_graphics_clock_mhz"]==1350.0
    for key in ("before","after"):
        motion=item["qmp_checks"][key]
        assert motion["samples"]==32 and motion["unique_frames"]==32
        assert len(motion["full_rgb_sha256"])==32
        assert len(set(motion["full_rgb_sha256"]))==32
        assert len(motion["capture_interval_ms"])==31
        assert all(len(h)==64 for h in motion["full_rgb_sha256"])
    for name,source in [
        ("mean_gpu_busy_pct","gpu_pct"),
        ("mean_board_power_w","power_w"),
        ("mean_gpu_graphics_clock_mhz","graphics_clock_mhz"),
        ("mean_hw_decoder_util_pct","decoder_pct"),
        ("mean_hw_encoder_util_pct","encoder_pct")
    ]:
        recomputed=statistics.mean(row[source] for row in item["gpu_sensor_samples"])
        assert abs(recomputed-item[name])<=0.00012,(item["run"],name,recomputed,item[name])
    guest=statistics.mean(row["guest_hz"] for row in item["per_second_guest_presentation"])
    assert abs(guest-item["mean_guest_presents_per_second"])<=0.00012
    max_gap=max(row["max_gap_ms"] for row in item["per_second_guest_presentation"])
    assert max_gap==item["max_presentation_gap_ms"]
for group,rows in [("accepted",[x for x in matched if x["variant"]=="accepted"]),
                   ("m2v-master",[x for x in matched if x["variant"]=="m2v-master"])]:
    archived=d["aggregate"][group]
    assert archived["n"]==3
    for metric,col in [
        ("gpu_busy_pct","mean_gpu_busy_pct"),
        ("board_power_w","mean_board_power_w"),
        ("qemu_cpu_pct","mean_qemu_cpu_pct_of_one_core"),
        ("presents_per_second","mean_guest_presents_per_second"),
        ("max_presentation_gap_ms","max_presentation_gap_ms"),
        ("hw_decoder_util_pct","mean_hw_decoder_util_pct"),
        ("gpu_clock_mhz","mean_gpu_graphics_clock_mhz")
    ]:
        values=[v[col] for v in rows]
        assert archived[metric]["runs"]==values
        assert abs(archived[metric]["mean"]-statistics.mean(values))<0.000011
        assert abs(archived[metric]["sd_run_means"]-statistics.stdev(values))<0.000011
    print(group,"n=",len(rows),
          "GPU=",round(statistics.mean(v["mean_gpu_busy_pct"] for v in rows),4),
          "W=",round(statistics.mean(v["mean_board_power_w"] for v in rows),4),
          "FPS=",round(statistics.mean(v["mean_guest_presents_per_second"] for v in rows),4))
assert len(d["excluded"])==2
assert {x["run"] for x in d["excluded"]}=={"master-b1","accepted-a3"}
assert not any(v["run"] in {x["run"] for x in matched} for v in d["excluded"])
print("PASS — 6 matched 60s runs, 1 supplemental 45s run, 2 explicitly excluded attempts.")
