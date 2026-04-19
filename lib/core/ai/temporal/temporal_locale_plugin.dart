import 'package:flutter/widgets.dart';

import 'temporal_resolution.dart';
import 'temporal_locale_plugin_zh_cn.dart';

abstract interface class TemporalLocalePlugin {
  bool supports(Locale locale);

  TemporalCandidate? resolve(TemporalPluginRequest request);
}

final class TemporalLocalePluginRegistry {
  static final List<TemporalLocalePlugin> _plugins = <TemporalLocalePlugin>[
    ZhCnTemporalLocalePlugin(),
  ];

  static TemporalCandidate? resolve(TemporalPluginRequest request) {
    for (final plugin in _plugins) {
      if (!plugin.supports(request.locale)) continue;
      final candidate = plugin.resolve(request);
      if (candidate != null) {
        return candidate.withResolver(TemporalResolver.localePlugin);
      }
    }
    return null;
  }
}
