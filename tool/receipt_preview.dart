// Standalone check for the redesigned ESC/POS receipt.
// Usage:  dart run tool/receipt_preview.dart [--print]
//   default: decode the byte stream and show a 48-column text preview
//   --print: also send the raw bytes to the POS80 printer
import 'dart:io';
import 'package:billcat/models/transaction_record.dart';
import 'package:billcat/services/thermal_printer.dart';

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
