# Metal2Vulkan memory and GPU performance research

This companion archive discusses Metal2Vulkan-specific findings from an independent x86-64 macOS guest running through the Linux/Vulkan backend. It keeps **working source-level changes**, **diagnostic compatibility corrections**, and **failed GPU optimizations** separate.

| Investigation | Source / evidence | State |
|---|---|---|
| [Internal private backing selection](private-backed-surfaces.md) | [One small current-upstream-file-level patch](../patches/private-owned-iosurface-backing.patch), integrated with a larger REIMS backing change | Local integrated validation; standalone upstream build not claimed |
| [Spotlight Clear/self-read ghost text](../diary/spotlight-clear-selfread.md) | [Original opt-in diagnostic patch](../patches/EXPERIMENTAL-spotlight-clear-selfread.patch), [Metal2Vulkan #17](https://github.com/steelbrain/metal2vulkan/issues/17) | Bug reproduced with same-binary A/B/A; not cherry-pickable to current master |
| [Selective byte-store merge](../diary/selective-byte-store-regression.md) | [Rejected patch](../patches/REJECTED-selective-byte-stores.patch), [A/B/A data](../results/byte-store-ab-a.json) | **Rejected**, approximately 30 FPS to 6.47 FPS |
| [Direct external-memory image rendering](direct-external-import-negative.md) | GPU and presentation measurements only | **Rejected** at approximately 12.47 FPS and 89.73% GPU busy |
| [Shadow-copy causal census](../diary/shadow-copy-census.md) | [Aggregate counts](../results/shadow-census.json) | Observation only; no false assumption all copies are redundant |

The independent REIMS patch bundles are documented in the [REIMS source archive](https://github.com/swittk/reims-vgpu-field-notes/blob/main/archive/README.md). The private-backing source bundle includes source in both projects, and their exact tested source preimages are not one current public upstream commit.

**Practical lesson:** correctness guards, no-copy imports and fewer shader loads are not enough to establish improved live macOS performance. GPU residency, write lifetime, mapping churn, staging and real rendered frames all matter. Performance comparisons here are bounded, sequential, from one anonymized GPU host—not general performance claims for Vulkan hardware.
