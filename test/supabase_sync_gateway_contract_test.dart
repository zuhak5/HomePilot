import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('zero-row optimistic writes use list responses instead of HTTP 406', () {
    final source = File(
      'lib/src/core/sync/supabase_sync_gateway.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('.maybeSingle()')));
    expect(source, contains('final responseRows = await _withDataTimeout'));
    expect(source, contains('_zeroOrOneRemoteRow(responseRows)'));
  });
}
