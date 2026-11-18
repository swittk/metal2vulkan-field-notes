# Guest-present-driven desktop capture — 18 November 2026

**Implementation:** REIMS / QEMU / Sunshine, pinned to their November 18 development sources. This replaces the explicitly **rejected fixed 16 ms GUI/capture polling workaround**, which is preserved only as [historical evidence](../capture-cadence-2026-11-18/README.md). A fixed capture timer is **not a supported fallback**.

## Data flow

1. The REIMS graphics present queue waits for a guest surface's writer and any cache fill. When the surface is *actually shown*, it emits a new optional `display_shown(display)` callback; it also covers colour-only presents and display resets.
2. The backwards-compatible sized C callback table carries that notification into QEMU. It performs only an atomic dirty flag update and schedules a bottom half; no GPU read, QEMU BQL acquisition, or call back into REIMS occurs on the producer thread.
3. QEMU's event loop coalesces notifications by display. At most **one GPU readback per display** runs at a time. Another present during a read leaves a dirty bit so the completion handler schedules **one latest-frame** read; no unbounded queue, fixed capture timer, or fabricated content.
4. The completed read copies into the existing QEMU display surface, emits the D-Bus `UpdateMap`, and the Sunshine QEMU adapter **blocks for the next frame** from its latest-frame mailbox instead of sleeping to a requested frame interval. Its 500 ms mailbox wait timeout remains solely for interruption/stop responsiveness and does not start a new GPU capture or manufacture a video frame.

QEMU's generic UI subsystem still owns its ordinary display refresh timer, as it does for all backends. Calls from that generic timer return the **cached surface** without a GPU read when the per-display dirty bit is clear. Thus the source of new captures is **the guest-present callback**, not the timer. Screen dumps retain their cached-frame behavior; no separate guest display or frontend process is installed.

## Source patches and applicability

- [EVENT-01: REIMS graphics shown callback and C ABI](../../patches/EVENT-01-reims-display-shown-callback-20261118.patch) — Rust device, sized C callback, notification tests.
- [EVENT-02: QEMU coalesced asynchronous readback](../../patches/EVENT-02-qemu-present-driven-20261118.patch) — PCI graphics backend, per-display atomic dirty bit, readback lifecycle.
- [EVENT-03: Sunshine notification-driven mailbox](../../patches/EVENT-03-sunshine-no-periodic-pacing-20261118.patch) — no per-frame sleep or fixed capture interval.

The patch set is based on REIMS `8f8e14af003cc17eaeb5b82e768550b9e001b993`, its vendor QEMU `f56d36ff50346f90a6dbf27e2570eeb98bb2387c`, and the local Sunshine integration source `96cf5ee`. The guest integration also holds independent pre-existing Metal2Vulkan RG16 chroma and NVENC compatibility changes constant; those are not part of this patch.

The QEMU binary used for validation is SHA-256 `615e53e39c715cda9e60229356208748e07970343f3fb99fb0bf34e9bf7b448a`, and the patched Sunshine executable SHA-256 `eccebafc8525430954c32a2d8d71c7b174f02011c9ee9068641fb22e3fdac1d4`. No default resolution, bitrate, video codec, source quality, guest CPU count, or GPU was reduced.

## Reproducible checks

- Rust `cargo check --offline -p reims-vgpu -p reims-vgpu-c`, release C ABI distribution, and QEMU C compilation and link passed.
- Focused guest-independent Rust regression test **PASS**: `cargo test --offline -p reims-vgpu --lib a_display_change_notifies_each_head_but_readback_does_not` — 1 passed, 0 failed; checks two display reset notifications and confirms readback itself does not notify.
- Each of the three source patches passed `git apply --check` and actual application against separately reconstructed **pristine HEAD** copies of its pinned REIMS, QEMU, or Sunshine source files.
- The corrected image booted macOS Sequoia 15.8.1. QMP returned **no such property** for the rejected capture `refresh-interval` knob.
- A native AppKit window moves itself at 40 Hz; there is no Finder dragging, window snapping, AppleScript, or Accessibility permission. It logs its own timing and finishes with an explicit `APP_DONE` marker.
- The local paired Moonlight receiver captures actual 1080p HEVC at requested 60 fps and 15 Mbps. It preserves frame indices, presentation and receive timestamps, and the real encoded bitstream for offline decode. This is not an emulated or interpolated stream.
- Full video validation requires verifying the guest's completion receipt, continuous per-frame marker positions at four scanlines, no corrupted HEVC pictures, no unexplained direction reversals, and no lost Moonlight frame-number sequence.

## Limits

- Validates server-side QEMU → Sunshine → local Moonlight decode; cannot establish timing on a physical remote Moonlight client, its display, or its network.
- A guest producing 40 distinct window positions per second **need not** generate a 60 fps encoded stream. A nominal receiver request for 60 is not evidence that 60 new guest frames exist.
- A GPU readback and CPU memory copy remain in the QEMU software D-Bus path. This source patch is correctness-first, not a GPU zero-copy redesign.
- Source code and tests are experimental and **have not been sent to either upstream maintainer**; this repository is an independent evidence archive.

## Full 275-second guest and encoded-stream test

[Machine-readable, sanitized test record](validation.json) · [native AppKit motion fixture](reims-window-motion.m)

This recording was made in the **same event-driven QEMU and Sunshine binaries** with actual guest motion throughout, not a replay, sleep-only test, generated animation, or 16 ms sampling. A local paired Moonlight receiver requested 60 fps, 1920×1080 HEVC at 15 Mbps. The guest-native AppKit test independently logged 10,996 motion ticks at 40 Hz for **275.001 seconds** (maximum timer gap 51.302 ms, zero over 60 ms).

| Observation | Verified result |
| --- | ---: |
| Encoded HEVC frames / cleanly decoded frames | **12,607 / 12,607** |
| Moving-window measurement window | 272.931 seconds |
| Frames inside validated visual window | 12,057 |
| Actual received video rate | 44.177 fps |
| Receiver interframe gap, p99 / maximum | 37.289 / **41.894 ms** |
| Capture presentation gap, p99 / maximum | 39.011 / 59.389 ms |
| Host processing latency, p50 / p99 | 14.1 / 17.7 ms |
| Unexplained reversed window movement | 0 |
| Cross-scanline marker tearing or missing active marker | 0 |
| Missing/nonconsecutive Moonlight video frame numbers | 0 |
| Profiler-owned probes left installed | 0 |

The guest app moves at 40 Hz, and its WindowServer submissions occur near that rate; **44.177 encoded fps is appropriate variable-rate output**, not a failure to manufacture artificial 60-fps duplicates. Ordinary repeated positions at the reversal points of the deterministic 4.4-second triangle path are expected. The longest unchanged detected position was 89.4 ms; 52 such holds exceeded 60 ms. That metric is a *position hold*, not an encoded-frame gap. No output frame had a scanline marker disagreement.

### Evidence of event-driven capture, not a timer

The complete 335-second QEMU uprobe trace recorded:

| Stage | Count | Notes |
| --- | ---: | --- |
| Actual guest-present notifications | 11,405 | After accepted surface/colour presents and reset |
| GPU readbacks | **11,399** | At most one in flight per display; overlapping notifications coalesce |
| QEMU update-map messages | 11,280 | Only when a listener is available |
| Ordinary GUI refresh requests | 21,157 | These remain part of unmodified QEMU UI infrastructure, but **do not initiate a GPU read on each call** |

During the 271-second central active interval, the guest produced about **40.43 notifications/s**, the host performed **40.41 GPU reads/s**, and the generic refresh callback still ran at 60 Hz. The readback rate followed **actual guest presentations**, not the 60 Hz refresh or any fixed timer. Median / p99 GPU read function duration: 3.689 / 9.017 ms. No call in that trace exceeded 60 ms; the maximum read call was 14.697 ms.

After the window stopped, guest presents fell to about 2.76/s and GPU reads to **the same ~2.76/s**, rather than running at a fixed 60/s or 62.5/s. The guest compositor can still present occasional idle frames; the implementation forwards actual ones and does not synthesize more. No periodic capture setting is used.

The first attempted 275-second test was **invalid**: the guest app rejected a duration over 80 seconds, and the recorder had a 9,000-frame archival cap. Both harness errors were identified and corrected. The validated recording checks the explicit `APP_DONE` guest receipt and uses an isolated recorder with a 25,000-frame archival limit, large enough to save the entire run. These recorder controls **do not change runtime capture cadence**.

### What remains unproved

Some upstream guest-present timing variability remains. In the long run, guest-present / QEMU update-map intervals occasionally reached approximately 74–78 ms (roughly 17–29 such intervals above 60 ms, depending on the stage), while the received HEVC frame intervals never exceeded 41.9 ms. These source-side gaps may reflect actual WindowServer composition timing or GPU scheduling; they were **not** shown to produce unexpected visual motion in this fixture. They should not be called universally smooth 60-fps rendering or conclusive elimination of the owner's reported physical-client twitch.

The test does not measure Moonlight's **physical client presentation timestamps or display latency**, its networking path, or arbitrary application workloads. The fix is nevertheless materially architectural: it removes timer-driven capture and blocks for new frames, while preserving GPU asynchronously readback, proper per-display coalescing, and the user's original requested video settings.
