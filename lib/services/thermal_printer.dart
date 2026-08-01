import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';
import '../models/transaction_record.dart';

/// A 1-bit logo bitmap ready for ESC/POS raster printing.
/// [rows] holds (width+7)~/8 bytes per row; bit 7 is the leftmost dot,
/// a 1 bit prints black. Produced by decodeReceiptLogo (thermal_logo.dart).
class LogoBitmap {
  final int width; // dots
  final int height; // dots
  final Uint8List rows;
  const LogoBitmap(this.width, this.height, this.rows);
}

/// Raw ESC/POS thermal printing for Windows (80mm / 3-inch rolls).
///
/// The printer ignores rasterised PDFs, and Out-Printer prints oversized,
/// wrapping text. Sending native ESC/POS commands straight to the spooler as
/// RAW data gives a proper small, full-width, aligned receipt with a bold
/// total and an automatic paper cut.
class ThermalPrinter {
  // 80mm, font A: 48 characters per line.
  static const int width = 48;

  // Item table columns: NAME | QTY | PRICE  (28 + 6 + 14 = 48).
  static const int _nameW = 28;
  static const int _qtyW = 6;
  static const int _priceW = 14;

  static const _esc = 0x1B;
  static const _gs = 0x1D;
  static const _lf = 0x0A;

  static List<int> _t(String s) {
    final out = <int>[];
    for (final r in s.runes) {
      out.add(r >= 0x20 && r <= 0x7E ? r : 0x20); // printable ASCII only
    }
    return out;
  }

  static String _center(String s) {
    if (s.length >= width) return s.substring(0, width);
    return ' ' * ((width - s.length) ~/ 2) + s;
  }

  static String _row(String l, String r) {
    if (l.length + r.length >= width) {
      l = l.substring(0, (width - r.length - 1).clamp(0, l.length));
    }
    return l + ' ' * (width - l.length - r.length) + r;
  }

  /// Greedy word-wrap into lines of at most [w] characters. Words longer
  /// than the column are hard-split.
  static List<String> _wrap(String s, int w) {
    final lines = <String>[];
    var cur = '';
    for (var word in s.split(RegExp(r'\s+')).where((x) => x.isNotEmpty)) {
      while (word.length > w) {
        if (cur.isNotEmpty) {
          lines.add(cur);
          cur = '';
        }
        lines.add(word.substring(0, w));
        word = word.substring(w);
      }
      if (cur.isEmpty) {
        cur = word;
      } else if (cur.length + 1 + word.length <= w) {
        cur = '$cur $word';
      } else {
        lines.add(cur);
        cur = word;
      }
    }
    if (cur.isNotEmpty) lines.add(cur);
    return lines.isEmpty ? [''] : lines;
  }

  static void _line(List<int> b, String s) {
    b.addAll(_t(s));
    b.add(_lf);
  }

  static void _sep(List<int> b) => _line(b, '-' * width);

  /// ESC/POS native QR code (GS ( k), centered by the caller's justification.
  static List<int> _qr(String data) {
    final d = _t(data);
    final len = d.length + 3;
    return [
      _gs, 0x28, 0x6B, 4, 0, 49, 65, 50, 0, // model 2
      _gs, 0x28, 0x6B, 3, 0, 49, 67, 6, // module size 6
      _gs, 0x28, 0x6B, 3, 0, 49, 69, 49, // error correction M
      _gs, 0x28, 0x6B, len & 0xFF, (len >> 8) & 0xFF, 49, 80, 48, ...d,
      _gs, 0x28, 0x6B, 3, 0, 49, 81, 48, // print
    ];
  }

  /// Build the ESC/POS byte stream for a receipt.
  ///
  /// Layout mirrors the standard retail model:
  ///   [logo] / store name / address / phone / GSTIN / date / invoice id
  ///   customer block, ITEM|QTY|PRICE table, totals, big GRAND TOTAL,
  ///   payment method, UPI QR (when configured), footer, cut.
  static List<int> buildReceipt(
    TransactionRecord tx, {
    required String storeName,
    required String storeAddress,
    required String storePhone,
    required String storeGstin,
    required String receiptFooter,
    required String taxLabel,
    required String taxRate,
    required String currencySymbol,
    String storeUpiId = '',
    LogoBitmap? logo,
  }) {
    final isRupee = currencySymbol == '₹';
    String money(double v) =>
        isRupee ? 'Rs ${v.toStringAsFixed(2)}' : '$currencySymbol${v.toStringAsFixed(2)}';

    final b = <int>[];
    b.addAll([_esc, 0x40]); // init

    // ── Header (all centered) ────────────────────────────────────────────
    b.addAll([_esc, 0x61, 0x01]); // center justification

    if (logo != null && logo.width > 0 && logo.height > 0) {
      final wb = (logo.width + 7) ~/ 8;
      b.addAll([
        _gs, 0x76, 0x30, 0x00, // GS v 0: raster bit image, normal size
        wb & 0xFF, (wb >> 8) & 0xFF,
        logo.height & 0xFF, (logo.height >> 8) & 0xFF,
      ]);
      b.addAll(logo.rows);
      b.add(_lf);
    }

    if (storeName.isNotEmpty) {
      b.addAll([_esc, 0x21, 0x38]); // bold + double height/width
      // Double-width halves the columns available on the line.
      for (final l in _wrap(storeName.toUpperCase(), width ~/ 2)) {
        _line(b, l);
      }
      b.addAll([_esc, 0x21, 0x00]); // normal
    }
    for (final l in _wrap(storeAddress, width)) {
      if (l.isNotEmpty) _line(b, l);
    }
    if (storePhone.isNotEmpty) _line(b, 'Phone: $storePhone');
    if (storeGstin.isNotEmpty) _line(b, 'GSTIN: $storeGstin');
    final d = tx.createdAt;
    _line(
      b,
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}',
    );
    if (tx.invoiceNumber != null && tx.invoiceNumber!.isNotEmpty) {
      _line(b, 'INVOICE ID: ${tx.invoiceNumber}');
    }

    b.addAll([_esc, 0x61, 0x00]); // back to left justification
    _sep(b);

    // ── Customer block ───────────────────────────────────────────────────
    final hasCustomer =
        (tx.customerName != null && tx.customerName!.isNotEmpty) ||
        (tx.customerPhone != null && tx.customerPhone!.isNotEmpty);
    if (hasCustomer) {
      if (tx.customerName != null && tx.customerName!.isNotEmpty) {
        _line(b, _center('Customer: ${tx.customerName}'));
      }
      if (tx.customerPhone != null && tx.customerPhone!.isNotEmpty) {
        _line(b, _center('Phone: ${tx.customerPhone}'));
      }
      _sep(b);
    }

    // ── Item table: ITEM | QTY | PRICE ───────────────────────────────────
    b.addAll([_esc, 0x21, 0x08]); // bold
    _line(
      b,
      'ITEM'.padRight(_nameW) +
          'QTY'.padLeft(4).padRight(_qtyW) +
          'PRICE'.padLeft(_priceW),
    );
    b.addAll([_esc, 0x21, 0x00]);
    b.add(_lf);
    for (final i in tx.items) {
      final nameLines = _wrap(i.displayName, _nameW);
      _line(
        b,
        nameLines.first.padRight(_nameW) +
            '${i.quantity}'.padLeft(4).padRight(_qtyW) +
            money(i.total).padLeft(_priceW),
      );
      for (final l in nameLines.skip(1)) {
        _line(b, l);
      }
      b.add(_lf); // gap between items
    }
    _sep(b);

    // ── Totals ───────────────────────────────────────────────────────────
    _line(b, _row('Subtotal', money(tx.subtotal)));
    if (tx.discountAmount > 0) {
      _line(b, _row('Discount', '-${money(tx.discountAmount)}'));
    }
    if (tx.taxAmount > 0) {
      final label = taxRate.isNotEmpty ? '$taxLabel ($taxRate%)' : taxLabel;
      _line(b, _row(label, money(tx.taxAmount)));
    }
    _sep(b);

    // ── Grand total — label bold, value big ──────────────────────────────
    const gtLabel = 'GRAND TOTAL';
    final gtValue = money(tx.total);
    if (gtLabel.length + gtValue.length * 2 < width) {
      // Mixed sizes on one line: double-width chars occupy two columns.
      b.addAll([_esc, 0x21, 0x08]); // bold
      b.addAll(_t(gtLabel));
      b.addAll(_t(' ' * (width - gtLabel.length - gtValue.length * 2)));
      b.addAll([_esc, 0x21, 0x38]); // bold + double height/width
      b.addAll(_t(gtValue));
      b.add(_lf);
      b.addAll([_esc, 0x21, 0x00]);
    } else {
      b.addAll([_esc, 0x21, 0x18]); // bold + double height
      _line(b, _row(gtLabel, gtValue));
      b.addAll([_esc, 0x21, 0x00]);
    }
    _sep(b);

    // ── Payment ──────────────────────────────────────────────────────────
    _line(b, _row('Payment Method', tx.paymentMethod));
    _sep(b);

    // ── UPI QR (when the store has a UPI id configured) ──────────────────
    if (storeUpiId.isNotEmpty) {
      final upiUrl =
          'upi://pay?pa=${Uri.encodeComponent(storeUpiId)}'
          '&pn=${Uri.encodeComponent(storeName)}'
          '&am=${tx.total.toStringAsFixed(2)}&cu=INR'
          '${tx.invoiceNumber != null && tx.invoiceNumber!.isNotEmpty ? '&tn=${Uri.encodeComponent(tx.invoiceNumber!)}' : ''}';
      b.addAll([_esc, 0x61, 0x01]); // center
      b.add(_lf);
      b.addAll(_qr(upiUrl));
      b.add(_lf);
      _line(b, 'SCAN TO PAY VIA UPI');
      b.addAll([_esc, 0x61, 0x00]);
    }

    // ── Footer ───────────────────────────────────────────────────────────
    if (receiptFooter.isNotEmpty) {
      b.add(_lf);
      for (final rawLine in receiptFooter.split('\n')) {
        for (final l in _wrap(rawLine, width)) {
          if (l.isNotEmpty) _line(b, _center(l));
        }
      }
    }

    b.addAll([_esc, 0x64, 0x03]); // feed 3 lines
    b.addAll([_gs, 0x56, 0x42, 0x00]); // feed + partial cut
    return b;
  }

  /// Send raw bytes to a Windows printer through the spooler (datatype RAW).
  static bool rawPrint(String printerName, List<int> bytes) {
    final pName = printerName.toNativeUtf16();
    final phPrinter = calloc<HANDLE>();
    final docName = 'BillCat Receipt'.toNativeUtf16();
    final dataType = 'RAW'.toNativeUtf16();
    final docInfo = calloc<DOC_INFO_1>();
    final buffer = calloc<Uint8>(bytes.length);
    final written = calloc<DWORD>();
    try {
      if (OpenPrinter(pName, phPrinter, nullptr) == 0) return false;
      final hPrinter = phPrinter.value;
      docInfo.ref.pDocName = docName;
      docInfo.ref.pOutputFile = nullptr;
      docInfo.ref.pDatatype = dataType;
      if (StartDocPrinter(hPrinter, 1, docInfo.cast()) == 0) {
        ClosePrinter(hPrinter);
        return false;
      }
      StartPagePrinter(hPrinter);
      for (var i = 0; i < bytes.length; i++) {
        buffer[i] = bytes[i] & 0xFF;
      }
      final ok = WritePrinter(hPrinter, buffer.cast(), bytes.length, written);
      EndPagePrinter(hPrinter);
      EndDocPrinter(hPrinter);
      ClosePrinter(hPrinter);
      return ok != 0;
    } catch (_) {
      return false;
    } finally {
      calloc.free(pName);
      calloc.free(phPrinter);
      calloc.free(docName);
      calloc.free(dataType);
      calloc.free(docInfo);
      calloc.free(buffer);
      calloc.free(written);
    }
  }
}
