# Metal2Vulkan field notes — shadowing, host memory and render-pass correctness

Independent source and performance investigations from a macOS guest running on the Linux/Vulkan REIMS backend. This archive records both successful, narrow correctness changes and **negative results that failed actual GPU testing**.

**Start with the [research index](archive/README.md)** for the private backing change, Spotlight render-pass correction, rejected selective-byte-store implementation, direct external-memory rendering regression, and shadow-copy census.

## Published source and tests

- [Private-owned IOSurface backing classification](patches/private-owned-iosurface-backing.patch): a small shape-based change checked against its pinned upstream source file. See [scope and risks](archive/private-backed-surfaces.md). The larger tested integration spans REIMS and Metal2Vulkan; no standalone upstream build of this patch is claimed.
- [Spotlight Clear/self-read diagnostic patch](patches/EXPERIMENTAL-spotlight-clear-selfread.patch): replicated visual ghost text/caret rendering and native guest readback behavior, documented in the [same-binary diary](diary/spotlight-clear-selfread.md) and reported as [Metal2Vulkan #17](https://github.com/steelbrain/metal2vulkan/issues/17). The original patch does not cleanly apply to current master.
- [Rejected selective-byte-store patch](patches/REJECTED-selective-byte-stores.patch): passed narrow logic/IR tests, yet severely regressed live GPU presentation. Read the [A/B/A diary](diary/selective-byte-store-regression.md) before considering similar alternatives.
- [Direct externally backed host-image negative result](archive/direct-external-import-negative.md): an inspected single-host experiment ran at approximately 12.47 FPS and 89.73% GPU. No falsely reusable patch is offered because its old source baseline cannot be replayed from the later snapshots.
- [Shadow-copy census](diary/shadow-copy-census.md) and [machine-readable aggregates](results/shadow-census.json): count repeated transfers without claiming all copies are redundant.

## New comparison against upstream master (November 2026)

An [8-trial same-GPU standalone benchmark](benchmarks/2026-11-16-master-vs-accepted/README.md) compared the October accepted private-IOSurface implementation with current Metal2Vulkan master (commit d9236a8) using one identical correctness-checked 1080p test program. The older implementation had around 20–23% lower mean completion latency in that *host-side* workload. **Current master already contains a PrivateSurface classification**, and this is not a single-patch A/B or a guest screensaver comparison; details and reproducible source are included.

## Evidence boundaries

All hardware measurements were made on a single anonymized Linux/NVIDIA host. A separate [Metal2Vulkan #11](https://github.com/steelbrain/metal2vulkan/issues/11) reports an AMD/RADV shadowing regression; our results do not establish the same hardware mechanism. No device-ID tuning was deployed as a generic fast path.

No host-identifying information, internal paths, raw logs, GPU UUIDs, Apple binaries, VM images, guest media, or private shader corpus is published. Source patches retain the upstream **GPL-2.0-or-later OR LGPL-3.0-or-later** license; original narrative and aggregate results are offered under CC BY 4.0.

The companion [REIMS engineering archive](https://github.com/swittk/reims-vgpu-field-notes) covers the full decoder, guest-memory, GPU-private backing, and guest compatibility integration. This repository is neither an official Metal2Vulkan release nor a ready-to-merge PR branch.
