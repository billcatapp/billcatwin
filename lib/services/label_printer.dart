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
  static const double _colGapMm = 2.5;

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
  }) {
    if (labels.isEmpty) return true;
    final webWmm = labelWmm * perRow + _colGapMm * (perRow - 1);
    final currency = _ascii(currencySymbol);
    final buf = StringBuffer();

    for (var start = 0; start < labels.length; start += perRow) {
      final row = labels.sublist(
        start,
        (start + perRow).clamp(0, labels.length),
      );
      buf
        ..write(
          'SIZE ${webWmm.toStringAsFixed(1)} mm,'
          '${labelHmm.toStringAsFixed(1)} mm\r\n',
        )
        ..write('GAP ${rowGapMm.toStringAsFixed(1)} mm,0\r\n')
        ..write('DIRECTION 1\r\n')
        ..write('CLS\r\n');
      for (var col = 0; col < row.length; col++) {
        final label = row[col];
        final cellX = (col * (labelWmm + _colGapMm) * _dpmm).round();
        final cellW = (labelWmm * _dpmm).round();
        final barcodeVal = _tsplSafe(
          label.barcode.isNotEmpty ? label.barcode : label.sku,
        );

        // 12-digit numeric → EAN-13 (95 modules incl. check digit the
        // printer appends); anything else → Code 128 set B.
        final isEan =
            barcodeVal.length == 12 &&
            barcodeVal.codeUnits.every((c) => c >= 0x30 && c <= 0x39);
        final symbology = isEan ? 'EAN13' : '128';
        final barcodeW = isEan
            ? 95 * 2
            : ((barcodeVal.length + 2) * 11 + 13) * 2;
        final barcodeH = (labelHmm * _dpmm * 0.42).round();
        final bx = cellX + ((cellW - barcodeW) / 2).round().clamp(0, cellW);
        buf.write(
          'BARCODE $bx,${2 * _dpmm},"$symbology",$barcodeH,0,0,2,2,"$barcodeVal"\r\n',
        );

        // Product name line, centred (font 2 is 12x20 dots); truncate so it
        // never runs past the cell edge since TSPL doesn't wrap text.
        final maxChars = (cellW / 12).floor().clamp(1, 1000);
        var name = _tsplSafe(label.name);
        if (name.length > maxChars) name = name.substring(0, maxChars);
        final nameW = name.length * 12;
        final nx = cellX + ((cellW - nameW) / 2).round().clamp(0, cellW);
        final nameY = 2 * _dpmm + barcodeH + _dpmm;
        buf.write('TEXT $nx,$nameY,"2",0,1,1,"$name"\r\n');

        // Price line, centred below the name.
        final price = _tsplSafe('$currency${label.price.toStringAsFixed(2)}');
        final priceW = price.length * 12;
        final px = cellX + ((cellW - priceW) / 2).round().clamp(0, cellW);
        final priceY = nameY + 20 + 4;
        buf.write('TEXT $px,$priceY,"2",0,1,1,"$price"\r\n');
      }
      buf.write('PRINT 1\r\n');
    }
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
