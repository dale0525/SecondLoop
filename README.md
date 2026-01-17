# SecondLoop

Local-first personal AI assistant (MVP in progress).

## Dev Setup (Pixi + FVM)

1) Install Pixi: https://pixi.sh

2) Install the pinned Flutter SDK (via FVM):

```bash
pixi run setup-flutter
```

3) Common commands:

```bash
pixi run analyze
pixi run test
pixi run frb-generate
pixi run run-macos
pixi run run-android
pixi run run-windows
```

Notes:
- `run-macos` is only available on macOS.
- `run-windows` is only available on Windows (it depends on `setup-windows`) and will download `nuget.exe` into `.tool/nuget/` so Flutter won't auto-download it.

To run arbitrary Flutter commands through FVM:

```bash
pixi run dart pub global run fvm:main flutter <args...>
```

## Troubleshooting

- If you see build errors referencing macOS paths like `/Users/.../fvm/versions/...` on Windows, delete generated Flutter artifacts (or run `dart pub global run fvm:main flutter clean`) and then run `pixi run setup-flutter` again.

## Platform Prerequisites

- Android: Android Studio + SDK (`flutter doctor -v`)
- Windows (dev/build): Visual Studio 2022 + Desktop development with C++ + Individual component `C++ ATL for latest v143 build tools (x86 & x64)` (for `atlstr.h`). End users do not need VS/ATL (they may need the VC++ runtime, which your installer should include).
- macOS/iOS: Xcode + Command Line Tools
