import 'package:flutter/widgets.dart';

const double kTrayPopupWindowWidth = 288;
const double kTrayPopupWindowHeightWithProUsage = 296;
const double kTrayPopupWindowHeightCompact = 200;

Size resolveTrayPopupWindowSize({required bool reserveProUsageSpace}) {
  return Size(
    kTrayPopupWindowWidth,
    reserveProUsageSpace
        ? kTrayPopupWindowHeightWithProUsage
        : kTrayPopupWindowHeightCompact,
  );
}
