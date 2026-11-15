# Related upstream work — link, don't duplicate

- [metal2vulkan #11](https://github.com/steelbrain/metal2vulkan/issues/11): RADV host-page texture-shadow performance regression, distinct hardware and workload. Our negative byte-store experiment is adjacent evidence; it does not establish the same causal GPU behavior.
- [metal2vulkan #16](https://github.com/steelbrain/metal2vulkan/issues/16): readback cost discussion. Our measured cost is a different guest/renderer path; don't equate the two without matching traces.
- [REIMS #107](https://github.com/steelbrain/reims-vgpu/pull/107), [#108](https://github.com/steelbrain/reims-vgpu/pull/108): resident merge/readback and staging changes, potentially overlapping work.

Suggested note (not yet posted): the independent field results show that changing four word writes to selective byte stores can pass semantic/IR checks yet regress a live 1080p macOS guest from about 30 to 6.47 presents/sec; see the negative-result diary. A potential private storage classification change is separately recorded with caveats and an upstream-file-level patch.

**No public issue or PR has been created or commented on from this archive yet.**
