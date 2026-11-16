# Rejected: render directly into an externally backed linear host image

A tempting way to remove shadow-copy work is to avoid GPU-private shadows and render directly into an image over imported host memory. Our tested single-host prototype preserved inspected pixels in a limited Vulkan alias/layout probe and reported no validation errors in the bounded cases.

However, the **live original guest workload regressed severely**:

| Measurement | Direct external host-memory image candidate |
|---|---:|
| 1080p moving screensaver presentation rate | **12.47/s** |
| Average GPU utilization | **89.73%** |
| Approximate board power | **112.87 W** |
| Hardware decoder utilization | **42.03%** |

A subsequent normal native-rendering return reached about **30.00 presentations/s and 62.2% GPU** in its own short run; the direct-import candidate was not accepted. A profiler attributed the majority of the candidate's cost to actual render passes into external/system memory, not just a shadow-copy pass. This establishes a strong single-host negative result, **not** a cross-vendor impossibility proof.

No source patch is included here: its historical experimental base could not be faithfully replayed from the later source snapshot, and publishing it as a reusable optimization would be misleading. The quantitative evidence and rejection remain useful. A more appropriate question for future work is how to preserve GPU-local rendering while avoiding genuinely redundant coherence transfers.
