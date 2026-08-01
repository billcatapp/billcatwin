import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'thermal_printer.dart';

/// Decodes the store logo image file into a 1-bit bitmap for ESC/POS raster
/// printing (GS v 0). Returns null when the path is empty, the file is
/// missing, or decoding fails — the receipt simply prints without a logo.
///
/// Kept separate from ThermalPrinter so that file stays pure Dart
/// (dart:ui is only available inside a Flutter runtime).
Future<LogoBitmap?> decodeReceiptLogo(String path, {int maxWidth = 360}) async {
  try {
    if (path.isEmpty) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    final codec = await ui.instantiateImageCodec(
      await file.readAsBytes(),
      targetWidth: maxWidth,
      allowUpscaling: false,
    );
    final frame = await codec.getNextFrame();
    final img = frame.image;
    final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return null;
    final w = img.width, h = img.height;
    final wb = (w + 7) ~/ 8;
    final rows = Uint8List(wb * h);
    final px = data.buffer.asUint8List();
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final o = (y * w + x) * 4;
        // Alpha-weighted luminance; transparent pixels stay white.
        final lum = (px[o] * 299 + px[o + 1] * 587 + px[o + 2] * 114) ~/ 1000;
        if (px[o + 3] > 128 && lum < 160) {
          rows[y * wb + (x >> 3)] |= 0x80 >> (x & 7);
        }
      }
    }
    img.dispose();
    return LogoBitmap(w, h, rows);
  } catch (_) {
    return null;
  }
}
