const int kPlatformSafeJsInt = 0x001FFFFFFFFFFFFF;

typedef PlatformInt64 = int;

final class PlatformInt64Util {
  const PlatformInt64Util._();

  static int from(int value) => value;
}

int coercePlatformInt(Object value) {
  if (value is BigInt) return value.toInt();
  if (value is num) return value.toInt();
  throw ArgumentError.value(value, 'value', 'Unsupported platform int value');
}

int? coerceNullablePlatformInt(Object? value) {
  if (value == null) return null;
  return coercePlatformInt(value);
}

int platformIntToInt(PlatformInt64 value) => value.toInt();

int? platformIntToNullableInt(PlatformInt64? value) => value?.toInt();

PlatformInt64 platformIntFromInt(int value) => PlatformInt64Util.from(value);

int comparePlatformInt(PlatformInt64 left, PlatformInt64 right) =>
    left.toInt().compareTo(right.toInt());

int compareNullablePlatformIntAsc(
  PlatformInt64? left,
  PlatformInt64? right, {
  bool nullsLast = true,
}) {
  if (left == null && right == null) return 0;
  if (left == null) return nullsLast ? 1 : -1;
  if (right == null) return nullsLast ? -1 : 1;
  return comparePlatformInt(left, right);
}

int compareNullablePlatformIntDesc(
  PlatformInt64? left,
  PlatformInt64? right, {
  bool nullsLast = true,
}) {
  return compareNullablePlatformIntAsc(
    right,
    left,
    nullsLast: nullsLast,
  );
}
