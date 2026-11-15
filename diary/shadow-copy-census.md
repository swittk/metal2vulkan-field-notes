# Diary — short shadow-copy census (October 30, 2026)

A bounded five-second moving-video/desktop trace on a single anonymized Linux/NVIDIA host contained:

| Event | Count |
|---|---:|
| Render attachments | 601 |
| Shadow uses | 1,203 |
| Shadow-copy events | 1,804 |
| Invalidation events | 601 |

Distinct dominant 1920x1080 Load/Store render targets accounted for substantial activity. Some read aliases shared truth resources with render shadows and incurred repeated whole-frame imports.

**Critical caution:** the approximately four copy-related operations per 30-FPS presentation cannot all be called redundant copies of the same surface. Different truth resources and write lifetimes were involved. Skipping a merge on an unproven alias equivalence risks stale or incorrect pixels.

A candidate future investigation is whether an **already-resident GPU image** can satisfy certain sampled reads while its write lifetime is explicitly known unchanged. This is a hypothesis, not a tested safe optimization.

The raw internal event trace, host paths, resource object IDs, and potentially identifying system logs are withheld. Only aggregate counts and interpretation are provided.
