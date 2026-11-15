# Metal2Vulkan: shadow and memory-transfer field notes

Independent public analysis of runtime shadowing and GPU transfer approaches observed while integrating a macOS guest through REIMS. **Not an official release, and not a claim that upstream has reviewed or accepted the experiments.**

## Source and evidence

- [Small private-storage classification patch](patches/private-owned-iosurface-backing.patch): proposes classifying runtime-owned private Metal storage as PrivateBuffer *before* classifying an associated internal IOSurface as an externally mutable Surface. A patch of this shape was used in the integrated local build. The published patch is independently checked to **apply cleanly to the pinned upstream source file**; it has **not** been independently rebuilt/tested against current upstream master.
- [Current upstream-file hash contract](manifest/private-backed-source.json) and [classification diary](diary/private-owned-storage.md).
- [REJECTED selective byte-store candidate patch](patches/REJECTED-selective-byte-stores.patch): negative research example only, **do not deploy**.
- [Byte-store A/B/A regression diary](diary/selective-byte-store-regression.md), [normalized results](results/byte-store-ab-a.json).
- [Shadow copy census and limits](diary/shadow-copy-census.md), [normalized metrics](results/shadow-census.json).
- [Upstream overlap notes](UPSTREAM.md).

The integrated REIMS memory and VideoToolbox findings are in [reims-vgpu-field-notes](https://github.com/swittk/reims-vgpu-field-notes).

## Additional confirmed visual bug: Spotlight scrambled text

- [Spotlight Clear/self-read experimental correction](patches/EXPERIMENTAL-spotlight-clear-selfread.patch): tested in an integrated Linux/Vulkan runtime, but **not applicable directly to current upstream master**, and opt-in diagnostic policy is not an upstream design.
- [Spotlight investigation diary and same-binary A/B/A evidence](diary/spotlight-clear-selfread.md) and [normalized result](results/spotlight-selfread.json).
- [Recorded patch source hashes](manifest/spotlight-selfread-source.json) and [upstream issue draft](issue-drafts/metal2vulkan-clear-selfread-spotlight.md).

This is a render-pass Clear/attachment self-read correctness issue, **not** a Spotlight string parsing or REIMS VideoToolbox decoder issue.

## Why publish a failed optimization?

The selective byte-store candidate removed some destination loads and passed narrow semantic/SPIR-V checks, yet **actual live display performance collapsed**. That is important negative evidence against equating shorter shader source code, fewer loads, or one GPU capability flag with better real-world performance.

All results were collected on one anonymized Linux x86-64 NVIDIA host. No GPU UUID/model/PCI ID, hostnames, driver IDs, private guest assets, firmware, source media, system images, raw traces, or credentials are published.

## License and limitations

Derivative source patches preserve Metal2Vulkan's original choice of **GPL-2.0-or-later OR LGPL-3.0-or-later**; original explanatory text and aggregate measurements are CC BY 4.0. See the provided license notices. Never infer portable Vulkan correctness or multi-GPU performance from our single-host trials.
