// Replicates perLineCaps + the save-time safe re-check to prove the
// partial-quantity and same-product-twice fixes.  dart run tool/chkcap.dart

class Line {
  Line(this.key, this.qty);
  final String key;
  final int qty;
}

// Mirror of perLineCaps(): distribute each product's remaining budget across
// its lines.
Map<int, int> perLineCaps(List<Line> items, Map<String, int> done) {
  final budget = <String, int>{};
  for (final l in items) {
    budget[l.key] = (budget[l.key] ?? 0) + l.qty;
  }
  for (final e in done.entries) {
    final v = (budget[e.key] ?? 0) - e.value;
    budget[e.key] = v < 0 ? 0 : v;
  }
  final caps = <int, int>{};
  for (var i = 0; i < items.length; i++) {
    final key = items[i].key;
    final avail = budget[key] ?? 0;
    final take = items[i].qty < avail ? items[i].qty : avail;
    caps[i] = take;
    budget[key] = avail - take;
  }
  return caps;
}

int pass = 0, fail = 0;
void check(String n, bool ok, [String e = '']) {
  print('${ok ? "ok  " : "FAIL"}  $n${e.isEmpty ? "" : "  ($e)"}');
  ok ? pass++ : fail++;
}

void main() {
  // 1. Partial return: bought 3 (one line), choose 1. selectedQty clamps the
  //    chosen qty to cap.
  final oneLine = [Line('A', 3)];
  final cap1 = perLineCaps(oneLine, {});
  check('single line cap = 3', cap1[0] == 3);
  final chosen = 1;
  final sel = chosen.clamp(1, cap1[0]!); // selectedQty logic
  check('partial: choose 1 of 3 => return 1', sel == 1);

  // 2. Same product on TWO lines (2 + 2 = 4), nothing returned yet.
  final two = [Line('K', 2), Line('K', 2)];
  final capFresh = perLineCaps(two, {});
  check('two lines both returnable (2,2)',
      capFresh[0] == 2 && capFresh[1] == 2);
  // Select both fully; save-time re-check against the same budget.
  final safe = <int, int>{};
  final live = perLineCaps(two, {}); // live caps
  for (final e in {0: 2, 1: 2}.entries) {
    final take = e.value < (live[e.key] ?? 0) ? e.value : live[e.key]!;
    if (take > 0) safe[e.key] = take;
  }
  final totalReturned = safe.values.fold(0, (s, v) => s + v);
  check('return BOTH lines => 4 units (not 2)', totalReturned == 4,
      'got $totalReturned');

  // 3. After 2 of that product already returned: remaining returnable = 2.
  final capAfter = perLineCaps(two, {'K': 2});
  final remain = (capAfter[0] ?? 0) + (capAfter[1] ?? 0);
  check('after returning 2, exactly 2 still returnable', remain == 2,
      'caps=$capAfter');

  // 4. After all 4 returned: nothing returnable, no negative.
  final capDone = perLineCaps(two, {'K': 4});
  check('fully returned => 0 returnable',
      (capDone[0] ?? 0) == 0 && (capDone[1] ?? 0) == 0);

  print('\n$pass passed, $fail failed');
}
