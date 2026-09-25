/// Defensive JSON helpers.
///
/// The backend sends money and quantity fields as *strings* in some places and
/// as JSON numbers in others (`"quantity": "2"` in request bodies, numeric in
/// several responses), and optional relations are sometimes an embedded object
/// and sometimes just a flat `xxxName` field. Rather than sprinkle casts around
/// the models and risk a runtime type error on a live till, every read goes
/// through one of these.
library;

String? asString(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  return s.isEmpty ? null : s;
}

num? asNum(dynamic v) {
  if (v == null) return null;
  if (v is num) return v;
  return num.tryParse(v.toString());
}

double asDouble(dynamic v, [double fallback = 0]) =>
    asNum(v)?.toDouble() ?? fallback;

double? asDoubleOrNull(dynamic v) => asNum(v)?.toDouble();

int asInt(dynamic v, [int fallback = 0]) => asNum(v)?.toInt() ?? fallback;

bool asBool(dynamic v, [bool fallback = false]) {
  if (v is bool) return v;
  if (v == null) return fallback;
  final s = v.toString().toLowerCase();
  if (s == 'true' || s == '1') return true;
  if (s == 'false' || s == '0') return false;
  return fallback;
}

Map<String, dynamic>? asMap(dynamic v) {
  if (v is Map) {
    return v.map((key, value) => MapEntry(key.toString(), value));
  }
  return null;
}

List<Map<String, dynamic>> asMapList(dynamic v) {
  if (v is List) {
    return v
        .whereType<Map>()
        .map((e) => e.map((k, val) => MapEntry(k.toString(), val)))
        .toList();
  }
  return const [];
}

List<String> asStringList(dynamic v) {
  if (v is List) {
    return v.where((e) => e != null).map((e) => e.toString()).toList();
  }
  return const [];
}

/// First non-null value among [keys] — used where the field name the API uses
/// isn't pinned down by the docs (e.g. `saleNumber` vs `number` vs `code`).
dynamic firstOf(Map<String, dynamic> json, List<String> keys) {
  for (final k in keys) {
    final v = json[k];
    if (v != null && v.toString().isNotEmpty) return v;
  }
  return null;
}

String? firstString(Map<String, dynamic> json, List<String> keys) =>
    asString(firstOf(json, keys));

/// First usable URL out of an `images` array.
///
/// The array may hold plain strings or objects — `{url}`, `{path}`, `{src}` —
/// and is frequently empty, so this returns null rather than guessing.
String? firstImageUrl(dynamic images) {
  if (images is! List) return asString(images);
  for (final entry in images) {
    if (entry == null) continue;
    if (entry is String) {
      if (entry.trim().isNotEmpty) return entry.trim();
      continue;
    }
    final map = asMap(entry);
    final url = firstString(map ?? const {}, ['url', 'path', 'src', 'image']);
    if (url != null) return url;
  }
  return null;
}

/// Like `Iterable.firstWhere(..., orElse: () => null)` without pulling in
/// package:collection.
T? firstWhereOrNull<T>(Iterable<T> items, bool Function(T) test) {
  for (final item in items) {
    if (test(item)) return item;
  }
  return null;
}
