import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workingwithmaps/core/database/app_database.dart';
import 'package:workingwithmaps/core/sync/queue_coalescing.dart';

import '../../support/test_database.dart';

void main() {
  for (final barrier in ['delete', 'frozen patch']) {
    test('Coalescing stops at $barrier for the same entity', () async {
      final db = createTestDatabase(seedDemoData: false);
      addTearDown(db.close);
      final now = DateTime.utc(2026);
      await db.transaction(() => enqueueObjectUpdate(db, 'object', now));
      await db
          .into(db.syncQueue)
          .insert(
            SyncQueueCompanion.insert(
              entityType: 'object',
              entityId: 'object',
              operation: barrier == 'delete' ? 'delete' : 'patch',
              payload: barrier == 'delete'
                  ? const Value.absent()
                  : const Value('{}'),
            ),
          );
      await db.transaction(() => enqueueObjectUpdate(db, 'object', now));
      final rows = await db.select(db.syncQueue).get();
      expect(rows, hasLength(3));
      // Следующая правка может заменить только хвост после барьера.
      await db.transaction(() => enqueueObjectUpdate(db, 'object', now));
      expect(
        (await db.select(db.syncQueue).get()).map((q) => q.id),
        rows.map((q) => q.id),
      );
    });
  }
}
