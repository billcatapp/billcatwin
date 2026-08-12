// Verifies the unified #XXXXXX invoice number logic.
//   dart run tool/chkinvoice.dart
import 'package:billcat/models/transaction_record.dart';

TransactionRecord sale(String id, {String? invoiceNumber}) => TransactionRecord(
  id: id,
  invoiceNumber: invoiceNumber,
  items: const [],
  subtotal: 0,
  discountAmount: 0,
  taxAmount: 0,
  total: 0,
  paymentMethod: 'cash',
  createdAt: DateTime(2026, 8, 12),
);

void main() {
  var pass = 0, fail = 0;
  void check(String name, bool ok) {
    print('${ok ? "ok  " : "FAIL"}  $name');
    ok ? pass++ : fail++;
  }

  // 1. Normal sale: # + first 6 of id, upper. Stored INV… is ignored.
  final s = sale('0cd045ab-1234', invoiceNumber: 'INV2608810707');
  check('normal sale derives #0CD045 (ignores stored INV…)',
      s.displayInvoice == '#0CD045');

  // 2. Print preview and saved bill share the id => same number.
  final preview = sale('abcdef12-9999'); // snapshot
  final saved = sale('abcdef12-9999'); // checkout, same id
  check('preview == saved when id shared',
      preview.displayInvoice == saved.displayInvoice &&
          saved.displayInvoice == '#ABCDEF');

  // 3. Return keeps its stored RTN-#… and points back at the original.
  final orig = sale('0cd045ab-1234');
  final base = '#${TransactionRecord.shortId(orig.id)}'; // #0CD045
  final ret = sale('ffff0000-5555',
      invoiceNumber: '${TransactionRecord.returnPrefix}$base'); // RTN-#0CD045
  check('return shows its RTN-# number', ret.displayInvoice == 'RTN-#0CD045');
  check('return points back at #0CD045', ret.returnOfInvoice == '#0CD045');
  check('return isReturn', ret.isReturn && !ret.isExchange);

  // 4. Exchange reversal.
  final exc = sale('1111aaaa-7777',
      invoiceNumber: '${TransactionRecord.exchangePrefix}$base'); // EXC-#0CD045
  check('exchange shows EXC-# number', exc.displayInvoice == 'EXC-#0CD045');
  check('exchange isExchange', exc.isExchange);

  // 5. Old Mac bill (no invoice number) — still consistent from id.
  final mac = sale('842095ff-0000');
  check('mac bill (no invoice) derives #842095',
      mac.displayInvoice == '#842095');

  print('\n$pass passed, $fail failed');
}
