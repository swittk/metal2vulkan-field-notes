# Actual macOS Sequoia forest-screensaver A/B — Metal2Vulkan master vs accepted integration

**Measured 16 November 2026, inside the actual REIMS macOS guest.** This study compares the accepted REIMS/Metal2Vulkan private-backing implementation with [Metal2Vulkan master at `d9236a8`](https://github.com/steelbrain/metal2vulkan/commit/d9236a8a11d3b90a1aa27b54e2d74d3891c4d2e5).

These are **real 1920×1080 moving forest screensaver frames** from an x86-64 macOS Sequoia 15.8.1 guest, *not* the earlier [standalone synthetic IOSurface benchmark](../2026-11-16-master-vs-accepted/README.md). Host GPU: NVIDIA RTX 2080 Ti, proprietary driver 580.126.09.

## Measured outcome

Both implementations delivered correct moving frames at approximately **30 guest presentations/s**. The balanced comparison uses **three valid 60-second runs per variant**.

| Quantity | Accepted integration | Current M2V master integration |
|---|---:|---:|
| Mean GPU busy utilization | **20.028%** | **20.433%** |
| Between-run SD of GPU busy | 0.069 percentage points | 0.093 percentage points |
| Mean GPU board power | 73.176 W | 72.780 W |
| Mean guest presentation callbacks | 30.006/s | 29.994/s |
| Graphics clock across all valid runs | 1,350 MHz | 1,350 MHz |
| Hardware decoder utilization | 9.917% | 9.950% |
| QEMU CPU (% of one core), mean | 179.58% | 165.13% |
| Worst presentation gap by run | 47.6 / 43.8 / 55.9 ms | 57.9 / 65.7 / 87.8 ms |

**Current master averaged 0.406 percentage points more GPU busy, about 2.03% relative.** This is a small difference, *not* a large real-guest GPU regression. Board power differed by less than 0.4 W; do **not** interpret this as an energy result. QEMU CPU is much more variable between runs and cannot be attributed to Metal2Vulkan alone.

Current master already has a `Backing::PrivateSurface` path for runtime-owned private IOSurface backing. The original historical **76.7% → ~19.8% GPU** optimization compared two *earlier* coherence/backing integrations. It is **not** the baseline of this current-master A/B.

## Six matched real-guest runs

| Chronological run | Renderer | GPU busy | GPU board power | QEMU CPU (% of one core) | Guest presents/s | Maximum gap |
|---|---|---:|---:|---:|---:|---:|
| accepted-a2 | Accepted | 20.050% | 73.111 W | 157.738% | 30.017 | 47.6 ms |
| master-b2 | Master | 20.533% | 72.838 W | 173.660% | 30.000 | 57.9 ms |
| master-b3 | Master | 20.417% | 72.754 W | 159.697% | 30.000 | 65.7 ms |
| accepted-a3b | Accepted return | 20.083% | 73.017 W | 203.322% | 30.000 | 43.8 ms |
| accepted-a4 | Accepted return | 19.950% | 73.401 W | 177.673% | 30.000 | 55.9 ms |
| master-b4 | Master, second VM boot | 20.350% | 72.747 W | 162.023% | 29.983 | 87.8 ms |

A separate **45-second accepted-a1** run was valid (19.8667% GPU, 72.9582 W, 30.0 presents/s), archived as supplemental **without** mixing it into the balanced six-run means.

All six matched runs: **32 distinct full-resolution QMP frames out of 32 before, and again after, every measurement**; no black/stale/stationary output accepted. Their raw per-second sensor readings, per-second presentation counts and full RGB SHA-256 frame-hash sequences are in [observations.json](observations.json). Run `python3 check_results.py` to validate and recompute the tabulated aggregate.

## Controlled conditions and validity gate

- **Same installed macOS guest**, same 72 GiB installation disk, REIMS VM graphics topology, QEMU configuration and display modes. The disposable VM container was killed/recreated between arms; neither installation nor disk contents were wiped. Compose config was checked to differ **only in the QEMU image**, aside from the separate diagnostics-only tests.
- Same physical NVIDIA RTX 2080 Ti and 580.126.09 driver. **1,350 MHz graphics clock in every matched run**, about 10% hardware decoder utilization, **0% hardware encoder activity** throughout the measured period.
- Actual animated 1920×1080 forest video, REIMS guest presentation callbacks near 30/s. QMP captured a full-resolution P6 RGB screenshot **32 times approximately 135 ms apart both before and after** each timed interval. All 384 hashes (six runs × two sequences × 32) were unique **within their respective sequences**. Pixel readback was outside the GPU utilization timing window.
- NVIDIA utilization, board power, clock, decoder and encoder sensors sampled once per second for 60 observations; QEMU CPU calculated from Linux process CPU ticks. Presentation rates and maximum gaps came from REIMS per-second diagnostics.
- Samples were rejected unless presentation rate was within 29.5–30.5/s, both QMP sequences had at least 30 distinct images, hardware decoder remained active, encoder activity was zero, and the same VM stayed active throughout. The six accepted runs met all gates.

**These are steady 30 FPS intervals, not a comprehensive test of rare presentation stalls or cold-start latency.** Animation segments can differ between sequential VM boots, and this is one Linux/NVIDIA host: differences near half a percentage point should not be generalized to other GPUs or to energy consumption.

## The necessary source compatibility work

The accepted arm uses the established REIMS private-backing and external-write-coherency integration (locally accepted November 8 image). The comparison arm uses **unmodified upstream Metal2Vulkan source** at `d9236a8`, linked into the accepted REIMS code with REIMS-side API shims needed by the newer M2V runtime.

Two real REIMS device-identity errors were exposed and corrected to make the master arm render accurately:

1. [GPU address-pool identity](pool-reservation-compat.patch): the runtime exposes a generation-specific device handle on a held address-pool buffer. REIMS incorrectly compared its `DeviceProperties` pointer with the original root device; a second reservation of the same pinned GPU range failed. Keeping the root handle with the cache fixes the identity check.
2. [Private IOSurface buffer-cache identity](private-buffer-device-identity.patch): the same root-versus-generation comparison made **separate GPU-private buffers** instead of reusing a surface's shared backing. QEMU then displayed black, despite guest frame callbacks. Keying by the source root device restored **32/32 moving forest images** and a diagnostics-only GPU readback showed nonzero source pixels identical to rendered destination pixels.

The initial startup failure and black framebuffer were **correctness failures, not performance measurements**. Both source fixes are in REIMS, not alterations to current Metal2Vulkan master. Other REIMS-side API compatibility shims are necessary (including changed Metal capability model). This is therefore an **integrated library-version A/B**, not a pure single-function patch test or a measurement of today's entirely different REIMS guest graphics architecture.

Every final performance run used a freshly built QEMU image with diagnostics removed, validated by a binary marker scan. Source hashes, image hashes and exact capture code versions are retained in the experiment provenance.

## Independent source provenance and loop-pacing investigation

The A/B's **current-master variant did not use stock current REIMS**. It used the older, previously accepted REIMS integration, rebuilt against unmodified Metal2Vulkan master d9236a8. For an inspectable record of what changed **outside M2V**, see:

- [Ten-file REIMS API adapter delta](reims-m2v-master-api-compat.patch) and [input/output SHA-256 contract](reims-m2v-master-api-compat-contract.json). This patch was generated from the **actual frozen older REIMS source and accepted overlays** to the final build's compiled adapter files, then applied to a fresh sparse preimage tree; all resulting file SHA-256 hashes matched. It is **not** a recommended patch to current upstream REIMS. The original initial experimental adapter manifest predates three later build corrections, so the contract uses the final built source revisions.
- [Address-pool root/generation-device identity fix](pool-reservation-compat.patch). The older REIMS consumer used an AddressPool.device().properties() pointer to identify a reservation even though the current M2V runtime can return a generation-specific handle. This assumption is already corrected in contemporary upstream REIMS, independently of our experimental adapter.
- [Private IOSurface backing-cache identity fix](private-buffer-device-identity.patch). This is a bug in our **local 2026-10-31 REIMS private-backing optimization**, not a demonstrated bug in current upstream REIMS or M2V. It must reuse the source root device's buffer rather than compare the returned generation handle's properties.

The older REIMS video-loop pacing repair is **already published separately**, with its actual code and evidence:

- [REIMS issue #157](https://github.com/steelbrain/reims-vgpu/issues/157), including the maintainer's response that the relevant fix was pushed to the development branch. This concerns the **older AppleParavirtGPU / apple-gfx transport**, not a demonstration of a bug in today's reims-graphics-pci driver.
- [Complete historical 17-file loop fix](https://github.com/swittk/reims-vgpu-field-notes/blob/479e3a5a80210a7e684036634c99866825ce4974/patches/complete-loop-fix.patch), [narrow scattered-memory import decision](https://github.com/swittk/reims-vgpu-field-notes/blob/479e3a5a80210a7e684036634c99866825ce4974/patches/native-import-only.patch), [base-source hashes](https://github.com/swittk/reims-vgpu-field-notes/blob/479e3a5a80210a7e684036634c99866825ce4974/manifest/complete-patch-bases.json), and [investigation and rejected candidates](https://github.com/swittk/reims-vgpu-field-notes/blob/479e3a5a80210a7e684036634c99866825ce4974/diary/02-approaches-and-failures.md).
- [Accepted loop-pacing results](https://github.com/swittk/reims-vgpu-field-notes/blob/479e3a5a80210a7e684036634c99866825ce4974/diary/03-accepted-implementation.md): approximately 260 s at 30 FPS on the original screensaver, worst QEMU gap 59.6 ms and no gaps >60 ms; a **separate** 150 s native-player control at nearly 60 FPS improved from 110.855 ms worst gap and six >60 ms gaps to 55.357 ms worst gap and zero such gaps.

**Do not merge the two studies into one latency result.** The A/B reported here uses three **60-second** moving-screensaver windows per arm, insufficient to characterize rare events near the original 120-second video loop. It captures per-run worst inter-presentation gaps (accepted: 47.6/43.8/55.9 ms; integrated M2V master: 57.9/65.7/87.8 ms), not input-to-display or decode latency percentiles. Both variants also had excluded startup/transition failures. The separate historical 150/260-second pacing experiments demonstrate the older loop fix but are not a matched current-REIMS or current-M2V long-duration latency comparison.

The original 42 accepted REIMS and 11 Metal2Vulkan source overlays, guest/firmware materials and environment are not all redistributed here, so the public materials establish **inspectable source differences and measurements**, not a byte-for-byte, one-command reconstruction of the private VM.

## Rejected tests are not hidden

- **master-b1:** one otherwise moving-frame run averaged **27.932 guest presentations/s**, with a transient stall. It failed the 30 FPS requirement. The harness rejected the attempt; **no GPU mean from it is reported or imputed**.
- **accepted-a3:** during a guest transition after switching the VM back, the *pre-measurement* 32-frame motion test failed. No GPU sampling was started. Accepted REIMS also exhibited intermittent startup/transition stalls.

These exclusions affect any assertion about full-run latency tails. The evidence above supports only steady 30 FPS GPU busy behavior, not a claim that one renderer has better behavior through all guest startup/transition periods.

## Evidence and reproduction

- [Observations and frame hashes](observations.json): six balanced 60-second runs, one supplemental 45-second run, and both excluded attempts.
- [Offline validator](check_results.py): checks count, QMP hashes, clock/decoder/encoder gating, per-second sensor averages, and calculated means/SDs.
- [Measurement harness](measure_screensaver.py) and [QMP full-resolution motion checker](qmp_motion_check.py): source-equivalent, with host GPU UUID/index/bus address, container name, and guest QMP paths replaced by **environment variables**.
- [Address-pool identity correction](pool-reservation-compat.patch) and [private-buffer cache identity correction](private-buffer-device-identity.patch).

For the portable measurement scripts set `REIMS_BENCH_CONTAINER` (your running REIMS VM container name), `REIMS_BENCH_GPU_INDEX`, `REIMS_BENCH_GPU_UUID`, `REIMS_BENCH_GPU_BUS_ID` (from your `nvidia-smi` output), and `REIMS_QMP_SOCKET`, `REIMS_QMP_SCREENDUMP_DIR` (paths *inside your own running test VM container*). Then run `python3 measure_screensaver.py your-run-label 60` with a live moving 1080p forest workload. The public scripts preserve the measurement algorithm but remove machine-specific path/device wiring.

The proprietary macOS installation, guest disk image, raw Apple binaries, local deployment information and private machine identifiers are **not** published. Exact replay of both variants also needs the corresponding accepted REIMS source integration and guest inputs; this archive supplies measured evidence, methods and two reusable fixes, **not a one-command distributable macOS VM**.
