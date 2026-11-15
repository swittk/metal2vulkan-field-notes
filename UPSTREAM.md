# Related upstream work — link, don't duplicate

- [metal2vulkan #11](https://github.com/steelbrain/metal2vulkan/issues/11): RADV host-page texture-shadow performance regression, distinct hardware and workload. Our negative byte-store experiment is adjacent evidence; it does not establish the same causal GPU behavior.
- [metal2vulkan #16](https://github.com/steelbrain/metal2vulkan/issues/16): readback cost discussion. Our measured cost is a different guest/renderer path; don't equate the two without matching traces.
- [REIMS #107](https://github.com/steelbrain/reims-vgpu/pull/107), [#108](https://github.com/steelbrain/reims-vgpu/pull/108): resident merge/readback and staging changes, potentially overlapping work.

Suggested note (not yet posted): the independent field results show that changing four word writes to selective byte stores can pass semantic/IR checks yet regress a live 1080p macOS guest from about 30 to 6.47 presents/sec; see the negative-result diary. A potential private storage classification change is separately recorded with caveats and an upstream-file-level patch.

**Spotlight issue #17 has been filed. No pull request or other upstream issue was created from this archive.**


## Separate new issue: Spotlight ghost glyphs on Clear/attachment self-read

No pre-existing equivalent Spotlight self-read issue was found in the Metal2Vulkan or REIMS trackers in the November 2026 issue search. This is a **Metal2Vulkan render-pass semantics** issue, not video decoder work, and not the RADV shadow performance regression in #11.

**Filed upstream: [Metal2Vulkan #17 — Clear-loaded attachment self-read can reintroduce stale glyph/caret pixels](https://github.com/steelbrain/metal2vulkan/issues/17).**

The [issue draft](issue-drafts/metal2vulkan-clear-selfread-spotlight.md) links the [original diagnostic patch](patches/EXPERIMENTAL-spotlight-clear-selfread.patch), [measurements](results/spotlight-selfread.json), and [diary](diary/spotlight-clear-selfread.md). Upstream should adapt the structural logic to current render-pass code; the diagnostic env switch is *not* a product proposal.
