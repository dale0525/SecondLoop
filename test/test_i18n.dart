import 'package:flutter/material.dart';

import 'package:secondloop/i18n/strings.g.dart';

ThemeData _patchSplashFactory(ThemeData theme) =>
    theme.copyWith(splashFactory: InkRipple.splashFactory);

ThemeData _testThemeOrPatched(ThemeData? theme) =>
    _patchSplashFactory(theme ?? ThemeData());

MaterialApp _patchMaterialApp(MaterialApp app) {
  // Widget tests on macOS can crash when Material 3's InkSparkle tries to paint
  // with a fragment shader. Force a shader-free splash factory in tests.
  final theme = _testThemeOrPatched(app.theme);
  final darkTheme =
      app.darkTheme == null ? null : _patchSplashFactory(app.darkTheme!);
  final highContrastTheme = app.highContrastTheme == null
      ? null
      : _patchSplashFactory(app.highContrastTheme!);
  final highContrastDarkTheme = app.highContrastDarkTheme == null
      ? null
      : _patchSplashFactory(app.highContrastDarkTheme!);

  final isRouterApp = app.routerDelegate != null ||
      app.routerConfig != null ||
      app.routeInformationParser != null ||
      app.routeInformationProvider != null;
  if (isRouterApp) {
    return MaterialApp.router(
      key: app.key,
      scaffoldMessengerKey: app.scaffoldMessengerKey,
      routeInformationProvider: app.routeInformationProvider,
      routeInformationParser: app.routeInformationParser,
      routerDelegate: app.routerDelegate,
      routerConfig: app.routerConfig,
      backButtonDispatcher: app.backButtonDispatcher,
      builder: app.builder,
      title: app.title,
      onGenerateTitle: app.onGenerateTitle,
      onNavigationNotification: app.onNavigationNotification,
      color: app.color,
      theme: theme,
      darkTheme: darkTheme,
      highContrastTheme: highContrastTheme,
      highContrastDarkTheme: highContrastDarkTheme,
      themeMode: app.themeMode,
      themeAnimationDuration: app.themeAnimationDuration,
      themeAnimationCurve: app.themeAnimationCurve,
      locale: app.locale,
      localizationsDelegates: app.localizationsDelegates,
      localeListResolutionCallback: app.localeListResolutionCallback,
      localeResolutionCallback: app.localeResolutionCallback,
      supportedLocales: app.supportedLocales,
      debugShowMaterialGrid: app.debugShowMaterialGrid,
      showPerformanceOverlay: app.showPerformanceOverlay,
      checkerboardRasterCacheImages: app.checkerboardRasterCacheImages,
      checkerboardOffscreenLayers: app.checkerboardOffscreenLayers,
      showSemanticsDebugger: app.showSemanticsDebugger,
      debugShowCheckedModeBanner: app.debugShowCheckedModeBanner,
      shortcuts: app.shortcuts,
      actions: app.actions,
      restorationScopeId: app.restorationScopeId,
      scrollBehavior: app.scrollBehavior,
      themeAnimationStyle: app.themeAnimationStyle,
    );
  }

  return MaterialApp(
    key: app.key,
    navigatorKey: app.navigatorKey,
    scaffoldMessengerKey: app.scaffoldMessengerKey,
    home: app.home,
    routes: app.routes ?? const <String, WidgetBuilder>{},
    initialRoute: app.initialRoute,
    onGenerateRoute: app.onGenerateRoute,
    onGenerateInitialRoutes: app.onGenerateInitialRoutes,
    onUnknownRoute: app.onUnknownRoute,
    onNavigationNotification: app.onNavigationNotification,
    navigatorObservers: app.navigatorObservers ?? const <NavigatorObserver>[],
    builder: app.builder,
    title: app.title,
    onGenerateTitle: app.onGenerateTitle,
    color: app.color,
    theme: theme,
    darkTheme: darkTheme,
    highContrastTheme: highContrastTheme,
    highContrastDarkTheme: highContrastDarkTheme,
    themeMode: app.themeMode,
    themeAnimationDuration: app.themeAnimationDuration,
    themeAnimationCurve: app.themeAnimationCurve,
    locale: app.locale,
    localizationsDelegates: app.localizationsDelegates,
    localeListResolutionCallback: app.localeListResolutionCallback,
    localeResolutionCallback: app.localeResolutionCallback,
    supportedLocales: app.supportedLocales,
    debugShowMaterialGrid: app.debugShowMaterialGrid,
    showPerformanceOverlay: app.showPerformanceOverlay,
    checkerboardRasterCacheImages: app.checkerboardRasterCacheImages,
    checkerboardOffscreenLayers: app.checkerboardOffscreenLayers,
    showSemanticsDebugger: app.showSemanticsDebugger,
    debugShowCheckedModeBanner: app.debugShowCheckedModeBanner,
    shortcuts: app.shortcuts,
    actions: app.actions,
    restorationScopeId: app.restorationScopeId,
    scrollBehavior: app.scrollBehavior,
    themeAnimationStyle: app.themeAnimationStyle,
  );
}

Widget wrapWithI18n(Widget child) {
  if (child is MaterialApp) {
    return TranslationProvider(child: _patchMaterialApp(child));
  }

  return TranslationProvider(
    child: Builder(
      builder: (context) {
        return Theme(
            data: _patchSplashFactory(Theme.of(context)), child: child);
      },
    ),
  );
}
