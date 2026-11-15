# Diary — private runtime storage and IOSurface identity

A small local change was integrated into the tested Metal2Vulkan runtime: when a buffer is genuinely **runtime-owned**, has **private/memoryless storage mode**, and has **no caller-provided memory**, treat it as PrivateBuffer even if it happens to have an internal IOSurface association.

Suggested rationale: an internal surface handle does not automatically mean an external CPU writer exists. That distinction can determine whether a shadow merge is necessary; imported/caller memory continues to follow its existing policy.

The published patch includes exactly this classification-order change plus a comment. It was reconstructed against the pinned public upstream file and **git apply --check + git apply were verified** for that file. An integrated local build included a change of the same shape and passed the broader REIMS acceptance. **We did not perform a standalone end-to-end upstream-master test of this small patch**; it is a candidate, not an accepted upstream fix.

Safety boundary: never classify externally supplied IOSurfaces or host-page imports as private simply because they are associated with a Metal texture. Upstream regression tests should cover external CPU mutations, device readback, and resource lifetime.
