# Upstream discussions and deliberately separate findings

**Already reported:** [Metal2Vulkan #17](https://github.com/steelbrain/metal2vulkan/issues/17) (Clear-loaded attachment self-read and stale Spotlight pixels), with the [historical diagnostic source patch](patches/EXPERIMENTAL-spotlight-clear-selfread.patch), [exact replay hashes](manifest/spotlight-selfread-source.json), and bounded [on/off visual observations](diary/spotlight-clear-selfread.md). That diagnostic patch is not directly applicable to current upstream master, and a permanent environment toggle is not proposed.

**Relevant ongoing discussion:** [Metal2Vulkan #11](https://github.com/steelbrain/metal2vulkan/issues/11) reports substantial shadow/copy cost on RADV. We have different NVIDIA data: [selective byte stores](diary/selective-byte-store-regression.md) passed narrow source tests but regressed from ~30 to ~6.47 presentations/s, and [direct external-memory image rendering](archive/direct-external-import-negative.md) likewise regressed. These are independent cautionary results, not proof of the same cause or a proposed vendor-specific fix.

**Related REIMS work:** [REIMS #157](https://github.com/steelbrain/reims-vgpu/issues/157) describes expensive synthetic registration of scattered video buffers, while [REIMS #107](https://github.com/steelbrain/reims-vgpu/pull/107) and [#108](https://github.com/steelbrain/reims-vgpu/pull/108) concern reuse/merge and copy paths. Avoid conflating these separate source contracts.

The [private internal-backing case](archive/private-backed-surfaces.md) has an independently checked small classification patch but not an end-to-end current-master hardware validation. Any future upstream issue or PR would need a scoped reproduction on the present architecture.

No new upstream issues, PRs or comments were posted while curating this expanded source archive.
