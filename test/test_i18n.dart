import 'package:flutter/widgets.dart';

import 'package:secondloop/i18n/strings.g.dart';

Widget wrapWithI18n(Widget child) => TranslationProvider(child: child);
