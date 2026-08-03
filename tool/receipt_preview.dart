// Standalone check for the redesigned ESC/POS receipt.
// Usage:  dart run tool/receipt_preview.dart [--print]
//   default: decode the byte stream and show a 48-column text preview
//   --print: also send the raw bytes to the POS80 printer
import 'dart:io';
import 'dart:typed_data';
import 'package:billcat/models/transaction_record.dart';
import 'package:billcat/services/thermal_printer.dart';

/// Synthetic sample logo (rounded black box with two white stripes, like the
/// model mockup) — exercises the ESC/POS raster path without needing
/// dart:ui. In the app the real logo comes from Settings via
/// decodeReceiptLogo.
LogoBitmap sampleLogo() {
  const w = 160, h = 64, r = 12;
  final wb = (w + 7) ~/ 8;
  final rows = Uint8List(wb * h);
  bool outsideCorner(int x, int y, int cx, int cy) {
    final dx = x - cx, dy = y - cy;
    return dx * dx + dy * dy > r * r;
  }

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var black = true;
      if (x < r && y < r && outsideCorner(x, y, r, r)) black = false;
      if (x >= w - r && y < r && outsideCorner(x, y, w - r - 1, r)) {
        black = false;
      }
      if (x < r && y >= h - r && outsideCorner(x, y, r, h - r - 1)) {
        black = false;
      }
      if (x >= w - r &&
          y >= h - r &&
          outsideCorner(x, y, w - r - 1, h - r - 1)) {
        black = false;
      }
      // Two white stripes.
      if (y >= 20 && y <= 26 && x >= 24 && x <= w - 24) black = false;
      if (y >= 38 && y <= 44 && x >= 24 && x <= w - 24) black = false;
      if (black) rows[y * wb + (x >> 3)] |= 0x80 >> (x & 7);
    }
  }
  return LogoBitmap(w, h, rows);
}

// Same format as LocalDbService.generateInvoiceId (which needs sqflite).
String LocalDbService_generateInvoiceIdStub() {
  final now = DateTime.now();
  final prefix = 'INV${now.year % 100}${now.month.toString().padLeft(2, '0')}';
  final suffix = now.millisecondsSinceEpoch.toString().substring(7);
  return '$prefix$suffix';
}

void main(List<String> args) {
  final tx = TransactionRecord(
    id: 'test',
    invoiceNumber: LocalDbService_generateInvoiceIdStub(),
    customerName: 'fouzi',
    customerPhone: '9659394812',
    items: const [
      TransactionItem(
        productId: '1',
        productName: 'BOYS ETHNIC SET (NB - 1Y)',
        price: 1070.00,
        quantity: 1,
      ),
    ],
    subtotal: 1070.00,
    discountAmount: 107.00,
    taxAmount: 48.15,
    total: 1011.15,
    paymentMethod: 'cash',
    createdAt: DateTime.now(),
  );

  final bytes = ThermalPrinter.buildReceipt(
    tx,
    storeName: 'R3 Kids Boutique',
    storeAddress: 'C-17, 3rd Cross, Thillai Nagar, Trichy - 620017',
    storePhone: '+91 98006 46123, +91 63822 86970',
    storeGstin: '',
    receiptFooter: 'Thank you for your purchase!',
    taxLabel: 'GST',
    taxRate: '0',
    currencySymbol: '₹',
    storeUpiId: 'r3kids@upi',
    logo: sampleLogo(),
  );

  stdout.writeln(_decode(bytes));

  if (args.contains('--print')) {
    final ok = ThermalPrinter.rawPrint('POS80', bytes);
    stdout.writeln(ok ? 'SENT TO PRINTER' : 'PRINT FAILED');
  }
}

/// Minimal ESC/POS decoder: renders text + markers for QR/logo/cut so the
/// column layout can be eyeballed. Size codes shown as <<...>> for big text.
String _decode(List<int> b) {
  final out = StringBuffer();
  var i = 0;
  var big = false;
  out.writeln('=' * 48);
  while (i < b.length) {
    final c = b[i];
    if (c == 0x1B) {
      final n = b[i + 1];
      if (n == 0x40) {
        i += 2; // init
      } else if (n == 0x61 || n == 0x64) {
        if (n == 0x64) out.writeln('[feed ${b[i + 2]}]');
        i += 3; // justify / feed
      } else if (n == 0x21) {
        big = (b[i + 2] & 0x20) != 0;
        i += 3;
      } else {
        i += 2;
      }
    } else if (c == 0x1D) {
      final n = b[i + 1];
      if (n == 0x56) {
        out.writeln('[CUT]');
        i += 4;
      } else if (n == 0x28) {
        // GS ( k pL pH ... — skip payload, mark QR store/print fns
        final pL = b[i + 3], pH = b[i + 4];
        final fn = b[i + 6];
        if (fn == 81) out.writeln('        [ QR CODE PRINTS HERE ]');
        i += 5 + pL + pH * 256;
      } else if (n == 0x76) {
        // GS v 0 m xL xH yL yH data
        final xBytes = b[i + 4] + b[i + 5] * 256;
        final y = b[i + 6] + b[i + 7] * 256;
        out.writeln('[LOGO ${xBytes * 8}x$y dots]');
        i += 8 + xBytes * y;
      } else {
        i += 2;
      }
    } else if (c == 0x0A) {
      out.writeln();
      i++;
    } else {
      final ch = String.fromCharCode(c);
      out.write(big ? ch.toUpperCase() : ch);
      if (big) out.write('̲'); // mark double-width chars
      i++;
    }
  }
  out.writeln('=' * 48);
  return out.toString();
}
