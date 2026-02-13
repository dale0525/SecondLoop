const kDesktopSilentStartupArg = '--silent-startup';

final class DesktopLaunchArgs {
  const DesktopLaunchArgs({this.silentStartupRequested = false});

  final bool silentStartupRequested;

  factory DesktopLaunchArgs.fromMainArgs(List<String> args) {
    final requested = args.any((arg) => arg.trim() == kDesktopSilentStartupArg);
    return DesktopLaunchArgs(silentStartupRequested: requested);
  }
}
