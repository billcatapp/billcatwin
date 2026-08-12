// Verifies the invoice-number logic after reconciling to the Mac 8-char code.
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

  // 1. A new sale shows the stored 8-char Mac-format code verbatim.
  final s = sale('some-uuid-1234', invoiceNumber: 'A7K2M9QZ');
  check('sale shows its stored 8-char code', s.displayInvoice == 'A7K2M9QZ');

  // 2. Print preview and saved bill share the SAME stored number (they are
  //    passed the one invNum), so both read identically regardless of id.
  final preview = sale('preview-id-aaaa', invoiceNumber: 'B8N4P0RS');
  final saved = sale('saved-id-bbbb', invoiceNumber: 'B8N4P0RS');
  check('preview == saved when number shared',
      preview.displayInvoice == saved.displayInvoice &&
          saved.displayInvoice == 'B8N4P0RS');

  // 3. A return keeps its RTN-<code> and points back at the original.
  final ret = sale('ret-uuid', invoiceNumber: 'RTN-A7K2M9QZ');
  check('return shows RTN-<code>', ret.displayInvoice == 'RTN-A7K2M9QZ');
  check('return points back at the code', ret.returnOfInvoice == 'A7K2M9QZ');
  check('return isReturn', ret.isReturn && !ret.isExchange);

  // 4. Exchange reversal.
  final exc = sale('exc-uuid', invoiceNumber: 'EXC-A7K2M9QZ');
  check('exchange shows EXC-<code>', exc.displayInvoice == 'EXC-A7K2M9QZ');
  check('exchange isExchange', exc.isExchange);

  // 5. A very old bill with no stored number falls back to a short id.
  final old = sale('842095ff-0000');
  check('numberless bill falls back to short id',
      old.displayInvoice == '842095');

  // 6. Old INV… bills keep their issued number (not normalised away).
  final legacy = sale('legacy-uuid', invoiceNumber: 'INV2608810707');
  check('legacy INV bill keeps its number',
      legacy.displayInvoice == 'INV2608810707');

  print('\n$pass passed, $fail failed');
}
