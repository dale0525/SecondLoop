import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/i18n/strings.g.dart';
import 'package:secondloop/web_app/secondloop_web_app.dart';

void main() {
  setUp(() {
    LocaleSettings.setLocale(AppLocale.en);
  });

  testWidgets('web app localizes bootstrap failure in zh-CN', (tester) async {
    LocaleSettings.setLocale(AppLocale.zhCn);

    await tester.pumpWidget(
      SecondLoopWebApp(
        bootstrapLoader: () async => throw StateError('config_http_500'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Web 应用启动失败：'), findsOneWidget);
    expect(find.textContaining('config_http_500'), findsOneWidget);
  });
}
