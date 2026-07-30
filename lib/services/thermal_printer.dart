import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';
import '../models/transaction_record.dart';

/// Raw ESC/POS thermal printing for Windows (80mm / 3-inch rolls).
///
/// The printer ignores rasterised PDFs, and Out-Printer prints oversized,
/// wrapping text. Sending native ESC/POS commands straight to the spooler as
/// RAW data gives a proper small, full-width, aligned receipt with a bold
/// total and an automatic paper cut.
class ThermalPrinter {
  // 80mm, font A: 48 characters per line.
  static const int width = 48;

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

  /// Build the ESC/POS byte stream for a receipt.
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
  }) {
    final cur = (currencySymbol == '₹') ? 'Rs.' : currencySymbol;
    String money(double v) => '$cur${v.toStringAsFixed(2)}';

    final b = <int>[];
    b.addAll([_esc, 0x40]); // init

    // Header — store name big+bold, centered
    b.addAll([_esc, 0x61, 0x01]); // center
    if (storeName.isNotEmpty) {
      b.addAll([_esc, 0x21, 0x38]); // bold + double h/w
      b.addAll(_t(storeName));
      b.add(_lf);
      b.addAll([_esc, 0x21, 0x00]); // normal
    }
    if (storeAddress.isNotEmpty) {
      b.addAll(_t(storeAddress));
      b.add(_lf);
    }
    if (storePhone.isNotEmpty) {
      b.addAll(_t('Tel: $storePhone'));
      b.add(_lf);
    }
    if (storeGstin.isNotEmpty) {
      b.addAll(_t('GSTIN: $storeGstin'));
      b.add(_lf);
    }
    b.add(_lf); // breathing room under the header
    b.addAll([_esc, 0x61, 0x00]); // left
    b.addAll(_t('-' * width));
    b.add(_lf);

    // Meta
    if (tx.invoiceNumber != null && tx.invoiceNumber!.isNotEmpty) {
      b.addAll(_t('Invoice: ${tx.invoiceNumber}'));
      b.add(_lf);
    }
    final d = tx.createdAt;
    b.addAll(_t(
      'Date: ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}',
    ));
    b.add(_lf);
    if (tx.customerName != null && tx.customerName!.isNotEmpty) {
      b.addAll(_t('Customer: ${tx.customerName}'));
      b.add(_lf);
    }
    b.addAll(_t('-' * width));
    b.add(_lf);

    // Items
    b.addAll([_esc, 0x21, 0x08]); // bold
    b.addAll(_t(_row('ITEM', 'AMOUNT')));
    b.add(_lf);
    b.addAll([_esc, 0x21, 0x00]);
    for (final i in tx.items) {
      b.addAll(_t(i.displayName));
      b.add(_lf);
      b.addAll(_t(_row('  ${i.quantity} x ${money(i.price)}', money(i.total))));
      b.add(_lf);
    }
    b.addAll(_t('-' * width));
    b.add(_lf);

    // Totals
    b.addAll(_t(_row('Subtotal', money(tx.subtotal))));
    b.add(_lf);
    if (tx.discountAmount > 0) {
      b.addAll(_t(_row('Discount', '-${money(tx.discountAmount)}')));
      b.add(_lf);
    }
    if (tx.taxAmount > 0) {
      b.addAll(_t(_row('$taxLabel ($taxRate%)', money(tx.taxAmount))));
      b.add(_lf);
    }
    b.add(_lf); // separate the running totals from the grand total
    b.addAll([_esc, 0x21, 0x18]); // bold + double height
    b.addAll(_t(_row('TOTAL', money(tx.total))));
    b.add(_lf);
    b.addAll([_esc, 0x21, 0x00]);
    b.add(_lf); // clear the double-height line's descenders
    b.addAll(_t(_row('Paid via', tx.paymentMethod.toUpperCase())));
    b.add(_lf);
    b.addAll(_t('-' * width));
    b.add(_lf);

    // Footer
    b.add(_lf);
    if (receiptFooter.isNotEmpty) {
      b.addAll([_esc, 0x61, 0x01]);
      b.addAll(_t(receiptFooter));
      b.add(_lf);
      b.addAll([_esc, 0x61, 0x00]);
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
