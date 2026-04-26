const kDesktopSilentStartupArg = '--silent-startup';
const _kVelopackInstallHookArg = '--veloapp-install';
const _kVelopackUpdatedHookArg = '--veloapp-updated';
const _kVelopackObsoleteHookArg = '--veloapp-obsolete';
const _kVelopackUninstallHookArg = '--veloapp-uninstall';

const _kVelopackHookArgs = <String>{
  _kVelopackInstallHookArg,
  _kVelopackUpdatedHookArg,
  _kVelopackObsoleteHookArg,
  _kVelopackUninstallHookArg,
};

final class DesktopLaunchArgs {
  const DesktopLaunchArgs({
    this.silentStartupRequested = false,
    this.velopackHookInvocationRequested = false,
    this.velopackUninstallHookInvocationRequested = false,
  });

  final bool silentStartupRequested;
  final bool velopackHookInvocationRequested;
  final bool velopackUninstallHookInvocationRequested;

  bool get shouldExitBeforeLaunchingApp => velopackHookInvocationRequested;

  factory DesktopLaunchArgs.fromMainArgs(List<String> args) {
    var silentStartupRequested = false;
    var velopackHookInvocationRequested = false;
    var velopackUninstallHookInvocationRequested = false;
    for (final rawArg in args) {
      final normalizedArg = rawArg.trim().toLowerCase();
      if (normalizedArg == kDesktopSilentStartupArg) {
        silentStartupRequested = true;
      }
      if (_kVelopackHookArgs.contains(normalizedArg)) {
        velopackHookInvocationRequested = true;
      }
      if (normalizedArg == _kVelopackUninstallHookArg) {
        velopackUninstallHookInvocationRequested = true;
      }
    }

    return DesktopLaunchArgs(
      silentStartupRequested: silentStartupRequested,
      velopackHookInvocationRequested: velopackHookInvocationRequested,
      velopackUninstallHookInvocationRequested:
          velopackUninstallHookInvocationRequested,
    );
  }
}
