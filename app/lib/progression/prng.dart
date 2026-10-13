/// Tiny deterministic hashing and PRNG, identical on the VM and on the web.
///
/// `dart:math` `Random(seed)` is not guaranteed to produce the same sequence
/// across SDK versions or platforms, and `String.hashCode` is not stable, so
/// challenge selection uses these instead. Only shifts, xors and small
/// multiplications are used so results stay exact in JavaScript numbers.
library;

const int _mask32 = 0xFFFFFFFF;

/// 32-bit FNV-1a hash of the UTF-16 code units of [s].
int fnv1a32(String s) {
  var h = 0x811C9DC5;
  for (final c in s.codeUnits) {
    h = (h ^ c) & _mask32;
    // h * 16777619 == h * (2^24 + 2^8 + 0x93), each term exact below 2^53.
    h = (((h << 24) & _mask32) + ((h << 8) & _mask32) + h * 0x93) & _mask32;
  }
  return h;
}

/// xorshift32 generator. A zero seed is replaced by a fixed non-zero constant.
class XorShift32 {
  XorShift32(int seed) : _x = (seed & _mask32) == 0 ? 0x9E3779B9 : seed & _mask32;

  /// Seeds from a string via [fnv1a32].
  XorShift32.fromString(String s) : this(fnv1a32(s));

  int _x;

  /// Next unsigned 32-bit value.
  int nextUint32() {
    var x = _x;
    x ^= (x << 13) & _mask32;
    x ^= x >> 17;
    x ^= (x << 5) & _mask32;
    _x = x & _mask32;
    return _x;
  }

  /// Uniform-ish integer in `[0, max)`.
  int nextInt(int max) {
    if (max <= 0) throw ArgumentError.value(max, 'max');
    return nextUint32() % max;
  }

  /// Fisher–Yates shuffle of a copy of [items].
  List<T> shuffled<T>(Iterable<T> items) {
    final l = List<T>.of(items);
    for (var i = l.length - 1; i > 0; i--) {
      final j = nextInt(i + 1);
      final t = l[i];
      l[i] = l[j];
      l[j] = t;
    }
    return l;
  }
}
