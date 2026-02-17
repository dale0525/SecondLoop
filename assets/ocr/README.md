Desktop OCR runtime/model assets (and optional Whisper runtime payload) are prepared into:

- `assets/ocr/desktop_runtime/`

The folder is generated from GitHub Release runtime assets by:

- `dart run tools/prepare_desktop_runtime.dart`

Do not commit `assets/ocr/desktop_runtime/` into git. The folder is ignored by
`.gitignore` and should be generated locally/CI before desktop run/build.

## Whisper GPU strategy for Windows and Linux

### Current state

- `rust/Cargo.toml` enables `whisper-rs` with `metal` on macOS.
- `rust/Cargo.toml` enables `whisper-rs` with `vulkan` on Windows/Linux.
- `rust/src/api/audio_transcribe.rs` tries GPU first on desktop (macOS/Windows/Linux), then falls back to CPU if GPU context init fails.

So Windows/Linux local Whisper now follows GPU-first policy with CPU fallback.

### Backend options

- `cuda` (NVIDIA, Windows/Linux): best peak performance on NVIDIA, but CUDA runtime dependencies are required.
- `vulkan` (cross-vendor, Windows/Linux): broad compatibility across NVIDIA/AMD/Intel, good default universal backend.
- `hipblas` (AMD ROCm, Linux only): higher integration complexity; not suitable for first rollout.
- OpenVINO (Windows/Linux): encoder acceleration path in `whisper.cpp`, but introduces extra model conversion and packaging complexity.

### Recommended rollout

1. Completed Phase 1: `vulkan` backend builds for Windows/Linux with CPU fallback.
2. Next Phase 2: add optional `cuda` backend builds for Windows/Linux NVIDIA-focused distribution.
3. Defer `hipblas` and OpenVINO until backend matrix and CI capacity are ready.

### Packaging and CI implications

- Build matrix should become backend-aware (`windows-x64-vulkan`, `linux-x64-vulkan`, optional CUDA flavors).
- Runtime payload checks should validate backend-related dynamic dependencies.
- Add smoke tests per backend artifact and verify GPU-init failure can fall back to CPU.

### References

- whisper.cpp backend docs:
  - https://github.com/ggml-org/whisper.cpp#nvidia-gpu-support
  - https://github.com/ggml-org/whisper.cpp#vulkan-gpu-support
  - https://github.com/ggml-org/whisper.cpp#openvino-support
- whisper-rs features:
  - https://docs.rs/crate/whisper-rs/0.15.1/source/README.md
  - https://docs.rs/crate/whisper-rs/0.15.1/source/Cargo.toml
- whisper-rs-sys build behavior (CUDA/Vulkan/HIP handling):
  - https://docs.rs/crate/whisper-rs-sys/0.14.1/source/build.rs
