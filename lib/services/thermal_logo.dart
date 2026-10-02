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
/// [maxWidth] is in printer dots. An 80mm head prints 576 of them per line
/// (48 columns x 12 dots), so 512 fills most of the paper and still leaves a
/// margin either side. It was 360 — barely over half the width — which is
/// what made the logo print small next to the store name.
///
/// Upscaling stays off on purpose: a source image narrower than this is
/// stretched into visible blocks once it is reduced to 1-bit black and
/// white. A logo that still prints small needs a larger source file, not a
/// larger number here.
Future<LogoBitmap?> decodeReceiptLogo(String path, {int maxWidth = 512}) async {
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

    // Trim blank rows off the top and bottom. A logo is usually a square
    // canvas with the artwork centred in it, and every empty row prints as
    // blank paper — which is what put a large gap between the logo and the
    // store name. Only vertical padding is trimmed: the image is centred by
    // the printer, so blank columns cost nothing.
    var top = 0;
    while (top < h && _rowIsBlank(rows, wb, top)) {
      top++;
    }
    // Entirely blank: nothing worth printing.
    if (top == h) return null;
    var bottom = h - 1;
    while (bottom > top && _rowIsBlank(rows, wb, bottom)) {
      bottom--;
    }
    if (top == 0 && bottom == h - 1) return LogoBitmap(w, h, rows);
    return LogoBitmap(
      w,
      bottom - top + 1,
      rows.sublist(top * wb, (bottom + 1) * wb),
    );
  } catch (_) {
    return null;
  }
}

/// Whether row [y] of a packed 1-bit bitmap has no black pixels at all.
bool _rowIsBlank(Uint8List rows, int bytesPerRow, int y) {
  final start = y * bytesPerRow;
  for (var i = start; i < start + bytesPerRow; i++) {
    if (rows[i] != 0) return false;
  }
  return true;
}
