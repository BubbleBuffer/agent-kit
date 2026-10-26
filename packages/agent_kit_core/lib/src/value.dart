/// JSON helpers and the value base class shared by every kit model.
library;

/// A decoded JSON object.
typedef Json = Map<String, Object?>;

/// Base class of every kit model: an immutable value with a JSON form.
///
/// Equality and the hash code are defined by [toJson], so two values are
/// equal exactly when they serialize to the same JSON. Subclasses only
/// implement [toJson]; they never override `==` themselves.
abstract class KitValue {
  /// Const constructor for subclasses.
  const KitValue();

  /// The JSON form: a map of JSON values, with null fields left out.
  Json toJson();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KitValue &&
          other.runtimeType == runtimeType &&
          jsonEquals(toJson(), other.toJson());

  @override
  int get hashCode => jsonHash(toJson());

  @override
  String toString() => '$runtimeType${toJson()}';
}

/// Deep equality of two JSON values.
bool jsonEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map<Object?, Object?> && b is Map<Object?, Object?>) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !jsonEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List<Object?> && b is List<Object?>) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!jsonEquals(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is KitValue && b is KitValue) return a == b;
  return a == b;
}

/// A hash consistent with [jsonEquals]; map key order does not matter.
int jsonHash(Object? value) {
  if (value is Map<Object?, Object?>) {
    var h = 0;
    for (final entry in value.entries) {
      h ^= Object.hash(entry.key, jsonHash(entry.value));
    }
    return h;
  }
  if (value is List<Object?>) return Object.hashAll(value.map(jsonHash));
  return value.hashCode;
}

/// Drops the null values of [map], so JSON stays compact.
Json compact(Json map) => {
  for (final entry in map.entries)
    if (entry.value != null) entry.key: entry.value,
};

/// Serializes a list of values.
List<Json> jsonList(Iterable<KitValue> values) => [
  for (final v in values) v.toJson(),
];

/// Serializes a time as a UTC ISO-8601 string.
String? timeJson(DateTime? t) => t?.toUtc().toIso8601String();

/// Typed readers for decoded JSON. Each throws a [FormatException] naming
/// the key when a value has the wrong type.
extension JsonRead on Json {
  Never _bad(String key, String want) =>
      throw FormatException('"$key" should be $want, got ${this[key]}');

  /// A required string.
  String str(String key) {
    final v = this[key];
    return v is String ? v : _bad(key, 'a string');
  }

  /// An optional string.
  String? strOpt(String key) {
    final v = this[key];
    if (v == null) return null;
    return v is String ? v : _bad(key, 'a string');
  }

  /// A required integer.
  int integer(String key) {
    final v = this[key];
    return v is num ? v.toInt() : _bad(key, 'a number');
  }

  /// An optional integer.
  int? intOpt(String key) {
    final v = this[key];
    if (v == null) return null;
    return v is num ? v.toInt() : _bad(key, 'a number');
  }

  /// A boolean, [fallback] when absent.
  bool boolean(String key, {bool fallback = false}) {
    final v = this[key];
    if (v == null) return fallback;
    return v is bool ? v : _bad(key, 'a boolean');
  }

  /// A required time.
  DateTime time(String key) => DateTime.parse(str(key));

  /// An optional time.
  DateTime? timeOpt(String key) {
    final s = strOpt(key);
    return s == null ? null : DateTime.parse(s);
  }

  /// A required object.
  Json obj(String key) {
    final v = this[key];
    return v is Map<String, Object?> ? v : _bad(key, 'an object');
  }

  /// An optional object.
  Json? objOpt(String key) {
    final v = this[key];
    if (v == null) return null;
    return v is Map<String, Object?> ? v : _bad(key, 'an object');
  }

  /// A list of objects mapped through [read]; empty when absent. Entries for
  /// which [read] returns null are skipped (unknown variants).
  List<T> listOf<T extends Object>(String key, T? Function(Json) read) {
    final v = this[key];
    if (v == null) return const [];
    if (v is! List<Object?>) _bad(key, 'a list');
    final out = <T>[];
    for (final e in v) {
      if (e is! Map<String, Object?>) _bad(key, 'a list of objects');
      final item = read(e);
      if (item != null) out.add(item);
    }
    return List.unmodifiable(out);
  }

  /// A list of strings; empty when absent.
  List<String> strings(String key) {
    final v = this[key];
    if (v == null) return const [];
    if (v is! List<Object?>) _bad(key, 'a list');
    return List.unmodifiable([
      for (final e in v) e is String ? e : _bad(key, 'a list of strings'),
    ]);
  }

  /// An enum value by name; [fallback] when absent or unknown, so newer
  /// backends do not break older kits.
  T enumOf<T extends Enum>(String key, List<T> values, T fallback) {
    final v = this[key];
    for (final e in values) {
      if (e.name == v) return e;
    }
    return fallback;
  }

  /// An optional enum value by name; null when absent or unknown.
  T? enumOpt<T extends Enum>(String key, List<T> values) {
    final v = this[key];
    for (final e in values) {
      if (e.name == v) return e;
    }
    return null;
  }
}
