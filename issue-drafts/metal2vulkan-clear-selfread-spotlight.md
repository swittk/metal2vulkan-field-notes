# Clear-loaded attachment self-read can reintroduce stale glyph/caret pixels (Spotlight)

## Symptom

On an x86-64 macOS guest using the Linux/Vulkan Metal2Vulkan backend, typing into Spotlight could leave old letters and duplicate carets behind. The issue appeared in the displayed image; it was not a keyboard, string encoding, or search index error.

## Observed cause

The attached-image read path took the shadow copy before the render pass's color-attachment Clear action. A first draw that sampled the **same color attachment** could read the prior glyphs from its sampled shadow and reintroduce them into the freshly cleared target.

## Suggested direction

The attached-image self-read shadow should reflect the correct load action before its first draw. The tested correction was deliberately narrow: recognize only a first copy into an image-backed sampled shadow of **the same cleared attachment/subresource**, for single sample/layer and a single zero-offset region, with the entire read footprint inside the known clear area. Preserve Load, independent source, memoryless, multisample, layers, and out-of-clear-footprint behavior.

**Please treat the linked patch as a diagnostic implementation, not a merge-ready change.** It uses a default-off diagnostic environment flag. An upstream solution should be structural in the current render-pass pipeline, not tied to Spotlight or to a permanent user-facing performance/correctness switch. Current master has diverged from the source used for the local fix.

## Bounded evidence (single host)

Same-binary A/B/A Spotlight tests measured excess ghost/caret groups:

| Mode | Groups |
|---|---:|
| Original baseline | 91 |
| Correction ON | 0 |
| Warm correction ON | 0 |
| Same binary correction OFF | 66 |
| Final bounded correction ON | 0 |

Actual QEMU GPU captures were also visually inspected; the caret metric was not used as the sole correctness oracle. Activity Monitor, Keyboard Settings and a valid Safari query also showed no ghost groups with the correction on.

Native guest Metal readback repeated the following three times:
- Clear/self-read 3×40: 120 stale pixels OFF, **0 ON**.
- Clear/self-read 144×64: 9,216 stale pixels OFF, **0 ON**.
- Load/self-read and Clear/independent-source controls were unchanged.

Integrated CPU runtime tests: 1,166 pass, 0 fail, 1 ignored, including eight eligibility/footprint checks. Five release build stages completed.

A physical native-Metal reference was **not obtained**; the evidence is not a universal Metal conformance guarantee.

## Public source and diary

- [Original experimental 119-line patch](https://github.com/swittk/metal2vulkan-field-notes/blob/main/patches/EXPERIMENTAL-spotlight-clear-selfread.patch)
- [Failure analysis, A/B/A and guest readback diary](https://github.com/swittk/metal2vulkan-field-notes/blob/main/diary/spotlight-clear-selfread.md)
- [Source hash provenance and replay](https://github.com/swittk/metal2vulkan-field-notes/blob/main/manifest/spotlight-selfread-source.json)
- [Sanitized measurements](https://github.com/swittk/metal2vulkan-field-notes/blob/main/results/spotlight-selfread.json)

The old patch was verified to reverse from recorded final source and replay byte-for-byte. It **does not apply cleanly to current upstream master**, and no separate current-master build has been claimed. These are reference implementation ideas and reproducible bounded findings, not an attempt to upload an unreviewed dependency stack.
