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

- CI release workflow installs platform `ffmpeg` and runs:
  - `dart run tools/prepare_bundled_ffmpeg.dart --platform=<target>`
- Local dev can run:
  - `pixi run prepare-ffmpeg` (auto-detect host platform)

The small placeholder files in this folder are only a repository default; they
are replaced during desktop packaging.
