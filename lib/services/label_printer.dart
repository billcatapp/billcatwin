import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Sends raw TSPL commands straight to a Windows label printer via the
/// spooler (RAW datatype), bypassing the driver's page/stock configuration.
/// This lets the app own label width/height/gap/columns so end users never
/// have to configure printer driver stock settings.
class LabelPrinter {
  // ── winspool.drv bindings ──────────────────────────────────────────────────

  static final DynamicLibrary _winspool = DynamicLibrary.open('winspool.drv');

  static final int Function(Pointer<Utf8>, Pointer<IntPtr>, Pointer<Void>)
  _openPrinter = _winspool
      .lookupFunction<
        Int32 Function(Pointer<Utf8>, Pointer<IntPtr>, Pointer<Void>),
        int Function(Pointer<Utf8>, Pointer<IntPtr>, Pointer<Void>)
      >('OpenPrinterA');

  static final int Function(int) _closePrinter = _winspool
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        'ClosePrinter',
      );

  static final int Function(int, int, Pointer<_DocInfo1>) _startDocPrinter =
      _winspool.lookupFunction<
        Uint32 Function(IntPtr, Uint32, Pointer<_DocInfo1>),
        int Function(int, int, Pointer<_DocInfo1>)
      >('StartDocPrinterA');

  static final int Function(int) _endDocPrinter = _winspool
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        'EndDocPrinter',
      );

  static final int Function(int) _startPagePrinter = _winspool
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        'StartPagePrinter',
      );

  static final int Function(int) _endPagePrinter = _winspool
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        'EndPagePrinter',
      );

  static final int Function(int, Pointer<Uint8>, int, Pointer<Uint32>)
  _writePrinter = _winspool
      .lookupFunction<
        Int32 Function(IntPtr, Pointer<Uint8>, Uint32, Pointer<Uint32>),
        int Function(int, Pointer<Uint8>, int, Pointer<Uint32>)
      >('WritePrinter');

  /// Writes [data] to [printerName] as a RAW spool job. Returns true on success.
  static bool sendRaw(String printerName, String data) {
    final namePtr = printerName.toNativeUtf8();
    final handlePtr = calloc<IntPtr>();
    try {
      if (_openPrinter(namePtr, handlePtr, nullptr) == 0) return false;
      final hPrinter = handlePtr.value;
      final docInfo = calloc<_DocInfo1>();
      final docName = 'BillCat Labels'.toNativeUtf8();
      final dataType = 'RAW'.toNativeUtf8();
      docInfo.ref.pDocName = docName;
      docInfo.ref.pOutputFile = nullptr.cast();
      docInfo.ref.pDatatype = dataType;
      var ok = false;
      try {
        if (_startDocPrinter(hPrinter, 1, docInfo) != 0) {
          if (_startPagePrinter(hPrinter) != 0) {
            final bytes = data.codeUnits;
            final buf = calloc<Uint8>(bytes.length);
            for (var i = 0; i < bytes.length; i++) {
              buf[i] = bytes[i] & 0xFF;
            }
            final written = calloc<Uint32>();
            ok = _writePrinter(hPrinter, buf, bytes.length, written) != 0;
            calloc.free(written);
            calloc.free(buf);
            _endPagePrinter(hPrinter);
          }
          _endDocPrinter(hPrinter);
        }
      } finally {
        calloc.free(docName);
        calloc.free(dataType);
        calloc.free(docInfo);
        _closePrinter(hPrinter);
      }
      return ok;
    } finally {
      calloc.free(namePtr);
      calloc.free(handlePtr);
    }
  }

  // ── TSPL label composition ─────────────────────────────────────────────────

  /// Dots per millimetre for a 203 dpi print head.
  static const int _dpmm = 8;

  /// Horizontal gap between side-by-side labels on the web, in mm.
  static const double _colGapMm = 0;

  /// Print width of a 4-inch, 203 dpi head (832 dots), in mm. Desktop label
  /// printers hold the roll centred under the head, so a row of stickers
  /// narrower than this sits in the middle of it.
  static const double _headWmm = 104;

  /// The page set-up width: the whole head, so every printer (one that obeys
  /// SIZE and one that keeps its own) puts x = 0 at the same place.
  static double _pageWmm(double webWmm) =>
      webWmm > _headWmm ? webWmm : _headWmm;

  /// How far in from the head's left edge the centred row of stickers
  /// starts, in dots.
  static int _leftDots(double webWmm) =>
      ((_pageWmm(webWmm) - webWmm) / 2 * _dpmm).round();

  /// Prints [labels] (one entry per physical sticker, in print order) on a
  /// TSPL label printer. Labels are laid out [perRow] across; the printer's
  /// gap sensor keeps every row aligned to a label edge.
  static bool printBarcodeLabels({
    required String printerName,
    required List<LabelData> labels,
    required double labelWmm,
    required double labelHmm,
    required int perRow,
    double rowGapMm = 3.0,
    String currencySymbol = '',
    String storeName = '',
    // A 2D QR code (TSPL QRCODE) holding the same value instead of the 1D
    // bars, when the shop chose 2D under Print Barcodes' gear.
    bool qr = false,
    // Moves the whole print down (positive) or up (negative) on the
    // sticker, in mm, for a printer that places it off the label.
    double shiftMm = 0,
  }) {
    if (labels.isEmpty) return true;
    final webWmm = labelWmm * perRow + _colGapMm * (perRow - 1);
    final currency = _ascii(currencySymbol);
    // Printed across the top of every sticker, so a label on a shelf says
    // whose shop it came from. Empty keeps the old layout untouched.
    final store = _tsplSafe(storeName.trim());
    final snbc = _needsSnbcFix(printerName, labelHmm);
    final job = StringBuffer();
    var allSent = true;

    for (var start = 0; start < labels.length; start += perRow) {
      final row = labels.sublist(
        start,
        (start + perRow).clamp(0, labels.length),
      );
      final lastRow = start + perRow >= labels.length;
      // Other printers take every row in one job. An SNBC with stickers
      // taller than it keeps gets one job per row instead (see [_isSnbc]).
      final buf = snbc ? StringBuffer() : job;
      buf.write(
        _setup(
          _pageWmm(webWmm),
          labelHmm,
          rowGapMm,
          snbc ? _snbcShiftMm(labelHmm) : shiftMm,
        ),
      );
      if (snbc) {
        buf.write('SET TEAR ${lastRow ? 'ON' : 'OFF'}\r\n');
      } else if (_isSnbc(printerName)) {
        // Short stickers on an SNBC: plain tear-off, in case a taller
        // print left it switched off.
        buf.write('SET TEAR ON\r\n');
      }
      buf.write('CLS\r\n');
      for (var col = 0; col < row.length; col++) {
        final label = row[col];
        // Centred on the head, so the print sits in the middle of the roll.
        final cellX =
            _leftDots(webWmm) +
            (col * (labelWmm + _colGapMm) * _dpmm).round();
        final cellW = (labelWmm * _dpmm).round();
        final barcodeVal = _tsplSafe(
          label.barcode.isNotEmpty ? label.barcode : label.sku,
        );

        if (qr) {
          _writeQrLabel(
            buf,
            cellX: cellX,
            cellW: cellW,
            cellH: (labelHmm * _dpmm).round(),
            value: barcodeVal,
            store: store,
            name: _tsplSafe(label.name),
            // No paise on a whole-rupee price, as on the shop's design.
            price: _tsplSafe(
              '$currency${label.price == label.price.roundToDouble() ? label.price.toStringAsFixed(0) : label.price.toStringAsFixed(2)}',
            ),
          );
          continue;
        }

        // 12-digit numeric → EAN-13 (95 modules incl. check digit the
        // printer appends); anything else → Code 128 set B.
        final isEan =
            barcodeVal.length == 12 &&
            barcodeVal.codeUnits.every((c) => c >= 0x30 && c <= 0x39);
        final symbology = isEan ? 'EAN13' : '128';
        final barcodeW = isEan
            ? 95 * 2
            : ((barcodeVal.length + 2) * 11 + 13) * 2;
        final barcodeH = (labelHmm * _dpmm * 0.38).round();
        final bx = cellX + ((cellW - barcodeW) / 2).round().clamp(0, cellW);
        // With a store name the barcode drops just below it (font 2 is 20
        // dots tall); without one it keeps its original top margin, so an
        // existing label roll prints exactly as it always did.
        final barcodeY = store.isEmpty ? 2 * _dpmm : 2 + 20 + 4;
        buf.write(
          'BARCODE $bx,$barcodeY,"$symbology",$barcodeH,0,0,2,2,"$barcodeVal"\r\n',
        );

        // Split "Product Name (Variant)" so the variant prints on its own line
        // below the product name instead of being truncated off the edge.
        var mainName = _tsplSafe(label.name);
        String? variant;
        final vm = RegExp(r'^(.*)\s*\((.+)\)\s*$').firstMatch(mainName);
        if (vm != null) {
          mainName = vm.group(1)!.trim();
          variant = vm.group(2)!.trim();
        }

        // Centred text helpers. Font 2 = 12x20 dots, font 1 = 8x12 dots.
        // TSPL doesn't wrap, so truncate each line to the cell width.
        void writeCentred(
          String text,
          int y,
          String font,
          int charW, {
          bool bold = false,
        }) {
          final maxChars = (cellW / charW).floor().clamp(1, 1000);
          var t = text;
          if (t.length > maxChars) t = t.substring(0, maxChars);
          final w = t.length * charW;
          final x = cellX + ((cellW - w) / 2).round().clamp(0, cellW);
          buf.write('TEXT $x,$y,"$font",0,1,1,"$t"\r\n');
          // TSPL has no bold attribute. Overprinting the same text one dot to
          // the right thickens every stroke without changing the character
          // size, so nothing below has to move.
          if (bold) buf.write('TEXT ${x + 1},$y,"$font",0,1,1,"$t"\r\n');
        }

        // TSPL positions every element absolutely, so the store name can be
        // emitted here even though it prints above the barcode.
        // Font 2 (12x20) rather than font 1, overprinted for weight, so the
        // shop name reads as the heading of the sticker.
        if (store.isNotEmpty) writeCentred(store, 2, '2', 12, bold: true);

        // Font 2 is 20 dots tall, font 1 is 12 dots tall; add generous gaps
        // between the barcode, name, variant and price so they don't crowd.
        var y = barcodeY + barcodeH + 12;
        writeCentred(mainName, y, '2', 12); // product name
        y += 20 + 10;
        if (variant != null && variant.isNotEmpty) {
          writeCentred(variant, y, '1', 8); // variant, smaller font
          y += 12 + 10;
        }
        writeCentred(
          _tsplSafe('$currency${label.price.toStringAsFixed(2)}'),
          y,
          '2',
          12,
        ); // price
      }
      buf.write('PRINT 1\r\n');
      if (snbc && !sendRaw(printerName, buf.toString())) allSent = false;
    }
    return snbc ? allSent : sendRaw(printerName, job.toString());
  }

  /// SNBC printers (seen on a TVSE LP46 Dlite with the BPLE driver) keep
  /// their own label length and ignore TSPL SIZE. Within one job they feed
  /// every row after the first about 10 mm off its sticker, and between
  /// jobs the tear-off advance skips a whole sticker. So each row goes as
  /// its own job, tear-off stays off until the last row, and the print is
  /// moved up by [_snbcShiftMm], measured on that printer.
  static bool _isSnbc(String printerName) {
    final n = printerName.toLowerCase();
    return n.contains('snbc') || n.contains('bple');
  }

  /// The label length SNBC printers keep for themselves (1 inch), in mm.
  /// Stickers no taller than this print right in one ordinary job.
  static const double _snbcKeptLenMm = 25.4;

  /// Whether a print needs the SNBC workaround: an SNBC printer and a
  /// sticker taller than the length it keeps.
  static bool _needsSnbcFix(String printerName, double labelHmm) =>
      _isSnbc(printerName) && labelHmm > _snbcKeptLenMm;

  /// Vertical correction for SNBC printers, in mm (negative = up). Measured
  /// as 12.5 mm on 35 mm stickers; it grows with how much taller the sticker
  /// is than the 1 inch the printer keeps.
  static double _snbcShiftMm(double labelHmm) => -(labelHmm - 22.5);

  /// One 2D sticker, in the shop's design: the business name large across
  /// the top; below it, product name, variant and a big price on the left
  /// and the QR code on the right. Each line takes the largest built-in
  /// printer font (and size multiplier) that fits its space, so a short name
  /// prints big and a long one still fits.
  static void _writeQrLabel(
    StringBuffer buf, {
    required int cellX,
    required int cellW,
    required int cellH,
    required String value,
    required String store,
    required String name,
    required String price,
  }) {
    const margin = 2 * _dpmm;
    // Built-in TSPL fonts with a size multiplier, largest first:
    // (font, multiplier, character width, height) in dots at 203 dpi.
    // Font 5 is left out: it has no lower-case letters.
    const sizes = <(String, int, int, int)>[
      ('3', 2, 32, 48),
      ('2', 2, 24, 40),
      ('4', 1, 24, 32),
      ('3', 1, 16, 24),
      ('2', 1, 12, 20),
      ('1', 1, 8, 12),
    ];
    (String, int, int, int) fitting(String t, int width, {int maxH = 999}) {
      for (final s in sizes) {
        if (t.length * s.$3 <= width && s.$4 <= maxH) return s;
      }
      return sizes.last;
    }

    String clip(String t, int width, int charW) {
      final max = (width / charW).floor().clamp(1, 1000);
      return t.length > max ? t.substring(0, max) : t;
    }

    // Writes [t] centred in [x]..[x]+[width] at [y]; bold overprints it one
    // dot to the right (TSPL has no bold).
    int line(String t, int x, int width, int y, {int maxH = 999, bool bold = true}) {
      final s = fitting(t, width, maxH: maxH);
      final text = clip(t, width, s.$3);
      final w = text.length * s.$3;
      final tx = x + ((width - w) / 2).round().clamp(0, width);
      buf.write('TEXT $tx,$y,"${s.$1}",0,${s.$2},${s.$2},"$text"\r\n');
      if (bold) {
        buf.write('TEXT ${tx + 1},$y,"${s.$1}",0,${s.$2},${s.$2},"$text"\r\n');
      }
      return s.$4;
    }

    final innerW = cellW - 2 * margin;
    var top = margin;
    // ── Business name, across the top ──
    if (store.isNotEmpty) {
      top += line(store, cellX + margin, innerW, top, maxH: 40) + 6;
    }

    // ── QR code on the right ──
    // Modules across at error level M, byte mode (the worst case): version
    // 1 holds 14 characters, 2 holds 26, 3 holds 42.
    final modules = value.length <= 14
        ? 21
        : value.length <= 26
        ? 25
        : 29;
    final room = cellH - margin - top;
    final widthCap = (innerW * 0.42).round();
    final maxSide = room < widthCap ? room : widthCap;
    final cell = (maxSide ~/ modules).clamp(2, 10);
    final side = modules * cell;
    final qx = cellX + cellW - margin - side;
    final qy = top + ((room - side) / 2).round();
    buf.write('QRCODE $qx,$qy,M,$cell,A,0,"$value"\r\n');

    // ── Name, variant and price on the left ──
    var mainName = name;
    String? variant;
    final vm = RegExp(r'^(.*)\s*\((.+)\)\s*$').firstMatch(mainName);
    if (vm != null) {
      mainName = vm.group(1)!.trim();
      variant = vm.group(2)!.trim();
    }
    final lx = cellX + margin;
    final lw = qx - 3 * _dpmm - lx;
    final nameS = fitting(mainName, lw, maxH: 24);
    final variantS = variant == null || variant.isEmpty
        ? null
        : fitting(variant, lw, maxH: 24);
    final priceS = fitting(price, lw, maxH: 48);
    const gap = 6;
    final blockH =
        nameS.$4 + (variantS == null ? 0 : gap + variantS.$4) + gap * 2 +
        priceS.$4;
    // Centred against the QR code, never above the space under the name.
    var y = qy + ((side - blockH) / 2).round();
    if (y < top) y = top;
    y += line(mainName, lx, lw, y, maxH: 24) + gap;
    if (variant != null && variant.isNotEmpty) {
      y += line(variant, lx, lw, y, maxH: 24) + gap;
    }
    line(price, lx, lw, y + gap, maxH: 48);
  }

  /// Page set-up sent before every row of labels: the sticker size and gap
  /// exactly as the shop set them, the print origin at the label's corner,
  /// and the vertical position. The SHIFT is always sent, so a stored offset
  /// from an earlier roll or setting cannot push the print off the sticker.
  ///
  /// Sizes go in whole millimetres: printers that only emulate TSPL (SNBC,
  /// among others) reject a decimal like "35.0 mm", silently drop the SIZE
  /// line and print on their stored default label — commonly 4 x 1 inch —
  /// cutting every taller sticker off at about 25 mm.
  static String _setup(
    double webWmm,
    double labelHmm,
    double gapMm,
    double shiftMm,
  ) =>
      // A space after each comma, exactly as the TSPL manual writes them,
      // for emulations (SNBC) that parse the line strictly.
      'SIZE ${webWmm.round()} mm, ${labelHmm.round()} mm\r\n'
      'GAP ${gapMm.round()} mm, 0 mm\r\n'
      'DIRECTION 1\r\n'
      'REFERENCE 0,0\r\n'
      'SHIFT ${(shiftMm * _dpmm).round()}\r\n';

  /// Has a TSPL label printer measure the loaded roll again, told the label
  /// height and gap to look for (GAPDETECT with lengths) rather than left to
  /// guess: it feeds a few labels, finds the real label edges, and
  /// remembers them. Needed when a roll of a different size is loaded: a
  /// printer still set for the old label prints only that much of each
  /// sticker, off its edge. Returns true when the commands went.
  static bool calibrate(
    String printerName, {
    required double labelWmm,
    required double labelHmm,
    required int perRow,
    double gapMm = 3.0,
  }) {
    final webWmm = labelWmm * perRow + _colGapMm * (perRow - 1);
    // Whole millimetres, for the reason given on [_setup].
    return sendRaw(
      printerName,
      'SIZE ${webWmm.round()} mm,${labelHmm.round()} mm\r\n'
      'GAP ${gapMm.round()} mm,0 mm\r\n'
      'GAPDETECT ${(labelHmm * _dpmm).round()},${(gapMm * _dpmm).round()}\r\n',
    );
  }

  /// One row of test stickers: a box drawn 1 mm inside every edge of each
  /// sticker, with TOP and BOTTOM written against those edges and the size
  /// in the middle. Shows exactly where the printer puts the print, so the
  /// position can be corrected before real labels are wasted.
  static bool printTestLabel(
    String printerName, {
    required double labelWmm,
    required double labelHmm,
    required int perRow,
    double gapMm = 3.0,
    double shiftMm = 0,
  }) {
    final webWmm = labelWmm * perRow + _colGapMm * (perRow - 1);
    final w = (labelWmm * _dpmm).round();
    final h = (labelHmm * _dpmm).round();
    const m = 1 * _dpmm;
    final buf = StringBuffer()
      ..write(
        _setup(
          _pageWmm(webWmm),
          labelHmm,
          gapMm,
          _needsSnbcFix(printerName, labelHmm)
              ? _snbcShiftMm(labelHmm)
              : shiftMm,
        ),
      )
      ..write('CLS\r\n');
    for (var col = 0; col < perRow; col++) {
      final x =
          _leftDots(webWmm) + (col * (labelWmm + _colGapMm) * _dpmm).round();
      final size =
          '${labelWmm.toStringAsFixed(0)} x ${labelHmm.toStringAsFixed(0)} mm';
      buf
        ..write('BOX ${x + m},$m,${x + w - m},${h - m},3\r\n')
        ..write('TEXT ${x + (w - 3 * 12) ~/ 2},${m + 6},"2",0,1,1,"TOP"\r\n')
        ..write(
          'TEXT ${x + (w - size.length * 12) ~/ 2},${(h - 20) ~/ 2},'
          '"2",0,1,1,"$size"\r\n',
        )
        ..write(
          'TEXT ${x + (w - 6 * 12) ~/ 2},${h - m - 26},"2",0,1,1,"BOTTOM"\r\n',
        );
    }
    buf.write('PRINT 1\r\n');
    return sendRaw(printerName, buf.toString());
  }

  /// Whether [printerName] looks like a TSPL-compatible (TSC-engine) label
  /// printer. Zebra (ZPL), Godex (EZPL), Dymo/Brother and office printers
  /// speak different languages, so they take the standard driver path.
  static bool isTsplCompatible(String printerName) {
    final n = printerName.toLowerCase();
    const tsplHints = [
      'tsc',
      'tt0',
      'te2',
      'ttp',
      'tdp',
      'ttc',
      'bar code printer',
      'barcode printer',
      'xprinter',
      'idprt',
      'hprt',
      'gainscha',
      'gprinter',
      'rongta',
      'tvs',
      'snbc',
      'lp46',
      'lp 46',
    ];
    const nonTsplHints = [
      'zebra',
      'zdesigner',
      'godex',
      'dymo',
      'brother',
      'citizen',
      'sato',
      'honeywell',
      'intermec',
      'datamax',
      'argox',
      'hp ',
      'canon',
      'epson',
      'microsoft',
      'onenote',
      'fax',
      'pdf',
    ];
    if (nonTsplHints.any(n.contains)) return false;
    return tsplHints.any(n.contains);
  }

  /// TSPL built-in fonts are ASCII-only; map common currency symbols.
  static String _ascii(String s) {
    switch (s) {
      case '₹':
        return 'Rs.';
      case '€':
        return 'EUR ';
      case '£':
        return 'GBP ';
      default:
        return s.codeUnits.every((c) => c >= 32 && c < 127) ? s : '';
    }
  }

  /// Strips characters that would break a quoted TSPL parameter.
  static String _tsplSafe(String s) => s
      .replaceAll('"', '')
      .replaceAll('\\', '')
      .replaceAll(RegExp(r'[\r\n]'), ' ');
}

class LabelData {
  final String name;
  final String sku;
  final double price;

  /// Value encoded in the barcode; falls back to [sku] when empty.
  final String barcode;

  const LabelData({
    required this.name,
    required this.sku,
    required this.price,
    this.barcode = '',
  });
}

final class _DocInfo1 extends Struct {
  external Pointer<Utf8> pDocName;
  external Pointer<Utf8> pOutputFile;
  external Pointer<Utf8> pDatatype;
}
