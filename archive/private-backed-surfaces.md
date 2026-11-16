# Keep truly internal legacy backing on the GPU

A legacy REIMS GPU resource may own an internal IOSurface-shaped object even when its memory is **private Metal runtime storage**, with no external CPU writer. Treating that internal association like an externally mutable guest-page surface forces shadow/copy traffic that need not apply to private resources.

The accepted local integration used both: a REIMS-owned internal private buffer for eligible legacy resources, and Metal2Vulkan's existing distinction between actual host-page imports and a private resource. The narrow source classification patch [private-owned-iosurface-backing.patch](../patches/private-owned-iosurface-backing.patch) moves the private/no-caller-memory case before generic surface classification, while imported/caller storage retains its old policy.

The broader **14-file combined REIMS/Metal2Vulkan** source diff, exact before/after hashes and the three valid ~19.8%-GPU moving-wallpaper samples are documented in the [REIMS private-backing case study](https://github.com/swittk/reims-vgpu-field-notes/blob/main/archive/external-write-private-backing/README.md).

**Important:** this is not a blanket recommendation to treat arbitrary IOSurfaces as private. Imported memory may have external writers or GPU-writeback requirements; misclassification can silently yield stale or torn pixels. The single-line Metal2Vulkan classification patch was checked for applicability to a pinned public file, but its independent current-master end-to-end correctness was not demonstrated. The full mixed-source integration uses a different historical baseline.


## November 16 source and performance update

Latest upstream master ([d9236a8](https://github.com/steelbrain/metal2vulkan/commit/d9236a8a11d3b90a1aa27b54e2d74d3891c4d2e5)) already has a distinct `PrivateSurface` branch for runtime-owned private IOSurface memory. The small October patch is therefore **not a missing master feature ready to cherry-pick**.

In a [same-GPU eight-run standalone source comparison](../benchmarks/2026-11-16-master-vs-accepted/README.md), the old integrated implementation had lower mean completion latency, but the three-week source change includes many other semantics. It cannot be attributed to the one historical branch or used to predict guest desktop FPS without a full-stack matched test.
