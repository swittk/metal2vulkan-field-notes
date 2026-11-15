# Spotlight text scrambling: Clear load and attachment self-read

Observed October 29, 2026. Independent Linux/Vulkan Metal2Vulkan integration with an x86-64 macOS guest. A Spotlight query accumulated ghost glyphs and repeated carets while typing. This is a rendering problem, not search-index contents or the video-loop problem.

## Cause and bounded correction

When the first draw reads its own color attachment, the attached-image read emulation copied the prior attachment into a sampled-image shadow **before** render-pass Clear. That left old glyph/caret pixels available for the next draw to reproduce.

[EXPERIMENTAL diagnostic patch](../patches/EXPERIMENTAL-spotlight-clear-selfread.patch) adds render/selfread_clear.rs and three small render.rs integrations.

The correction applies only when the first copy is into an image-backed shadow of the very same color attachment/subresource being cleared, with one region, zero offsets, one sample and one layer, not memoryless, and the full sampled read footprint inside the known clear region. Ordinary Load passes, independent sources, multisampled/layered passes, and out-of-bounds read footprints retain their original behavior.

**Upstream caveat:** this was an opt-in diagnostic controlled by REIMS_DIAG_SELFREAD_CLEAR=1, not a proposed permanent public env switch. Proper upstream logic should express render-pass/attachment semantics structurally and not recognize Spotlight by name. A physical Metal GPU reference was not obtained, so this is not a universal Metal conformance claim.

## Same-binary observation

| Spotlight case | Excess ghost/caret groups |
|---|---:|
| Original baseline | 91 |
| Correction enabled | 0 |
| Warm repeat enabled | 0 |
| Same binary correction OFF | 66 |
| Final bounded correction ON | 0 |

Capture used QEMU's actual AppleGPU framebuffer, checked visually; caret-group scoring alone is not a correctness oracle. Activity Monitor, Keyboard Settings, and a **valid** Safari query rerun also had zero excess groups. The first Safari trial sent keystrokes to another window; it was excluded.

## Native guest Metal readback

Three repeated public Metal guest tests: Clear/self-read 3x40 kept 120 stale pixels OFF and zero ON; Clear/self-read 144x64 kept 9,216 stale pixels OFF and zero ON. Load/self-read and Clear/independent-source controls remained unchanged. This tests guest-rendered behavior, not equivalence to a physical Mac.

## Test and replay status

Integrated CPU suite: 1,166 passed, zero failed, one ignored, including eight targeted eligibility/footprint tests. Five release build stages passed. Reverse-and-forward git-apply replay reconstructed the recorded input and the exact final source bytes.

The historical patch **does not cleanly apply to current public metal2vulkan master**; render.rs has changed. This source is an implementation reference, not an upstream-ready PR. See the file-hash [manifest](../manifest/spotlight-selfread-source.json).

No guest disk, private images, host identifiers, raw logs or media are distributed.
