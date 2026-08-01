// Standalone check for the redesigned ESC/POS receipt.
// Usage:  dart run tool/receipt_preview.dart [--print]
//   default: decode the byte stream and show a 48-column text preview
//   --print: also send the raw bytes to the POS80 printer
import 'dart:io';
import 'package:billcat/models/transaction_record.dart';
import 'package:billcat/services/thermal_printer.dart';

void main(List<String> args) {
  final tx = TransactionRecord(
    id: 'test',
    invoiceNumber: '9482-A84F-912C',
    customerName: 'Jamie Richardson',
    customerPhone: '+1 (555) 012-3456',
    items: const [
      TransactionItem(
        productId: '1',
        productName: 'Modern Desk Lamp - Matte Black',
        price: 145.00,
        quantity: 1,
      ),
      TransactionItem(
        productId: '2',
        productName: 'USB-C Braided Cable 2m',
        price: 19.00,
        quantity: 2,
      ),
      TransactionItem(
        productId: '3',
        productName: 'Leather Desk Pad - Obsidian',
        price: 89.50,
        quantity: 1,
      ),
    ],
    subtotal: 272.50,
    discountAmount: 10.00,
    taxAmount: 21.80,
    total: 284.30,
    paymentMethod: 'Card',
    createdAt: DateTime(2023, 10, 24, 14, 32, 5),
  );

  final bytes = ThermalPrinter.buildReceipt(
    tx,
    storeName: 'Boutique Supply Co.',
    storeAddress: '11th Cross, Thillainagar, Trichy - 620017',
    storePhone: '+91 431 2765432',
    storeGstin: '33AAAAAA0000A1Z5',
    receiptFooter:
        'Thank you for shopping with us.\nReturns accepted within 30 days with receipt.',
    taxLabel: 'Tax',
    taxRate: '8',
    currencySymbol: '₹',
    storeUpiId: 'boutique@upi',
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
