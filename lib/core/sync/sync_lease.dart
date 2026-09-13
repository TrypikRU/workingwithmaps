import 'dart:convert';
import 'package:drift/drift.dart';
import '../database/app_database.dart';
import '../utils/local_id.dart';

class SyncLeaseLost implements Exception {}

/// Cross-isolate/process ownership. Atomic UPSERT elects the writer. Fencing in
/// every mutation transaction prevents a stale owner from resetting/ACKing rows.
class SyncLease {
  SyncLease(
    this.database, {
    DateTime Function()? clock,
    this.duration = const Duration(minutes: 2),
  }) : clock = clock ?? DateTime.now;
  static const key = 'sync.engine_lease';
  final AppDatabase database;
  final DateTime Function() clock;
  final Duration duration;
  final String owner = localId();
  String _value() => jsonEncode({
    'owner': owner,
    'expiresAt': clock().add(duration).millisecondsSinceEpoch,
  });
  Future<bool> acquire() async =>
      await database.customUpdate(
        '''
    INSERT INTO app_metadata(key, value, updated_at) VALUES (?, ?, ?)
    ON CONFLICT(key) DO UPDATE SET value=excluded.value, updated_at=excluded.updated_at
    WHERE CAST(json_extract(app_metadata.value, '\$.expiresAt') AS INTEGER) <= ?
  ''',
        variables: [
          Variable(key),
          Variable(_value()),
          Variable(clock().millisecondsSinceEpoch ~/ 1000),
          Variable(clock().millisecondsSinceEpoch),
        ],
        updates: {database.appMetadata},
      ) ==
      1;

  /// Runs inside the claim/recovery/ACK/failure transaction. A killed/frozen
  /// worker loses ownership after two minutes, without requiring a cleanup hook.
  Future<void> renew() async {
    final changed = await database.customUpdate(
      '''
      UPDATE app_metadata SET value=?, updated_at=? WHERE key=?
      AND json_extract(value, '\$.owner')=?
      AND CAST(json_extract(value, '\$.expiresAt') AS INTEGER)>?
    ''',
      variables: [
        Variable(_value()),
        Variable(clock().millisecondsSinceEpoch ~/ 1000),
        Variable(key),
        Variable(owner),
        Variable(clock().millisecondsSinceEpoch),
      ],
      updates: {database.appMetadata},
    );
    if (changed != 1) throw SyncLeaseLost();
  }

  Future<void> release() => database
      .customUpdate(
        '''
    DELETE FROM app_metadata WHERE key=? AND json_extract(value, '\$.owner')=?
  ''',
        variables: [Variable(key), Variable(owner)],
        updates: {database.appMetadata},
      )
      .then((_) {});
  static bool isActive(String? value) =>
      value != null &&
      (jsonDecode(value)['expiresAt'] as int) >
          DateTime.now().millisecondsSinceEpoch;
}
