import 'dart:io';
import 'dart:typed_data';

/// PNG uni de [w] × [h] pixels, fabriqué à la main (pour les tests).
Uint8List solidPng(int w, int h, {int r = 200, int g = 60, int b = 60}) {
  final raw = BytesBuilder();
  for (var y = 0; y < h; y++) {
    raw.addByte(0); // filtre « aucun »
    for (var x = 0; x < w; x++) {
      raw.add([r, g, b]);
    }
  }
  final out = BytesBuilder()
    ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

  void chunk(String type, List<int> data) {
    final typeBytes = type.codeUnits;
    out.add(_u32(data.length));
    out.add(typeBytes);
    out.add(data);
    out.add(_u32(_crc32([...typeBytes, ...data])));
  }

  chunk('IHDR', [..._u32(w), ..._u32(h), 8, 2, 0, 0, 0]);
  chunk('IDAT', zlib.encode(raw.toBytes()));
  chunk('IEND', const []);
  return out.toBytes();
}

List<int> _u32(int v) => [
  (v >> 24) & 255,
  (v >> 16) & 255,
  (v >> 8) & 255,
  v & 255,
];

final List<int> _table = () {
  return List<int>.generate(256, (n) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    return c;
  });
}();

int _crc32(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c = _table[(c ^ b) & 255] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}
