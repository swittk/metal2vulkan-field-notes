# Same-GPU standalone private-IOSurface benchmark — November 16, 2026

A bounded **standalone Metal2Vulkan rendering comparison**, performed to answer the maintainer's question on [Metal2Vulkan #11](https://github.com/steelbrain/metal2vulkan/issues/11): how does our historical integrated private-backing implementation compare to **current upstream master**?

## What this DOES and DOES NOT establish

We compared the **October 31 locally accepted, integrated Metal2Vulkan source** with upstream Metal2Vulkan [commit d9236a8](https://github.com/steelbrain/metal2vulkan/commit/d9236a8a11d3b90a1aa27b54e2d74d3891c4d2e5) from November 16. Both executables were built in Rust 1.98.1 release mode from identical [benchmark code](bench.rs), with identical [Cargo dependency lockfiles](Cargo.lock). Both ran on **the same physical NVIDIA RTX 2080 Ti (driver 580.126.09) used by our accepted macOS VM**. This is not the other eGPU.

This is a **host-side Metal2Vulkan-only experiment**, not the actual macOS screensaver. The running guest stayed alive and was not modified, rebooted, or switched to another image. Its GPU was idle before each benchmark start (0–2% sampled utilization); its background memory allocation and processes remained in place. Utilization readings therefore include this background load. The workload uses a 1920×1080 pitched RGBA8 surface, 32 bytes of row padding, a 256-byte offset, an internal GPU-private backing/IOSurface alias, one or four render clear/load/store passes per scheduled frame at 30 Hz, plus a 16×16 sampled pixel-region readback on every frame. **Every sampled texel was checked against the new expected frame color**; 30 Hz here is *requested submission pacing*, not measured QEMU presentation FPS.

Each condition ran twice, in **accepted → master → master → accepted** order. Four-pass trials ran for 12 seconds (360 frames each), and one-pass trials for 8 seconds (240 frames each). The matching runs emitted identical sampled output hashes. NVIDIA utilization/power/clock figures were sampled at 500 ms intervals within the timed portion. No streaming client was connected during the tests.

## Results on this one GPU

| Test | Accepted October integration (two runs) | November 16 upstream master (two runs) |
|---|---:|---:|
| 4 passes, mean submission-to-completion latency | **1.498 / 1.575 ms** | 1.926 / 1.937 ms |
| 4 passes, p95 completion latency | **1.908 / 1.905 ms** | 1.999 / 2.068 ms |
| 4 passes, p99 completion latency | **1.941 / 1.979 ms** | 19.813 / 12.062 ms |
| 4 passes, mean sampled GPU busy | **3.455 / 3.500%** | 5.565 / 5.435% |
| 1 pass, mean submission-to-completion latency | **1.369 / 1.467 ms** | 1.752 / 1.950 ms |
| 1 pass, p95 completion latency | **1.910 / 1.913 ms** | 2.002 / 2.755 ms |
| 1 pass, p99 completion latency | **1.947 / 1.966 ms** | 11.731 / 13.609 ms |
| 1 pass, mean sampled GPU busy | **2.933 / 3.867%** | 6.333 / 6.600% |

Mean of the two run-level mean latencies: **1.537 ms versus 1.932 ms** with four render passes (~20.5% lower in the older implementation), and **1.418 ms versus 1.851 ms** with one pass (~23.4% lower). The largest distinction in these brief trials was the longer **p99 latency tail** on current master; p95 was much closer. Board-power readings were not consistently lower, so we do **not** claim power savings.

All eight runs passed sampled pixel validation. Detailed per-run latency statistics, sample counts, NVIDIA clock/utilization observations, output hashes and limits appear in [observations.json](observations.json).

## Source-level context (essential qualification)

Current Metal2Vulkan master **already recognizes internally owned private IOSurface backing**: [shadow.rs](https://github.com/steelbrain/metal2vulkan/blob/d9236a8a11d3b90a1aa27b54e2d74d3891c4d2e5/crates/metal2vulkan-runtime/src/shadow.rs) classifies a (surface, no caller memory, private) buffer as `Backing::PrivateSurface`. This substantially overlaps our earlier one-line private-backing classification, so there is **no basis to claim the one-line optimization remains absent from master**.

The October integration also used a substantially older complete runtime and other upstream/local changes. Consequently the measured **old-integrated-source versus current-master** difference is not an isolated one-line patch A/B. It might reflect other correctness mechanisms, tracking, scheduling or implementation changes. It does not prove that current master is slower on a real macOS guest, or that our patch should be reapplied.

We prepared a single-line ablation of the current-master `PrivateSurface` classification to test its effect separately. This ablation **was not run as a matched trial**: the running macOS guest became active (~20% GPU) and our benchmark automatically refused to start. We did not interrupt it to finish the experiment. No ablation metric is claimed.

The earlier 76.7% → 19.8% historical screensaver improvement is from **a different integration and correctness-control comparison**, not a current-master A/B and not directly comparable to these host-side results.

## Independently repeat the standalone workload

This archive includes [bench.rs](bench.rs), [Cargo.lock](Cargo.lock), and [build instructions](BUILD.md) for any compatible Metal2Vulkan checkout. The earlier integrated source has precise hashes and historical patches in the companion [REIMS notes](https://github.com/swittk/reims-vgpu-field-notes/tree/bffe66db86ef0be2e032e946f5a6de9124ec9d11/archive/external-write-private-backing) but is *not* a directly checkoutable standalone upstream commit; that limits independent repetition of the exact older arm. The current-master arm is directly reproducible from the pinned public commit.

No host names, machine paths, VM disks, Apple binaries, private media, or unredacted GPU telemetry are published.
