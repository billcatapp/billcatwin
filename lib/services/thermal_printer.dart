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

  // Item table columns: ITEM | QTY | RATE | AMT  (18 + 5 + 12 + 13 = 48).
  // RATE is the per-unit price, AMT the line total; both tax-inclusive and
  // printed WITHOUT the currency symbol. "Rs " cost three columns on every
  // row and pushed six-figure amounts onto a second line.
  static const int _nameW = 18;
  static const int _qtyW = 5;
  static const int _rateW = 12;
  static const int _amtW = 13;

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
      // Two feeds: the blank rows inside the logo are trimmed off now, so
      // without this the store name sits hard against the artwork.
      b.add(_lf);
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
    // A blank line between each, so the header reads as separate facts
    // rather than one dense block.
    b.add(_lf);
    for (final l in _wrap(storeAddress, width)) {
      if (l.isNotEmpty) _line(b, l);
    }
    if (storeAddress.trim().isNotEmpty) b.add(_lf);
    if (storePhone.isNotEmpty) {
      _line(b, 'Phone: $storePhone');
      b.add(_lf);
    }
    if (storeGstin.isNotEmpty) {
      _line(b, 'GSTIN: $storeGstin');
      b.add(_lf);
    }
    b.add(_lf);
    b.addAll([_esc, 0x21, 0x08]); // bold
    _line(b, 'TAX INVOICE');
    b.addAll([_esc, 0x21, 0x00]);

    b.addAll([_esc, 0x61, 0x00]); // back to left justification
    _sep(b);

    // ── Bill details: one labelled line each, colons aligned ─────────────
    const labelW = 12;
    void detail(String label, String value) {
      _line(b, '${label.padRight(labelW)}: $value');
      b.add(_lf); // spaced, so each detail reads on its own
    }

    final d = tx.createdAt;
    detail('Bill No', tx.displayInvoice);
    detail(
      'Date',
      '${d.day.toString().padLeft(2, '0')}/'
          '${d.month.toString().padLeft(2, '0')}/${d.year}',
    );
    detail(
      'Time',
      '${d.hour.toString().padLeft(2, '0')}:'
          '${d.minute.toString().padLeft(2, '0')}:'
          '${d.second.toString().padLeft(2, '0')}',
    );
    // Each omitted when unset, so a till with no staff list and a walk-in
    // customer prints the same compact block it always did.
    if (tx.salesperson.isNotEmpty) detail('Salesperson', tx.salesperson);
    if (tx.customerName != null && tx.customerName!.isNotEmpty) {
      detail('Customer', tx.customerName!);
    }
    if (tx.customerPhone != null && tx.customerPhone!.isNotEmpty) {
      detail('Phone', tx.customerPhone!);
    }
    _sep(b);

    // ── Item table: ITEM | QTY | PRICE ───────────────────────────────────
    // Each line is shown TAX-INCLUSIVE (the item's GST share folded into
    // its price) and no separate GST row is printed — display only, the
    // charged totals are untouched. Items without their own recorded rate
    // follow the store's default tax rate — never a blended bill average,
    // which used to smear one taxed item's GST across every line.
    final fallbackRate = double.tryParse(taxRate) ?? 0.0;
    // A line's total already contains its tax, so it IS the inclusive
    // figure. Bills taken before prices became tax-inclusive stored the
    // line before tax, so those still have it added on.
    final inclusivePricing = tx.priceIncludesTax;
    double lineInclusive(TransactionItem i) {
      if (inclusivePricing) return i.total;
      final rate = i.taxPercent > 0 ? i.taxPercent : fallbackRate;
      return i.total * (1 + rate / 100);
    }

    String pct(double rate) {
      if (rate <= 0) return '0%';
      return (rate - rate.roundToDouble()).abs() < 0.05
          ? '${rate.round()}%'
          : '${rate.toStringAsFixed(1)}%';
    }

    // Whether this bill carries GST at all — gates the summary below.
    final hasTax = tx.taxAmount > 0 || tx.items.any((i) => i.taxPercent > 0);
    // ITEM | QTY | RATE | AMT. RATE is what one unit costs, so a line of
    // three reads as 3 x 250 = 750 rather than just 750. Both money columns
    // are tax-inclusive, matching the line totals.

    b.addAll([_esc, 0x21, 0x08]); // bold
    _line(
      b,
      'ITEM'.padRight(_nameW) +
          'QTY'.padLeft(_qtyW) +
          'RATE'.padLeft(_rateW) +
          'AMT'.padLeft(_amtW),
    );
    b.addAll([_esc, 0x21, 0x00]);
    b.add(_lf);
    var inclusiveSubtotal = 0.0;
    for (final i in tx.items) {
      final incl = lineInclusive(i);
      inclusiveSubtotal += incl;
      // Guard the division: a zero quantity would otherwise print infinity.
      final unit = i.quantity > 0 ? incl / i.quantity : incl;
      final nameLines = _wrap(i.displayName, _nameW);
      _line(
        b,
        nameLines.first.padRight(_nameW) +
            '${i.quantity}'.padLeft(_qtyW) +
            unit.toStringAsFixed(2).padLeft(_rateW) +
            incl.toStringAsFixed(2).padLeft(_amtW),
      );
      for (final l in nameLines.skip(1)) {
        _line(b, l);
      }
      b.add(_lf); // gap between items
    }
    _sep(b);

    // ── Totals (lines already tax-inclusive — no separate GST row) ───────
    // Item count and unit count both: three lines of stock can be four
    // pieces, and a customer checking the bag wants the piece count.
    final totalQty = tx.items.fold<int>(0, (s, i) => s + i.quantity);
    _line(b, _row('Total Items', '${tx.items.length}'));
    if (totalQty != tx.items.length) {
      _line(b, _row('Total Qty', '$totalQty'));
    }
    _line(b, _row('Subtotal', money(inclusiveSubtotal)));
    if (tx.discountAmount > 0) {
      _line(b, _row('Discount', '-${money(tx.discountAmount)}'));
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
    b.add(_lf); // model: payment row sits right under the total, no rule

    // ── Payment ──────────────────────────────────────────────────────────
    _line(b, _row('Payment Method', tx.paymentMethod));
    // Hybrid split: show how much was cash vs UPI.
    if (tx.hybridCash > 0.005 || tx.hybridUpi > 0.005) {
      _line(b, _row('  Cash', money(tx.hybridCash)));
      _line(b, _row('  UPI', money(tx.hybridUpi)));
    }
    // Credit sale: show what was paid and what is still owed.
    if (tx.balanceDue > 0.005) {
      _line(b, _row('Paid', money(tx.amountPaid)));
      b.addAll([_esc, 0x21, 0x08]); // bold
      _line(b, _row('BALANCE DUE', money(tx.balanceDue)));
      b.addAll([_esc, 0x21, 0x00]);
    }

    // ── GST summary, one row per rate slab ───────────────────────────────
    // The line prices above are shown tax-inclusive, which hides what was
    // actually charged as GST. This is the breakdown a tax invoice has to
    // carry, split the same way _gstSplitBill splits it everywhere else:
    // each line at its own rate falling back to the store rate, with the
    // bill discount spread proportionally so the taxable base matches what
    // the customer paid.
    //
    // IGST is not a column. It is 0.00 on every intra-state sale, which is
    // all a single shop rings up, and 48 characters is not enough to carry a
    // column of zeroes without clipping the amounts that matter.
    if (hasTax) {
      final subtotal = tx.items.fold<double>(0, (s, i) => s + i.total);
      final discountFactor = subtotal > 0
          ? (subtotal - tx.discountAmount) / subtotal
          : 1.0;
      // rate -> (value paid, tax). Tax is read against the line's FULL
      // value, since a discount does not reduce it; the paid value is the
      // discounted one, which is what the slab's amount has to add up to.
      final byRate = <double, ({double paid, double tax})>{};
      for (final i in tx.items) {
        final rate = i.taxPercent > 0 ? i.taxPercent : fallbackRate;
        if (rate <= 0) continue;
        final prev = byRate[rate] ?? (paid: 0.0, tax: 0.0);
        byRate[rate] = (
          paid: prev.paid + i.total * discountFactor,
          tax: prev.tax + i.total * rate / 100,
        );
      }
      if (byRate.isNotEmpty) {
        _sep(b);
        b.addAll([_esc, 0x21, 0x08]); // bold
        _line(
          b,
          'GST%'.padRight(6) +
              'TAX'.padLeft(11) +
              'CGST'.padLeft(10) +
              'SGST'.padLeft(10) +
              'AMT'.padLeft(11),
        );
        b.addAll([_esc, 0x21, 0x00]);
        final rates = byRate.keys.toList()..sort();
        for (final r in rates) {
          // The slab's value as paid: already tax-inclusive on a current
          // bill, pre-tax on one taken before prices carried their tax.
          final paid = byRate[r]!.paid;
          final tax = byRate[r]!.tax;
          final taxable = inclusivePricing ? paid - tax : paid;
          // Halved for the CGST/SGST split, the way an intra-state invoice
          // states it.
          final half = tax / 2;
          // AMT is the slab's value INCLUDING its tax, so the row reads
          // across as taxable + CGST + SGST = amount, and the amounts down
          // the column add up to the bill.
          _line(
            b,
            pct(r).padRight(6) +
                taxable.toStringAsFixed(2).padLeft(11) +
                half.toStringAsFixed(2).padLeft(10) +
                half.toStringAsFixed(2).padLeft(10) +
                (taxable + tax).toStringAsFixed(2).padLeft(11),
          );
        }
      }
    }

    // ── UPI QR (when the store has a UPI id configured) ──────────────────
    if (storeUpiId.isNotEmpty) {
      // On a split payment only the UPI share is to be scanned — the rest is
      // being handed over in cash — so the code carries that share, not the
      // bill total. hybridUpi is 0 on every other kind of bill.
      final qrAmount = tx.hybridUpi > 0 ? tx.hybridUpi : tx.total;
      final upiUrl =
          'upi://pay?pa=${Uri.encodeComponent(storeUpiId)}'
          '&pn=${Uri.encodeComponent(storeName)}'
          '&am=${qrAmount.toStringAsFixed(2)}&cu=INR'
          '&tn=${Uri.encodeComponent(tx.displayInvoice)}';
      b.addAll([_esc, 0x61, 0x01]); // center
      b.add(_lf);
      b.addAll(_qr(upiUrl));
      b.add(_lf);
      _line(
        b,
        tx.hybridUpi > 0
            ? 'SCAN TO PAY ${qrAmount.toStringAsFixed(2)} VIA UPI'
            : 'SCAN TO PAY VIA UPI',
      );
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

    // Feed well past the tear bar so the whole bill clears the printer and
    // there is blank paper to hold when it is torn off.
    b.addAll([_esc, 0x64, 0x06]); // feed 6 lines
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
