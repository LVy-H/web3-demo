/// Minimal QR encoder — byte mode, error-correction level L, versions 1–13,
/// mask pattern 0.
///
/// Why this exists: the ORGANIZE distribute sheet and the run-event console
/// must render scannable QR codes (share links, rotating live tickets), but
/// the Revolution workspace deliberately carries no QR dependency and the R3
/// fan-out freezes every pubspec. This is a self-contained, pure-Dart
/// implementation of the subset Tessera needs:
///
/// - **Byte mode only** — payloads are deep links (`tessera://…`), never
///   numeric/alphanumeric-optimizable content worth the extra modes.
/// - **EC level L** — codes render on a bright in-app surface at generous
///   size; L maximizes capacity so live tickets (~160 chars) fit in v7–v8.
/// - **Versions 1–13** — up to 425 payload bytes, ~2.5× the longest payload
///   we mint (ticket wire 96 chars + deep-link chrome).
/// - **Fixed mask 0** — ISO 18004 *recommends* picking the penalty-minimal
///   mask but any declared mask decodes; fixing it keeps output reproducible
///   for tests.
///
/// The algorithm follows the well-trodden structure of Nayuki's reference
/// "QR Code generator" (placement order, format/version BCH, zigzag fill).
/// Verified against `zbarimg` decode (see test/qr_matrix_test.dart header).
library;

import 'dart:convert';
import 'dart:typed_data';

/// An immutable QR module matrix. `true` = dark module.
class QrMatrix {
  /// Modules per side (`17 + 4 × version`).
  final int size;

  /// The chosen QR version (1–13).
  final int version;

  final List<bool> _modules;

  QrMatrix._(this.version, this._modules)
    : size = 17 + 4 * version,
      assert(_modules.length == (17 + 4 * version) * (17 + 4 * version));

  /// Whether the module at [row], [col] is dark.
  bool isDark(int row, int col) => _modules[row * size + col];

  /// Encode [text] (UTF-8, byte mode, EC L). Throws [ArgumentError] when the
  /// payload exceeds version 13's capacity (425 bytes).
  factory QrMatrix.encodeText(String text) =>
      QrMatrix.encodeBytes(Uint8List.fromList(utf8.encode(text)));

  /// Encode raw [data] (byte mode, EC L).
  factory QrMatrix.encodeBytes(Uint8List data) {
    final version = _smallestVersionFor(data.length);
    final codewords = _buildCodewords(data, version);
    return _Builder(version).build(codewords);
  }

  /// Max payload bytes for [version] at EC L in byte mode.
  static int capacityForVersion(int version) {
    final dataCodewords = _dataCodewords(version);
    final countBits = version <= 9 ? 8 : 16;
    return (dataCodewords * 8 - 4 - countBits) ~/ 8;
  }

  static int _smallestVersionFor(int payloadBytes) {
    for (var v = 1; v <= _maxVersion; v++) {
      if (capacityForVersion(v) >= payloadBytes) return v;
    }
    throw ArgumentError(
      'payload of $payloadBytes bytes exceeds the v$_maxVersion-L capacity '
      'of ${capacityForVersion(_maxVersion)} bytes',
    );
  }

  // ── EC tables (ISO 18004 table 9, level L, versions 1–13) ────────────────

  static const int _maxVersion = 13;

  /// EC codewords per block, indexed by `version - 1`.
  static const List<int> _ecPerBlock = [
    7, 10, 15, 20, 26, 18, 20, 24, 30, 18, 20, 24, 26, //
  ];

  /// Blocks as `(count, dataCodewordsPerBlock)` pairs, indexed by
  /// `version - 1`. Later groups carry one extra data codeword.
  static const List<List<(int, int)>> _blocks = [
    [(1, 19)],
    [(1, 34)],
    [(1, 55)],
    [(1, 80)],
    [(1, 108)],
    [(2, 68)],
    [(2, 78)],
    [(2, 97)],
    [(2, 116)],
    [(2, 68), (2, 69)],
    [(4, 81)],
    [(2, 92), (2, 93)],
    [(4, 107)],
  ];

  static int _dataCodewords(int version) {
    var total = 0;
    for (final (count, dataLen) in _blocks[version - 1]) {
      total += count * dataLen;
    }
    return total;
  }

  // ── Segment + codeword construction ───────────────────────────────────────

  static Uint8List _buildCodewords(Uint8List data, int version) {
    final dataCapacityBits = _dataCodewords(version) * 8;
    final bits = _BitBuffer();
    bits.append(0x4, 4); // byte-mode indicator
    bits.append(data.length, version <= 9 ? 8 : 16);
    for (final byte in data) {
      bits.append(byte, 8);
    }
    // Terminator (up to 4 zero bits), pad to a byte boundary, then pad bytes.
    bits.append(0, (dataCapacityBits - bits.length).clamp(0, 4));
    bits.append(0, (8 - bits.length % 8) % 8);
    var pad = 0xEC;
    while (bits.length < dataCapacityBits) {
      bits.append(pad, 8);
      pad = pad == 0xEC ? 0x11 : 0xEC;
    }
    return _interleave(bits.toBytes(), version);
  }

  /// Split data codewords into EC blocks, compute Reed–Solomon EC for each,
  /// and interleave data-then-EC in block order (ISO 18004 §8.6).
  static Uint8List _interleave(Uint8List dataCodewords, int version) {
    final ecLen = _ecPerBlock[version - 1];
    final gen = _rsGenerator(ecLen);

    final blocks = <Uint8List>[];
    final ecBlocks = <Uint8List>[];
    var offset = 0;
    for (final (count, dataLen) in _blocks[version - 1]) {
      for (var i = 0; i < count; i++) {
        final block = dataCodewords.sublist(offset, offset + dataLen);
        offset += dataLen;
        blocks.add(block);
        ecBlocks.add(_rsRemainder(block, gen));
      }
    }

    final maxDataLen = blocks.map((b) => b.length).reduce((a, b) => a > b ? a : b);
    final out = BytesBuilder();
    for (var i = 0; i < maxDataLen; i++) {
      for (final block in blocks) {
        if (i < block.length) out.addByte(block[i]);
      }
    }
    for (var i = 0; i < ecLen; i++) {
      for (final ec in ecBlocks) {
        out.addByte(ec[i]);
      }
    }
    return out.toBytes();
  }

  // ── GF(256) Reed–Solomon (polynomial 0x11D) ──────────────────────────────

  static int _gfMultiply(int a, int b) {
    var result = 0;
    for (var i = 7; i >= 0; i--) {
      result = (result << 1) ^ ((result >> 7) * 0x11D);
      result ^= ((b >> i) & 1) * a;
    }
    return result & 0xFF;
  }

  /// Generator polynomial coefficients for [degree] EC codewords
  /// (monic, highest-order term implicit).
  static Uint8List _rsGenerator(int degree) {
    final result = Uint8List(degree);
    result[degree - 1] = 1; // x^0 coefficient of the running product
    var root = 1;
    for (var i = 0; i < degree; i++) {
      for (var j = 0; j < degree; j++) {
        result[j] = _gfMultiply(result[j], root);
        if (j + 1 < degree) result[j] ^= result[j + 1];
      }
      root = _gfMultiply(root, 0x02);
    }
    return result;
  }

  static Uint8List _rsRemainder(Uint8List data, Uint8List generator) {
    final result = Uint8List(generator.length);
    for (final byte in data) {
      final factor = byte ^ result[0];
      result.setRange(0, result.length - 1, result.sublist(1));
      result[result.length - 1] = 0;
      for (var i = 0; i < result.length; i++) {
        result[i] ^= _gfMultiply(generator[i], factor);
      }
    }
    return result;
  }
}

/// Append-only bit buffer (MSB first).
class _BitBuffer {
  final List<bool> _bits = [];

  int get length => _bits.length;

  void append(int value, int bitCount) {
    for (var i = bitCount - 1; i >= 0; i--) {
      _bits.add((value >> i) & 1 == 1);
    }
  }

  Uint8List toBytes() {
    final out = Uint8List((_bits.length + 7) ~/ 8);
    for (var i = 0; i < _bits.length; i++) {
      if (_bits[i]) out[i >> 3] |= 0x80 >> (i & 7);
    }
    return out;
  }
}

/// Mutable matrix assembly: function patterns, format/version info, zigzag
/// data placement, mask 0.
class _Builder {
  final int version;
  final int size;
  late final List<bool> modules = List.filled(size * size, false);
  late final List<bool> isFunction = List.filled(size * size, false);

  _Builder(this.version) : size = 17 + 4 * version;

  QrMatrix build(Uint8List codewords) {
    _drawFunctionPatterns();
    _drawCodewords(codewords);
    _applyMask0();
    return QrMatrix._(version, modules);
  }

  void _set(int row, int col, bool dark) {
    modules[row * size + col] = dark;
    isFunction[row * size + col] = true;
  }

  void _drawFunctionPatterns() {
    // Timing patterns.
    for (var i = 0; i < size; i++) {
      _set(6, i, i.isEven);
      _set(i, 6, i.isEven);
    }
    // Finder patterns + separators (clipped at the edges).
    _drawFinder(3, 3);
    _drawFinder(3, size - 4);
    _drawFinder(size - 4, 3);
    // Alignment patterns (skip the three finder corners).
    final positions = _alignmentPositions();
    final last = positions.length - 1;
    for (var i = 0; i < positions.length; i++) {
      for (var j = 0; j < positions.length; j++) {
        final corner =
            (i == 0 && j == 0) || (i == 0 && j == last) || (i == last && j == 0);
        if (!corner) _drawAlignment(positions[i], positions[j]);
      }
    }
    _drawFormatBits();
    _drawVersionInfo();
  }

  void _drawFinder(int centerRow, int centerCol) {
    for (var dr = -4; dr <= 4; dr++) {
      for (var dc = -4; dc <= 4; dc++) {
        final r = centerRow + dr;
        final c = centerCol + dc;
        if (r < 0 || r >= size || c < 0 || c >= size) continue;
        final dist = dr.abs() > dc.abs() ? dr.abs() : dc.abs();
        _set(r, c, dist != 2 && dist != 4);
      }
    }
  }

  void _drawAlignment(int centerRow, int centerCol) {
    for (var dr = -2; dr <= 2; dr++) {
      for (var dc = -2; dc <= 2; dc++) {
        final dist = dr.abs() > dc.abs() ? dr.abs() : dc.abs();
        _set(centerRow + dr, centerCol + dc, dist != 1);
      }
    }
  }

  /// Alignment pattern center coordinates (ISO 18004 annex E, v2–13).
  List<int> _alignmentPositions() => switch (version) {
    1 => const [],
    2 => const [6, 18],
    3 => const [6, 22],
    4 => const [6, 26],
    5 => const [6, 30],
    6 => const [6, 34],
    7 => const [6, 22, 38],
    8 => const [6, 24, 42],
    9 => const [6, 26, 46],
    10 => const [6, 28, 50],
    11 => const [6, 30, 54],
    12 => const [6, 32, 58],
    _ => const [6, 34, 62],
  };

  /// Format info for (EC L, mask 0): BCH(15,5) plus the fixed XOR mask.
  void _drawFormatBits() {
    const data = 0x08; // L (format bits 01) << 3 | mask 0
    var rem = data;
    for (var i = 0; i < 10; i++) {
      rem = (rem << 1) ^ ((rem >> 9) * 0x537);
    }
    final bits = ((data << 10) | rem) ^ 0x5412;
    bool bit(int i) => (bits >> i) & 1 == 1;

    // First copy, around the top-left finder.
    for (var i = 0; i <= 5; i++) {
      _set(i, 8, bit(i));
    }
    _set(7, 8, bit(6));
    _set(8, 8, bit(7));
    _set(8, 7, bit(8));
    for (var i = 9; i <= 14; i++) {
      _set(8, 14 - i, bit(i));
    }
    // Second copy, split bottom-left / top-right.
    for (var i = 0; i <= 7; i++) {
      _set(8, size - 1 - i, bit(i));
    }
    for (var i = 8; i <= 14; i++) {
      _set(size - 15 + i, 8, bit(i));
    }
    _set(size - 8, 8, true); // dark module
  }

  /// Version info blocks (versions ≥ 7): BCH(18,6) with generator 0x1F25.
  void _drawVersionInfo() {
    if (version < 7) return;
    var rem = version;
    for (var i = 0; i < 12; i++) {
      rem = (rem << 1) ^ ((rem >> 11) * 0x1F25);
    }
    final bits = (version << 12) | rem;
    for (var i = 0; i < 18; i++) {
      final dark = (bits >> i) & 1 == 1;
      final long = size - 11 + i % 3;
      final short = i ~/ 3;
      _set(short, long, dark); // top-right block
      _set(long, short, dark); // bottom-left block
    }
  }

  /// Standard zigzag placement: two-module columns right-to-left, alternating
  /// upward/downward, skipping the vertical timing column.
  void _drawCodewords(Uint8List codewords) {
    var bitIndex = 0;
    final totalBits = codewords.length * 8;
    for (var right = size - 1; right >= 1; right -= 2) {
      if (right == 6) right = 5;
      for (var vert = 0; vert < size; vert++) {
        for (var j = 0; j < 2; j++) {
          final col = right - j;
          final upward = ((right + 1) & 2) == 0;
          final row = upward ? size - 1 - vert : vert;
          final idx = row * size + col;
          if (!isFunction[idx] && bitIndex < totalBits) {
            modules[idx] =
                (codewords[bitIndex >> 3] >> (7 - (bitIndex & 7))) & 1 == 1;
            bitIndex++;
          }
          // Remaining modules (the spec's remainder bits) stay light.
        }
      }
    }
  }

  /// Mask 0: invert every non-function module where `(row + col)` is even.
  void _applyMask0() {
    for (var row = 0; row < size; row++) {
      for (var col = 0; col < size; col++) {
        final idx = row * size + col;
        if (!isFunction[idx] && (row + col).isEven) {
          modules[idx] = !modules[idx];
        }
      }
    }
  }
}
