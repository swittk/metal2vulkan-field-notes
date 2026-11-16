# Rebuild the standalone private-IOSurface workload

Requires a Linux x86-64 host with an NVIDIA Vulkan-capable GPU, Vulkan ICD and Rust 1.98.1, plus a **separately checked-out** Metal2Vulkan source tree. A GPU must be selected deliberately; if multiple GPUs are present, exclude the others through your normal Vulkan/OCI device visibility setup. Never compare an external/eGPU to a different physical production GPU and call it matched.

The executable is a standalone Metal2Vulkan consumer, not a REIMS guest driver or QEMU extension.

1. Set `M2V_ROOT` to the path of the checkout you want to evaluate (for the November 16 master comparison: `d9236a8a11d3b90a1aa27b54e2d74d3891c4d2e5`).
2. Generate a minimal consumer project beside that checkout (not inside the Metal2Vulkan workspace):

```sh
mkdir -p "$PWD/test-bench/src"
cp bench.rs "$PWD/test-bench/src/main.rs"
cat > "$PWD/test-bench/Cargo.toml" <<EOF
[package]
name = "reims_shadow_isolated_bench"
version = "0.1.0"
edition = "2021"

[dependencies]
metal2vulkan = { path = "$M2V_ROOT/crates/metal2vulkan" }
metal2vulkan-runtime = { path = "$M2V_ROOT/crates/metal2vulkan-runtime" }
EOF
cp Cargo.lock "$PWD/test-bench/Cargo.lock"
CARGO_TARGET_DIR="$PWD/test-target" cargo +1.98.1 build --offline --release --locked   --manifest-path "$PWD/test-bench/Cargo.toml"
BENCH_SECS=12 BENCH_PASSES=4 BENCH_RESOLUTION=1920x1080   "$PWD/test-target/release/reims_shadow_isolated_bench"
```]

The original runs used Docker to isolate the GPU and to keep the accepted guest untouched, but the source does not require Docker itself. The command-line flags name requested duration, number of full-screen clear/load/store render passes, and dimensions. The benchmark requests frames at 30 Hz and checks a 16×16 readback on each frame, but does not confirm real physical scanout.

Run multiple times on the **same GPU** with alternate arm ordering; ignore static/failed/CPU-fallback outcomes. If the GPU is already busy due to active guest rendering or a streaming client, defer the benchmark rather than report a confounded number.

These commands are illustrative; the exact old integrated source checkout is not distributed in this repo, and public master changes after the pinned commit need new verification.
