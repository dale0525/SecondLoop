Bundled ffmpeg binaries
=======================

Desktop builds now bundle a real `ffmpeg` binary into app assets before
packaging.

Expected file layout:

- `assets/bin/ffmpeg/macos/ffmpeg`
- `assets/bin/ffmpeg/linux/ffmpeg`
- `assets/bin/ffmpeg/windows/ffmpeg.exe`

The runtime extracts the bundled binary to a temp directory and invokes that
path directly, so desktop transcode no longer depends on end-user system
`ffmpeg`.

How binaries are prepared:

- Use a runnable desktop `ffmpeg` binary (static builds are recommended).
- macOS helper script downloads a static binary into `.tools/ffmpeg/macos/ffmpeg`:
  - `bash scripts/setup_ffmpeg_macos.sh`
- Windows helper script downloads a static binary into `.tools/ffmpeg/windows/ffmpeg.exe`:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/setup_ffmpeg_windows.ps1`
- Then prepare bundled assets:
  - `pixi run prepare-ffmpeg` (auto-detect host platform)
  - or `dart run tools/prepare_bundled_ffmpeg.dart --platform=<target>`

The small placeholder files in this folder are only a repository default; they
are replaced during desktop packaging.
